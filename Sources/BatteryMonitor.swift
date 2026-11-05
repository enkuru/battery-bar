import Foundation
import IOKit.ps

/// Reports battery changes from IOKit and Low Power Mode notifications, so nothing polls.
@MainActor
final class BatteryMonitor {
    private let onChange: (BatteryState?) -> Void
    private var lastState: BatteryState?

    init(onChange: @escaping (BatteryState?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        _ = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                   queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        lastState = BatteryState.current()
        onChange(lastState)
    }

    private func refresh() {
        let state = BatteryState.current()
        guard state != lastState else { return }

        lastState = state
        onChange(state)
    }
}
