import AppKit

/// What the menu-bar menu needs to know to enable the right items.
struct StatusMenuState {
    var isSessionActive: Bool
    var isPaused: Bool
    var isHamsterHidden: Bool
}

/// The 🐹 menu-bar item: shows the countdown and offers session controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var startStudying: () -> Void
        var pause: () -> Void
        var resume: () -> Void
        var skip: () -> Void
        var stop: () -> Void
        var toggleHamsterHidden: () -> Void
        var openSettings: () -> Void
    }

    private let item: NSStatusItem
    private let actions: Actions
    private let state: () -> StatusMenuState
    private var currentTitle = ""

    init(actions: Actions, state: @escaping () -> StatusMenuState) {
        self.actions = actions
        self.state = state
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "Study Hamster"
        setTitle("🐹")
    }

    /// Updates the menu-bar text ("🐹", "🐹 18:42", "☕️ 3:12"). Digits are monospaced so it doesn't jiggle.
    func setTitle(_ title: String) {
        guard title != currentTitle, let button = item.button else { return }
        currentTitle = title
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    // MARK: - Menu

    /// Rebuilt every time it opens, so the enabled items always match the current session state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = state()
        menu.removeAllItems()
        menu.addItem(makeItem("Start Studying…", #selector(startStudying), enabled: !state.isSessionActive))
        menu.addItem(makeItem("Pause", #selector(pause), enabled: state.isSessionActive && !state.isPaused))
        menu.addItem(makeItem("Resume", #selector(resume), enabled: state.isPaused))
        menu.addItem(makeItem("Skip to Next", #selector(skip), enabled: state.isSessionActive))
        menu.addItem(makeItem("Stop Session", #selector(stop), enabled: state.isSessionActive))
        menu.addItem(.separator())
        menu.addItem(makeItem(state.isHamsterHidden ? "Show Hamster" : "Hide Hamster", #selector(toggleHamsterHidden)))
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Study Hamster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        menuItem.isEnabled = enabled
        return menuItem
    }

    @objc private func startStudying() { actions.startStudying() }
    @objc private func pause() { actions.pause() }
    @objc private func resume() { actions.resume() }
    @objc private func skip() { actions.skip() }
    @objc private func stop() { actions.stop() }
    @objc private func toggleHamsterHidden() { actions.toggleHamsterHidden() }
    @objc private func openSettings() { actions.openSettings() }
}
