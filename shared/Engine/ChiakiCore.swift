import Foundation

// Thin layer over libchiaki: one-time init, error mapping, logging and helpers for the fixed-size
// C arrays (imported as tuples) that the library uses for keys and names.

enum ChiakiError: Error, CustomStringConvertible {
    case code(ChiakiErrorCode, String)
    case timeout(String)
    case failed(String)

    var description: String {
        switch self {
        case .code(let code, let what):
            return "\(what): \(String(cString: chiaki_error_string(code)))"
        case .timeout(let what):
            return "\(what): tempo esgotado"
        case .failed(let what):
            return what
        }
    }
}

func chiakiCheck(_ err: ChiakiErrorCode, _ what: String) throws {
    if err != CHIAKI_ERR_SUCCESS { throw ChiakiError.code(err, what) }
}

enum ChiakiCore {
    private static let initialized: Bool = {
        chiaki_lib_init() == CHIAKI_ERR_SUCCESS
    }()

    /// Must run before any other library call. Safe to call many times.
    static func ensureInitialized() {
        precondition(initialized, "chiaki_lib_init failed")
    }
}

/// Owns a heap-allocated ChiakiLog (the library keeps the pointer) and forwards messages to `sink`.
final class ChiakiLogger {
    let pointer: UnsafeMutablePointer<ChiakiLog>
    var sink: (ChiakiLogLevel, String) -> Void

    init(verbose: Bool = false, sink: ((ChiakiLogLevel, String) -> Void)? = nil) {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: ChiakiLog())
        self.sink = sink ?? { level, message in
            let tag: String
            switch level {
            case CHIAKI_LOG_ERROR: tag = "ERRO"
            case CHIAKI_LOG_WARNING: tag = "AVISO"
            case CHIAKI_LOG_INFO: tag = "info"
            default: tag = "debug"
            }
            FileHandle.standardError.write(Data("[chiaki \(tag)] \(message)\n".utf8))
        }
        var mask = CHIAKI_LOG_ERROR.rawValue | CHIAKI_LOG_WARNING.rawValue | CHIAKI_LOG_INFO.rawValue
        if verbose { mask |= CHIAKI_LOG_VERBOSE.rawValue | CHIAKI_LOG_DEBUG.rawValue }
        chiaki_log_init(pointer, mask, { level, message, user in
            guard let user, let message else { return }
            let logger = Unmanaged<ChiakiLogger>.fromOpaque(user).takeUnretainedValue()
            logger.sink(level, String(cString: message))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func setLevel(verbose: Bool) {
        var mask = CHIAKI_LOG_ERROR.rawValue | CHIAKI_LOG_WARNING.rawValue | CHIAKI_LOG_INFO.rawValue
        if verbose { mask |= CHIAKI_LOG_VERBOSE.rawValue | CHIAKI_LOG_DEBUG.rawValue }
        chiaki_log_set_level(pointer, mask)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

// MARK: - Fixed-size C arrays (tuples) and hex

/// Raw bytes of any value, e.g. a `char name[0x20]` field imported as a tuple.
func bytes<T>(of value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}

/// A NUL-terminated `char[N]` tuple as a String.
func cString<T>(_ value: T) -> String {
    let raw = bytes(of: value)
    return String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
}

/// Copies `data` into a fixed-size tuple field, zero-padding the rest (the library wants "\0" padding).
func store<T>(_ data: [UInt8], into value: inout T) {
    withUnsafeMutableBytes(of: &value) { buffer in
        for i in 0..<buffer.count {
            buffer[i] = i < data.count ? data[i] : 0
        }
    }
}

func hexString(_ data: [UInt8]) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func hexBytes(_ string: String) -> [UInt8]? {
    let chars = Array(string.filter { !$0.isWhitespace && $0 != ":" })
    guard chars.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    out.reserveCapacity(chars.count / 2)
    var index = 0
    while index < chars.count {
        guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { return nil }
        out.append(byte)
        index += 2
    }
    return out
}
