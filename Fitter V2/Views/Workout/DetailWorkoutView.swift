//
//  DetailWorkoutView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 15/05/25.
//

import SwiftUI

struct DetailWorkoutView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var isEditing = false
    @State private var workoutTitle: String = ""
    let plan: CDWorkoutPlan

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider().background(Color.gray)
                content
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            workoutTitle = plan.displayTitle
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            if isEditing {
                Button("Cancelar") { 
                    isEditing = false
                    workoutTitle = plan.displayTitle // Reset title
                }
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .semibold))
            } else {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            Spacer()
            Button(action: {
                if isEditing {
                    Task {
                        do {
                            plan.title = workoutTitle
                            try await viewModel.updatePlan(plan)
                            isEditing = false
                        } catch {
                            print("❌ Erro ao salvar plano: \(error)")
                        }
                    }
                } else {
                    isEditing = true
                }
            }) {
                if isEditing {
                    Text("Salvar")
                        .foregroundColor(.green)
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Image(systemName: "square.and.pencil")
                        .imageScale(.large)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                }
            }
            .disabled(isEditing && workoutTitle.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
    }

    // MARK: - Content
    private var content: some View {
        ScrollView {
            if isEditing {
                editingSection
            } else {
                readOnlySection
            }
        }
    }

    private var editingSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField("Nome do treino", text: $workoutTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal)

            SectionHeader(text: "Exercícios")
            ForEach(plan.exercisesArray.sorted(by: { $0.order < $1.order })) { exercise in
                WorkoutExerciseRow(exercise: exercise)
                    .padding(.horizontal)
            }

            SectionHeader(text: "Grupos Musculares")
            Text(plan.muscleGroupsString)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
        }
    }

    private var readOnlySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(plan.displayTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal)

            Text(plan.muscleGroupsString)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)

            SectionHeader(text: "Exercícios")
            ForEach(plan.exercisesArray.sorted(by: { $0.order < $1.order })) { exercise in
                WorkoutExerciseRow(exercise: exercise)
                    .padding(.horizontal)
            }

            SectionHeader(text: "Grupos Musculares")
            Text(plan.muscleGroupsString)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.green)
            .padding(.horizontal)
    }
}

// MARK: - Exercise Row
struct WorkoutExerciseRow: View {
    var exercise: CDPlanExercise
    var body: some View {
        HStack(spacing: 12) {
            Text(exercise.template?.safeName ?? "Exercício")
                .foregroundColor(.white)
            Spacer()
        }
    }
}
