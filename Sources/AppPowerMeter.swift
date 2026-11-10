import AppKit
import Darwin
import UniformTypeIdentifiers

/// One app's processor power, its helper processes included.
struct AppPower: Identifiable {
    /// The app bundle's path, or the executable's for a command-line tool.
    let id: String
    let name: String
    let icon: NSImage
    let watts: Double
    /// The app Quit asks to quit; nil for command-line tools and for BatteryBar itself.
    let runningApp: NSRunningApplication?
}

/// Processor power per app, from the kernel's per-process energy counters. Only the user's own processes
/// can be read without admin rights, so system daemons are left out; the screen and graphics are not counted.
@MainActor
final class AppPowerMeter {
    private struct Tracked {
        let startTime: UInt64
        let app: String
        let energy: UInt64
    }

    private struct Identity {
        let name: String
        let icon: NSImage
        let runningApp: NSRunningApplication?
    }

    private static let smoothing: TimeInterval = 5
    /// After a longer pause the counters span minutes of history, which says nothing about now.
    private static let maxInterval: TimeInterval = 15
    private static let minimumWatts = 0.05

    private var processes: [pid_t: Tracked] = [:]
    private var averages: [String: Double] = [:]
    private var identities: [String: Identity] = [:]
    private var lastSample: Date?

    /// Reads every process once. Returns the busiest apps, or nil until two readings close together exist.
    func sample(at date: Date, top count: Int) -> [AppPower]? {
        var nanojoules: [String: UInt64] = [:]
        var current: [pid_t: Tracked] = [:]

        for pid in Self.allProcesses() {
            guard let usage = Self.usage(of: pid) else { continue }

            if let known = processes[pid], known.startTime == usage.ri_proc_start_abstime {
                nanojoules[known.app, default: 0] += usage.ri_energy_nj &- known.energy
                current[pid] = Tracked(startTime: known.startTime, app: known.app, energy: usage.ri_energy_nj)
            } else if let app = app(of: pid) {
                // A process seen for the first time counts from the next reading.
                current[pid] = Tracked(startTime: usage.ri_proc_start_abstime, app: app, energy: usage.ri_energy_nj)
            }
        }

        let interval = lastSample.map { date.timeIntervalSince($0) }
        processes = current
        lastSample = date
        let runningApps = Set(current.values.map(\.app))
        identities = identities.filter { runningApps.contains($0.key) }
        guard let interval, interval > 0, interval <= Self.maxInterval else {
            averages = [:]
            return nil
        }

        let weight = 1 - exp(-interval / Self.smoothing)
        averages = nanojoules.reduce(into: [:]) { result, entry in
            let watts = Double(entry.value) / 1e9 / interval
            let previous = averages[entry.key] ?? watts
            result[entry.key] = previous + weight * (watts - previous)
        }

        return averages
            .filter { $0.value >= Self.minimumWatts }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .compactMap { app, watts in
                identities[app].map {
                    AppPower(id: app, name: $0.name, icon: $0.icon, watts: watts, runningApp: $0.runningApp)
                }
            }
    }

    /// Groups a process under the app it works for: the process macOS holds responsible for it (an app's
    /// helpers and the system services it starts, such as a virtual machine), then the outermost .app bundle
    /// in that process's path.
    private func app(of pid: pid_t) -> String? {
        let owner = Self.responsibleProcess(for: pid) ?? pid
        guard let path = Self.executablePath(of: owner) ?? Self.executablePath(of: pid) else { return nil }

        if let bundleEnd = path.range(of: ".app/") {
            let bundle = String(path[..<bundleEnd.lowerBound]) + ".app"
            if identities[bundle] == nil {
                identities[bundle] = Identity(name: FileManager.default.displayName(atPath: bundle),
                                              icon: NSWorkspace.shared.icon(forFile: bundle),
                                              runningApp: Self.runningApp(at: bundle))
            }
            return bundle
        }
        if identities[path] == nil {
            identities[path] = Identity(name: Self.processName(of: owner) ?? (path as NSString).lastPathComponent,
                                        icon: NSWorkspace.shared.icon(for: .unixExecutable), runningApp: nil)
        }
        return path
    }

    /// A Dock or menu bar app at that path. Background-only bundles are left out, since they may not answer
    /// a request to quit.
    private static func runningApp(at bundle: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.path == bundle && $0.activationPolicy != .prohibited && $0 != NSRunningApplication.current
        }
    }

    /// A private libsystem function; looked up at run time, so if a macOS update removes it BatteryBar keeps
    /// working and groups by path alone.
    private static let responsibleProcessFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsibleProcess(for pid: pid_t) -> pid_t? {
        guard let owner = responsibleProcessFunction?(pid), owner > 0 else { return nil }
        return owner
    }

    private static func allProcesses() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(max(0, Int(count))).filter { $0 > 0 }
    }

    /// Nil for processes of other users, which need admin rights.
    private static func usage(of pid: pid_t) -> rusage_info_v6? {
        var usage = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return status == 0 ? usage : nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    private static func processName(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }
}
