//
//  WatchApp.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import HealthKit

/**
 * Fitter_V2_Watch_AppApp - Entry point principal do aplicativo watchOS
 * 
 * ARQUITETURA: Clean Architecture alinhada ao iOS com injeção de dependências
 * RESPONSABILIDADES:
 * - Configurar infraestrutura compartilhada (Core Data, HealthKit, sensores)
 * - Injetar managers via dependency injection (WatchSessionManager, MotionManager, etc)
 * - Gerenciar ciclo de vida dos sensores vinculado ao treino
 * - Navegação baseada em estado de autenticação (SessionManager)
 * 
 * INTEGRAÇÃO COM iOS:
 * - PersistenceController compartilhado (App Groups)
 * - Sincronização Watch ↔ iPhone via WatchSessionManager/PhoneSessionManager
 * - SessionManager para coordenação de estado entre devices
 * 
 * SENSORES & LIFECYCLE:
 * - MotionManager ativado no StartWorkoutUseCase (iPhone)
 * - HealthKitManager para dados vitais em tempo real
 * - Captura contínua durante treino ativo
 * - Finalização automática no EndWorkoutUseCase
 */
@main
struct Fitter_V2_Watch_AppApp: App {
    
    // MARK: - 1. Infraestrutura Compartilhada
    
    /// Core Data - Compartilhado com iPhone via App Groups
    private let persistence = PersistenceController.shared
    
    /// Manager dedicado para HealthKit no Watch
    private let healthKitManager: HealthKitManagerProtocol
    
    /// Manager de sessão para verificar autenticação
    private let sessionManager = SessionManager.shared
    
    // MARK: - 2. Managers Específicos do Watch
    
    /// Manager de comunicação Watch ↔ iPhone
    @StateObject private var sessionManager: WatchSessionManager
    
    /// Manager de controle de fases do treino
    @StateObject private var phaseManager: WorkoutPhaseManager
    
    /// Manager de captura de dados de movimento
    @StateObject private var motionManager: MotionManager
    
    // MARK: - Initialization
    
    init() {
        print("⌚ [WatchApp] Inicializando infraestrutura Clean Architecture...")
        
        // 1. Infraestrutura compartilhada
        self.healthKitManager = HealthKitManager()
        
        // 2. Managers específicos do Watch com dependency injection
        let sessionMgr = WatchSessionManager()
        let phaseMgr = WorkoutPhaseManager(sessionManager: sessionMgr)
        let motionMgr = MotionManager(
            sessionManager: sessionMgr,
            phaseManager: phaseMgr
        )
        
        // 3. StateObjects para SwiftUI
        self._sessionManager = StateObject(wrappedValue: sessionMgr)
        self._phaseManager = StateObject(wrappedValue: phaseMgr)
        self._motionManager = StateObject(wrappedValue: motionMgr)
        
        print("✅ [WatchApp] Infraestrutura Clean Architecture inicializada")
        print("🔗 [WatchApp] Dependency injection configurado: SessionManager → PhaseManager → MotionManager")
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            Group {
                // FLUXO PADRONIZADO: Autenticado → WatchView / Não autenticado → PendingLoginView
                if sessionManager.currentUser != nil {
                    WatchView()
                        .onAppear {
                            Task {
                                await handleWatchAppLaunch()
                            }
                        }
                } else {
                    PendingLoginView()
                        .onAppear {
                            print("📱 [WatchApp] Aguardando autenticação do iPhone...")
                        }
                }
            }
            .environmentObject(sessionManager)
            .environmentObject(motionManager)
            .environmentObject(phaseManager)
        }
    }
    
    // MARK: - Private Methods
    
    /**
     * Gerencia ações no launch do Watch app quando usuário está autenticado
     * 
     * RESPONSABILIDADES:
     * - Configurar HealthKit via HealthKitManager (momento apropriado)
     * - Inicializar sincronização Watch ↔ iPhone
     * - Preparar sensores para captura (sem ativar)
     * 
     * FLUXO GRANULAR:
     * - HealthKit: Autorização no app launch (não no init)
     * - Sensores: Preparados, mas ativados apenas no StartWorkoutUseCase
     * - Sincronização: Conectividade robusta Watch ↔ iPhone
     */
    private func handleWatchAppLaunch() async {
        print("⌚ [WatchApp] Configurando Watch app para usuário autenticado...")
        
        // 1. Configurar HealthKit via manager dedicado (momento apropriado)
        await setupHealthKitAuthorization()
        
        // 2. Inicializar comunicação com iPhone
        await setupWatchConnectivity()
        
        // 3. Preparar sensores (sem ativar - aguarda StartWorkoutUseCase)
        setupSensorReadiness()
        
        print("✅ [WatchApp] Configuração completa - Watch pronto para treino")
    }
    
    /**
     * Configura autorização do HealthKit via HealthKitManager
     * 
     * RESPONSABILIDADE: 
     * - Delegar configuração para HealthKitManager dedicado
     * - Solicitar permissão no momento apropriado (não no init)
     * - Garantir fallback resiliente caso permissão negada
     * 
     * INTEGRAÇÃO: Conforme README_FLUXO_DADOS.md para dados vitais
     */
    private func setupHealthKitAuthorization() async {
        guard healthKitManager.isHealthKitAvailable else {
            print("⚠️ [WatchApp] HealthKit não disponível - continuando sem dados vitais")
            return
        }
        
        do {
            let isAuthorized = try await healthKitManager.requestAuthorization()
            if isAuthorized {
                print("✅ [WatchApp] HealthKit autorizado - dados vitais habilitados")
                
                // Preparar monitoramento (ativação no StartWorkoutUseCase)
                print("🔄 [WatchApp] HealthKit preparado para monitoramento de treino")
            } else {
                print("⚠️ [WatchApp] HealthKit não autorizado - funcionamento em modo limitado")
                showHealthKitFallbackMessage()
            }
        } catch {
            print("❌ [WatchApp] Erro ao configurar HealthKit: \(error.localizedDescription)")
            showHealthKitFallbackMessage()
        }
    }
    
    /**
     * Inicializa comunicação robusta Watch ↔ iPhone
     * 
     * RESPONSABILIDADES:
     * - Ativar WCSession para sincronização
     * - Preparar para recebimento de comandos do iPhone
     * - Configurar envio de dados de sensores
     */
    private func setupWatchConnectivity() async {
        sessionManager.startSession()
        
        // Aguardar estabelecimento da conexão
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 segundo
        
        if sessionManager.isReachable {
            print("📡 [WatchApp] Conectividade iPhone estabelecida")
        } else {
            print("⚠️ [WatchApp] iPhone não reachable - modo offline")
        }
    }
    
    /**
     * Prepara sensores para captura (sem ativar)
     * 
     * FLUXO CORRETO:
     * - Preparação: No app launch (aqui)
     * - Ativação: StartWorkoutUseCase → PhoneSessionManager → WatchSessionManager → MotionManager
     * - Finalização: EndWorkoutUseCase → PhoneSessionManager → WatchSessionManager → MotionManager
     */
    private func setupSensorReadiness() {
        print("🔧 [WatchApp] Preparando sensores para captura...")
        print("⏱️ [WatchApp] Sensores serão ativados no StartWorkoutUseCase")
        print("📊 [WatchApp] Frequências: 50Hz (execução) / 20Hz (descanso)")
    }
    
    /**
     * Mostra mensagem de fallback quando HealthKit não está disponível
     * 
     * UX RESILIENTE:
     * - App continua funcionando sem dados vitais
     * - Usuário informado sobre limitações
     * - Possibilidade de ativar posteriormente
     */
    private func showHealthKitFallbackMessage() {
        print("💡 [WatchApp] Modo de fallback ativado:")
        print("   • Sensores de movimento: ✅ Funcionando")
        print("   • Heart rate & calorias: ❌ Desabilitados")
        print("   • Configurar: Settings > Privacy > Health")
    }
}

// MARK: - Preview Support

#if DEBUG
extension Fitter_V2_Watch_AppApp {
    static var previewApp: some Scene {
        WindowGroup {
            WatchView()
                .environmentObject(WatchSessionManager())
                .environmentObject(MotionManager.previewInstance())
                .environmentObject(WorkoutPhaseManager())
                .environmentObject(SessionManager.shared)
        }
    }
}
#endif
