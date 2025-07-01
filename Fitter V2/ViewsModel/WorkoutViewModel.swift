//
//  WorkoutViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//

import SwiftUI
import Combine
import CoreData

@MainActor
final class WorkoutViewModel: ObservableObject {
    // MARK: - Constants
    /// Ordem padrão dos grupos musculares para exibição
    /// Esta ordem é usada em toda a aplicação para consistência:
    /// - CreateWorkoutView: exercícios selecionados e grupos musculares
    /// - ListExerciseView: filtros de grupos disponíveis
    /// - WorkoutView: visualização de planos
    static let muscleGroupDisplayOrder: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
    
    // MARK: - Published Properties
    @Published var selectedExercises: Set<String> = []
    @Published private(set) var isLoading = false
    
    // MARK: - Private Properties
    private let workoutManager: WorkoutManager
    private lazy var workoutService: WorkoutService = WorkoutService(
        workoutManager: workoutManager,
        firebaseExerciseService: firebaseExerciseService
    )
    private let firebaseExerciseService: FirebaseExerciseService
    private let networkMonitor: NetworkMonitor
    private var currentUser: CDAppUser?
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Context Detection
    private var isPreviewMode: Bool {
        // Detecta se estamos em preview verificando se o usuário atual está no contexto de preview
        guard let user = currentUser else { return false }
        return user.managedObjectContext === PreviewCoreDataStack.shared.viewContext
    }
    
    private var contextToUse: NSManagedObjectContext {
        isPreviewMode ? PreviewCoreDataStack.shared.viewContext : CoreDataStack.shared.viewContext
    }
    
    // MARK: - Computed Properties
    var plans: [CDWorkoutPlan] {
        if isPreviewMode {
            return fetchPreviewPlans()
        } else {
            return workoutManager.workoutPlans
        }
    }
    
    // FIREBASE EXERCISES - Nova fonte principal
    var firebaseExercises: [FirebaseExercise] {
        if isPreviewMode {
            return fetchPreviewFirebaseExercises()
        } else {
            return firebaseExerciseService.exercises
        }
    }
    
    // LOCAL EXERCISES - Apenas para exercícios já salvos nos planos
    var localExercises: [CDExerciseTemplate] {
        if isPreviewMode {
            return fetchPreviewExercises()
        } else {
            return workoutManager.exercises
        }
    }
    
    /// Lista de exercícios selecionados ordenados por:
    /// 1º Grupo muscular (Chest → Back → Legs → Biceps → Triceps → Shoulders → Core)
    /// 2º Nome alfabético dentro do mesmo grupo
    var selectedFirebaseExercisesList: [FirebaseExercise] {
        return firebaseExercises
            .filter { selectedExercises.contains($0.safeTemplateId) }
            .sorted { exercise1, exercise2 in
                // Primeiro critério: ordem do grupo muscular
                let group1 = MuscleGroup(rawValue: exercise1.muscleGroup)
                let group2 = MuscleGroup(rawValue: exercise2.muscleGroup)
                
                let index1 = group1.map { Self.muscleGroupDisplayOrder.firstIndex(of: $0) ?? Self.muscleGroupDisplayOrder.count } ?? Self.muscleGroupDisplayOrder.count
                let index2 = group2.map { Self.muscleGroupDisplayOrder.firstIndex(of: $0) ?? Self.muscleGroupDisplayOrder.count } ?? Self.muscleGroupDisplayOrder.count
                
                if index1 != index2 {
                    return index1 < index2  // Ordena por grupo muscular
                } else {
                    // Segundo critério: ordem alfabética dentro do mesmo grupo
                    return exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
                }
            }
    }
    
    /// Grupos musculares dos exercícios selecionados, ordenados conforme definido
    /// Ordem: Chest → Back → Legs → Biceps → Triceps → Shoulders → Core
    var selectedMuscleGroups: [MuscleGroup] {
        let groups = Set(selectedFirebaseExercisesList.compactMap { 
            $0.muscleGroupEnum
        })
        return Self.muscleGroupDisplayOrder.filter { groups.contains($0) }
    }
    
    // MARK: - Initialization
    init(
        workoutManager: WorkoutManager = WorkoutManager.shared,
        firebaseExerciseService: FirebaseExerciseService = FirebaseExerciseService.shared,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.workoutManager = workoutManager
        self.firebaseExerciseService = firebaseExerciseService
        self.networkMonitor = networkMonitor
        
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    /// Atualiza o usuário logado
    func updateUser(_ user: CDAppUser?) {
        print("🎯 WorkoutViewModel.updateUser - Recebido usuário: \(user?.safeName ?? "nil")")
        currentUser = user
        Task {
            await loadPlansForCurrentUser()
        }
    }
    
    /// Busca planos do usuário atual
    func loadPlansForCurrentUser() async {
        guard let user = currentUser else {
            print("Nenhum usuário logado no ViewModel!")
            return
        }
        
        if isPreviewMode {
            print("🎯 Preview mode detectado - carregando dados do contexto de preview")
            objectWillChange.send() // Força atualização da UI
        } else {
            await workoutManager.loadWorkoutPlans(for: user)
        }
    }
    
    /// Carrega exercícios do Firebase
    func loadFirebaseExercises() async {
        if isPreviewMode {
            print("🎯 Preview mode - exercícios Firebase simulados")
            objectWillChange.send() // Força atualização da UI
        } else {
            await firebaseExerciseService.loadExercises()
        }
    }
    
    /// Carrega exercícios locais (apenas para compatibilidade)
    func loadExercises() async {
        // Mantém compatibilidade, mas agora carrega exercícios do Firebase
        await loadFirebaseExercises()
    }
    
    /// Cria um novo plano de treino copiando exercícios do Firebase para local
    func createWorkoutPlan(title: String, selectedFirebaseExercises: [FirebaseExercise]) async throws {
        guard let user = currentUser else {
            throw WorkoutError.userNotFound
        }
        
        if isPreviewMode {
            try await createPreviewWorkoutPlan(title: title, user: user, firebaseExercises: selectedFirebaseExercises)
        } else {
            do {
                try await workoutService.createWorkoutPlanWithFirebaseExercises(
                    title: title,
                    user: user,
                    firebaseExercises: selectedFirebaseExercises
                )
                selectedExercises = [] // Limpa seleção após criar
            } catch {
                throw WorkoutError.saveError(error.localizedDescription)
            }
        }
    }
    
    /// Cria plano com exercícios do Firebase (novo método principal)
    func createWorkoutPlanWithFirebaseExercises(title: String) async throws {
        let selectedFirebaseExercises = selectedFirebaseExercisesList
        try await createWorkoutPlan(title: title, selectedFirebaseExercises: selectedFirebaseExercises)
    }
    
    /// Reordena planos
    func move(fromOffsets: IndexSet, toOffset: Int) {
        if isPreviewMode {
            // Em preview, apenas simula a reordenação
            print("🎯 Preview mode - reordenação simulada")
        } else {
            var revised = plans
            revised.move(fromOffsets: fromOffsets, toOffset: toOffset)
            
            // Aplica nova ordem e nomes
            for (idx, plan) in revised.enumerated() {
                let suffix = idx < letters.count ? String(letters[idx]) : "\(idx + 1)"
                plan.title = "Treino \(suffix)"
            }
            
            // Atualiza via manager
            Task {
                try await workoutManager.reorderWorkoutPlans(revised)
            }
        }
    }
    
    /// Remove plano
    func deletePlan(_ plan: CDWorkoutPlan) async throws {
        if isPreviewMode {
            print("🎯 Preview mode - delete simulado para: \(plan.displayTitle)")
            // Em preview, apenas simula a remoção
            objectWillChange.send()
        } else {
            do {
                try await workoutManager.deleteWorkoutPlan(plan)
            } catch {
                throw WorkoutError.saveError(error.localizedDescription)
            }
        }
    }
    
    /// Atualiza plano existente
    func updatePlan(_ plan: CDWorkoutPlan) async throws {
        guard currentUser != nil else {
            throw WorkoutError.userNotFound
        }
        
        if isPreviewMode {
            print("🎯 Preview mode - update simulado para: \(plan.displayTitle)")
            // Em preview, apenas simula a atualização
            objectWillChange.send()
        } else {
            do {
                try await workoutManager.updateWorkoutPlan(plan)
            } catch {
                throw WorkoutError.saveError(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Firebase Exercise Helper Methods
    
    func equipmentOptions(for group: MuscleGroup?) -> [String] {
        if isPreviewMode {
            return previewEquipmentOptions(for: group)
        } else {
            return firebaseExerciseService.equipmentOptions(for: group)
        }
    }
    
    func filteredFirebaseExercises(for group: MuscleGroup?, equipment: String?) -> [FirebaseExercise] {
        if isPreviewMode {
            return previewFilteredFirebaseExercises(for: group, equipment: equipment)
        } else {
            return firebaseExerciseService.filteredExercises(for: group, equipment: equipment)
        }
    }
    
    // MARK: - Legacy Helper Methods (compatibilidade)
    
    func filteredExercises(for group: MuscleGroup?, equipment: String?) -> [CDExerciseTemplate] {
        // Mantém compatibilidade para componentes antigos
        return localExercises
            .filter {
                (group == nil || $0.muscleGroup == group?.rawValue) &&
                (equipment == nil || $0.equipment == equipment)
            }
            .sorted { exercise1, exercise2 in
                exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
            }
    }
    
    // MARK: - Preview Helper Methods
    
    private func fetchPreviewPlans() -> [CDWorkoutPlan] {
        guard let user = currentUser else { return [] }
        
        let context = contextToUse
        let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkoutPlan.order, ascending: true)]
        request.predicate = NSPredicate(format: "user == %@", user)
        
        do {
            let plans = try context.fetch(request)
            print("🎯 Preview - Carregados \(plans.count) planos para usuário: \(user.safeName)")
            return plans
        } catch {
            print("❌ Preview - Erro ao carregar planos: \(error)")
            return []
        }
    }
    
    private func fetchPreviewExercises() -> [CDExerciseTemplate] {
        let context = contextToUse
        let request: NSFetchRequest<CDExerciseTemplate> = CDExerciseTemplate.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDExerciseTemplate.name, ascending: true)]
        
        do {
            let exercises = try context.fetch(request)
            return exercises
        } catch {
            print("❌ Preview - Erro ao carregar exercícios: \(error)")
            return []
        }
    }
    
    private func fetchPreviewFirebaseExercises() -> [FirebaseExercise] {
        // Em preview, simula exercícios do Firebase ordenados por grupo muscular
        let exercises = [
            FirebaseExercise(
                templateId: "preview_chest_1",
                name: "Supino Reto",
                muscleGroup: "chest",
                equipment: "Barra",
                gripVariation: "Pronada",
                imageName: "chest_1"
            ),
            FirebaseExercise(
                templateId: "preview_back_1",
                name: "Puxada Aberta",
                muscleGroup: "back",
                equipment: "Polia",
                gripVariation: "Pronada",
                imageName: "back_1"
            )
        ]
        
        return exercises.sorted { exercise1, exercise2 in
            let group1 = MuscleGroup(rawValue: exercise1.muscleGroup)
            let group2 = MuscleGroup(rawValue: exercise2.muscleGroup)
            
            let index1 = group1.map { Self.muscleGroupDisplayOrder.firstIndex(of: $0) ?? Self.muscleGroupDisplayOrder.count } ?? Self.muscleGroupDisplayOrder.count
            let index2 = group2.map { Self.muscleGroupDisplayOrder.firstIndex(of: $0) ?? Self.muscleGroupDisplayOrder.count } ?? Self.muscleGroupDisplayOrder.count
            
            if index1 != index2 {
                return index1 < index2
            } else {
                return exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
            }
        }
    }
    
    private func createPreviewWorkoutPlan(title: String, user: CDAppUser, firebaseExercises: [FirebaseExercise]) async throws {
        let context = contextToUse
        
        let newPlan = CDWorkoutPlan(context: context)
        newPlan.id = UUID()
        newPlan.title = title
        newPlan.createdAt = Date()
        newPlan.order = Int32(fetchPreviewPlans().count)
        newPlan.user = user
        newPlan.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        
        // Converte exercícios do Firebase para CoreData e cria PlanExercises
        var muscleGroupsSet: Set<String> = []
        for (idx, fbExercise) in firebaseExercises.enumerated() {
            // Converte para CoreData Template
            let template = fbExercise.toCoreDataTemplate(context: context)
            
            // Cria PlanExercise
            let planExercise = CDPlanExercise(context: context)
            planExercise.id = UUID()
            planExercise.order = Int32(idx)
            planExercise.plan = newPlan
            planExercise.template = template
            planExercise.cloudSyncStatus = CloudSyncStatus.synced.rawValue
            
            muscleGroupsSet.insert(fbExercise.muscleGroup)
        }
        
        newPlan.muscleGroups = muscleGroupsSet.joined(separator: ",")
        
        do {
            try context.save()
            selectedExercises = []
            objectWillChange.send() // Força atualização da UI
            print("✅ Preview - Plano criado: \(newPlan.displayTitle)")
        } catch {
            throw WorkoutError.saveError(error.localizedDescription)
        }
    }
    
    private func previewEquipmentOptions(for group: MuscleGroup?) -> [String] {
        guard let group = group else { return [] }
        let exercises = fetchPreviewFirebaseExercises()
        let set = Set(
            exercises
                .filter { $0.muscleGroup == group.rawValue }
                .map { $0.equipment }
        )
        let priority = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
        let first = priority.filter { set.contains($0) }
        let others = Array(set.subtracting(priority)).sorted()
        return first + others
    }
    
    private func previewFilteredFirebaseExercises(for group: MuscleGroup?, equipment: String?) -> [FirebaseExercise] {
        let exercises = fetchPreviewFirebaseExercises()
        return exercises
            .filter {
                (group == nil || $0.muscleGroup == group?.rawValue) &&
                (equipment == nil || $0.equipment == equipment)
            }
            .sorted { exercise1, exercise2 in
                exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
            }
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observa mudanças do WorkoutManager apenas se não estiver em preview
        workoutManager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if !(self?.isPreviewMode ?? false) {
                    self?.isLoading = isLoading
                }
            }
            .store(in: &cancellables)
        
        // Observa mudanças do FirebaseExerciseService
        firebaseExerciseService.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if !(self?.isPreviewMode ?? false) {
                    self?.isLoading = isLoading
                }
            }
            .store(in: &cancellables)
        
        // Observa mudanças nos exercícios do Firebase
        firebaseExerciseService.$exercises
            .receive(on: DispatchQueue.main)
            .sink { [weak self] exercises in
                if !(self?.isPreviewMode ?? false) {
                    print("📋 WorkoutViewModel: Firebase exercises atualizados - \(exercises.count) exercícios")
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        // Observa status da rede para sync automático
        #if os(iOS)
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if !(self?.isPreviewMode ?? false) && isConnected {
                    // Trigger sync in background when connected
                    print("📶 Rede conectada - trigger sync automático")
                    Task {
                        await self?.loadFirebaseExercises()
                    }
                }
            }
            .store(in: &cancellables)
        #endif
    }
}

// MARK: - Error Types
enum WorkoutError: LocalizedError {
    case userNotFound
    case fetchError(String)
    case saveError(String)
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "Usuário não encontrado"
        case .fetchError(let message):
            return "Erro ao carregar dados: \(message)"
        case .saveError(let message):
            return "Erro ao salvar dados: \(message)"
        }
    }
}

// MARK: - Extensão de segurança para índices de array
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
