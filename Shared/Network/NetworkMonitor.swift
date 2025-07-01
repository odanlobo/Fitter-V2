//
//  NetworkMonitor.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
        
        var description: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "Celular"
            case .ethernet: return "Ethernet"
            case .unknown: return "Desconhecido"
            }
        }
    }
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(from: path) ?? .unknown
                
                if path.status == .satisfied {
                    print("📶 [NETWORK] Conectado via \(self?.connectionType.description ?? "unknown")")
                } else {
                    print("📵 [NETWORK] Desconectado")
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    private func getConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }
    
    deinit {
        monitor.cancel()
    }
} 