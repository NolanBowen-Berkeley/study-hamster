import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: HamsterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let controller = HamsterController(settings: SettingsStore())
        controller.start()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs sends a reopen event, not a new
    /// launch: bring a hidden hamster back, since the menu-bar item may be out of sight behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.handleReopen()
        return false
    }

    /// The menu bar never shows for an accessory app, but its key equivalents still route through the main
    /// menu: this is what makes ⌘V / ⌘A / ⌘Z work in the hamster's text field and ⌘W close Settings.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "Study Hamster")
        appMenu.addItem(withTitle: "Quit Study Hamster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenuItem(appMenu))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenuItem(editMenu))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(submenuItem(windowMenu))

        NSApp.mainMenu = mainMenu
    }

    private func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
