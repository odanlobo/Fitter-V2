//
//  ListExerciseViewModel.swift
//  Fitter V2
//
//  REFATORADO em 15/12/25 - ITEM 71 ✅
//  RESPONSABILIDADE: Modernizar para herdar de BaseViewModel mantendo filtros existentes
//  MIGRAÇÃO: Herança de BaseViewModel + eliminação de duplicação de estados
//  ARQUITETURA: Clean Architecture com BaseViewModel inheritance implementada
//

import SwiftUI
import Combine

@MainActor
class ListExerciseViewModel: BaseViewModel {
    // MARK: - Public States (específicos do ListExercise)
    @Published var selectedMuscleGroup: MuscleGroup? = nil
    @Published var selectedEquipment: String? = nil
    @Published var selectedGrip: String? = nil
    @Published var showGripFilter: Bool = true
    @Published var showEquipmentFilter: Bool = true
    @Published var exercises: [FirebaseExercise] = []
    @Published var searchText: String = ""
    
    // MARK: - Selected Exercises Tracking
    var selectedExerciseIds: Set<String> = []
    
    // MARK: - Dependencies (Clean Architecture)
    private let fetchExercisesUseCase: FetchFBExercisesUseCaseProtocol
    
    // MARK: - Init (Dependency Injection)
    init(
        fetchExercisesUseCase: FetchFBExercisesUseCaseProtocol,
        coreDataService: CoreDataServiceProtocol,
        authUseCase: AuthUseCaseProtocol
    ) {
        self.fetchExercisesUseCase = fetchExercisesUseCase
        super.init(coreDataService: coreDataService, authUseCase: authUseCase)
        print("🎯 ListExerciseViewModel inicializado com BaseViewModel + FetchFBExercisesUseCase")
    }
    
    // MARK: - Convenience Init (para compatibilidade e previews)
    convenience init(fetchUseCase: FetchFBExercisesUseCaseProtocol) {
        // Para manter compatibilidade, cria serviços padrão
        let coreDataService = CoreDataService()
        let authService = AuthService(coreDataService: coreDataService)
        let authUseCase = AuthUseCase(authService: authService)
        
        self.init(
            fetchExercisesUseCase: fetchUseCase,
            coreDataService: coreDataService,
            authUseCase: authUseCase
        )
        print("🔄 ListExerciseViewModel com UseCase personalizado")
    }
    
    // MARK: - Filtering Logic (PRESERVADO 100%)

    /// Grupos musculares que possuem exercícios disponíveis
    var availableMuscleGroups: [MuscleGroup] {
        let availableGroups = Set(exercises.compactMap { exercise in
            MuscleGroup(rawValue: exercise.muscleGroup)
        })
        
        // Retorna na ordem preferencial (mesma do WorkoutViewModel)
        let order: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
        let result = order.filter { availableGroups.contains($0) }
        
        print("🔍 Grupos musculares disponíveis: \(result.map { $0.displayName })")
        return result
    }

    /// Equipamentos disponíveis com priorização
    /// Exemplo: Se Firebase tem ["Barra", "TRX", "Halteres", "Elástico"]
    /// Resultado: ["Barra", "Halteres", "Elástico", "TRX"] (priorizados primeiro, depois alfabético)
    var equipmentOptions: [String] {
        guard let group = selectedMuscleGroup else { 
            // Se nenhum grupo selecionado, retorna equipamentos de todos os exercícios
            let allEquipments = Set(exercises.map { $0.equipment })
            
            // Lista de prioridade: estes equipamentos aparecem primeiro (se existirem)
            let priority = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
            let priorityItems = priority.filter { allEquipments.contains($0) }
            
            // Outros equipamentos do Firebase aparecem depois, em ordem alfabética
            let otherItems = Array(allEquipments.subtracting(Set(priority))).sorted()
            
            return priorityItems + otherItems
        }
        
        // Se grupo específico selecionado, retorna apenas equipamentos desse grupo
        let set = Set(filteredExercises(for: group, equipment: nil).map { $0.equipment })
        
        // Lista de prioridade: estes equipamentos aparecem primeiro (se existirem)
        let priority = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
        let priorityItems = priority.filter { set.contains($0) }
        
        // Outros equipamentos do Firebase aparecem depois, em ordem alfabética
        let otherItems = Array(set.subtracting(Set(priority))).sorted()
        let result = priorityItems + otherItems
        
        print("🔍 Equipamentos disponíveis para \(group.displayName): \(result)")
        return result
    }
    
    /// Pegadas disponíveis com priorização  
    /// Exemplo: Se Firebase tem ["Pronada", "Mista", "Supinada", "Hammer"]
    /// Resultado: ["Pronada", "Supinada", "Neutra", "Hammer", "Mista"] (priorizados primeiro, depois alfabético)
    var gripOptions: [String] {
        guard let group = selectedMuscleGroup else { 
            // Se nenhum grupo selecionado, retorna pegadas de todos os exercícios
            let allGrips = Set(exercises.compactMap { $0.displayGripVariation })
            
            // Lista de prioridade: estas pegadas aparecem primeiro (se existirem)
            let priority = ["Pronada", "Supinada", "Neutra"]
            let priorityItems = priority.filter { allGrips.contains($0) }
            
            // Outras pegadas do Firebase aparecem depois, em ordem alfabética
            let otherItems = Array(allGrips.subtracting(Set(priority))).sorted()
            
            return priorityItems + otherItems
        }
        
        // Se grupo específico selecionado, retorna apenas pegadas desse grupo
        let grips = Set(filteredExercises(for: group, equipment: nil).compactMap { $0.displayGripVariation })
        
        // Lista de prioridade: estas pegadas aparecem primeiro (se existirem)
        let priority = ["Pronada", "Supinada", "Neutra"]
        let priorityItems = priority.filter { grips.contains($0) }
        
        // Outras pegadas do Firebase aparecem depois, em ordem alfabética
        let otherItems = Array(grips.subtracting(Set(priority))).sorted()
        let result = priorityItems + otherItems
        
        print("🔍 Pegadas disponíveis para \(group.displayName): \(result)")
        return result
    }
    
    /// Lista de exercícios filtrados e ordenados
    /// Ordenação: 1) Selecionados primeiro (ordem alfabética), 2) Não selecionados (ordem alfabética)
    var filteredFirebaseExercises: [FirebaseExercise] {
        var filtered = exercises
        if let group = selectedMuscleGroup {
            filtered = filtered.filter { $0.muscleGroup == group.rawValue }
        }
        if let equipment = selectedEquipment {
            filtered = filtered.filter { $0.displayEquipment == equipment }
        }
        if let grip = selectedGrip {
            filtered = filtered.filter { $0.displayGripVariation == grip }
        }
        // Filtro de busca (nome, pegada, equipamento)
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let search = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            filtered = filtered.filter { exercise in
                exercise.safeName.lowercased().contains(search) ||
                (exercise.displayGripVariation?.lowercased().contains(search) ?? false) ||
                (exercise.displayEquipment?.lowercased().contains(search) ?? false)
            }
            // Ordenação especial: Nome do Exercício > Equipamento > Pegada
            return filtered.sorted { a, b in
                let nameCompare = a.safeName.localizedCompare(b.safeName)
                if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
                let equipCompare = (a.displayEquipment ?? "").localizedCompare(b.displayEquipment ?? "")
                if equipCompare != .orderedSame { return equipCompare == .orderedAscending }
                let gripCompare = (a.displayGripVariation ?? "").localizedCompare(b.displayGripVariation ?? "")
                if gripCompare != .orderedSame { return gripCompare == .orderedAscending }
                return true
            }
        }
        // Ordena exercícios: selecionados primeiro (alfabético), depois não selecionados (alfabético)
        return filtered.sorted { exercise1, exercise2 in
            let isSelected1 = selectedExerciseIds.contains(exercise1.safeTemplateId)
            let isSelected2 = selectedExerciseIds.contains(exercise2.safeTemplateId)
            if isSelected1 && !isSelected2 {
                return true
            } else if !isSelected1 && isSelected2 {
                return false
            } else {
                return exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
            }
        }
    }
    
    func filteredExercises(for group: MuscleGroup, equipment: String?) -> [FirebaseExercise] {
        exercises
            .filter {
                $0.muscleGroup == group.rawValue && (equipment == nil || $0.displayEquipment == equipment)
            }
            .sorted { exercise1, exercise2 in
                exercise1.safeName.localizedCompare(exercise2.safeName) == .orderedAscending
            }
    }

    // MARK: - Data Loading (REFATORADO com BaseViewModel)

    func loadExercises() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // Não faz nada em preview
            return
        }
        #endif
        
        // ✅ Usa BaseViewModel.withLoading() para gerenciar estado
        await withLoading {
            let input = FetchFBExercisesInput(
                muscleGroup: selectedMuscleGroup?.rawValue,
                equipment: selectedEquipment,
                searchText: searchText.isEmpty ? nil : searchText,
                limit: 100,
                sortBy: "name"
            )
            
            let output = try await fetchExercisesUseCase.fetchExercises(input)
            exercises = output.exercises
            print("✅ \(exercises.count) exercícios carregados via UseCase")
        }
    }
    
    /// Busca exercícios por texto livre
    func searchExercises() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await loadExercises()
            return
        }
        
        // ✅ Usa BaseViewModel.withLoading() para gerenciar estado
        await withLoading {
            let searchResults = try await fetchExercisesUseCase.searchExercises(query: searchText)
            exercises = searchResults
            print("🔍 \(exercises.count) exercícios encontrados para '\(searchText)'")
        }
    }
    
    // MARK: - Filtros (PRESERVADO)

    func resetFilters() {
        selectedMuscleGroup = nil
        selectedEquipment = nil
        selectedGrip = nil
        showGripFilter = true
        showEquipmentFilter = true
        
        // Recarrega exercícios sem filtros
        Task {
            await loadExercises()
        }
    }
    
    // MARK: - Selected Exercises Management (PRESERVADO)
    
    func updateSelectedExercises(_ selectedIds: Set<String>) {
        selectedExerciseIds = selectedIds
        objectWillChange.send() // Força atualização da UI para reordenar lista
    }
    
    // MARK: - Reactive Listeners (REFATORADO)
    
    /// Inicia monitoramento de mudanças de filtros para recarregar automaticamente
    func startReactiveLoading() {
        // Recarrega exercícios quando filtros mudam
        $selectedMuscleGroup
            .combineLatest($selectedEquipment, $selectedGrip)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    await self?.loadExercises()
                }
            }
            .store(in: &cancellables)
        
        // Busca quando texto de pesquisa muda
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.searchExercises()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Para o monitoramento reativo
    func stopReactiveLoading() {
        cancellables.removeAll()
    }
    
    // MARK: - Debug Helper (PRESERVADO)
    
    /// Exemplo de como a ordenação funciona:
    /// Exercícios: ["Supino Inclinado", "Agachamento", "Supino Reto", "Rosca Direta"]
    /// Selecionados: ["Supino Reto", "Agachamento"]
    /// Resultado: ["Agachamento", "Supino Reto", "Rosca Direta", "Supino Inclinado"]
    /// (Selecionados primeiro em ordem alfabética, depois não selecionados em ordem alfabética)
    private func exampleExerciseOrdering() {
        let exercises = ["Supino Inclinado", "Agachamento", "Supino Reto", "Rosca Direta"]
        let selected = Set(["Supino Reto", "Agachamento"])
        
        let result = exercises.sorted { exercise1, exercise2 in
            let isSelected1 = selected.contains(exercise1)
            let isSelected2 = selected.contains(exercise2)
            
            if isSelected1 && !isSelected2 {
                return true
            } else if !isSelected1 && isSelected2 {
                return false
            } else {
                return exercise1.localizedCompare(exercise2) == .orderedAscending
            }
        }
        
        print("🔍 Exemplo ordenação exercícios: \(result)")
        // Output: ["Agachamento", "Supino Reto", "Rosca Direta", "Supino Inclinado"]
    }
}

// MARK: - Preview Support

#if DEBUG
extension ListExerciseViewModel {
    static var preview: ListExerciseViewModel {
        // Mock UseCase para previews
        let mockRepository = MockFirestoreExerciseRepository()
        let mockUseCase = FetchFBExercisesUseCase(repository: mockRepository)
        let vm = ListExerciseViewModel(fetchExercisesUseCase: mockUseCase)
        
        // Ativa modo preview
        vm.isPreviewMode = true
        
        // Popula com exercícios mockados
        vm.exercises = [
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
            ),
            FirebaseExercise(
                templateId: "preview_shoulders_1",
                name: "Desenvolvimento",
                muscleGroup: "shoulders",
                equipment: "Halteres",
                gripVariation: "Neutra",
                description: "Exercício para ombros",
                videoURL: "https://example.com/video3.mp4",
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        return vm
    }
}

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
#endif
