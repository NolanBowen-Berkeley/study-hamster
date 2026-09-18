import AppKit
import HamsterCore
import SwiftUI

/// The Settings form.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let previewSound: () -> Void

    var body: some View {
        Form {
            Section {
                minutesStepper("Focus", value: $settings.pomodoro.focusMinutes, range: 1...180)
                minutesStepper("Short break", value: $settings.pomodoro.shortBreakMinutes, range: 1...60)
                minutesStepper("Long break", value: $settings.pomodoro.longBreakMinutes, range: 1...120)
                Stepper(value: $settings.pomodoro.focusBlocksBeforeLongBreak, in: 1...12) {
                    LabeledContent("Long break every", value: pomodoroCount(settings.pomodoro.focusBlocksBeforeLongBreak))
                }
                Button("Reset to Defaults") { settings.resetPomodoroToDefaults() }
                    .disabled(settings.pomodoro == .standard)
            } header: {
                Text("Pomodoro")
            } footer: {
                Text("Changes apply to your next study session.")
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                Toggle("Play sounds", isOn: $settings.soundEnabled)
                HStack {
                    Picker("Sound", selection: $settings.soundName) {
                        ForEach(SoundPlayer.choices, id: \.self) { name in
                            Text(name == SoundPlayer.squeak ? "Squeak (hamster)" : name).tag(name)
                        }
                    }
                    Button("Preview", action: previewSound)
                }
                .disabled(!settings.soundEnabled)
            }

            Section("Hamster") {
                Toggle("Eyes follow the cursor", isOn: $settings.eyesFollowCursor)
                Toggle("Show the timer tag", isOn: $settings.showTimerTag)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func minutesStepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: 1) {
            LabeledContent(title, value: TimeFormat.humanDuration(value.wrappedValue * 60))
        }
    }

    private func pomodoroCount(_ count: Int) -> String {
        count == 1 ? "1 pomodoro" : "\(count) pomodoros"
    }
}

/// Owns the Settings window. The app is an accessory (no Dock icon), so it activates itself explicitly when
/// the window opens and hands focus back when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let sounds: SoundPlayer
    private var window: NSWindow?

    init(settings: SettingsStore, sounds: SoundPlayer) {
        self.settings = settings
        self.sounds = sounds
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        window.level = .normal
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(settings: settings) { [weak self] in
            guard let self else { return }
            sounds.play(settings.soundName)
        }
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Study Hamster Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Give the app you were studying in its focus back.
        NSApp.deactivate()
    }
}
