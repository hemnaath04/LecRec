import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverController: PopoverController!
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var settings = Settings.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install()   // without this, Command V does nothing in any field
        Notifier.requestAuthorization()

        popoverController = PopoverController(settings: settings)
        popoverController.onStatusChange = { [weak self] recording in
            self?.updateIcon(recording: recording)
        }
        popoverController.onOpenSettings = { [weak self] in self?.showSettings() }

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
        } else if !SkillInstaller.isInstalled {
            // A fresh build ships an updated skill; keep the installed copy current.
            try? SkillInstaller.install()
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

    private func showOnboarding() {
        let controller = OnboardingWindowController(settings: settings)
        controller.onFinish = { [weak self] updated in
            self?.settings = updated
            self?.popoverController.reload(settings: updated)
        }
        onboardingController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        popover.performClose(nil)
        let controller = SettingsWindowController(settings: settings)
        controller.onSave = { [weak self] updated in
            self?.settings = updated
            self?.popoverController.reload(settings: updated)
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
application.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
application.run()
