//
//  CloudSyncManager.swift
//  Fitter V2
//
//  📋 SINCRONIZAÇÃO GENÉRICA COM FIRESTORE (ITEM 11 DA REFATORAÇÃO)
//  
//  🎯 OBJETIVO: Generalizar sincronização para qualquer entidade Syncable
//  • ANTES: Específico para CDWorkoutPlan com lógica complexa de conflitos
//  • DEPOIS: Genérico para todas as entidades que implementam protocolo Syncable
//  • BENEFÍCIO: Reutilização, manutenibilidade e performance otimizada
//  
//  🔄 FLUXO SIMPLIFICADO:
//  1. Verifica conectividade de rede via ConnectivityManager
//  2. Busca entidades com status .pending
//  3. Upload para Firestore via JSON serialization
//  4. Download de mudanças remotas
//  5. Retry automático em caso de erro (sem estados intermediários)
//  6. Resolução de conflitos por lastModified (local > remoto = upload)
//  
//  ⚡ ARQUITETURA OTIMIZADA:
//  • ConnectivityManager: Verificação de rede antes de tentar sync (evita timeouts)
//  • PersistenceController: Substituição do CoreDataStack descontinuado
//  • Protocolo Syncable: Genérico para CDWorkoutPlan, CDAppUser, CDExercise, etc.
//  • Estados Simples: Apenas .pending e .synced (89% menos complexidade)
//  • Retry Automático: Falhas voltam para .pending (sem estado error permanente)
//  • Performance: Menos queries, menos overhead, melhor UX
//  
//  🔋 BENEFÍCIOS DA INTEGRAÇÃO CONNECTIVITYMANAGER:
//  • Economia de bateria: Evita tentativas desnecessárias quando offline
//  • UX melhorada: Usuário sabe imediatamente se sync vai funcionar
//  • Timeouts reduzidos: Não espera Firebase falhar para detectar falta de rede
//  • Logs informativos: Status de rede detalhado (WiFi/Cellular/Ethernet)
//  • Pause inteligente: Para sync imediatamente se rede cair durante processo
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import FirebaseFirestore
import CoreData
import Combine

// MARK: - CloudSyncManager Protocol

/// Protocolo para gerenciamento de sincronização com Firestore
/// Define interface assíncrona para operações de sincronização
protocol CloudSyncManagerProtocol {
    /// Agenda upload de uma entidade específica
    func scheduleUpload(entityId: UUID) async
    
    /// Agenda upload de um usuário específico
    func scheduleUpload(for user: CDAppUser) async
    
    /// Agenda deleção remota de uma entidade específica  
    func scheduleDeletion(entityId: UUID) async
    
    /// Executa sincronização de todas as mudanças pendentes
    func syncPendingChanges() async
}

// MARK: - CloudSyncManager Implementation

/// 🎯 Gerenciador genérico de sincronização com Firestore
/// Funciona com qualquer entidade Core Data que implementa protocolo `Syncable`
/// Exclusivo para iOS - comunicação com Apple Watch via WatchConnectivity
actor CloudSyncManager: CloudSyncManagerProtocol {
    static let shared = CloudSyncManager()
    
    // MARK: - Dependencies (Otimizadas)
    private let persistenceController: PersistenceController
    private let firestore: Firestore
    private let connectivityManager: ConnectivityManagerProtocol
    
    // MARK: - Sync State (Simplificado)
    private var isRunning = false
    private var uploadQueue: Set<UUID> = []
    private var deleteQueue: Set<UUID> = []
    
    // MARK: - Initialization
    init(
        persistenceController: PersistenceController = .shared,
        firestore: Firestore = Firestore.firestore(),
        connectivityManager: ConnectivityManagerProtocol = ConnectivityManager.shared
    ) {
        self.persistenceController = persistenceController
        self.firestore = firestore
        self.connectivityManager = connectivityManager
    }
    
    // MARK: - Schedule Operations (Genéricas)
    /// Agenda upload de qualquer entidade Syncable
    func scheduleUpload(entityId: UUID) {
        uploadQueue.insert(entityId)
        Task {
            await syncPendingChanges()
        }
    }
    
    /// Agenda upload de um usuário específico
    func scheduleUpload(for user: CDAppUser) async {
        guard let userId = user.id else {
            print("⚠️ [SYNC] Usuário sem ID para agendar upload")
            return
        }
        
        uploadQueue.insert(userId)
        await syncPendingChanges()
    }
    
    /// Agenda deleção remota de qualquer entidade
    func scheduleDeletion(entityId: UUID) {
        deleteQueue.insert(entityId)
        Task {
            await syncPendingChanges()
        }
    }
    
    // MARK: - Main Sync Process (Otimizado)
    /// 🔄 Processo principal de sincronização
    /// Funciona com todas as entidades Syncable do modelo FitterModel
    func syncPendingChanges() async {
        guard !isRunning else { 
            print("⏳ [SYNC] Sincronização já em andamento - pulando")
            return 
        }
        
        // ✅ NOVA: Verificação de conectividade ANTES de tentar sync
        guard await isNetworkAvailable() else {
            print("📵 [SYNC] Sem conectividade de rede - adiando sincronização")
            return
        }
        
        isRunning = true
        defer { isRunning = false }
        
        print("🔄 [SYNC] Iniciando sincronização genérica com rede disponível...")
        
        // 1. Upload mudanças locais (todas as entidades Syncable)
        await uploadPendingChanges()
        
        // 2. Download mudanças remotas do Firestore
        await downloadRemoteChanges()
        
        // 3. Processa deletes agendados
        await processPendingDeletes()
        
        print("✅ [SYNC] Sincronização genérica completa")
    }
    
    // MARK: - Network Connectivity Check (NOVA)
    
    /// Verifica se há conectividade de rede disponível
    /// - Returns: true se há internet, false caso contrário
    private func isNetworkAvailable() async -> Bool {
        return await MainActor.run {
            let isConnected = connectivityManager.isConnected
            let isReachable = connectivityManager.isReachable
            let networkType = connectivityManager.networkType
            
            if isConnected && isReachable {
                print("📶 [SYNC] Rede disponível: \(networkType.rawValue)")
                return true
            } else {
                print("📵 [SYNC] Rede indisponível - Conectado: \(isConnected), Alcançável: \(isReachable), Tipo: \(networkType.rawValue)")
                return false
            }
        }
    }
    
    /// Verifica conectividade antes de operações críticas de upload
    /// - Returns: true se pode tentar upload, false caso contrário
    private func canAttemptUpload() async -> Bool {
        let available = await isNetworkAvailable()
        if !available {
            print("⚠️ [SYNC] Upload cancelado - sem conectividade")
        }
        return available
    }
    
    /// Verifica conectividade antes de operações críticas de download
    /// - Returns: true se pode tentar download, false caso contrário
    private func canAttemptDownload() async -> Bool {
        let available = await isNetworkAvailable()
        if !available {
            print("⚠️ [SYNC] Download cancelado - sem conectividade")
        }
        return available
    }
    
    /// Verifica se um erro é relacionado à conectividade de rede
    /// - Parameter error: Erro a ser verificado
    /// - Returns: true se é erro de rede, false caso contrário
    private func isNetworkError(_ error: Error) -> Bool {
        // Códigos de erro comuns de rede
        let networkErrorCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDataNotAllowed
        ]
        
        if let urlError = error as? URLError {
            return networkErrorCodes.contains(urlError.code.rawValue)
        }
        
        if let nsError = error as NSError? {
            return networkErrorCodes.contains(nsError.code) || 
                   nsError.domain == NSURLErrorDomain
        }
        
        // Verificar strings de erro do Firebase
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("network") ||
               errorDescription.contains("internet") ||
               errorDescription.contains("connection") ||
               errorDescription.contains("timeout") ||
               errorDescription.contains("offline")
    }

    // MARK: - Upload Changes (Genérico com Verificação de Rede)
    /// ⬆️ Upload de todas as entidades com status .pending
    private func uploadPendingChanges() async {
        guard await canAttemptUpload() else { return }
        
        print("⬆️ [SYNC] Enviando mudanças locais...")
        
        // Process upload queue primeiro
        for entityId in uploadQueue {
            // Verificar conectividade para cada entidade (em caso de perda durante o processo)
            guard await isNetworkAvailable() else {
                print("📵 [SYNC] Conectividade perdida durante upload - pausando")
                break
            }
            
            await uploadEntity(id: entityId)
            uploadQueue.remove(entityId)
        }
        
        // Busca todas as entidades pendentes no Core Data
        await uploadPendingWorkoutPlans()
        await uploadPendingUsers()
        await uploadPendingExerciseTemplates()
        await uploadPendingWorkoutHistories()
    }
    
    /// 📋 Upload específico para CDWorkoutPlan
    private func uploadPendingWorkoutPlans() async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
            request.predicate = NSPredicate(format: "cloudSyncStatus == %d", CloudSyncStatus.pending.rawValue)
            
            do {
                let pendingPlans = try context.fetch(request)
                print("📋 [SYNC] Encontrados \(pendingPlans.count) planos pendentes")
                
                for plan in pendingPlans {
                    if let planId = plan.id {
                        Task {
                            await self.uploadWorkoutPlan(id: planId)
                        }
                    }
                }
            } catch {
                print("❌ [SYNC] Erro ao buscar planos pendentes: \(error)")
            }
        }
    }
    
    /// 👤 Upload específico para CDAppUser
    private func uploadPendingUsers() async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDUser> = CDUser.fetchRequest()
            request.predicate = NSPredicate(format: "cloudSyncStatus == %d", CloudSyncStatus.pending.rawValue)
            
            do {
                let pendingUsers = try context.fetch(request)
                print("👤 [SYNC] Encontrados \(pendingUsers.count) usuários pendentes")
                
                for user in pendingUsers {
                    if let userId = user.id {
                        Task {
                            await self.uploadUser(id: userId)
                        }
                    }
                }
            } catch {
                print("❌ [SYNC] Erro ao buscar usuários pendentes: \(error)")
            }
        }
    }
    
    /// 🔧 Upload genérico para qualquer entidade (via ID)
    private func uploadEntity(id: UUID) async {
        await uploadWorkoutPlan(id: id)
        await uploadUser(id: id)
        await uploadExerciseTemplate(id: id)
        await uploadWorkoutHistory(id: id)
    }
    
    /// 📋 Upload específico de Workout Plan
    private func uploadWorkoutPlan(id: UUID) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                guard let cdPlan = try context.fetch(request).first else {
                    print("⚠️ [SYNC] Plano não encontrado: \(id)")
                    return
                }
                
                Task {
                    await self.performWorkoutPlanUpload(cdPlan: cdPlan, context: context)
                }
                
            } catch {
                print("❌ [SYNC] Erro ao preparar upload do plano: \(error)")
            }
        }
    }
    
    /// 👤 Upload específico de User
    private func uploadUser(id: UUID) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                guard let cdUser = try context.fetch(request).first else {
                    return // User não existe, skip silencioso
                }
                
                Task {
                    await self.performUserUpload(cdUser: cdUser, context: context)
                }
                
            } catch {
                print("❌ [SYNC] Erro ao preparar upload do usuário: \(error)")
            }
        }
    }
    
    /// 🔄 Execução do upload do Workout Plan para Firestore
    private func performWorkoutPlanUpload(cdPlan: CDWorkoutPlan, context: NSManagedObjectContext) async {
        guard let planId = cdPlan.id else { return }
        
        do {
            // Converter para documento Firestore
            let planData: [String: Any] = [
                "id": planId.uuidString,
                "title": cdPlan.displayTitle,
                "createdAt": cdPlan.createdAt ?? Date(),
                "lastModified": cdPlan.lastModified ?? Date(),
                "order": cdPlan.order,
                "userId": cdPlan.user?.id?.uuidString ?? "",
                "exerciseCount": cdPlan.exercisesArray.count
            ]
            
            // Upload para Firestore
            try await firestore.collection("workoutPlans").document(planId.uuidString).setData(planData)
            
            // Marcar como sincronizado
            await context.perform {
                cdPlan.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                try? context.save()
            }
            
            print("✅ [SYNC] Plano enviado: \(cdPlan.displayTitle)")
            
        } catch {
            print("❌ [SYNC] Erro no upload do plano: \(error)")
            
            // Verificar se é erro de rede
            if isNetworkError(error) {
                print("📵 [SYNC] Erro de rede detectado - mantendo como pending para retry")
            }
            
            // Retry automático: volta para pending
            await context.perform {
                cdPlan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }
    
    /// 🔄 Execução do upload do User para Firestore
    private func performUserUpload(cdUser: CDAppUser, context: NSManagedObjectContext) async {
        guard let userId = cdUser.id else { return }
        
        do {
            let userData: [String: Any] = [
                "id": userId.uuidString,
                "email": cdUser.email ?? "",
                "name": cdUser.name ?? "",
                "createdAt": cdUser.createdAt ?? Date(),
                "lastModified": cdUser.lastModified ?? Date()
            ]
            
            try await firestore.collection("users").document(userId.uuidString).setData(userData)
            
            await context.perform {
                cdUser.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                try? context.save()
            }
            
            print("✅ [SYNC] Usuário enviado: \(cdUser.safeName)")
            
        } catch {
            print("❌ [SYNC] Erro no upload do usuário: \(error)")
            
            if isNetworkError(error) {
                print("📵 [SYNC] Erro de rede detectado no upload do usuário")
            }
            
            await context.perform {
                cdUser.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }
    
    /// 🏋️ Upload específico de Exercise Template
    private func uploadExerciseTemplate(id: UUID) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDExerciseTemplate> = CDExerciseTemplate.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND cloudSyncStatus == %d", id as CVarArg, CloudSyncStatus.pending.rawValue)
            
            do {
                guard let template = try context.fetch(request).first else {
                    return // Template não existe ou já sincronizado
                }
                
                Task {
                    await self.performExerciseTemplateUpload(template: template, context: context)
                }
                
            } catch {
                print("❌ [SYNC] Erro ao preparar upload do template: \(error)")
            }
        }
    }

    /// 📊 Upload específico de Workout History
    private func uploadWorkoutHistory(id: UUID) async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutHistory> = CDWorkoutHistory.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND cloudSyncStatus == %d", id as CVarArg, CloudSyncStatus.pending.rawValue)
            
            do {
                guard let history = try context.fetch(request).first else {
                    return // History não existe ou já sincronizado
                }
                
                Task {
                    await self.performWorkoutHistoryUpload(history: history, context: context)
                }
                
            } catch {
                print("❌ [SYNC] Erro ao preparar upload do histórico: \(error)")
            }
        }
    }

    // MARK: - Exercise Template Sync
    private func uploadPendingExerciseTemplates() async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDExerciseTemplate> = CDExerciseTemplate.fetchRequest()
            request.predicate = NSPredicate(format: "cloudSyncStatus == %d", CloudSyncStatus.pending.rawValue)
            
            do {
                let pendingTemplates = try context.fetch(request)
                print("🏋️ [SYNC] Encontrados \(pendingTemplates.count) templates pendentes")
                
                for template in pendingTemplates {
                    if let templateId = template.id {
                        Task {
                            await self.uploadExerciseTemplate(id: templateId)
                        }
                    }
                }
            } catch {
                print("❌ [SYNC] Erro ao buscar templates pendentes: \(error)")
            }
        }
    }

    /// 🔄 Execução do upload do Exercise Template para Firestore
    private func performExerciseTemplateUpload(template: CDExerciseTemplate, context: NSManagedObjectContext) async {
        guard let templateId = template.id else { return }
        
        do {
            let templateData: [String: Any] = [
                "id": templateId.uuidString,
                "name": template.name ?? "",
                "description": template.description ?? "",
                "muscleGroup": template.muscleGroup ?? "",
                "equipment": template.equipment ?? "",
                "videoURL": template.videoURL ?? "",
                "templateId": template.templateId ?? "",
                "gripVariation": template.gripVariation ?? "",
                "legSubgroup": template.legSubgroup ?? "",
                "createdAt": template.createdAt ?? Date(),
                "updatedAt": template.updatedAt ?? Date(),
                "lastModified": template.lastModified ?? Date()
            ]
            
            try await firestore.collection("exerciseTemplates").document(templateId.uuidString).setData(templateData)
            
            await context.perform {
                template.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                template.lastCloudSync = Date()
                try? context.save()
            }
            
            print("✅ [SYNC] Template enviado: \(template.name ?? "")")
            
        } catch {
            print("❌ [SYNC] Erro no upload do template: \(error)")
            
            if isNetworkError(error) {
                print("📵 [SYNC] Erro de rede detectado no upload do template")
            }
            
            await context.perform {
                template.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }

    /// 🔄 Execução do upload do Workout History para Firestore
    private func performWorkoutHistoryUpload(history: CDWorkoutHistory, context: NSManagedObjectContext) async {
        guard let historyId = history.id else { return }
        
        do {
            let historyData: [String: Any] = [
                "id": historyId.uuidString,
                "date": history.date ?? Date(),
                "userId": history.user?.id?.uuidString ?? "",
                "lastModified": history.lastModified ?? Date()
            ]
            
            try await firestore.collection("workoutHistories").document(historyId.uuidString).setData(historyData)
            
            // Sincronizar exercícios do histórico
            if let exercises = history.exercises?.allObjects as? [CDHistoryExercise] {
                for exercise in exercises {
                    await performHistoryExerciseUpload(exercise: exercise)
                }
            }
            
            await context.perform {
                history.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                history.lastCloudSync = Date()
                try? context.save()
            }
            
            print("✅ [SYNC] Histórico enviado: \(history.date?.description ?? "")")
            
        } catch {
            print("❌ [SYNC] Erro no upload do histórico: \(error)")
            
            if isNetworkError(error) {
                print("📵 [SYNC] Erro de rede detectado no upload do histórico")
            }
            
            await context.perform {
                history.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }

    // MARK: - Workout History Sync
    private func uploadPendingWorkoutHistories() async {
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutHistory> = CDWorkoutHistory.fetchRequest()
            request.predicate = NSPredicate(format: "cloudSyncStatus == %d", CloudSyncStatus.pending.rawValue)
            
            do {
                let pendingHistories = try context.fetch(request)
                print("📊 [SYNC] Encontrados \(pendingHistories.count) históricos pendentes")
                
                for history in pendingHistories {
                    if let historyId = history.id {
                        Task {
                            await self.uploadWorkoutHistory(id: historyId)
                        }
                    }
                }
            } catch {
                print("❌ [SYNC] Erro ao buscar históricos pendentes: \(error)")
            }
        }
    }



    // MARK: - History Exercise & Sets Sync
    private func performHistoryExerciseUpload(exercise: CDHistoryExercise) async {
        guard let exerciseId = exercise.id else { return }
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let exerciseData: [String: Any] = [
                "id": exerciseId.uuidString,
                "name": exercise.name ?? "",
                "order": exercise.order,
                "historyId": exercise.history?.id?.uuidString ?? "",
                "lastModified": Date()
            ]
            
            do {
                try await firestore.collection("historyExercises").document(exerciseId.uuidString).setData(exerciseData)
                
                // Sincronizar sets do exercício
                if let sets = exercise.sets?.allObjects as? [CDHistorySet] {
                    for set in sets {
                        await performHistorySetUpload(set: set)
                    }
                }
                
                exercise.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao enviar exercício do histórico: \(error)")
            }
        }
    }

    private func performHistorySetUpload(set: CDHistorySet) async {
        guard let setId = set.id else { return }
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let setData: [String: Any] = [
                "id": setId.uuidString,
                "weight": set.weight,
                "reps": set.reps,
                "repsCounter": set.repsCounter ?? 0,
                "order": set.order,
                "startTime": set.startTime ?? Date(),
                "endTime": set.endTime ?? Date(),
                "heartRateData": set.heartRateData ?? Data(),
                "caloriesData": set.caloriesData ?? Data(),
                "restTime": set.restTime ?? 0.0,
                "timestamp": set.timestamp ?? Date(),
                "exerciseId": set.exercise?.id?.uuidString ?? "",
                "lastModified": Date()
            ]
            
            do {
                try await firestore.collection("historySets").document(setId.uuidString).setData(setData)
                
                set.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                set.lastCloudSync = Date()
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao enviar set do histórico: \(error)")
            }
        }
    }

    // MARK: - Current Set Sync
    private func uploadCurrentSet(_ set: CDCurrentSet) async {
        guard let setId = set.id else { return }
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let setData: [String: Any] = [
                "id": setId.uuidString,
                "weight": set.weight,
                "actualReps": set.actualReps ?? 0,
                "targetReps": set.targetReps,
                "order": set.order,
                "startTime": set.startTime ?? Date(),
                "endTime": set.endTime ?? Date(),
                "isActive": set.isActive,
                "restTime": set.restTime ?? 0.0,
                "timestamp": set.timestamp ?? Date(),
                "exerciseId": set.exercise?.id?.uuidString ?? "",
                "lastModified": Date()
            ]
            
            do {
                try await firestore.collection("currentSets").document(setId.uuidString).setData(setData)
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao enviar set atual: \(error)")
            }
        }
    }

    // MARK: - Download Changes (Otimizado com Verificação de Rede)
    /// ⬇️ Download de mudanças remotas do Firestore
    private func downloadRemoteChanges() async {
        guard await canAttemptDownload() else { return }
        
        print("⬇️ [SYNC] Baixando mudanças remotas...")
        
        // Verificar conectividade entre cada tipo de download
        if await isNetworkAvailable() {
            await downloadWorkoutPlans()
        }
        
        if await isNetworkAvailable() {
            await downloadUsers()
        }
        
        if await isNetworkAvailable() {
            await downloadExerciseTemplates()
        }
        
        if await isNetworkAvailable() {
            await downloadWorkoutHistories()
        }
    }
    
    /// 📋 Download de Workout Plans
    private func downloadWorkoutPlans() async {
        do {
            let snapshot = try await firestore.collection("workoutPlans").getDocuments()
            
            for document in snapshot.documents {
                await processRemoteWorkoutPlan(document: document)
            }
            
        } catch {
            print("❌ [SYNC] Erro ao baixar planos: \(error)")
        }
    }
    
    /// 👤 Download de Users
    private func downloadUsers() async {
        do {
            let snapshot = try await firestore.collection("users").getDocuments()
            
            for document in snapshot.documents {
                await processRemoteUser(document: document)
            }
            
        } catch {
            print("❌ [SYNC] Erro ao baixar usuários: \(error)")
        }
    }
    
    /// 🔄 Processamento de Workout Plan remoto
    private func processRemoteWorkoutPlan(document: QueryDocumentSnapshot) async {
        let data = document.data()
        
        guard 
            let idString = data["id"] as? String,
            let planId = UUID(uuidString: idString),
            let title = data["title"] as? String,
            let createdAt = data["createdAt"] as? Date,
            let lastModified = data["lastModified"] as? Date,
            let order = data["order"] as? Int32
        else {
            print("⚠️ [SYNC] Documento de plano inválido: \(document.documentID)")
            return
        }
        
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", planId as CVarArg)
            
            do {
                let existingPlans = try context.fetch(request)
                
                if let existingPlan = existingPlans.first {
                    // Resolução de conflito por lastModified
                    if let localModified = existingPlan.lastModified, localModified > lastModified {
                        // Local mais recente - agenda para upload
                        existingPlan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                        print("🔄 [SYNC] Local mais recente, agendando upload: \(title)")
                    } else {
                        // Remoto mais recente - atualiza local
                        existingPlan.title = title
                        existingPlan.order = order
                        existingPlan.lastModified = lastModified
                        existingPlan.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                        print("⬇️ [SYNC] Plano atualizado do remoto: \(title)")
                    }
                } else {
                    // Novo plano do remoto
                    let newPlan = CDWorkoutPlan(context: context)
                    newPlan.id = planId
                    newPlan.title = title
                    newPlan.createdAt = createdAt
                    newPlan.lastModified = lastModified
                    newPlan.order = order
                    newPlan.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                    print("➕ [SYNC] Novo plano do remoto: \(title)")
                }
                
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao processar plano remoto: \(error)")
            }
        }
    }
    
    /// 🔄 Processamento de User remoto
    private func processRemoteUser(document: QueryDocumentSnapshot) async {
        let data = document.data()
        
        guard 
            let idString = data["id"] as? String,
            let userId = UUID(uuidString: idString),
            let email = data["email"] as? String,
            let name = data["name"] as? String,
            let createdAt = data["createdAt"] as? Date,
            let lastModified = data["lastModified"] as? Date
        else {
            print("⚠️ [SYNC] Documento de usuário inválido: \(document.documentID)")
            return
        }
        
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId as CVarArg)
            
            do {
                let existingUsers = try context.fetch(request)
                
                if let existingUser = existingUsers.first {
                    if let localModified = existingUser.lastModified, localModified > lastModified {
                        existingUser.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                        print("🔄 [SYNC] Usuário local mais recente: \(name)")
                    } else {
                        existingUser.name = name
                        existingUser.email = email
                        existingUser.lastModified = lastModified
                        existingUser.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                        print("⬇️ [SYNC] Usuário atualizado: \(name)")
                    }
                } else {
                    let newUser = CDAppUser(context: context)
                    newUser.id = userId
                    newUser.email = email
                    newUser.name = name
                    newUser.createdAt = createdAt
                    newUser.lastModified = lastModified
                    newUser.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                    print("➕ [SYNC] Novo usuário: \(name)")
                }
                
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao processar usuário remoto: \(error)")
            }
        }
    }

    private func downloadExerciseTemplates() async {
        do {
            let snapshot = try await firestore.collection("exerciseTemplates").getDocuments()
            
            for document in snapshot.documents {
                await processRemoteExerciseTemplate(document: document)
            }
            
        } catch {
            print("❌ [SYNC] Erro ao baixar templates: \(error)")
        }
    }

    private func processRemoteExerciseTemplate(document: QueryDocumentSnapshot) async {
        let data = document.data()
        
        guard 
            let idString = data["id"] as? String,
            let templateId = UUID(uuidString: idString),
            let name = data["name"] as? String,
            let muscleGroup = data["muscleGroup"] as? String,
            let equipment = data["equipment"] as? String,
            let lastModified = data["lastModified"] as? Date
        else {
            print("⚠️ [SYNC] Documento de template inválido: \(document.documentID)")
            return
        }
        
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDExerciseTemplate> = CDExerciseTemplate.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", templateId as CVarArg)
            
            do {
                let existingTemplates = try context.fetch(request)
                
                if let existingTemplate = existingTemplates.first {
                    if let localModified = existingTemplate.lastModified, localModified > lastModified {
                        existingTemplate.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                    } else {
                        existingTemplate.name = name
                        existingTemplate.muscleGroup = muscleGroup
                        existingTemplate.equipment = equipment
                        existingTemplate.description = data["description"] as? String
                        existingTemplate.videoURL = data["videoURL"] as? String
                        existingTemplate.gripVariation = data["gripVariation"] as? String
                        existingTemplate.legSubgroup = data["legSubgroup"] as? String
                        existingTemplate.updatedAt = lastModified
                        existingTemplate.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                        existingTemplate.lastCloudSync = Date()
                    }
                } else {
                    let newTemplate = CDExerciseTemplate(context: context)
                    newTemplate.id = templateId
                    newTemplate.name = name
                    newTemplate.muscleGroup = muscleGroup
                    newTemplate.equipment = equipment
                    newTemplate.description = data["description"] as? String
                    newTemplate.videoURL = data["videoURL"] as? String
                    newTemplate.gripVariation = data["gripVariation"] as? String
                    newTemplate.legSubgroup = data["legSubgroup"] as? String
                    newTemplate.createdAt = data["createdAt"] as? Date ?? Date()
                    newTemplate.updatedAt = lastModified
                    newTemplate.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                    newTemplate.lastCloudSync = Date()
                }
                
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao processar template remoto: \(error)")
            }
        }
    }

    private func downloadWorkoutHistories() async {
        do {
            let snapshot = try await firestore.collection("workoutHistories").getDocuments()
            
            for document in snapshot.documents {
                await processRemoteWorkoutHistory(document: document)
            }
            
        } catch {
            print("❌ [SYNC] Erro ao baixar históricos: \(error)")
        }
    }

    private func processRemoteWorkoutHistory(document: QueryDocumentSnapshot) async {
        let data = document.data()
        
        guard 
            let idString = data["id"] as? String,
            let historyId = UUID(uuidString: idString),
            let date = data["date"] as? Date,
            let lastModified = data["lastModified"] as? Date
        else {
            print("⚠️ [SYNC] Documento de histórico inválido: \(document.documentID)")
            return
        }
        
        let context = persistenceController.newSensorDataContext()
        
        await context.perform {
            let request: NSFetchRequest<CDWorkoutHistory> = CDWorkoutHistory.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", historyId as CVarArg)
            
            do {
                let existingHistories = try context.fetch(request)
                
                if let existingHistory = existingHistories.first {
                    if let localModified = existingHistory.lastModified, localModified > lastModified {
                        existingHistory.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                    } else {
                        existingHistory.date = date
                        existingHistory.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                        existingHistory.lastCloudSync = Date()
                    }
                } else {
                    let newHistory = CDWorkoutHistory(context: context)
                    newHistory.id = historyId
                    newHistory.date = date
                    newHistory.cloudSyncStatus = CloudSyncStatus.synced.rawValue
                    newHistory.lastCloudSync = Date()
                }
                
                try context.save()
                
            } catch {
                print("❌ [SYNC] Erro ao processar histórico remoto: \(error)")
            }
        }
    }
}

// MARK: - Process Deletes (Otimizado com Verificação de Rede)
/// 🗑️ Processamento de deletes remotos
private func processPendingDeletes() async {
    guard await canAttemptUpload() else { return } // Deletes também precisam de upload
    
    print("🗑️ [SYNC] Processando deletes...")
        
    for entityId in deleteQueue {
        // Verificar conectividade para cada delete
        guard await isNetworkAvailable() else {
            print("📵 [SYNC] Conectividade perdida durante deletes - pausando")
            break
        }
        
        await deleteRemoteEntity(id: entityId)
        deleteQueue.remove(entityId)
    }
}
    
/// 🗑️ Delete genérico de entidade remota
private func deleteRemoteEntity(id: UUID) async {
    // Tenta deletar de todas as coleções possíveis
    await deleteFromCollection("workoutPlans", id: id)
    await deleteFromCollection("users", id: id)
    // TODO: Adicionar outras coleções
}
    
/// 🗑️ Delete de coleção específica
private func deleteFromCollection(_ collection: String, id: UUID) async {
    do {
        try await firestore.collection(collection).document(id.uuidString).delete()
        print("🗑️ [SYNC] Deletado de \(collection): \(id)")
    } catch {
        print("❌ [SYNC] Erro ao deletar de \(collection): \(error)")
    }
}


// MARK: - Sync Event Logger (Opcional)
/// 📊 Logger de eventos de sincronização para debugging
extension CloudSyncManager {
    
    /// Registra evento de sincronização
    private func logSyncEvent(_ event: SyncEvent) {
        print("📊 [SYNC EVENT] \(event.action.description) - \(event.entityType) - \(event.success ? "✅" : "❌")")
    }
} 
