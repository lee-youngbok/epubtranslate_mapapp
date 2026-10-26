import Foundation

#if !arch(arm64)
#error("EPUBTranslator is engineered exclusively for Apple Silicon (arm64 architecture). Intel (x86_64) is not supported.")
#endif

/// Provides hardware information and diagnostics for Apple Silicon architecture
public struct AppleSiliconHardwareInfo: Sendable {

    public static let shared = AppleSiliconHardwareInfo()

    public let architecture: String = "arm64"
    public let chipName: String
    public let processorCount: Int
    public let activeCores: Int
    public let hasNeuralEngine: Bool = true

    public init() {
        self.processorCount = ProcessInfo.processInfo.processorCount
        self.activeCores = ProcessInfo.processInfo.activeProcessorCount
        self.chipName = Self.fetchCPUBrandString()
    }

    /// Read CPU brand string from sysctl on macOS or device identifier on iOS/iPadOS
    private static func fetchCPUBrandString() -> String {
        #if os(macOS)
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon (arm64)" }

        var brand = [CChar](repeating: 0, count: size)
        if sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0) == 0 {
            let rawStr = brand.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) } ?? ""
            }
            let str = rawStr.trimmingCharacters(in: .whitespacesAndNewlines)
            return str.isEmpty ? "Apple Silicon (arm64)" : str
        }
        return "Apple Silicon (arm64)"
        #else
        return "Apple Silicon (A-Series / M-Series)"
        #endif
    }
}
