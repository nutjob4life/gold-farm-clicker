import Foundation

enum ClickerPhase: Equatable, Sendable {
    case idle
    case attacking
    case selectingFood
    case eating
    case selectingWeapon

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .attacking: "Attacking"
        case .selectingFood: "Selecting food"
        case .eating: "Eating"
        case .selectingWeapon: "Selecting weapon"
        }
    }
}

@MainActor
@Observable
final class ClickerEngine {
    private enum Defaults {
        static let secondsBetweenAttacks = 10.0
        static let minutesUntilEat = 20.0
        static let weaponSlot = 1
        static let foodSlot = 9
        static let eatHoldSeconds = 10.0
    }

    private enum Keys {
        static let secondsBetweenAttacks = "secondsBetweenAttacks"
        static let minutesUntilEat = "minutesUntilEat"
        static let weaponSlot = "weaponSlot"
        static let foodSlot = "foodSlot"
    }

    private(set) var isRunning = false
    private(set) var phase: ClickerPhase = .idle
    private(set) var nextActionDate: Date?
    private(set) var cyclesCompleted = 0
    private(set) var attacksThisCycle = 0
    private(set) var lastError: String?
    private(set) var minecraftDetected = false

    /// Seconds to wait between left-clicks while attacking.
    var secondsBetweenAttacks: Double {
        didSet {
            let clamped = Self.clampSecondsBetweenAttacks(secondsBetweenAttacks)
            if clamped != secondsBetweenAttacks {
                secondsBetweenAttacks = clamped
                return
            }
            UserDefaults.standard.set(secondsBetweenAttacks, forKey: Keys.secondsBetweenAttacks)
        }
    }

    /// Minutes of attacking before an eat cycle.
    var minutesUntilEat: Double {
        didSet {
            let clamped = Self.clampMinutesUntilEat(minutesUntilEat)
            if clamped != minutesUntilEat {
                minutesUntilEat = clamped
                return
            }
            UserDefaults.standard.set(minutesUntilEat, forKey: Keys.minutesUntilEat)
        }
    }

    /// Hotbar slot for the weapon (1–9).
    var weaponSlot: Int {
        didSet {
            let clamped = Self.clampSlot(weaponSlot)
            if clamped != weaponSlot {
                weaponSlot = clamped
                return
            }
            UserDefaults.standard.set(weaponSlot, forKey: Keys.weaponSlot)
        }
    }

    /// Hotbar slot for food (1–9).
    var foodSlot: Int {
        didSet {
            let clamped = Self.clampSlot(foodSlot)
            if clamped != foodSlot {
                foodSlot = clamped
                return
            }
            UserDefaults.standard.set(foodSlot, forKey: Keys.foodSlot)
        }
    }

    let eatHoldDuration: Duration = .seconds(Defaults.eatHoldSeconds)

    private var runTask: Task<Void, Never>?
    private var activityToken: NSObjectProtocol?
    private var holdingRightMouse = false
    private var lastClickPoint: CGPoint?

    init() {
        let defaults = UserDefaults.standard
        let storedInterval = defaults.object(forKey: Keys.secondsBetweenAttacks) as? Double
        let storedMinutes = defaults.object(forKey: Keys.minutesUntilEat) as? Double
        let storedWeapon = defaults.object(forKey: Keys.weaponSlot) as? Int
        let storedFood = defaults.object(forKey: Keys.foodSlot) as? Int

        secondsBetweenAttacks = Self.clampSecondsBetweenAttacks(
            storedInterval ?? Defaults.secondsBetweenAttacks
        )
        minutesUntilEat = Self.clampMinutesUntilEat(
            storedMinutes ?? Defaults.minutesUntilEat
        )
        weaponSlot = Self.clampSlot(storedWeapon ?? Defaults.weaponSlot)
        foodSlot = Self.clampSlot(storedFood ?? Defaults.foodSlot)
    }

    /// Attack-phase length. `GFC_ATTACK_SECONDS` overrides for quick testing.
    var attackPhaseDuration: Duration {
        if let env = ProcessInfo.processInfo.environment["GFC_ATTACK_SECONDS"],
           let seconds = Double(env),
           seconds > 0
        {
            return .seconds(seconds)
        }
        return .seconds(minutesUntilEat * 60)
    }

    var clickInterval: Duration {
        .seconds(secondsBetweenAttacks)
    }

    func refreshMinecraftDetection() {
        minecraftDetected = MinecraftTarget.findMinecraftWindow() != nil
    }

    func start() {
        guard !isRunning else { return }

        guard Permissions.isTrusted else {
            lastError = "Accessibility permission required."
            Permissions.requestTrustPrompt()
            return
        }

        guard MinecraftTarget.findMinecraftWindow() != nil else {
            lastError = "Minecraft window not found."
            minecraftDetected = false
            return
        }

        lastError = nil
        isRunning = true
        phase = .attacking
        attacksThisCycle = 0
        beginSleepPrevention()

        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        finishStop()
    }

    // MARK: - Loop

    private func runLoop() async {
        do {
            while !Task.isCancelled {
                try await attackPhase()
                try await eatSequence()
                cyclesCompleted += 1
            }
        } catch is CancellationError {
            // Expected on Stop.
        } catch {
            lastError = error.localizedDescription
        }

        finishStop()
    }

    private func attackPhase() async throws {
        phase = .attacking
        attacksThisCycle = 0

        let deadline = Date.now.addingTimeInterval(attackPhaseDuration.timeInterval)
        var firstClick = true

        while Date.now < deadline {
            try Task.checkCancellation()

            if !firstClick {
                try await sleepUntilNextAction(clickInterval)
            }
            firstClick = false

            try Task.checkCancellation()
            let point = try await prepareTarget()
            InputSender.leftClick(at: point)
            attacksThisCycle += 1
        }
    }

    private func eatSequence() async throws {
        try Task.checkCancellation()

        phase = .selectingFood
        nextActionDate = nil
        var point = try await prepareTarget()
        await InputSender.pressHotbarSlot(foodSlot)

        try Task.checkCancellation()

        phase = .eating
        point = try await prepareTarget()
        InputSender.rightMouseDown(at: point)
        holdingRightMouse = true
        lastClickPoint = point

        do {
            try await sleepUntilNextAction(eatHoldDuration)
        } catch {
            releaseRightMouseIfNeeded()
            throw error
        }

        releaseRightMouseIfNeeded()

        try Task.checkCancellation()

        phase = .selectingWeapon
        nextActionDate = nil
        _ = try await prepareTarget()
        await InputSender.pressHotbarSlot(weaponSlot)
    }

    // MARK: - Helpers

    private func prepareTarget() async throws -> CGPoint {
        guard let window = MinecraftTarget.findMinecraftWindow() else {
            minecraftDetected = false
            throw ClickerError.minecraftNotFound
        }
        minecraftDetected = true

        _ = await MinecraftTarget.activate(pid: window.pid)

        // Re-resolve bounds after activation in case the window moved.
        let fresh = MinecraftTarget.findMinecraftWindow() ?? window
        let point = MinecraftTarget.centerPoint(of: fresh)
        lastClickPoint = point
        return point
    }

    private func sleepUntilNextAction(_ duration: Duration) async throws {
        nextActionDate = Date.now.addingTimeInterval(duration.timeInterval)
        try await Task.sleep(for: duration)
        nextActionDate = nil
    }

    private func releaseRightMouseIfNeeded() {
        guard holdingRightMouse else { return }
        if let point = lastClickPoint {
            InputSender.rightMouseUp(at: point)
        } else if let window = MinecraftTarget.findMinecraftWindow() {
            InputSender.rightMouseUp(at: MinecraftTarget.centerPoint(of: window))
        }
        holdingRightMouse = false
    }

    private func finishStop() {
        releaseRightMouseIfNeeded()
        endSleepPrevention()
        isRunning = false
        phase = .idle
        nextActionDate = nil
        runTask = nil
    }

    private func beginSleepPrevention() {
        endSleepPrevention()
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Gold Farm Clicker is sending input to Minecraft"
        )
    }

    private func endSleepPrevention() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    private static func clampSecondsBetweenAttacks(_ value: Double) -> Double {
        min(3600, max(0.5, value))
    }

    private static func clampMinutesUntilEat(_ value: Double) -> Double {
        min(24 * 60, max(0.1, value))
    }

    private static func clampSlot(_ value: Int) -> Int {
        min(9, max(1, value))
    }
}

enum ClickerError: LocalizedError {
    case minecraftNotFound

    var errorDescription: String? {
        switch self {
        case .minecraftNotFound:
            "Minecraft window disappeared."
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
