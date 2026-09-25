import AppKit

/// A menu bar only app has no main menu by default, and without an Edit menu the
/// standard Cut, Copy, Paste and Select All key equivalents are never bound. The
/// result is text fields where Command V silently does nothing.
///
/// The menu is never displayed (the app has no Dock icon and no menu bar title),
/// it exists purely so the shortcuts resolve through the responder chain.
enum AppMenu {
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(withTitle: "Settings\u{2026}",
                                           action: Selector(("showSettingsFromMenu:")), keyEquivalent: ",")
        settingsItem.target = NSApp.delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LecRec", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // nil targets route through the responder chain to whichever field has focus.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = editMenu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let dashboard = viewMenu.addItem(withTitle: "Dashboard",
                                         action: Selector(("showDashboard:")), keyEquivalent: "0")
        dashboard.target = NSApp.delegate
        let live = viewMenu.addItem(withTitle: "Live Monitor",
                                    action: Selector(("showLiveFromMenu:")), keyEquivalent: "l")
        live.target = NSApp.delegate
        let refresh = viewMenu.addItem(withTitle: "Refresh",
                                       action: Selector(("refreshLibrary:")), keyEquivalent: "r")
        refresh.target = NSApp.delegate
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
