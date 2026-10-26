import Foundation
import Network
import Observation

/// Monitors network connectivity state to inform the user about language pack download availability
/// and confirm 100% on-device offline translation readiness.
@Observable
@MainActor
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.example.EPUBTranslator.NetworkMonitor")

    var isConnected: Bool = true
    var isCellular: Bool = false
    var isExpensive: Bool = false

    var statusDescription: String {
        if isConnected {
            return "온라인 (온디바이스 언어팩 자동 다운로드 가능)"
        } else {
            return "오프라인 (100% 온디바이스 ANE 번역 동작)"
        }
    }

    var badgeText: String {
        isConnected ? "100% 온디바이스 (프라이버시)" : "오프라인 지원 (온디바이스)"
    }

    var badgeIcon: String {
        isConnected ? "lock.shield.fill" : "bolt.shield.fill"
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
                self?.isCellular = path.isExpensive
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
