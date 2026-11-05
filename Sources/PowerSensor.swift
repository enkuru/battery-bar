import IOKit

/// Watts measured by the System Management Controller, which refreshes them about once a second.
struct PowerReading: Equatable {
    /// The whole Mac's draw.
    let system: Double
    /// The flow out of or into the battery; the charge state says which way.
    let battery: Double
    /// What the charger delivers; zero when unplugged.
    let adapter: Double
}

/// Reads live power from the SMC. Its keys are undocumented (the ones power tools such as AlDente read),
/// so a macOS update may remove them; `read()` then returns nil and the menu hides the live figures.
@MainActor
final class PowerSensor {
    private let connection: io_connect_t
    private var keyInfo: [UInt32: SMCParam.KeyInfo] = [:]

    init?() {
        let smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard smc != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(smc) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(smc, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func read() -> PowerReading? {
        guard let system = watts("PSTR"), let battery = watts("PPBR"), let adapter = watts("PDTR") else { return nil }
        return PowerReading(system: system, battery: abs(battery), adapter: adapter)
    }

    private func watts(_ key: String) -> Double? {
        let code = SMCParam.code(key)
        guard let info = keyInfo[code] ?? fetchKeyInfo(code),
              info.dataType == SMCParam.code("flt "), info.dataSize == 4
        else { return nil }

        var request = SMCParam()
        request.key = code
        request.keyInfo.dataSize = info.dataSize
        request.command = SMCParam.readBytes
        guard var response = call(request) else { return nil }
        return Double(withUnsafeBytes(of: &response.bytes) { $0.load(as: Float32.self) })
    }

    private func fetchKeyInfo(_ code: UInt32) -> SMCParam.KeyInfo? {
        var request = SMCParam()
        request.key = code
        request.command = SMCParam.readKeyInfo

        let info = call(request)?.keyInfo
        keyInfo[code] = info
        return info
    }

    private func call(_ request: SMCParam) -> SMCParam? {
        var request = request
        var response = SMCParam()
        let requestSize = MemoryLayout<SMCParam>.stride
        var responseSize = requestSize

        let status = IOConnectCallStructMethod(connection, SMCParam.handleEvent, &request, requestSize,
                                               &response, &responseSize)
        return status == kIOReturnSuccess && response.result == 0 ? response : nil
    }
}

/// The AppleSMC driver's 80-byte SMCKeyData_t; the padding field keeps Swift's layout equal to C's.
private struct SMCParam {
    static let handleEvent: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9

    struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PowerLimits {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var attributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var powerLimits = PowerLimits()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

    static func code(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
