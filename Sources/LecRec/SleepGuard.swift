import Foundation
import AppKit

/// Keeps the Mac awake for the length of a recording.
///
/// Honest scope: this blocks **idle** sleep, which is the case that actually
/// bites during a lecture, a machine sitting untouched on a desk for an hour.
/// It does not block **clamshell** sleep. Closing the lid triggers a separate,
/// lower-level suspend that ordinary power assertions do not override, so if you
/// shut the laptop the recording stops. Only `pmset disablesleep` or an external
/// display defeats that, and neither is something an app should do behind your
/// back. The UI says so rather than pretending otherwise.
final class SleepGuard {
    private var activity: NSObjectProtocol?
    private(set) var isHeld = false

    /// Also keeps the display awake, because a sleeping display on some setups
    /// drags the machine toward sleep, and it makes the level meter glanceable.
    func begin(reason: String) {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
            reason: reason)
        isHeld = true
        Diagnostics.log("sleep guard engaged: \(reason)")
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
        isHeld = false
        Diagnostics.log("sleep guard released")
    }

    /// Belt and braces: if the app is killed mid-lecture the activity dies with
    /// it, so nothing is left holding the system awake.
    deinit { end() }
}
