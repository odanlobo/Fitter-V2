//
//  SessionManager.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import Combine
import CoreData

/// Gerenciador de sessões ativas do app
/// Controla o estado da sessão atual e coordena com Watch/Core Data
/// 
/// ⚠️ REFATORAÇÃO EM ANDAMENTO:
/// - Lógica de negócio será migrada para Use Cases futuros
/// - Estados reduzidos conforme Clean Architecture
/// 
/// ✅ ARQUITETURA LOGIN OBRIGATÓRIO:
/// - Usuário sempre disponível após login inicial
/// - Sessões sempre vinculadas ao usuário autenticado
/// - Ownership garantido em todas as operações
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    // MARK: - Estados simplificados
    @Published var currentSession: CDCurrentSession?
    @Published var isSessionActive: Bool = false
    
    // ✅ LOGIN OBRIGATÓRIO: Referência ao usuário atual (nunca nil após login)
    // TODO: Injetar via AuthService/BaseViewModel no futuro
    private var _currentUser: CDAppUser?
    
    // MARK: - Dependências atualizadas
    private var viewContext: NSManagedObjectContext {
        return PersistenceController.shared.viewContext
    }
    
    #if os(iOS)
    private let connectivityManager = ConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()
    #endif
    
    private init() {
        // Carrega sessão ativa existente
        loadActiveSession()
        
        #if os(iOS)
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
    
    // MARK: - Gerenciamento de Sessão
    // TODO: Migrar para StartWorkoutUseCase (item 16)
    /// Inicia uma nova sessão de treino
    func startSession(for user: CDAppUser, with plan: CDWorkoutPlan) -> Bool {
        // Verifica se já há uma sessão ativa
        guard currentSession == nil else {
            return false // Apenas uma sessão ativa por vez
        }
        
        // Cria nova sessão usando o método do CDAppUser
        guard let newSession = user.startWorkout(with: plan, context: viewContext) else {
            return false
        }
        
        // Salva no Core Data
        do {
            try viewContext.save()
            self.currentSession = newSession
            self.isSessionActive = true
            
            #if os(iOS)
            // Notifica o Watch sobre a nova sessão
            Task {
                await sendSessionContextToWatch()
            }
            #endif
            
            print("✅ Sessão iniciada para o plano: \(plan.displayTitle)")
            return true
        } catch {
            print("❌ Erro ao iniciar sessão: \(error)")
            return false
        }
    }
    
    // TODO: Migrar para EndWorkoutUseCase (item 25) ✅ **CONCLUÍDO**
    /// Finaliza a sessão atual
    func endSession() {
        guard let session = currentSession,
              let user = session.user else { return }
        
        // Usa o método do CDAppUser para finalizar
        user.endWorkout(context: viewContext)
        
        // Salva as mudanças
        do {
            try viewContext.save()
            print("✅ Sessão finalizada com sucesso")
        } catch {
            print("❌ Erro ao finalizar sessão: \(error)")
        }
        
        // Limpa o estado
        self.currentSession = nil
        self.isSessionActive = false
        
        #if os(iOS)
        // Notifica o Watch que a sessão acabou
        Task {
            await sendSessionEndToWatch()
        }
        #endif
    }
    
    // ❌ MÉTODOS REMOVIDOS: Violavam o fluxo granular
    // ✅ Use StartExerciseUseCase.executeNextExercise() para próximo exercício
    // ✅ Use EndExerciseUseCase.execute() seguido de StartExerciseUseCase para navegação
    // ✅ Use StartSetUseCase.execute() para iniciar séries (item 28)
    // ✅ Use EndSetUseCase.execute() para finalizar séries (item 29)
    //
    // 🔄 FLUXO GRANULAR CORRETO:
    // StartExerciseUseCase → [LOOP: StartSetUseCase → EndSetUseCase] → EndExerciseUseCase → (repetir ou EndWorkoutUseCase)
    
    // TODO: Migrar para UpdateSensorDataUseCase (futuro)
    /// Atualiza dados de sensores da série atual
    func updateSensorData(
        rotation: (x: Double, y: Double, z: Double),
        acceleration: (x: Double, y: Double, z: Double),
        gravity: (x: Double, y: Double, z: Double),
        attitude: (roll: Double, pitch: Double, yaw: Double)
    ) {
        currentSession?.currentExercise?.currentSet?.updateSensorData(
            rotationX: rotation.x, rotationY: rotation.y, rotationZ: rotation.z,
            accelerationX: acceleration.x, accelerationY: acceleration.y, accelerationZ: acceleration.z,
            gravityX: gravity.x, gravityY: gravity.y, gravityZ: gravity.z,
            attitudeRoll: attitude.roll, attitudePitch: attitude.pitch, attitudeYaw: attitude.yaw
        )
    }
    
    // TODO: Migrar para UpdateHealthDataUseCase (futuro)
    /// Atualiza dados fisiológicos da série atual
    func updateHealthData(heartRate: Int?, caloriesBurned: Double?) {
        currentSession?.currentExercise?.currentSet?.updateHealthData(
            heartRate: heartRate,
            caloriesBurned: caloriesBurned
        )
    }
    
    // MARK: - Métodos Privados
    
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
            }
        } catch {
            print("❌ Erro ao carregar sessão ativa: \(error)")
        }
    }
    
    #if os(iOS)
    // MARK: - Integração com Apple Watch
    
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
    
    /// Envia contexto atual da sessão para o Watch
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
            "currentSetId": session.currentExercise?.currentSet?.safeId.uuidString ?? "",
            "currentSetOrder": session.currentExercise?.currentSet?.order ?? 0,
            "exerciseIndex": session.currentExerciseIndex,
            "isActive": session.isActive
        ]
        
        await connectivityManager.sendMessage(sessionContext, replyHandler: nil)
        print("📱➡️⌚ Contexto da sessão enviado ao Watch")
    }
    
    /// Notifica o Watch sobre o fim da sessão
    private func sendSessionEndToWatch() async {
        let message: [String: Any] = [
            "type": "sessionEnd"
        ]
        
        await connectivityManager.sendMessage(message, replyHandler: nil)
        print("📱➡️⌚ Fim de sessão notificado ao Watch")
    }
    #endif
    
    // ✅ LOGIN OBRIGATÓRIO: Limpeza completa durante logout por inatividade
    func handleInactivityLogout() {
        if isSessionActive {
            print("🏋️‍♂️ Limpando sessão ativa devido ao logout por inatividade")
            endSession() // Finaliza sessão ativa automaticamente
        }
        
        // ✅ Limpa usuário atual conforme LOGIN OBRIGATÓRIO
        clearCurrentUser()
        print("🔒 SessionManager: Logout por inatividade concluído")
    }
}

// MARK: - Computed Properties
extension SessionManager {
    /// Exercício atual da sessão
    var currentExercise: CDCurrentExercise? {
        currentSession?.currentExercise
    }
    
    /// Série atual do exercício
    var currentSet: CDCurrentSet? {
        currentSession?.currentExercise?.currentSet
    }
    
    /// Plano de treino da sessão atual
    var currentPlan: CDWorkoutPlan? {
        currentSession?.plan
    }
    
    /// Usuário atual autenticado
    /// ✅ LOGIN OBRIGATÓRIO: Nunca nil após login inicial (sessão persistente)
    /// ⚠️ Durante refatoração: usa currentSession.user como fallback
    /// TODO: Migrar para AuthService.currentUser no item 34
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
            "currentSetId": session.currentExercise?.currentSet?.safeId.uuidString ?? "",
            "currentSetOrder": session.currentExercise?.currentSet?.order ?? 0,
            "exerciseIndex": session.currentExerciseIndex,
            "isActive": session.isActive
        ]
    }
    #endif
} 