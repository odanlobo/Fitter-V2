//
//  WorkoutViewModel.swift
//  Fitter V2
//
//  REFATORADO em 15/12/25 - ITEM 72 ✅
//  RESPONSABILIDADE: Herdar de BaseViewModel e usar Use Cases ao invés de WorkoutManager diretamente
//  MIGRAÇÃO: BaseViewModel inheritance + Use Cases migration + eliminação de violações críticas
//  ARQUITETURA: Clean Architecture com BaseViewModel + Use Cases orquestração
//

import SwiftUI
import Combine
import CoreData

@MainActor
final class WorkoutViewModel: BaseViewModel {
    // MARK: - Constants
    /// Ordem padrão dos grupos musculares para exibição
    /// Esta ordem é usada em toda a aplicação para consistência:
    /// - CreateWorkoutView: exercícios selecionados e grupos musculares
    /// - ListExerciseView: filtros de grupos disponíveis
    /// - WorkoutView: visualização de planos
    static let muscleGroupDisplayOrder: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
    
    // MARK: - Published Properties (específicos do Workout)
    @Published var selectedExercises: Set<String> = []
    @Published var exercises: [FirebaseExercise] = []
    
    // MARK: - Use Cases (Clean Architecture)
    private let fetchExercisesUseCase: FetchFBExercisesUseCaseProtocol
    private let createWorkoutUseCase: CreateWorkoutUseCaseProtocol
    private let updateWorkoutUseCase: UpdateWorkoutUseCaseProtocol
    private let deleteWorkoutUseCase: DeleteWorkoutUseCaseProtocol
    private let reorderWorkoutUseCase: ReorderWorkoutUseCaseProtocol
    private let fetchWorkoutUseCase: FetchWorkoutUseCaseProtocol
    
    // MARK: - Private Properties
    private let networkMonitor: NetworkMonitor
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    
    // MARK: - Computed Properties
    var plans: [CDWorkoutPlan] {
        if isPreviewMode {
            return fetchPreviewPlans()
        } else {
            return fetchedPlans
        }
    }
    
    @Published private var fetchedPlans: [CDWorkoutPlan] = []
    
    // FIREBASE EXERCISES - Nova fonte principal via UseCase
    var firebaseExercises: [FirebaseExercise] {
        if isPreviewMode {
            return fetchPreviewFirebaseExercises()
        } else {
            return exercises
        }
    }
    
    // LOCAL EXERCISES - Apenas para exercícios já salvos nos planos
    var localExercises: [CDExerciseTemplate] {
        if isPreviewMode {
            return fetchPreviewExercises()
        } else {
            return fetchedLocalExercises
        }
    }
    
    @Published private var fetchedLocalExercises: [CDExerciseTemplate] = []
    
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
    
    // MARK: - Initialization (Dependency Injection)
    init(
        createUseCase: CreateWorkoutUseCaseProtocol,
        fetchUseCase: FetchWorkoutUseCaseProtocol,
        updateUseCase: UpdateWorkoutUseCaseProtocol,
        deleteUseCase: DeleteWorkoutUseCaseProtocol,
        reorderWorkoutUseCase: ReorderWorkoutUseCaseProtocol,
        reorderExerciseUseCase: ReorderExerciseUseCaseProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol,
        fetchFBExercisesUseCase: FetchFBExercisesUseCaseProtocol,
        networkMonitor: NetworkMonitor = .shared,
        coreDataService: CoreDataServiceProtocol,
        authUseCase: AuthUseCaseProtocol
    ) {
        self.fetchExercisesUseCase = fetchFBExercisesUseCase
        self.createWorkoutUseCase = createUseCase
        self.updateWorkoutUseCase = updateUseCase
        self.deleteWorkoutUseCase = deleteUseCase
        self.reorderWorkoutUseCase = reorderWorkoutUseCase
        self.fetchWorkoutUseCase = fetchUseCase
        self.networkMonitor = networkMonitor
        
        super.init(coreDataService: coreDataService, authUseCase: authUseCase)
        
        setupObservers()
        print("🎯 WorkoutViewModel inicializado com BaseViewModel + Use Cases")
    }
    

    
    // MARK: - Public Methods
    
    /// Busca planos do usuário atual via Use Case
    func loadPlansForCurrentUser() async {
        guard let user = currentUser else {
            print("Nenhum usuário logado no ViewModel!")
            return
        }
        
        if isPreviewMode {
            print("🎯 Preview mode detectado - carregando dados do contexto de preview")
            objectWillChange.send() // Força atualização da UI
        } else {
            await executeUseCase {
                let input = FetchAllWorkoutsInput(user: user)
                let output = try await fetchWorkoutUseCase.fetchAllWorkouts(input)
                fetchedPlans = output.workouts
                print("✅ \(fetchedPlans.count) planos carregados via Use Case")
            }
        }
    }
    
    /// Carrega exercícios do Firebase via UseCase
    func loadFirebaseExercises() async {
        if isPreviewMode {
            print("🎯 Preview mode - exercícios Firebase simulados")
            objectWillChange.send() // Força atualização da UI
            return
        }
        
        await executeUseCase {
            let input = FetchFBExercisesInput(
                muscleGroup: nil,
                equipment: nil,
                searchText: nil,
                limit: 200,
                sortBy: "name"
            )
            
            let output = try await fetchExercisesUseCase.fetchExercises(input)
            exercises = output.exercises
            print("✅ \(exercises.count) exercícios carregados via UseCase")
        }
    }
    
    /// Carrega exercícios locais (apenas para compatibilidade)
    func loadExercises() async {
        // Mantém compatibilidade, mas agora carrega exercícios do Firebase
        await loadFirebaseExercises()
    }
    
    /// Busca exercícios por texto livre
    func searchExercises(query: String) async {
        if isPreviewMode {
            print("🎯 Preview mode - busca simulada")
            return
        }
        
        await executeUseCase {
            let searchResults = try await fetchExercisesUseCase.searchExercises(query: query)
            exercises = searchResults
            print("🔍 \(exercises.count) exercícios encontrados para '\(query)'")
        }
    }
    
    /// Cria um novo plano de treino via Use Case
    func createWorkoutPlan(title: String, selectedFirebaseExercises: [FirebaseExercise]) async throws {
        guard let user = currentUser else {
            throw WorkoutError.userNotFound
        }
        
        if isPreviewMode {
            try await createPreviewWorkoutPlan(title: title, user: user, firebaseExercises: selectedFirebaseExercises)
        } else {
            // Converte exercícios Firebase para templates locais
            let templates = selectedFirebaseExercises.map { $0.toCoreDataTemplate(context: viewContext) }
            
            let input = CreateWorkoutInput(
                title: title.isEmpty ? nil : title,
                muscleGroups: generateMuscleGroups(from: selectedFirebaseExercises),
                user: user,
                exerciseTemplates: templates
            )
            
            let output = try await createWorkoutUseCase.execute(input)
            selectedExercises = [] // Limpa seleção após criar
            
            // Recarrega planos após criação
            await loadPlansForCurrentUser()
            
            print("✅ Plano criado via Use Case: \(output.workoutPlan.displayTitle)")
        }
    }
    
    /// Cria plano com exercícios do Firebase (novo método principal)
    func createWorkoutPlanWithFirebaseExercises(title: String) async throws {
        let selectedFirebaseExercises = selectedFirebaseExercisesList
        try await createWorkoutPlan(title: title, selectedFirebaseExercises: selectedFirebaseExercises)
    }
    
    /// Reordena planos via Use Case
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
            
            // Atualiza via Use Case
            Task {
                await executeUseCase {
                    let input = ReorderWorkoutInput(workoutPlans: revised, user: currentUser)
                    let output = try await reorderWorkoutUseCase.execute(input)
                    print("✅ Reordenação concluída via Use Case: \(output.affectedCount) planos")
                    
                    // Recarrega planos após reordenação
                    await loadPlansForCurrentUser()
                }
            }
        }
    }
    
    /// Remove plano via Use Case
    func deletePlan(_ plan: CDWorkoutPlan) async throws {
        if isPreviewMode {
            print("🎯 Preview mode - delete simulado para: \(plan.displayTitle)")
            // Em preview, apenas simula a remoção
            objectWillChange.send()
        } else {
            let input = DeleteWorkoutInput(workoutPlan: plan)
            let output = try await deleteWorkoutUseCase.execute(input)
            
            // Recarrega planos após exclusão
            await loadPlansForCurrentUser()
            
            print("✅ Plano excluído via Use Case: \(output.deletedPlan.displayTitle)")
        }
    }
    
    /// Atualiza plano existente via Use Case
    func updatePlan(_ plan: CDWorkoutPlan) async throws {
        guard currentUser != nil else {
            throw WorkoutError.userNotFound
        }
        
        if isPreviewMode {
            print("🎯 Preview mode - update simulado para: \(plan.displayTitle)")
            // Em preview, apenas simula a atualização
            objectWillChange.send()
        } else {
            let input = UpdateWorkoutInput(workoutPlan: plan)
            let output = try await updateWorkoutUseCase.execute(input)
            
            // Recarrega planos após atualização
            await loadPlansForCurrentUser()
            
            print("✅ Plano atualizado via Use Case: \(output.updatedWorkoutPlan.displayTitle)")
        }
    }
    
    // MARK: - Firebase Exercise Helper Methods (REFATORADO)
    
    func equipmentOptions(for group: MuscleGroup?) -> [String] {
        if isPreviewMode {
            return previewEquipmentOptions(for: group)
        } else {
            let relevantExercises = group != nil ? 
                exercises.filter { $0.muscleGroup == group?.rawValue } : 
                exercises
            
            let equipmentSet = Set(relevantExercises.map { $0.equipment })
            
            // Lista de prioridade: estes equipamentos aparecem primeiro (se existirem)
            let priority = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
            let priorityItems = priority.filter { equipmentSet.contains($0) }
            
            // Outros equipamentos aparecem depois, em ordem alfabética
            let otherItems = Array(equipmentSet.subtracting(Set(priority))).sorted()
            
            return priorityItems + otherItems
        }
    }
    
    func filteredFirebaseExercises(for group: MuscleGroup?, equipment: String?) -> [FirebaseExercise] {
        if isPreviewMode {
            return previewFilteredFirebaseExercises(for: group, equipment: equipment)
        } else {
            return exercises
                .filter {
                    (group == nil || $0.muscleGroup == group?.rawValue) &&
                    (equipment == nil || $0.equipment == equipment)
                }
                .sorted { exercise1, exercise2 in
                    exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
                }
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
    
    // MARK: - Private Methods
    
    private func generateMuscleGroups(from exercises: [FirebaseExercise]) -> String {
        let muscleGroups = Set(exercises.map { $0.muscleGroup })
        return muscleGroups.sorted().joined(separator: ", ")
    }
    
    private func setupObservers() {
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
    
    // MARK: - Preview Helper Methods (PRESERVADO)
    
    private func fetchPreviewPlans() -> [CDWorkoutPlan] {
        guard let user = currentUser else { return [] }
        
        let context = viewContext
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
        let context = viewContext
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
                description: "Exercício básico para peitorais",
                videoURL: "https://example.com/video1.mp4",
                createdAt: Date(),
                updatedAt: Date()
            ),
            FirebaseExercise(
                templateId: "preview_back_1",
                name: "Puxada Aberta",
                muscleGroup: "back",
                equipment: "Polia",
                gripVariation: "Pronada",
                description: "Exercício para dorsais",
                videoURL: "https://example.com/video2.mp4",
                createdAt: Date(),
                updatedAt: Date()
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
        let context = viewContext
        
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

// MARK: - Preview Support
// MARK: - Mock Repository para Previews

private class MockFirestoreExerciseRepository: FirestoreExerciseRepositoryProtocol {
    func fetchExercises(
        muscleGroup: String?,
        equipment: String?,
        searchText: String?,
        limit: Int,
        sortBy: String
    ) async throws -> [FirebaseExercise] {
        // Retorna exercícios mockados para previews
        return []
    }
}

#if DEBUG
extension WorkoutViewModel {
    
    /// Cria instância para preview
    /// - Parameter mockUser: Usuário mock para usar no preview
    /// - Returns: WorkoutViewModel configurado para preview
    static func previewInstance(with mockUser: CDAppUser? = nil) -> WorkoutViewModel {
        // Para preview, usa mocks simples
        let mockRepository = MockFirestoreExerciseRepository()
        let mockFetchFBUseCase = FetchFBExercisesUseCase(repository: mockRepository)
        let mockCoreDataService = CoreDataService()
        let mockAuthService = AuthService(coreDataService: mockCoreDataService)
        let mockAuthUseCase = AuthUseCase(authService: mockAuthService)
        let mockWorkoutDataService = WorkoutDataService(coreDataService: mockCoreDataService, adapter: CoreDataAdapter())
        let mockSubscriptionManager = SubscriptionManager.shared
        let mockSyncUseCase = SyncWorkoutUseCase()
        
        let vm = WorkoutViewModel(
            createUseCase: CreateWorkoutUseCase(workoutDataService: mockWorkoutDataService, subscriptionManager: mockSubscriptionManager, syncUseCase: mockSyncUseCase),
            fetchUseCase: FetchWorkoutUseCase(workoutDataService: mockWorkoutDataService),
            updateUseCase: UpdateWorkoutUseCase(workoutDataService: mockWorkoutDataService, syncUseCase: mockSyncUseCase),
            deleteUseCase: DeleteWorkoutUseCase(workoutDataService: mockWorkoutDataService, syncUseCase: mockSyncUseCase),
            reorderWorkoutUseCase: ReorderWorkoutUseCase(workoutDataService: mockWorkoutDataService, syncUseCase: mockSyncUseCase),
            reorderExerciseUseCase: ReorderExerciseUseCase(workoutDataService: mockWorkoutDataService, syncUseCase: mockSyncUseCase),
            syncUseCase: mockSyncUseCase,
            fetchFBExercisesUseCase: mockFetchFBUseCase,
            coreDataService: mockCoreDataService,
            authUseCase: mockAuthUseCase
        )
        vm.configureForPreview(mockUser: mockUser)
        return vm
    }
}
#endif
