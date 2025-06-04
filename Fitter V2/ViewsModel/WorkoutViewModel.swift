//
//  WorkoutViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//

import SwiftUI
import SwiftData

@MainActor
final class WorkoutViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var plans: [WorkoutPlan] = []
    @Published var selectedExercises: Set<String> = []
    @Published private(set) var exercises: [ExerciseTemplate] = []
    @Published private(set) var isLoading = false
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private var currentUserId: UUID? // Guarda apenas o id do usuário logado
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    
    // MARK: - Initialization
    init(modelContext: ModelContext, userId: UUID? = nil) {
        self.modelContext = modelContext
        self.currentUserId = userId
    }
    
    // MARK: - Public Methods
    /// Atualiza o usuário logado (deve ser chamado sempre que o usuário mudar)
    func updateUser(_ user: AppUser?) {
        currentUserId = user?.id
    }
    
    /// Busca apenas os planos do usuário atual
    func loadPlansForCurrentUser() async throws {
        guard let userId = currentUserId else {
            print("Nenhum usuário logado no ViewModel!")
            await MainActor.run {
                plans = []
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        let descriptor = FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.order)])
        let allPlans = try modelContext.fetch(descriptor)
        print("Total de planos encontrados no contexto: \(allPlans.count)")
        for plan in allPlans {
            print("Plano: \(plan.title), userId: \(String(describing: plan.user?.id)), esperado: \(userId)")
        }
        
        let filteredPlans = allPlans.filter { $0.user?.id == userId }
        print("Planos filtrados para o usuário: \(filteredPlans.count)")
        
        await MainActor.run {
            plans = filteredPlans
            print("🔄 UI atualizada com \(plans.count) planos")
        }
    }
    
    func loadExercises() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let request = FetchDescriptor<ExerciseTemplate>()
        do {
            exercises = try modelContext.fetch(request)
        } catch {
            throw WorkoutError.fetchError(error.localizedDescription)
        }
    }
    
    /// Adiciona um novo plano para o usuário atual
    func addPlan(_ plan: WorkoutPlan) async throws {
        guard let userId = currentUserId else {
            throw WorkoutError.userNotFound
        }
        // Busca o usuário no contexto atual para garantir referência correta
        let userDescriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == userId })
        guard let user = try? modelContext.fetch(userDescriptor).first else {
            throw WorkoutError.userNotFound
        }
        plan.user = user
        modelContext.insert(plan)
        
        do {
            try modelContext.save()
            try await loadPlansForCurrentUser()
            // Limpa seleção após criar
            await MainActor.run {
                self.selectedExercises = []
            }
        } catch {
            throw WorkoutError.saveError(error.localizedDescription)
        }
    }
    
    func move(fromOffsets: IndexSet, toOffset: Int) {
        var revised = plans
        revised.move(fromOffsets: fromOffsets, toOffset: toOffset)
        applyOrderAndTitles(to: revised)
    }
    
    /// Remove um plano de forma segura buscando fresh no contexto
    func deletePlanById(_ id: UUID) async throws {
        guard let userId = currentUserId else { throw WorkoutError.userNotFound }
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate { $0.id == id && $0.user?.id == userId })
        guard let plan = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(plan)
        try modelContext.save()
        try await loadPlansForCurrentUser()
    }
    
    /// Atualiza um plano existente
    func updatePlan(_ plan: WorkoutPlan) async throws {
        guard let userId = currentUserId else {
            throw WorkoutError.userNotFound
        }
        
        // Verifica se o plano pertence ao usuário atual
        guard plan.user?.id == userId else {
            throw WorkoutError.saveError("Tentativa de editar plano de outro usuário")
        }
        
        do {
            try modelContext.save()
            // Recarrega a lista para atualizar a UI
            try await loadPlansForCurrentUser()
            print("✅ Plano '\(plan.title)' atualizado com sucesso")
        } catch {
            throw WorkoutError.saveError("Erro ao atualizar plano: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    private func applyOrderAndTitles(to array: [WorkoutPlan]) {
        for (idx, plan) in array.enumerated() {
            plan.order = idx
            let suffix = idx < letters.count ? String(letters[idx]) : "\(idx + 1)"
            plan.title = "Treino \(suffix)"
        }
        
        do {
            try modelContext.save()
            plans = array
        } catch {
            print("Erro ao salvar ordem dos treinos: \(error)")
        }
    }
    
    // MARK: - Computed Properties
    var selectedExercisesList: [ExerciseTemplate] {
        exercises.filter { selectedExercises.contains($0.templateId) }
    }
    
    var selectedMuscleGroups: [MuscleGroup] {
        let order: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
        let groups = Set(selectedExercisesList.map { $0.muscleGroup })
        return order.filter { groups.contains($0) }
    }
    
    func equipmentOptions(for group: MuscleGroup?) -> [String] {
        guard let group = group else { return [] }
        let set = Set(
            exercises
                .filter { $0.muscleGroup == group }
                .map { $0.equipment }
        )
        let priority = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
        let first = priority.filter { set.contains($0) }
        let others = set.subtracting(priority).sorted()
        return first + others
    }
    
    func filteredExercises(for group: MuscleGroup?, equipment: String?) -> [ExerciseTemplate] {
        exercises.filter {
            (group == nil || $0.muscleGroup == group) &&
            (equipment == nil || $0.equipment == equipment)
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
