import SwiftUI

@main
struct GoldFarmClickerApp: App {
    @State private var engine = ClickerEngine()

    var body: some Scene {
        Window("Gold Farm Clicker", id: "main") {
            ContentView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 420)
    }
}

struct ContentView: View {
    @Bindable var engine: ClickerEngine
    @State private var accessibilityTrusted = Permissions.isTrusted

    private let hotbarSlots = Array(1...9)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 16) {
                Text("Gold Farm Clicker")
                    .font(.title2.weight(.semibold))

                Button(action: toggle) {
                    Text(engine.isRunning ? "Stop" : "Start")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isRunning ? .red : .accentColor)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                settingsSection
                    .disabled(engine.isRunning)
                    .opacity(engine.isRunning ? 0.55 : 1)

                statusSection(now: context.date)

                Divider()

                accessibilityRow
                minecraftRow
            }
            .padding(24)
            .frame(width: 380)
            .onChange(of: context.date) { _, _ in
                accessibilityTrusted = Permissions.isTrusted
                engine.refreshMinecraftDetection()
            }
        }
        .onAppear {
            accessibilityTrusted = Permissions.isTrusted
            engine.refreshMinecraftDetection()
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Between attacks")
                Spacer()
                TextField(
                    "",
                    value: $engine.secondsBetweenAttacks,
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                Text("s")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
            }

            HStack {
                Text("Time to eat")
                Spacer()
                TextField(
                    "",
                    value: $engine.minutesUntilEat,
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                Text("m")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
            }

            HStack {
                Text("Weapon slot")
                Spacer()
                Picker("", selection: $engine.weaponSlot) {
                    ForEach(hotbarSlots, id: \.self) { slot in
                        Text("\(slot)").tag(slot)
                    }
                }
                .labelsHidden()
                .frame(width: 64)
            }

            HStack {
                Text("Food slot")
                Spacer()
                Picker("", selection: $engine.foodSlot) {
                    ForEach(hotbarSlots, id: \.self) { slot in
                        Text("\(slot)").tag(slot)
                    }
                }
                .labelsHidden()
                .frame(width: 64)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func statusSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labeledRow("Phase", engine.phase.displayName)

            if engine.isRunning {
                labeledRow("Attacks this cycle", "\(engine.attacksThisCycle)")
                labeledRow("Cycles completed", "\(engine.cyclesCompleted)")

                if let next = engine.nextActionDate {
                    let remaining = max(0, Int(ceil(next.timeIntervalSince(now))))
                    labeledRow("Next action", "in \(remaining)s")
                } else {
                    labeledRow("Next action", "now")
                }
            } else {
                labeledRow("Cycles completed", "\(engine.cyclesCompleted)")
            }

            if let error = engine.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(accessibilityTrusted ? "Accessibility granted" : "Accessibility required")
                .font(.caption)
            Spacer()
            if !accessibilityTrusted {
                Button("Open Settings") {
                    Permissions.openAccessibilitySettings()
                    Permissions.requestTrustPrompt()
                }
                .font(.caption)
            }
        }
    }

    private var minecraftRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.minecraftDetected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(engine.minecraftDetected ? "Minecraft window found" : "Minecraft window not found")
                .font(.caption)
            Spacer()
        }
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func toggle() {
        if engine.isRunning {
            engine.stop()
        } else {
            accessibilityTrusted = Permissions.isTrusted
            if !accessibilityTrusted {
                Permissions.requestTrustPrompt()
            }
            engine.start()
        }
    }
}
