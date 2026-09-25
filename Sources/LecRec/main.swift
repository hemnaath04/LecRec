import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverController: PopoverController!
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var mainWindowController: MainWindowController?
    private var liveController: LiveMonitorWindowController?
    private var settings = Settings.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.Typeface.register()   // before any view builds a font
        AppMenu.install()   // without this, Command V does nothing in any field
        Notifier.requestAuthorization()
        Recorder.primePermissionIfNeeded()   // so the app appears in the Privacy list

        popoverController = PopoverController(settings: settings)
        popoverController.onLibraryChanged = { [weak self] in
            self?.mainWindowController?.reload()
        }
        popoverController.onOpenSettings = { [weak self] in self?.showSettings() }
        popoverController.onOpenLive = { [weak self] in self?.showLive() }
        popoverController.onLevelSample = { [weak self] level in
            self?.liveController?.observe(level: level)
        }
        // Opening the monitor the moment recording starts is the difference
        // between noticing a dead microphone now and noticing it after class.
        popoverController.onStatusChange = { [weak self] recording in
            self?.updateIcon(recording: recording)
            self?.mainWindowController?.setRecording(recording)
            if recording { self?.showLive() }
        }

        popover.contentViewController = popoverController
        popover.behavior = .transient

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateIcon(recording: false)

        // A first run with nothing configured would otherwise fail at the first
        // press, so setup happens before the user can get that far.
        if !settings.hasCompletedOnboarding || !settings.isReadyToRecord {
            showOnboarding()
        } else {
            if !SkillInstaller.isInstalled {
                // A fresh build ships an updated skill; keep the installed copy current.
                try? SkillInstaller.install()
            }
            showMainWindow()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func updateIcon(recording: Bool) {
        let name = recording ? "record.circle.fill" : "waveform"
        let description = recording ? "LecRec, recording" : "LecRec"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = !recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
    }

    @objc private func togglePopover() {
        Diagnostics.log("togglePopover fired, isShown=\(popover.isShown)")
        guard let button = statusItem.button else {
            Diagnostics.log("no status item button")
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverController.reload(settings: settings)
            // An accessory app is not active by default, so a transient popover
            // opens and closes in the same breath and text fields never get keys.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            Diagnostics.log("popover shown=\(popover.isShown)")
        }
    }

    /// The app is a normal windowed app that also lives in the menu bar, rather
    /// than a menu bar utility with no home.
    func showMainWindow() {
        if let existing = mainWindowController {
            existing.apply(settings: settings)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = MainWindowController(settings: settings)
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.onOpenLive = { [weak self] in self?.showLive() }
        controller.onRecordPressed = { [weak self] _ in
            self?.popoverController.toggleRecordingExternally()
        }
        mainWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.setRecording(popoverController.isRecording)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showDashboard(_ sender: Any?) { showMainWindow() }

    @objc func refreshLibrary(_ sender: Any?) { mainWindowController?.reload() }

    @objc func showSettingsFromMenu(_ sender: Any?) { showSettings() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showLive() {
        if let existing = liveController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LiveMonitorWindowController(recorder: popoverController.recorder)
        liveController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showLiveFromMenu(_ sender: Any?) { showLive() }

    private func showOnboarding() {
        let controller = OnboardingWindowController(settings: settings)
        controller.onFinish = { [weak self] updated in
            guard let self else { return }
            self.settings = updated
            self.popoverController.reload(settings: updated)
            try? SkillInstaller.install()
            self.showMainWindow()
        }
        onboardingController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        popover.performClose(nil)
        let controller = SettingsWindowController(settings: settings)
        controller.onSave = { [weak self] updated in
            self?.settings = updated
            self?.popoverController.reload(settings: updated)
            self?.mainWindowController?.apply(settings: updated)
        }
        settingsController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)   // real app: Dock icon and app switcher
application.run()
