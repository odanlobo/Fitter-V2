//
//  CreateWorkoutView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 14/05/25.
//

import SwiftUI
import SwiftData

struct CreateWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: LoginViewModel
    
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var workoutTitle: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var selectedEquipment: String? = nil
    @State private var showExerciseReplacement = false
    @State private var exerciseToReplace: ExerciseTemplate? = nil
    @State private var showError = false
    @State private var errorMessage = ""

    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

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
                        // Top Bar
                        HStack {
                            BackButton()
                            Spacer()
                            Text("Novo Treino")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Button("Salvar") {
                                Task {
                                    do {
                                        let planExercises = viewModel.selectedExercisesList.enumerated().map { idx, tpl in
                                            PlanExercise(order: idx, plan: nil, template: tpl)
                                        }
                                        let newPlan = WorkoutPlan(
                                            title: workoutTitle,
                                            createdAt: Date(),
                                            order: viewModel.plans.count
                                        )
                                        newPlan.exercises = planExercises
                                        try await viewModel.addPlan(newPlan)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            }
                            .disabled(viewModel.selectedExercises.isEmpty)
                            .foregroundColor(
                                viewModel.selectedExercises.isEmpty ? .gray : .white
                            )
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                // Informações Gerais
                                WorkoutInfoSection(workoutTitle: workoutTitle,
                                                 muscleGroups: viewModel.selectedMuscleGroups)
                                
                                // Seção de Exercícios
                                ExercisesSection(
                                    viewModel: viewModel,
                                    selectedExercises: $viewModel.selectedExercises,
                                    workoutTitle: workoutTitle,
                                    exerciseToReplace: $exerciseToReplace,
                                    showExerciseReplacement: $showExerciseReplacement
                                )
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
                do {
                    try await viewModel.loadExercises()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
        .onAppear {
            workoutTitle = gerarNomeDoTreino()
        }
    }
    
    private func gerarNomeDoTreino() -> String {
        let index = viewModel.plans.count
        if index < letters.count {
            return "Treino \(letters[index])"
        }
        return "Treino \(index + 1)"
    }
}

// MARK: - Subviews
private struct WorkoutInfoSection: View {
    let workoutTitle: String
    let muscleGroups: [MuscleGroup]
    
    var body: some View {
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
                    Text(muscleGroups.map { $0.displayName }.joined(separator: " + "))
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
}

private struct ExercisesSection: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Binding var selectedExercises: Set<String>
    let workoutTitle: String
    @Binding var exerciseToReplace: ExerciseTemplate?
    @Binding var showExerciseReplacement: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Exercícios")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                NavigationLink(
                    destination: ListExerciseView(
                        selectedExercises: $selectedExercises,
                        workoutTitle: workoutTitle
                    )
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            if selectedExercises.isEmpty {
                EmptyExercisesView()
            } else {
                ExercisesList(
                    viewModel: viewModel,
                    exerciseToReplace: $exerciseToReplace,
                    showExerciseReplacement: $showExerciseReplacement
                )
            }

            AddExercisesButton(workoutTitle: workoutTitle, selectedExercises: $selectedExercises)
                .padding(.top, 16)
        }
        Spacer(minLength: 32)
    }
}

private struct EmptyExercisesView: View {
    var body: some View {
        VStack {
            Text("Quando você for adicionando exercícios eles irão aparecer aqui.")
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
}

private struct ExercisesList: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Binding var exerciseToReplace: ExerciseTemplate?
    @Binding var showExerciseReplacement: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.selectedExercisesList) { tpl in
                let idx = viewModel.selectedExercisesList.firstIndex(of: tpl) ?? 0
                let temp = PlanExercise(
                    order: idx,
                    plan: nil,
                    template: tpl
                )
                WorkoutExerciseCard(
                    exercise: temp,
                    onReplace: {
                        exerciseToReplace = tpl
                        showExerciseReplacement = true
                    },
                    onDelete: {
                        viewModel.selectedExercises.remove(tpl.templateId)
                    }
                )
            }
        }
        .padding(.horizontal)
    }
}

private struct AddExercisesButton: View {
    let workoutTitle: String
    @Binding var selectedExercises: Set<String>
    
    var body: some View {
        NavigationLink(
            destination: ListExerciseView(
                selectedExercises: $selectedExercises,
                workoutTitle: workoutTitle
            )
        ) {
            Text("Adicionar exercícios +")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}
