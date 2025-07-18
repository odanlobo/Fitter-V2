//
//  ConnectivityManager.swift
//  Fitter V2
//
//  📋 GERENCIADOR DE CONECTIVIDADE REFATORADO (ITEM 43.3 DA REFATORAÇÃO)
//  
//  🎯 OBJETIVO: Remover toda lógica WCSession e manter apenas monitoramento de rede
//  • ANTES: WCSession + processamento de dados + sincronização de treinos
//  • DEPOIS: Apenas NWPathMonitor + estados de conectividade
//  • BENEFÍCIO: Responsabilidades claras, sem duplicação com WatchSessionManager/PhoneSessionManager
//  
//  🔄 ARQUITETURA LIMPA:
//  1. NWPathMonitor: Monitoramento de rede (WiFi/Cellular/Ethernet)
//  2. Publisher Combine: Estados online/offline reativo para UI
//  3. Sem WCSession: Delegado para WatchSessionManager/PhoneSessionManager
//  4. Sem processamento: Delegado para Use Cases específicos
//  5. Foco único: Status de conectividade de rede
//  
//  ⚡ RESPONSABILIDADES REMOVIDAS:
//  • Comunicação Watch-iPhone → WatchSessionManager/PhoneSessionManager
//  • Processamento de dados de sensores → Use Cases específicos
//  • Sincronização de treinos → CloudSyncManager
//  • Gerenciamento de sessão Watch → WatchSessionManager
//  • Processamento de mensagens → PhoneSessionManager
//
//  Created by Daniel Lobo on 13/05/25.
//  Refatorado em 15/12/25 - ITEM 43.3 ✅
//

import Foundation
import Network
import Combine

/// Erros específicos para ConnectivityManager
enum ConnectivityError: LocalizedError {
    case networkUnavailable
    case monitoringFailed(Error)
    case invalidNetworkType
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Rede não disponível"
        case .monitoringFailed(let error):
            return "Falha no monitoramento: \(error.localizedDescription)"
        case .invalidNetworkType:
            return "Tipo de rede inválido"
        }
    }
}

/// Tipos de conectividade de rede
enum NetworkType: String, CaseIterable {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case unknown = "Unknown"
    case unavailable = "Unavailable"
    
    var isConnected: Bool {
        self != .unavailable
    }
    
    var isReachable: Bool {
        self == .wifi || self == .cellular || self == .ethernet
    }
}

/// Protocolo para ConnectivityManager
protocol ConnectivityManagerProtocol: AnyObject {
    var isConnected: Bool { get }
    var networkType: NetworkType { get }
    var isReachable: Bool { get }
    
    func startMonitoring() async
    func stopMonitoring() async
    func checkConnectivity() async throws -> Bool
}

/// Gerenciador de conectividade de rede
/// 
/// Responsabilidades:
/// - Monitoramento de conectividade de rede (WiFi/Cellular/Ethernet)
/// - Estados online/offline reativo para UI
/// - Sem WCSession (delegado para WatchSessionManager/PhoneSessionManager)
/// - Sem processamento (delegado para Use Cases específicos)
/// 
/// ⚡ Clean Architecture:
/// - Implementa NWPathMonitor
/// - Delega comunicação para WatchSessionManager/PhoneSessionManager
/// - Delega processamento para Use Cases específicos
/// - Foco apenas em status de conectividade de rede
@MainActor
final class ConnectivityManager: ConnectivityManagerProtocol {
    
    // MARK: - Published Properties
    
    /// Indica se há conectividade de rede
    @Published private(set) var isConnected: Bool = false
    
    /// Tipo de rede atual
    @Published private(set) var networkType: NetworkType = .unavailable
    
    /// Indica se a rede está alcançável
    @Published private(set) var isReachable: Bool = false
    
    // MARK: - Private Properties
    
    /// Monitor de caminho de rede
    private let pathMonitor = NWPathMonitor()
    
    /// Fila para operações de monitoramento
    private let monitorQueue = DispatchQueue(label: "ConnectivityMonitor", qos: .utility)
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Logger para debug
    private let logger = Logger(subsystem: "com.fitter.app", category: "ConnectivityManager")
    
    // MARK: - Initialization
    
    init() {
        setupPathMonitorSync()
        print("🌐 ConnectivityManager inicializado")
    }
    
    deinit {
        // Operação síncrona para cleanup no deinit
        pathMonitor.cancel()
        cancellables.removeAll()
        print("🛑 ConnectivityManager deinitializado")
    }
    
    // MARK: - Public Methods
    
    /// Inicia o monitoramento de conectividade
    func startMonitoring() async {
        guard pathMonitor.pathUpdateHandler == nil else {
            logger.info("⚠️ Monitoramento já está ativo")
            return
        }
        
        await setupPathMonitorHandler()
        pathMonitor.start(queue: monitorQueue)
        logger.info("🔄 Monitoramento de conectividade iniciado")
    }
    
    /// Para o monitoramento de conectividade
    func stopMonitoring() async {
        pathMonitor.cancel()
        logger.info("🛑 Monitoramento de conectividade parado")
    }
    
    /// Verifica conectividade de forma assíncrona
    func checkConnectivity() async throws -> Bool {
        return await withCheckedContinuation { continuation in
            pathMonitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in
                    let isConnected = path.status == .satisfied
                    continuation.resume(returning: isConnected)
                    self?.pathMonitor.pathUpdateHandler = nil
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Configura o monitor de caminho de rede (versão síncrona para init)
    private func setupPathMonitorSync() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.handlePathUpdate(path)
            }
        }
    }
    
    /// Configura o monitor de caminho de rede (versão async para startMonitoring)
    private func setupPathMonitorHandler() async {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.handlePathUpdate(path)
            }
        }
    }
    
    /// Processa atualização do caminho de rede
    private func handlePathUpdate(_ path: NWPath) async {
        let wasConnected = isConnected
        let wasReachable = isReachable
        let oldNetworkType = networkType
        
        // Atualiza estado de conectividade
        isConnected = path.status == .satisfied
        isReachable = path.status == .satisfied
        
        // Determina tipo de rede
        networkType = determineNetworkType(path)
        
        // Log de mudanças
        if isConnected != wasConnected {
            logger.info("🌐 Conectividade alterada: \(isConnected ? "Conectado" : "Desconectado")")
        }
        
        if networkType != oldNetworkType {
            logger.info("📡 Tipo de rede alterado: \(networkType.rawValue)")
        }
        
        if isReachable != wasReachable {
            logger.info("📶 Alcance alterado: \(isReachable ? "Alcançável" : "Inalcançável")")
        }
        
        // Notifica mudanças para UI
        notifyConnectivityChange()
    }
    
    /// Determina o tipo de rede baseado no caminho
    private func determineNetworkType(_ path: NWPath) -> NetworkType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.status == .satisfied {
            return .unknown
        } else {
            return .unavailable
        }
    }
    
    /// Notifica mudanças de conectividade
    private func notifyConnectivityChange() {
        // Publica mudanças via Combine (já configurado via @Published)
        logger.info("📢 Mudança de conectividade notificada: \(networkType.rawValue)")
    }
}

// MARK: - Shared Instance

extension ConnectivityManager {
    /// Instância compartilhada do ConnectivityManager
    static let shared = ConnectivityManager()
}

// MARK: - Convenience Extensions

extension ConnectivityManager {
    
    /// Verifica se está conectado via WiFi
    var isWiFiConnected: Bool {
        return networkType == .wifi && isConnected
    }
    
    /// Verifica se está conectado via Cellular
    var isCellularConnected: Bool {
        return networkType == .cellular && isConnected
    }
    
    /// Verifica se está conectado via Ethernet
    var isEthernetConnected: Bool {
        return networkType == .ethernet && isConnected
    }
    
    /// Retorna descrição da conectividade atual
    var connectivityDescription: String {
        if !isConnected {
            return "Sem conectividade"
        }
        
        switch networkType {
        case .wifi:
            return "Conectado via WiFi"
        case .cellular:
            return "Conectado via Cellular"
        case .ethernet:
            return "Conectado via Ethernet"
        case .unknown:
            return "Conectado (tipo desconhecido)"
        case .unavailable:
            return "Sem conectividade"
        }
    }
}

// MARK: - Logger

private struct Logger {
    private let subsystem: String
    private let category: String
    
    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
    
    func info(_ message: String) {
        print("🌐 [\(category)] \(message)")
    }
    
    func warning(_ message: String) {
        print("⚠️ [\(category)] \(message)")
    }
    
    func error(_ message: String) {
        print("❌ [\(category)] \(message)")
    }
}

#if DEBUG
// MARK: - Preview Support
extension ConnectivityManager {
    
    /// Cria instância para preview
    /// - Returns: ConnectivityManager configurado para preview
    static func previewInstance() -> ConnectivityManager {
        let manager = ConnectivityManager()
        manager.isConnected = true
        manager.networkType = .wifi
        manager.isReachable = true
        return manager
    }
}
#endif 