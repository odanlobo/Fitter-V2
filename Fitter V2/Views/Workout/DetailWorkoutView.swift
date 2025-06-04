//
//  DetailWorkoutView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 15/05/25.
//

import SwiftUI
import SwiftData

struct DetailWorkoutView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var plan: WorkoutPlan
    @State private var isEditing = false

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
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            if isEditing {
                Button("Cancelar") { isEditing = false }
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
                if isEditing { try? modelContext.save() }
                isEditing.toggle()
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
            .disabled(isEditing && plan.title.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
    }

    // MARK: - Content
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isEditing {
                    editableSection
                } else {
                    readOnlySection
                }
                Spacer(minLength: 32)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Editable Section
    private var editableSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(text: "Título do Treino")
            TextField("Título do Treino", text: $plan.title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SectionHeader(text: "Exercícios")
            VStack(spacing: 12) {
                ForEach($plan.exercises) { $exercise in
                    WorkoutExerciseRow(exercise: exercise)
                        .padding(.horizontal)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { plan.exercises.removeAll { $0.id == exercise.id } } label: {
                                Label("Remover", systemImage: "trash")
                            }
                            Button { /* substituir lógica */ } label: {
                                Label("Substituir", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(.gray)
                        }
                }
                Button("Adicionar Exercício") { /* TODO: adicionar */ }
                    .foregroundColor(.blue)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Read-Only Section
    private var readOnlySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(plan.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal)

            let muscles = plan.exercises
                .compactMap { $0.template?.muscleGroup.rawValue.capitalized }
                .joined(separator: " + ")
            if !muscles.isEmpty {
                Text(muscles)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            }

            SectionHeader(text: "Exercícios")
            ForEach(plan.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                WorkoutExerciseRow(exercise: exercise)
                    .padding(.horizontal)
            }

            SectionHeader(text: "Grupos Musculares")
            Image("muscle_groups_map")
                .resizable()
                .scaledToFit()
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
    var exercise: PlanExercise
    var body: some View {
        HStack(spacing: 12) {
            Text(exercise.template?.name ?? "")
                .foregroundColor(.white)
            Spacer()
        }
    }
}
