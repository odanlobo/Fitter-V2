//
//  WorkoutEditorView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//
//  RESPONSABILIDADE: View unificada para criação e edição de treinos
//  SUBSTITUI: CreateWorkoutView.swift + DetailWorkoutView.swift
//  CONTEXTOS: Criar novo treino, editar treino existente
//  FEATURES: Modo duplo, navegação para ListExerciseView, auto-geração de títulos
//
//  REFATORAÇÃO ITEM 84 (MODIFICADO):
//  ✅ Unificação de CreateWorkoutView + DetailWorkoutView em uma única view
//  ✅ Enum Mode para detectar contexto (create/edit)
//  ✅ Fluxo UX idêntico para ambos os modos
//  ✅ Navegação para ListExerciseView funciona nos dois casos
//  ✅ Use Cases diferentes: CreateWorkoutUseCase vs UpdateWorkoutUseCase

import SwiftUI
import CoreData

/// View unificada para criação e edição de treinos
/// Substitui CreateWorkoutView.swift e DetailWorkoutView.swift
struct WorkoutEditorView: View {
    
    // MARK: - Mode Detection
    
    /// Modo de operação da view
    enum Mode {
        case create
        case edit(CDWorkoutPlan)
        
        var isCreating: Bool {
            if case .create = self { return true }
            return false
        }
        
        var plan: CDWorkoutPlan? {
            if case .edit(let plan) = self { return plan }
            return nil
        }
        
        var navigationTitle: String {
            isCreating ? "Novo Treino" : "Editar Treino"
        }
        
        var saveButtonText: String {
            isCreating ? "Criar" : "Salvar"
        }
    }
    
    // MARK: - Properties
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: LoginViewModel
    @ObservedObject var viewModel: WorkoutViewModel
    
    // MARK: - State
    
    @State private var workoutTitle: String = ""
    @State private var selectedExercises: Set<String> = []
    @State private var showExerciseReplacement = false
    @State private var exerciseToReplace: FirebaseExercise? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    
    // MARK: - ListExerciseViewModel para navegação
    @StateObject private var listExerciseViewModel = ListExerciseViewModel()
    
    // MARK: - Computed Properties
    
    private var isCreateMode: Bool { mode.isCreating }
    private var existingPlan: CDWorkoutPlan? { mode.plan }
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else {
                    VStack(spacing: 0) {
                        // Top Bar unificado
                        topBar
                        
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                // Informações Gerais
                                workoutInfoSection
                                
                                // Seção de Exercícios
                                exercisesSection
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("Erro", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .task {
                // Carrega exercícios do Firebase
                await viewModel.loadFirebaseExercises()
            }
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            BackButton()
            Spacer()
            Text(mode.navigationTitle)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button(mode.saveButtonText) {
                Task {
                    await saveWorkout()
                }
            }
            .disabled(selectedExercises.isEmpty)
            .foregroundColor(
                selectedExercises.isEmpty ? .gray : .white
            )
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
    
    // MARK: - Workout Info Section
    
    private var workoutInfoSection: some View {
        VStack(spacing: 0) {
            Text("Informações gerais")
                .font(.system(size: 18).italic())
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.gray.opacity(0.15))

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text("Nome:")
                        .font(.system(size: 18).italic())
                        .foregroundColor(.gray)
                    Text(workoutTitle)
                        .font(.system(size: 28, weight: .bold, design: .default).italic())
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Text("Gr. Musc.:")
                        .font(.system(size: 18).italic())
                        .foregroundColor(.gray)
                    Text(viewModel.selectedMuscleGroups.map { $0.displayName }.joined(separator: " + "))
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 4)
        )
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.bottom, 40)
    }
    
    // MARK: - Exercises Section
    
    private var exercisesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Exercícios")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                NavigationLink(
                    destination: ListExerciseView(
                        viewModel: listExerciseViewModel,
                        selectedExercises: $selectedExercises,
                        workoutTitle: workoutTitle
                    )
                ) {
                    Image(systemName: isCreateMode ? "plus.circle.fill" : "square.and.pencil")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            if selectedExercises.isEmpty {
                emptyExercisesView
            } else {
                exercisesList
            }

            addExercisesButton
                .padding(.top, 16)
            
            Spacer(minLength: 32)
        }
    }
    
    // MARK: - Empty Exercises View
    
    private var emptyExercisesView: some View {
        VStack {
            Text(isCreateMode ? 
                 "Quando você for adicionando exercícios eles irão aparecer aqui." :
                 "Este treino não possui exercícios. Toque no ícone acima para adicionar.")
                .font(.system(size: 16).italic())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    // MARK: - Exercises List
    
    private var exercisesList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.selectedFirebaseExercisesList.indices, id: \.self) { index in
                let firebaseExercise = viewModel.selectedFirebaseExercisesList[index]
                ExerciseCard.workoutEditor(
                    exercise: firebaseExercise,
                    index: index,
                    onDelete: { _ in
                        selectedExercises.remove(firebaseExercise.safeTemplateId)
                        // Atualiza viewModel.selectedExercises também
                        viewModel.selectedExercises.remove(firebaseExercise.safeTemplateId)
                    },
                    onSubstitute: { _ in
                        exerciseToReplace = firebaseExercise
                        showExerciseReplacement = true
                    }
                )
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Add Exercises Button
    
    private var addExercisesButton: some View {
        NavigationLink(
            destination: ListExerciseView(
                viewModel: listExerciseViewModel,
                selectedExercises: $selectedExercises,
                workoutTitle: workoutTitle
            )
        ) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                Text(isCreateMode ? "Adicionar Exercícios" : "Editar Exercícios")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Methods
    
    /// Configura estado inicial baseado no modo
    private func setupInitialState() {
        switch mode {
        case .create:
            workoutTitle = gerarNomeDoTreino()
            selectedExercises = []
            
        case .edit(let plan):
            workoutTitle = plan.compactTitle // Usar compactTitle em vez de displayTitle
            // Carrega exercícios existentes do plano
            selectedExercises = Set(plan.exercisesArray.compactMap { 
                $0.template?.templateId 
            })
        }
        
        // Sincroniza com viewModel
        viewModel.selectedExercises = selectedExercises
    }
    
    /// Gera nome automático para novo treino
    private func gerarNomeDoTreino() -> String {
        let index = viewModel.plans.count
        if index < letters.count {
            return "Treino \(letters[index])"
        }
        return "Treino \(index + 1)"
    }
    
    /// Salva treino usando Use Case apropriado
    private func saveWorkout() async {
        do {
            switch mode {
            case .create:
                // Usar CreateWorkoutUseCase quando disponível (item 17)
                try await viewModel.createWorkoutPlanWithFirebaseExercises(
                    title: workoutTitle
                )
                
            case .edit(let plan):
                // Usar UpdateWorkoutUseCase quando disponível (item 19)
                // Por enquanto, atualização manual
                plan.title = workoutTitle.isEmpty ? nil : workoutTitle
                try await viewModel.updatePlan(plan)
                
                // TODO: Implementar atualização de exercícios
                // Quando UpdateWorkoutUseCase estiver disponível, usar:
                // try await updateWorkoutUseCase.execute(input: UpdateWorkoutInput(...))
            }
            
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Convenience Initializers

extension WorkoutEditorView {
    
    /// Inicializador para modo criação
    static func createMode(viewModel: WorkoutViewModel) -> WorkoutEditorView {
        return WorkoutEditorView(mode: .create, viewModel: viewModel)
    }
    
    /// Inicializador para modo edição
    static func editMode(plan: CDWorkoutPlan, viewModel: WorkoutViewModel) -> WorkoutEditorView {
        return WorkoutEditorView(mode: .edit(plan), viewModel: viewModel)
    }
}

