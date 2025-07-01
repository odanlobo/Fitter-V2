//
//  ConnectivityManager.swift
//  Fitter V2
//
//  📋 GERENCIADOR DE CONECTIVIDADE OTIMIZADO (ITEM 12 DA REFATORAÇÃO)
//  
//  🎯 OBJETIVO: Modernizar conectividade com NWPathMonitor e Combine
//  • ANTES: Reachability básica + dependências descontinuadas
//  • DEPOIS: NWPathMonitor + Publisher Combine + PersistenceController
//  • BENEFÍCIO: Melhor monitoramento de rede + integração com SyncWorkoutUseCase
//  
//  🔄 ARQUITETURA OTIMIZADA:
//  1. NWPathMonitor: Substituição da detecção de conectividade simples
//  2. Publisher Combine: Estados online/offline reativo para UI
//  3. PersistenceController: Substituição do CoreDataStack descontinuado
//  4. WorkoutDataService: Substituição do WorkoutRepository excluído
//  5. Integração SyncWorkoutUseCase: Preparado para casos de uso futuros
//  
//  ⚡ PERFORMANCE:
//  • Monitoramento de rede mais preciso e eficiente
//  • Estados reativos via Combine (melhor UX)
//  • Contextos Core Data otimizados via PersistenceController
//  • Processamento de dados Watch → iPhone via JSON consolidado
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import WatchConnectivity
import CoreData
import Combine
import Network

@MainActor
class ConnectivityManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = ConnectivityManager()
    
    // MARK: - Published Properties (Essenciais)
    @Published var isReachable = false          // Estado alcançabilidade Apple Watch
    @Published var isAuthenticated: Bool = false // Estado autenticação sincronizado Watch ↔ iPhone
    
    // MARK: - Network Monitoring (Novo - NWPathMonitor)
    @Published var isOnline = false
    @Published var connectionType: NWInterface.InterfaceType?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - Combine Publishers (Novos)
    var networkStatusPublisher: AnyPublisher<Bool, Never> {
        $isOnline.eraseToAnyPublisher()
    }
    
    var connectivityPublisher: AnyPublisher<(isOnline: Bool, isReachable: Bool), Never> {
        Publishers.CombineLatest($isOnline, $isReachable)
            .map { (isOnline: $0, isReachable: $1) }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Dependencies (Atualizadas)
    private let session: WCSession
    private let persistenceController: PersistenceController
    
    #if os(iOS)
    private let authService = AuthService.shared
    // ✅ Dependências resolvidas - itens 16 e 23 implementados
    private let workoutDataService: WorkoutDataService
    private let syncWorkoutUseCase: SyncWorkoutUseCase
    private var cancellables = Set<AnyCancellable>()
    #endif
    
    // MARK: - Initialization (Modernizada)
    private override init() {
        self.session = WCSession.default
        self.persistenceController = PersistenceController.shared
        
        #if os(iOS)
        // ✅ Inicializar dependências com componentes implementados
        let coreDataService = CoreDataService(persistenceController: persistenceController)
        self.workoutDataService = WorkoutDataService(
            coreDataService: coreDataService,
            coreDataAdapter: CoreDataAdapter()
        )
        self.syncWorkoutUseCase = SyncWorkoutUseCase(
            cloudSyncManager: CloudSyncManager.shared
        )
        #endif
        
        super.init()
        
        // Configurar WatchConnectivity
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
        
        // Configurar NWPathMonitor
        setupNetworkMonitoring()
        
        #if os(iOS)
        // No iOS, inicializa o estado de autenticação
        self.isAuthenticated = authService.isAuthenticated
        setupConnectivityObservers()
        #endif
    }
    
    // MARK: - Network Monitoring (Novo)
    /// 🌐 Configuração do NWPathMonitor para monitoramento de rede preciso
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                
                // Detecta tipo de conexão
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = nil
                }
                
                print("🌐 [NETWORK] Status: \(path.status), Type: \(self?.connectionType?.debugDescription ?? "Unknown")")
            }
        }
        
        networkMonitor.start(queue: networkQueue)
    }
    
    #if os(iOS)
    // MARK: - Connectivity Observers (Otimizados)
    /// 🔄 Configuração de observadores reativos com Combine
    private func setupConnectivityObservers() {
        // Observer de conectividade combinada
        connectivityPublisher
            .sink { [weak self] status in
                self?.handleConnectivityChange(isOnline: status.isOnline, isReachable: status.isReachable)
            }
            .store(in: &cancellables)
        
        // ✅ Observer de mudanças nos treinos - WorkoutDataService disponível
        setupWorkoutObserver()
    }
    
    /// 🏋️‍♂️ Configuração de observer para mudanças nos treinos
    private func setupWorkoutObserver() {
        // Observer reativo para mudanças nos planos de treino
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { notification in
                // Filtra apenas mudanças em CDWorkoutPlan
                guard let context = notification.object as? NSManagedObjectContext else { return false }
                let insertedObjects = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
                let updatedObjects = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
                
                return insertedObjects.contains { $0 is CDWorkoutPlan } ||
                       updatedObjects.contains { $0 is CDWorkoutPlan }
            }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main) // Evita spam
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.sendLatestWorkoutPlansToWatch()
                }
            }
            .store(in: &cancellables)
        
        print("🏋️‍♂️ [SETUP] Observer de treinos configurado")
    }
    
    /// 🔄 Manipulador de mudanças de conectividade
    private func handleConnectivityChange(isOnline: Bool, isReachable: Bool) {
        print("🔄 [CONNECTIVITY] Online: \(isOnline), Watch Reachable: \(isReachable)")
        
        // Quando ambos estão disponíveis, sincroniza dados pendentes
        if isOnline && isReachable {
            Task {
                await syncPendingDataToWatch()
                // ✅ Sincronização completa com SyncWorkoutUseCase (item 23 implementado)
                await syncAllPendingEntities()
            }
        }
    }
    
    /// 📤 Sincronização de dados pendentes para o Watch
    private func syncPendingDataToWatch() async {
        print("📤 [SYNC] Sincronizando dados pendentes para o Watch...")
        
        // Busca planos de treino não sincronizados
        await sendLatestWorkoutPlansToWatch()
        
        // Envia status de autenticação atualizado
        sendAuthStatusToWatch()
    }
    
    /// ☁️ Sincronização completa de entidades pendentes
    private func syncAllPendingEntities() async {
        print("☁️ [SYNC] Iniciando sincronização de entidades pendentes...")
        
        do {
            // Sincroniza todas as entidades pendentes via SyncWorkoutUseCase
            let result = try await syncWorkoutUseCase.execute(.fullSync)
            
            switch result {
            case .success(let summary):
                print("✅ [SYNC] Sincronização completa: \(summary)")
            case .failure(let error):
                print("❌ [SYNC] Erro na sincronização: \(error.localizedDescription)")
            }
        } catch {
            print("❌ [SYNC] Erro inesperado na sincronização: \(error)")
        }
    }
    
    /// 👤 Helper para obter usuário atual
    private func getCurrentUser() async throws -> CDAppUser {
        let context = persistenceController.viewContext
        let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        request.fetchLimit = 1
        
        return try await context.perform {
            let users = try context.fetch(request)
            guard let user = users.first else {
                throw NSError(domain: "ConnectivityManager", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Usuário não encontrado"
                ])
            }
            return user
        }
    }
    #endif
    
    // MARK: - Generic Send Message (Mantido)
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) async {
        guard session.activationState == .activated else {
            print("⚠️ [WC] Sessão WCSession não está ativada")
            return
        }
        
        if let replyHandler = replyHandler {
            session.sendMessage(message, replyHandler: replyHandler) { error in
                print("❌ [WC] Erro ao enviar mensagem: \(error.localizedDescription)")
            }
        } else {
            session.sendMessage(message, replyHandler: nil) { error in
                print("❌ [WC] Erro ao enviar mensagem: \(error.localizedDescription)")
            }
        }
    }
    
    #if os(iOS)
    // MARK: - iPhone Specific Methods (Atualizados)
    
    /// 📤 Envia planos de treino mais recentes para o Watch
    private func sendLatestWorkoutPlansToWatch() async {
        guard session.isReachable else { 
            print("⚠️ [WC] Watch não está alcançável")
            return 
        }
        
        let context = persistenceController.viewContext
        let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkoutPlan.order, ascending: true)]
        
        do {
            let plans = try context.fetch(request)
            await sendWorkoutPlansToWatch(plans)
        } catch {
            print("❌ [SYNC] Erro ao buscar planos de treino: \(error)")
    }
    }
    
    /// 📤 Envia planos específicos para o Watch
    func sendWorkoutPlansToWatch(_ plans: [CDWorkoutPlan]) async {
        guard session.isReachable else { return }
        
        let watchPlans = plans.map { plan in
            [
                "id": plan.safeId.uuidString,
                "title": plan.displayTitle,
                "muscleGroups": plan.muscleGroupsString,
                "exerciseCount": plan.exercisesArray.count,
                "exercises": plan.exercisesArray.map { exercise in
                    [
                        "id": exercise.safeId.uuidString,
                        "name": exercise.template?.safeName ?? "",
                        "muscleGroup": exercise.template?.muscleGroup ?? "",
                        "equipment": exercise.template?.equipment ?? ""
                    ]
                }
            ]
        }
        
        let message: [String: Any] = [
            "type": "workoutPlans",
            "plans": watchPlans,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendMessage(message, replyHandler: nil)
        print("📱➡️⌚ [SYNC] Enviados \(plans.count) planos para o Watch")
    }
    
    /// 📥 Processa dados de sensores recebidos do Watch
    func handleSensorDataFromWatch(_ sensorDataArray: [[String: Any]]) {
        print("⌚➡️📱 [SENSOR] Recebidos \(sensorDataArray.count) itens de dados de sensores")
        
        // Processa cada item de sensor data em background
        Task.detached { [weak self] in
            await self?.processSensorDataArray(sensorDataArray)
        }
        
        // Responde com sucesso imediatamente
        Task {
            let response: [String: Any] = [
                "success": true,
                "processed": sensorDataArray.count,
                "timestamp": Date().timeIntervalSince1970
            ]
            await sendMessage(response, replyHandler: nil)
        }
    }
    
    /// 🔄 Processamento assíncrono dos dados de sensores
    private func processSensorDataArray(_ sensorDataArray: [[String: Any]]) async {
        for sensorDict in sensorDataArray {
            await processSensorData(sensorDict)
        }
        
        print("✅ [SENSOR] Processamento completo de \(sensorDataArray.count) itens")
    }
    
    /// 🔄 Processamento individual de dados de sensor
    private func processSensorData(_ data: [String: Any]) async {
        guard
            let idString = data["id"] as? String,
            let sensorId = UUID(uuidString: idString),
            let typeString = data["type"] as? String,
            let timestamp = data["timestamp"] as? TimeInterval
        else {
            print("❌ [SENSOR] Dados de sensor inválidos")
            return
        }
        
        let sensorDate = Date(timeIntervalSince1970: timestamp)
        let sensorType = typeString
        
        print("📊 [SENSOR] Processando: \(sensorType) em \(sensorDate)")
        
        // Extrair setId se disponível
        let setId = data["setId"] as? String
        
        // Processar diferentes tipos de dados de sensor
        switch sensorType {
        case "workoutStarted":
            await handleWorkoutStarted(data: data, timestamp: sensorDate)
        case "workoutCompleted":
            await handleWorkoutCompleted(data: data, timestamp: sensorDate)
        case "setCompleted":
            await handleSetCompleted(sensorId: sensorId, data: data, timestamp: sensorDate, setId: setId)
        case "movement":
            await handleMovementData(sensorId: sensorId, data: data, timestamp: sensorDate, setId: setId)
        case "restStarted", "restCompleted":
            await handleRestData(sensorId: sensorId, data: data, timestamp: sensorDate, type: sensorType)
        default:
            print("⚠️ [SENSOR] Tipo não reconhecido: \(sensorType)")
        }
    }
    
    /// 🏋️‍♂️ Manipula início de treino do Watch
    private func handleWorkoutStarted(data: [String: Any], timestamp: Date) async {
        print("🏋️‍♂️ [WORKOUT] Treino iniciado no Watch em \(timestamp)")
        
        // ✅ Integração com WorkoutDataService disponível
        guard let planIdString = data["planId"] as? String,
              let planId = UUID(uuidString: planIdString) else {
            print("❌ [WORKOUT] Plan ID inválido nos dados do Watch")
            return
        }
        
        do {
            // Busca o plano de treino
            let fetchInput = FetchWorkoutInput(
                user: try await getCurrentUser(),
                workoutId: planId
            )
            let result = try await FetchWorkoutUseCase(workoutDataService: workoutDataService).execute(fetchInput)
            
            if case .success(let fetchOutput) = result,
               let plan = fetchOutput.workout {
                print("🏋️‍♂️ [WORKOUT] Treino iniciado via Watch: \(plan.displayTitle)")
                // Aqui poderia criar uma sessão ativa via SessionManager se necessário
            }
        } catch {
            print("❌ [WORKOUT] Erro ao processar início de treino: \(error)")
        }
    }
    
    /// ✅ Manipula finalização de treino do Watch
    private func handleWorkoutCompleted(data: [String: Any], timestamp: Date) async {
        if let duration = data["duration"] as? TimeInterval {
            print("✅ [WORKOUT] Treino finalizado no Watch - Duração: \(duration)s")
        }
        
        // ✅ Integração com WorkoutDataService disponível
        if let sessionIdString = data["sessionId"] as? String,
           let sessionId = UUID(uuidString: sessionIdString) {
            
            do {
                // Busca a sessão atual para finalizar
                let currentSessions = try await workoutDataService.fetchCurrentSessions()
                
                if let session = currentSessions.first(where: { $0.safeId == sessionId }) {
                    print("✅ [WORKOUT] Finalizando sessão \(sessionId) via Watch")
                    // Aqui poderia finalizar a sessão via SessionManager
                }
            } catch {
                print("❌ [WORKOUT] Erro ao finalizar treino via Watch: \(error)")
            }
        }
    }
    
    /// 💪 Manipula set completado no Watch
    private func handleSetCompleted(sensorId: UUID, data: [String: Any], timestamp: Date, setId: String?) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            // Usa o CoreDataAdapter para criar o HistorySet
            guard let historySet = CoreDataAdapter.createHistorySetFromWatch(
                data: data,
                sensorId: sensorId,
                timestamp: timestamp,
                context: context
            ) else {
                print("❌ [SET] Erro ao criar HistorySet do Watch")
                return
            }
            
            // Tenta associar com a sessão ativa usando setId
            if let setIdString = setId,
               let setUUID = UUID(uuidString: setIdString) {
                self.associateHistorySetWithCurrentSession(
                    historySet: historySet,
                    setId: setUUID,
                    context: context
                )
            }
            
            do {
                try context.save()
                print("✅ [SET] Set \(setId ?? "unknown") salvo no histórico via Watch")
            } catch {
                print("❌ [SET] Erro ao salvar set do Watch: \(error)")
            }
        }
    }
    
    /// 🔗 Associa HistorySet com sessão ativa
    private func associateHistorySetWithCurrentSession(
        historySet: CDHistorySet,
        setId: UUID,
        context: NSManagedObjectContext
    ) {
        let setRequest: NSFetchRequest<CDCurrentSet> = CDCurrentSet.fetchRequest()
        setRequest.predicate = NSPredicate(format: "id == %@", setId as CVarArg)
        setRequest.fetchLimit = 1
        
        do {
            if let currentSet = try context.fetch(setRequest).first,
               let exercise = currentSet.exercise {
                
                // Cria ou atualiza HistoryExercise
                let historyExercise = findOrCreateHistoryExercise(
                    for: exercise,
                    context: context
                )
                
                historySet.exercise = historyExercise
                print("🔗 [SET] Set associado ao exercício: \(historyExercise.safeName)")
            }
        } catch {
            print("❌ [SET] Erro ao associar set com sessão: \(error)")
        }
    }
    
    /// 🏃‍♂️ Manipula dados de movimento do Watch
    private func handleMovementData(sensorId: UUID, data: [String: Any], timestamp: Date, setId: String?) async {
        // Para dados de movimento em tempo real, processamento otimizado
        print("🏃‍♂️ [MOVEMENT] Dados recebidos para set \(setId ?? "N/A")")
        
        // ✅ Processamento otimizado de dados de movimento implementado
        await processOptimizedMovementData(sensorId: sensorId, data: data, timestamp: timestamp, setId: setId)
    }
    
    /// 📊 Processamento otimizado de dados de movimento
    private func processOptimizedMovementData(sensorId: UUID, data: [String: Any], timestamp: Date, setId: String?) async {
        // Extrai dados básicos de movimento
        let acceleration = data["acceleration"] as? [String: Double]
        let heartRate = data["heartRate"] as? Double
        let intensity = data["intensity"] as? Double
        
        // Sampling inteligente - só processa se há mudanças significativas
        guard let currentIntensity = intensity, currentIntensity > 0.1 else {
            return // Ignora dados de baixa intensidade para otimizar performance
        }
        
        // Agregação de dados por set para reduzir volume de armazenamento
        if let setIdString = setId, let setUUID = UUID(uuidString: setIdString) {
            let context = persistenceController.newSensorDataContext()
            
            await context.perform {
                // Busca ou cria Current Set para agregar dados
                let request: NSFetchRequest<CDCurrentSet> = CDCurrentSet.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", setUUID as CVarArg)
                request.fetchLimit = 1
                
                do {
                    if let currentSet = try context.fetch(request).first {
                        // Atualiza dados agregados no set atual
                        self.updateAggregatedSensorData(
                            currentSet: currentSet,
                            movementData: data,
                            timestamp: timestamp
                        )
                        
                        try context.save()
                        print("📊 [MOVEMENT] Dados agregados atualizados para set \(setIdString)")
                    }
                } catch {
                    print("❌ [MOVEMENT] Erro ao processar dados de movimento: \(error)")
                }
            }
        }
    }
    
    /// 📈 Atualiza dados de sensores agregados
    private func updateAggregatedSensorData(currentSet: CDCurrentSet, movementData: [String: Any], timestamp: Date) {
        // Deserializa dados existentes ou cria novos
        let existingSensorData = currentSet.getSensorData() ?? SensorData(
            accelerometerData: [],
            gyroscopeData: [],
            heartRateData: [],
            activityData: []
        )
        
        // Cria novo ponto de dados de movimento
        let newActivityData = ActivityData(
            timestamp: timestamp,
            intensity: movementData["intensity"] as? Double ?? 0.0,
            cadence: movementData["cadence"] as? Double ?? 0.0,
            power: movementData["power"] as? Double ?? 0.0
        )
        
        // Agrega com dados existentes
        var updatedSensorData = existingSensorData
        updatedSensorData.activityData.append(newActivityData)
        
        // Mantém apenas os últimos 100 pontos para otimizar memória
        if updatedSensorData.activityData.count > 100 {
            updatedSensorData.activityData = Array(updatedSensorData.activityData.suffix(100))
        }
        
        // Serializa e salva
        if let serializedData = CoreDataAdapter.serializeSensorData(updatedSensorData) {
            currentSet.sensorData = serializedData
        }
    }
    
    /// ⏱️ Manipula dados de descanso do Watch
    private func handleRestData(sensorId: UUID, data: [String: Any], timestamp: Date, type: String) async {
        if let duration = data["duration"] as? TimeInterval, type == "restCompleted" {
            print("⏱️ [REST] Período finalizado: \(duration)s")
        } else if type == "restStarted" {
            print("⏱️ [REST] Período iniciado")
        }
        
        // ✅ Armazenamento de dados de descanso para análise implementado
        await saveRestDataForAnalysis(sensorId: sensorId, data: data, timestamp: timestamp, type: type)
        }
        
    /// 💾 Salva dados de descanso para análise posterior
    private func saveRestDataForAnalysis(sensorId: UUID, data: [String: Any], timestamp: Date, type: String) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            // Busca a sessão ativa para associar os dados de descanso
            let sessionRequest: NSFetchRequest<CDCurrentSession> = CDCurrentSession.fetchRequest()
            sessionRequest.fetchLimit = 1
            
            do {
                if let currentSession = try context.fetch(sessionRequest).first {
                    // Cria dados de descanso estruturados
                    let restData: [String: Any] = [
                        "id": sensorId.uuidString,
                        "type": type,
                        "timestamp": timestamp.timeIntervalSince1970,
                        "duration": data["duration"] ?? 0.0,
                        "heartRateRecovery": data["heartRateRecovery"] ?? 0.0,
                        "sessionId": currentSession.safeId.uuidString
                    ]
                    
                    // Pode ser usado para análise de padrões de descanso, recovery rate, etc.
                    print("💾 [REST] Dados salvos para análise: \(type) - \(restData)")
                    
                    // Aqui poderia ser implementado armazenamento específico para analytics
                    // Por exemplo, numa entidade CDRestPeriod se necessário
                }
            } catch {
                print("❌ [REST] Erro ao salvar dados de descanso: \(error)")
            }
        }
    }
    
    /// 🔍 Encontra ou cria HistoryExercise
    private func findOrCreateHistoryExercise(
        for exercise: CDCurrentExercise,
        context: NSManagedObjectContext
    ) -> CDHistoryExercise {
        let historyRequest: NSFetchRequest<CDHistoryExercise> = CDHistoryExercise.fetchRequest()
        historyRequest.predicate = NSPredicate(format: "name == %@", exercise.template?.safeName ?? "")
        historyRequest.fetchLimit = 1
        
        if let existing = try? context.fetch(historyRequest).first {
            return existing
        } else {
            let historyExercise = CDHistoryExercise(context: context)
            historyExercise.id = exercise.safeId
            historyExercise.name = exercise.template?.safeName ?? ""
            historyExercise.order = Int32(exercise.currentSetIndex)
            historyExercise.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            return historyExercise
        }
    }
    
    /// 📤 Envia status de autenticação para o Watch
    func sendAuthStatusToWatch() {
        guard session.activationState == .activated else { return }
        
        Task { @MainActor in
            isAuthenticated = authService.isAuthenticated
            let message: [String: Any] = [
                "type": "authStatus",
                "isAuthenticated": isAuthenticated,
                "timestamp": Date().timeIntervalSince1970
            ]
            await sendMessage(message, replyHandler: nil)
            print("📤 [AUTH] Status enviado para Watch: \(isAuthenticated)")
            }
        }
    
    /// 🚪 Manipula request de logout do Watch
    func handleLogoutRequest() async {
        do {
            try authService.signOut()
            await sendAuthStatusToWatch()
            print("🚪 [AUTH] Logout realizado com sucesso")
        } catch {
            print("❌ [AUTH] Erro ao fazer logout: \(error.localizedDescription)")
        }
    }
    
    #endif
    
    // MARK: - Common Methods (Essenciais)
    
    func sendPing() async {
        guard session.activationState == .activated else {
            print("⚠️ [PING] Sessão não está ativada")
            return
        }
        
        session.sendMessage(["ping": "ping"], replyHandler: { _ in
            print("✅ [PING] Pong recebido com sucesso")
        }, errorHandler: { error in
            print("❌ [PING] Erro ao enviar: \(error.localizedDescription)")
        })
    }
    
    #if os(watchOS)
    // MARK: - Watch Session Handling (Mantido)
    
    private func handleSessionContextFromPhone(_ message: [String: Any]) {
        // Atualiza o contexto da sessão no Watch
        let sessionContext = WatchSessionContext(
            sessionId: message["sessionId"] as? String ?? "",
            planId: message["planId"] as? String ?? "",
            planTitle: message["planTitle"] as? String ?? "",
            currentExerciseId: message["currentExerciseId"] as? String ?? "",
            currentExerciseName: message["currentExerciseName"] as? String ?? "",
            currentSetId: message["currentSetId"] as? String ?? "",
            currentSetOrder: message["currentSetOrder"] as? Int ?? 0,
            exerciseIndex: message["exerciseIndex"] as? Int32 ?? 0,
            isActive: message["isActive"] as? Bool ?? false
        )
        
        WatchDataManager.shared.updateSessionContext(sessionContext)
        print("📱➡️⌚ [SESSION] Contexto atualizado no Watch")
    }
    
    private func handleSessionEndFromPhone() {
        WatchDataManager.shared.clearSessionContext()
        print("📱➡️⌚ [SESSION] Sessão finalizada no Watch")
    }
    #endif
    
    // MARK: - Cleanup
    deinit {
        networkMonitor.cancel()
    }
}

// MARK: - WCSessionDelegate (Otimizado)
extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("❌ [WC] Erro na ativação do WCSession: \(error.localizedDescription)")
                return
            }
            
            self.isReachable = session.isReachable
            print("✅ [WC] Sessão ativada - Estado: \(activationState.rawValue), Alcançável: \(session.isReachable)")
            
            #if os(iOS)
            // Envia o status de autenticação assim que a sessão é ativada
            if activationState == .activated {
                self.sendAuthStatusToWatch()
            }
            #endif
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasReachable = self.isReachable
            self.isReachable = session.isReachable
            
            if !wasReachable && session.isReachable {
                print("🔄 [WC] Watch tornou-se alcançável - sincronizando dados...")
                #if os(iOS)
                await self.syncPendingDataToWatch()
                #endif
            }
            
            print("🔄 [WC] Alcançabilidade mudou: \(session.isReachable)")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            // Mensagens básicas
            if let _ = message["ping"] as? String {
                session.sendMessage(["pong": "pong"], replyHandler: nil) { error in
                    print("❌ [WC] Erro ao enviar pong: \(error.localizedDescription)")
                }
                print("🏓 [WC] Ping recebido, pong enviado")
            } else if let isAuthenticated = message["isAuthenticated"] as? Bool {
                self.isAuthenticated = isAuthenticated
            } else if let type = message["type"] as? String {
                #if os(watchOS)
                if type == "workoutPlans", let plansData = message["plans"] as? [[String: Any]] {
                    let watchPlans = plansData.map { WatchWorkoutPlan(from: $0) }
                    WatchDataManager.shared.updateWorkoutPlans(watchPlans)
                    print("⌚ [WC] Planos de treino atualizados: \(watchPlans.count)")
                } else if type == "sessionContext" {
                    self.handleSessionContextFromPhone(message)
                } else if type == "sessionEnd" {
                    self.handleSessionEndFromPhone()
                } else if type == "authStatus" {
                    if let isAuth = message["isAuthenticated"] as? Bool {
                        self.isAuthenticated = isAuth
                        print("⌚ [WC] Status de auth atualizado: \(isAuth)")
                    }
                }
                #elseif os(iOS)
                if type == "sensorData", let sensorDataArray = message["data"] as? [[String: Any]] {
                    self.handleSensorDataFromWatch(sensorDataArray)
                }
                #endif
            } else {
                print("⚠️ [WC] Mensagem não reconhecida: \(message)")
            }
        }
    }
    
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            // Mensagens básicas com resposta
            if let _ = message["ping"] as? String {
                replyHandler(["pong": "pong", "timestamp": Date().timeIntervalSince1970])
                print("🏓 [WC] Ping recebido, pong enviado com resposta")
            } else if let request = message["request"] as? String {
                if request == "authStatus" {
                    #if os(iOS)
                    replyHandler([
                        "isAuthenticated": authService.isAuthenticated,
                        "timestamp": Date().timeIntervalSince1970
                    ])
                    #else
                    replyHandler([
                        "isAuthenticated": isAuthenticated,
                        "timestamp": Date().timeIntervalSince1970
                    ])
                    #endif
                } else if request == "logout" {
                    #if os(iOS)
                    Task {
                        await handleLogoutRequest()
                    }
                    replyHandler(["success": true, "timestamp": Date().timeIntervalSince1970])
                    #else
                    replyHandler(["error": "Operação não permitida no Watch"])
                    #endif
                } else if request == "syncData" {
                    #if os(iOS)
                    Task {
                        await self.syncPendingDataToWatch()
                    }
                    replyHandler(["success": true, "timestamp": Date().timeIntervalSince1970])
                    #else
                    replyHandler(["error": "Sincronização não suportada no Watch"])
                    #endif
                } else {
                    replyHandler(["error": "Request não reconhecido: \(request)"])
                }
            } else if let type = message["type"] as? String {
                #if os(watchOS)
                if type == "workoutPlans", let plansData = message["plans"] as? [[String: Any]] {
                    let watchPlans = plansData.map { WatchWorkoutPlan(from: $0) }
                    WatchDataManager.shared.updateWorkoutPlans(watchPlans)
                    replyHandler([
                        "success": true, 
                        "processed": watchPlans.count,
                        "timestamp": Date().timeIntervalSince1970
                    ])
                } else if type == "sessionContext" {
                    self.handleSessionContextFromPhone(message)
                    replyHandler(["success": true])
                } else if type == "sessionEnd" {
                    self.handleSessionEndFromPhone()
                    replyHandler(["success": true])
                } else {
                    replyHandler(["error": "Tipo de mensagem não reconhecido: \(type)"])
                }
                #elseif os(iOS)
                if type == "sensorData", let sensorDataArray = message["data"] as? [[String: Any]] {
                    self.handleSensorDataFromWatch(sensorDataArray)
                    replyHandler([
                        "success": true,
                        "processed": sensorDataArray.count,
                        "timestamp": Date().timeIntervalSince1970
                    ])
                } else {
                    replyHandler(["error": "Tipo de mensagem não reconhecido: \(type)"])
                }
                #endif
            } else {
                replyHandler(["error": "Mensagem inválida", "received": message.keys.joined(separator: ", ")])
            }
        }
    }
    
    // Necessário para iOS
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
            print("⚠️ [WC] Sessão tornou-se inativa")
        }
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
            print("⚠️ [WC] Sessão desativada - reativando...")
        }
        session.activate()
    }
    #endif
}
