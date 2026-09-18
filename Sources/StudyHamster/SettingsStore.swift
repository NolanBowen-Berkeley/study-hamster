import Foundation
import HamsterCore

/// User preferences, persisted in UserDefaults. Published values drive the Settings window; the controller
/// reads them live (length changes apply to the next session).
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let pomodoro = "pomodoroSettings"
        static let soundEnabled = "soundEnabled"
        static let soundName = "soundName"
        static let eyesFollowCursor = "eyesFollowCursor"
        static let showTimerTag = "showTimerTag"
        static let hamsterHidden = "hamsterHidden"
        static let lastDurationText = "lastDurationText"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    private let defaults: UserDefaults

    @Published var pomodoro: PomodoroSettings {
        didSet {
            if let data = try? JSONEncoder().encode(pomodoro) {
                defaults.set(data, forKey: Key.pomodoro)
            }
        }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }
    /// One of `SoundPlayer.choices`.
    @Published var soundName: String {
        didSet { defaults.set(soundName, forKey: Key.soundName) }
    }
    @Published var eyesFollowCursor: Bool {
        didSet { defaults.set(eyesFollowCursor, forKey: Key.eyesFollowCursor) }
    }
    @Published var showTimerTag: Bool {
        didSet { defaults.set(showTimerTag, forKey: Key.showTimerTag) }
    }

    /// "Hide Hamster" from the menu: the panel stays away except to deliver alarms.
    var hamsterHidden: Bool {
        get { defaults.bool(forKey: Key.hamsterHidden) }
        set { defaults.set(newValue, forKey: Key.hamsterHidden) }
    }
    /// What was last typed into the ask bubble (pre-filled next time).
    var lastDurationText: String {
        get { defaults.string(forKey: Key.lastDurationText) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastDurationText) }
    }
    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.soundEnabled: true,
            Key.soundName: SoundPlayer.squeak,
            Key.eyesFollowCursor: true,
            Key.showTimerTag: true,
        ])

        let stored = defaults.data(forKey: Key.pomodoro)
            .flatMap { try? JSONDecoder().decode(PomodoroSettings.self, from: $0) }
        pomodoro = (stored ?? .standard).sanitized()
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        let name = defaults.string(forKey: Key.soundName) ?? SoundPlayer.squeak
        soundName = SoundPlayer.choices.contains(name) ? name : SoundPlayer.squeak
        eyesFollowCursor = defaults.bool(forKey: Key.eyesFollowCursor)
        showTimerTag = defaults.bool(forKey: Key.showTimerTag)
    }

    func resetPomodoroToDefaults() {
        pomodoro = .standard
    }
}
