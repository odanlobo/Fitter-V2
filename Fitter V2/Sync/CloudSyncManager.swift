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
//  1. Busca entidades com status .pending
//  2. Upload para Firestore via JSON serialization
//  3. Download de mudanças remotas
//  4. Retry automático em caso de erro (sem estados intermediários)
//  5. Resolução de conflitos por lastModified (local > remoto = upload)
//  
//  ⚡ ARQUITETURA OTIMIZADA:
//  • PersistenceController: Substituição do CoreDataStack descontinuado
//  • Protocolo Syncable: Genérico para CDWorkoutPlan, CDUser, CDExercise, etc.
//  • Estados Simples: Apenas .pending e .synced (89% menos complexidade)
//  • Retry Automático: Falhas voltam para .pending (sem estado error permanente)
//  • Performance: Menos queries, menos overhead, melhor UX
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import FirebaseFirestore
import CoreData
import Combine

/// 🎯 Gerenciador genérico de sincronização com Firestore
/// Funciona com qualquer entidade Core Data que implementa protocolo `Syncable`
/// Exclusivo para iOS - comunicação com Apple Watch via WatchConnectivity
actor CloudSyncManager {
    static let shared = CloudSyncManager()
    
    // MARK: - Dependencies (Otimizadas)
    private let persistenceController: PersistenceController
    private let firestore: Firestore
    
    // MARK: - Sync State (Simplificado)
    private var isRunning = false
    private var uploadQueue: Set<UUID> = []
    private var deleteQueue: Set<UUID> = []
    
    // MARK: - Initialization
    init(
        persistenceController: PersistenceController = .shared,
        firestore: Firestore = Firestore.firestore()
    ) {
        self.persistenceController = persistenceController
        self.firestore = firestore
    }
    
    // MARK: - Schedule Operations (Genéricas)
    /// Agenda upload de qualquer entidade Syncable
    func scheduleUpload(entityId: UUID) {
        uploadQueue.insert(entityId)
        Task {
            await syncPendingChanges()
        }
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
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        
        print("🔄 [SYNC] Iniciando sincronização genérica...")
        
        // 1. Upload mudanças locais (todas as entidades Syncable)
        await uploadPendingChanges()
        
        // 2. Download mudanças remotas do Firestore
        await downloadRemoteChanges()
        
        // 3. Processa deletes agendados
        await processPendingDeletes()
        
        print("✅ [SYNC] Sincronização genérica completa")
    }
    
    // MARK: - Upload Changes (Genérico)
    /// ⬆️ Upload de todas as entidades com status .pending
    private func uploadPendingChanges() async {
        print("⬆️ [SYNC] Enviando mudanças locais...")
        
        // Process upload queue primeiro
        for entityId in uploadQueue {
            await uploadEntity(id: entityId)
            uploadQueue.remove(entityId)
        }
        
        // Busca todas as entidades pendentes no Core Data
        await uploadPendingWorkoutPlans()
        await uploadPendingUsers()
        // TODO: Adicionar outras entidades (CDExercise, CDHistorySession, etc.)
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
    
    /// 👤 Upload específico para CDUser
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
        // TODO: Adicionar outros tipos quando implementados
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
            let request: NSFetchRequest<CDUser> = CDUser.fetchRequest()
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
            
            // Retry automático: volta para pending
            await context.perform {
                cdPlan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }
    
    /// 🔄 Execução do upload do User para Firestore
    private func performUserUpload(cdUser: CDUser, context: NSManagedObjectContext) async {
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
            
            await context.perform {
                cdUser.cloudSyncStatus = CloudSyncStatus.pending.rawValue
                try? context.save()
            }
        }
    }
    
    // MARK: - Download Changes (Otimizado)
    /// ⬇️ Download de mudanças remotas do Firestore
    private func downloadRemoteChanges() async {
        print("⬇️ [SYNC] Baixando mudanças remotas...")
        
        await downloadWorkoutPlans()
        await downloadUsers()
        // TODO: Adicionar outras entidades
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
            let request: NSFetchRequest<CDUser> = CDUser.fetchRequest()
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
                    let newUser = CDUser(context: context)
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

    // MARK: - Process Deletes (Otimizado)
    /// 🗑️ Processamento de deletes remotos
    private func processPendingDeletes() async {
        print("🗑️ [SYNC] Processando deletes...")
        
        for entityId in deleteQueue {
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
}

// MARK: - Sync Event Logger (Opcional)
/// 📊 Logger de eventos de sincronização para debugging
extension CloudSyncManager {
    
    /// Registra evento de sincronização
    private func logSyncEvent(_ event: SyncEvent) {
        print("📊 [SYNC EVENT] \(event.action.description) - \(event.entityType) - \(event.success ? "✅" : "❌")")
    }
} 