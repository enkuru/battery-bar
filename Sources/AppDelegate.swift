import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let batterySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!
    private static let autosaveName = "BatteryBar"
    // Undocumented AppKit default: a status item's spot, in points from the right screen edge.
    // Control Center's own item sits around 150, so a slightly larger value lands right beside it.
    private static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
    private static let besideControlCenter = 160.0
    private static let loginItemRegisteredKey = "LoginItemRegistered"
    private static let showsTimeKey = "ShowTimeLeftInMenuBar"

    private let statusItem: NSStatusItem
    private let model = BatteryModel()
    private var monitor: BatteryMonitor?
    private lazy var panel = NSHostingView(rootView: MenuPanel(model: model) { [weak self] app in self?.quit(app) })
    private var shownIcon: (state: BatteryState, caption: String?)?
    private var isMenuOpen = false

    private var showsTimeInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showsTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showsTimeKey) }
    }

    override init() {
        UserDefaults.standard.register(defaults: [Self.showsTimeKey: true])
        // Seed only once, so a spot the user picks later with Cmd-drag is kept.
        if UserDefaults.standard.object(forKey: Self.positionKey) == nil {
            UserDefaults.standard.set(Self.besideControlCenter, forKey: Self.positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.onChange = { [weak self] in self?.modelChanged() }
        let monitor = BatteryMonitor { [weak self] state in self?.model.update(state) }
        monitor.start()
        self.monitor = monitor

        registerLoginItemOnce()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let state = model.state {
            // Before measuring the panel: its power section appears only once there is a reading.
            model.sample()
            let panelItem = NSMenuItem()
            panelItem.view = panel
            fitPanel()
            menu.addItem(panelItem)
            menu.addItem(.separator())

            if state.isLowPowerMode {
                let lowPower = NSMenuItem(title: "Low Power Mode is on", action: #selector(openBatterySettings),
                                          keyEquivalent: "")
                lowPower.target = self
                lowPower.state = .on
                lowPower.onStateImage = Self.dot(color: .systemYellow)
                menu.addItem(lowPower)
            }
            let showTime = NSMenuItem(title: "Show Time Left in Menu Bar", action: #selector(toggleTimeInMenuBar),
                                      keyEquivalent: "")
            showTime.target = self
            showTime.state = showsTimeInMenuBar ? .on : .off
            menu.addItem(showTime)
        } else {
            menu.addItem(NSMenuItem(title: "No Battery", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Battery Settings…", action: #selector(openBatterySettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit BatteryBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        model.isLive = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        model.isLive = false
    }

    // Once only, so switching it off in System Settings › General › Login Items sticks.
    private func registerLoginItemOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.loginItemRegisteredKey) else { return }

        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Self.loginItemRegisteredKey)
        } catch {
            NSLog("BatteryBar could not add itself to Login Items: \(error)")
        }
    }

    private func modelChanged() {
        showStatusIcon()
        if isMenuOpen { fitPanel() }
    }

    /// Redraws only when what the icon shows has changed, which on battery is about once a minute.
    private func showStatusIcon() {
        guard let button = statusItem.button else { return }
        guard let state = model.state else {
            shownIcon = nil
            button.image = nil
            button.title = "No Battery"
            return
        }

        let caption = showsTimeInMenuBar ? menuBarTime : nil
        if let shownIcon, shownIcon.state == state, shownIcon.caption == caption { return }

        shownIcon = (state, caption)
        button.image = BatteryIcon.image(for: state, caption: caption)
        button.title = ""
    }

    private var menuBarTime: String? {
        guard case .estimate(let duration) = model.timeRemaining else { return nil }
        return TimeLeftFormat.compact(duration)
    }

    /// Menu item views are laid out by frame, so the panel's height follows its content by hand.
    private func fitPanel() {
        let height = panel.fittingSize.height
        guard panel.frame.size != NSSize(width: MenuPanel.width, height: height) else { return }

        panel.frame = NSRect(x: 0, y: 0, width: MenuPanel.width, height: height)
    }

    @objc private func toggleTimeInMenuBar() {
        showsTimeInMenuBar.toggle()
        showStatusIcon()
    }

    private func quit(_ app: NSRunningApplication) {
        // The menu closes first, so a "save changes?" alert from the app doesn't wait behind it.
        statusItem.menu?.cancelTracking()
        app.terminate()
    }

    @objc private func openBatterySettings() {
        NSWorkspace.shared.open(Self.batterySettingsURL)
    }

    private static func dot(color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
