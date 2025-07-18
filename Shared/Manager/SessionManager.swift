//
//  SessionManager.swift
//  Fitter V2
//
//  RESPONSABILIDADE: Coordenador de estado de sessão (Watch/iPhone)
//  ARQUITETURA: Clean Architecture - apenas estado, sem lógica de negócio
//  INTEGRAÇÃO: Use Cases fazem operações, SessionManager observa estado
//

import Foundation
import Combine
import CoreData

/// Coordenador de estado de sessões ativas do app
/// 
/// **Responsabilidades REDUZIDAS (Clean Architecture):**
/// - Observar estado da sessão atual
/// - Coordenar comunicação com Watch
/// - Gerenciar usuário autenticado
/// - Logout por inatividade
/// 
/// **❌ NÃO FAZ MAIS:**
/// - Operações CRUD (delegadas para Use Cases)
/// - Persistência direta (delegada para WorkoutDataService)
/// - Lógica de negócio (delegada para Use Cases)
/// 
/// **✅ FLUXO CORRETO:**
/// - Use Cases executam operações
/// - SessionManager observa mudanças
/// - SessionManager sincroniza com Watch
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    // MARK: - Estados Observados (Read-Only)
    @Published private(set) var currentSession: CDCurrentSession?
    @Published private(set) var isSessionActive: Bool = false
    
    // ✅ LOGIN OBRIGATÓRIO: Referência ao usuário atual (nunca nil após login)
    private var _currentUser: CDAppUser?
    
    // MARK: - Dependências (Observação apenas)
    private var viewContext: NSManagedObjectContext {
        return PersistenceController.shared.viewContext
    }
    
    #if os(iOS)
    private let phoneSessionManager: PhoneSessionManager
    private var cancellables = Set<AnyCancellable>()
    #endif
    
    private init() {
        #if os(iOS)
        // Configurar dependências para PhoneSessionManager
        let coreDataService = CoreDataService()
        let workoutDataService = WorkoutDataService(coreDataService: coreDataService)
        let syncWorkoutUseCase = SyncWorkoutUseCase()
        let updateDataToMLUseCase = UpdateDataToMLUseCase(
            mlModelManager: MLModelManager(),
            subscriptionManager: SubscriptionManager.shared
        )
        
        phoneSessionManager = PhoneSessionManager(
            coreDataService: coreDataService,
            workoutDataService: workoutDataService,
            syncWorkoutUseCase: syncWorkoutUseCase,
            updateDataToMLUseCase: updateDataToMLUseCase
        )
        #endif
        
        // Carrega sessão ativa existente
        loadActiveSession()
        
        #if os(iOS)
        phoneSessionManager.startSession()
        setupSessionObserver()
        #endif
    }
    
    // MARK: - Configuração LOGIN OBRIGATÓRIO
    
    /// Configura usuário atual (chamado após login bem-sucedido)
    /// ✅ LOGIN OBRIGATÓRIO: Garante que usuário nunca seja nil
    /// - Parameter user: Usuário autenticado (obrigatório)
    func setCurrentUser(_ user: CDAppUser) {
        _currentUser = user
        print("✅ SessionManager: Usuário configurado - \(user.safeName)")
    }
    
    /// Limpa usuário atual (chamado durante logout)
    /// ⚠️ Usado apenas durante logout manual ou por inatividade
    func clearCurrentUser() {
        _currentUser = nil
        print("🔒 SessionManager: Usuário limpo")
    }
    
    // MARK: - Observação de Estado (Read-Only)
    
    /// Atualiza estado da sessão (chamado pelos Use Cases)
    /// ✅ Use Cases fazem operações, SessionManager observa resultado
    /// - Parameter session: Nova sessão ativa ou nil se finalizada
    func updateSessionState(_ session: CDCurrentSession?) {
        currentSession = session
        isSessionActive = session?.isActive ?? false
        
        #if os(iOS)
        // Notifica o Watch sobre mudança de estado
        Task {
            await sendSessionContextToWatch()
        }
        #endif
        
        let status = session?.isActive == true ? "ativa" : "finalizada"
        print("🔄 SessionManager: Estado atualizado - Sessão \(status)")
    }
    
    /// Recarrega sessão do Core Data (usado após mudanças externas)
    /// ✅ Use Cases podem chamar para sincronizar estado
    func refreshSessionState() {
        loadActiveSession()
    }
    
    // MARK: - Métodos Privados (Observação)
    
    /// Carrega sessão ativa se existir na inicialização
    private func loadActiveSession() {
        let request: NSFetchRequest<CDCurrentSession> = CDCurrentSession.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == true")
        request.fetchLimit = 1
        
        do {
            if let activeSession = try viewContext.fetch(request).first {
                self.currentSession = activeSession
                self.isSessionActive = true
                
                #if os(iOS)
                // Se há uma sessão ativa ao carregar, notifica o Watch
                Task {
                    await sendSessionContextToWatch()
                }
                #endif
                
                print("✅ Sessão ativa carregada: \(activeSession.plan?.displayTitle ?? "Sem nome")")
            } else {
                self.currentSession = nil
                self.isSessionActive = false
            }
        } catch {
            print("❌ Erro ao carregar sessão ativa: \(error)")
        }
    }
    
    #if os(iOS)
    // MARK: - Integração com Apple Watch (Notificação apenas)
    
    /// Configura observador para mudanças na sessão
    private func setupSessionObserver() {
        // Observa mudanças na sessão para notificar o Watch
        $currentSession
            .sink { [weak self] session in
                Task { @MainActor in
                    await self?.sendSessionContextToWatch()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Envia contexto atual da sessão para o Watch (notificação apenas)
    private func sendSessionContextToWatch() async {
        guard let session = currentSession else {
            await sendSessionEndToWatch()
            return
        }
        
        let sessionContext: [String: Any] = [
            "type": "sessionContext",
            "sessionId": session.safeId.uuidString,
            "planId": session.plan?.safeId.uuidString ?? "",
            "planTitle": session.plan?.displayTitle ?? "",
            "currentExerciseId": session.currentExercise?.safeId.uuidString ?? "",
            "currentExerciseName": session.currentExercise?.template?.safeName ?? "",
            "currentSetId": session.currentExercise?.activeSet?.safeId.uuidString ?? "",
            "currentSetOrder": session.currentExercise?.activeSet?.order ?? 0,
            "exerciseIndex": session.currentExerciseIndex,
            "isActive": session.isActive
        ]
        
        do {
            try await phoneSessionManager.updateApplicationContext(sessionContext)
            print("📱➡️⌚ Contexto da sessão enviado ao Watch")
        } catch {
            print("❌ Erro ao enviar contexto da sessão para o Watch: \(error)")
        }
    }
    
    /// Notifica o Watch sobre o fim da sessão
    private func sendSessionEndToWatch() async {
        let message: [String: Any] = [
            "type": "sessionEnd"
        ]
        
        do {
            try await phoneSessionManager.updateApplicationContext(message)
            print("📱➡️⌚ Fim de sessão notificado ao Watch")
        } catch {
            print("❌ Erro ao notificar fim de sessão para o Watch: \(error)")
        }
    }
    #endif
    
    // ✅ LOGIN OBRIGATÓRIO: Limpeza completa durante logout por inatividade
    func handleInactivityLogout() {
        if isSessionActive {
            print("🏋️‍♂️ Sessão ativa detectada durante logout por inatividade")
            print("⚠️ Use EndWorkoutUseCase para finalizar sessão antes do logout")
            // SessionManager não executa mais operações - apenas observa
        }
        
        // ✅ Limpa usuário atual conforme LOGIN OBRIGATÓRIO
        clearCurrentUser()
        print("🔒 SessionManager: Logout por inatividade concluído")
    }
}

// MARK: - Computed Properties (Read-Only)
extension SessionManager {
    /// Exercício atual da sessão
    var currentExercise: CDCurrentExercise? {
        currentSession?.currentExercise
    }
    
    /// Série atual do exercício
    var currentSet: CDCurrentSet? {
        currentSession?.currentExercise?.activeSet
    }
    
    /// Plano de treino da sessão atual
    var currentPlan: CDWorkoutPlan? {
        currentSession?.plan
    }
    
    /// Usuário atual autenticado
    /// ✅ LOGIN OBRIGATÓRIO: Nunca nil após login inicial (sessão persistente)
    /// ✅ MIGRADO: Integra com AuthUseCase (item 47 concluído)
    var currentUser: CDAppUser! {
        return _currentUser ?? currentSession?.user
    }
    
    #if os(iOS)
    /// Contexto da sessão formatado para o Watch
    var sessionContextForWatch: [String: Any]? {
        guard let session = currentSession else { return nil }
        
        return [
            "sessionId": session.safeId.uuidString,
            "planId": session.plan?.safeId.uuidString ?? "",
            "planTitle": session.plan?.displayTitle ?? "",
            "currentExerciseId": session.currentExercise?.safeId.uuidString ?? "",
            "currentExerciseName": session.currentExercise?.template?.safeName ?? "",
            "currentSetId": session.currentExercise?.activeSet?.safeId.uuidString ?? "",
            "currentSetOrder": session.currentExercise?.activeSet?.order ?? 0,
            "exerciseIndex": session.currentExerciseIndex,
            "isActive": session.isActive
        ]
    }
    #endif
}

// MARK: - CloudSyncManager Async Adapter

/// Adapter assíncrono para usar CloudSyncManager actor em contextos MainActor
final class CloudSyncManagerAsyncAdapter: CloudSyncManagerProtocol {
    private let cloudSyncManager: CloudSyncManager
    
    init(cloudSyncManager: CloudSyncManager) {
        self.cloudSyncManager = cloudSyncManager
    }
    
    func scheduleUpload(entityId: UUID) async {
        await cloudSyncManager.scheduleUpload(entityId: entityId)
    }
    
    func scheduleUpload(for user: CDAppUser) async {
        await cloudSyncManager.scheduleUpload(for: user)
    }
    
    func scheduleDeletion(entityId: UUID) async {
        await cloudSyncManager.scheduleDeletion(entityId: entityId)
    }
    
    func syncPendingChanges() async {
        await cloudSyncManager.syncPendingChanges()
    }
}



// MARK: - Extension for SubscriptionManager.shared access
extension SubscriptionManager {
    /// Instância compartilhada do SubscriptionManager
    /// ✅ Para compatibilidade enquanto a injeção de dependência completa não está configurada
    static let shared: SubscriptionManager = {
        let coreDataService = CoreDataService()
        let revenueCatService = RevenueCatService()
        // Usar adapter assíncrono para CloudSyncManager actor
        let cloudSyncManager = CloudSyncManagerAsyncAdapter(cloudSyncManager: CloudSyncManager.shared)
        
        return SubscriptionManager(
            revenueCatService: revenueCatService,
            cloudSyncManager: cloudSyncManager,
            coreDataService: coreDataService
        )
    }()
}


