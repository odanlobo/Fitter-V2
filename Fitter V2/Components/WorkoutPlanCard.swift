//
//  WorkoutPlanCard.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 15/05/25.
//

import SwiftUI

struct WorkoutPlanCard: View {
    @State private var offset: CGFloat = 0
    
    let plan: WorkoutPlan
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var longPress: (() -> Void)? = nil
    
    // Computa a opacidade do handle a partir do offset
    private var handleOpacity: Double {
        let progress = min(abs(offset) / 70, 1)   // 0 à 1
        return 1 - progress                       // 1 → 0
    }

    // Acesso defensivo ao título
    var safeTitle: String {
        // Se o objeto foi deletado, retorna string vazia
        (try? plan.title) ?? ""
    }

    // Acesso defensivo aos grupos musculares
    var safeMuscleGroups: String {
        let order: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
        guard let exercises = try? plan.exercises, !exercises.isEmpty else { return "" }
        let groups = Set(exercises.compactMap { $0.template?.muscleGroup })
        return order.filter { groups.contains($0) }.map { $0.displayName }.joined(separator: " + ")
    }

    var body: some View {
        ZStack {
            // MARK: – Fundo com botão de lixeira
            HStack(spacing: 8) {
                Spacer()

                Button(action: {
                    onDelete?()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                        .fontWeight(.heavy)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .padding(.horizontal)

            // MARK: – Card principal
            HStack(spacing: 12) {
                // Nome e grupos musculares
                VStack(alignment: .leading, spacing: 4) {
                    Text(safeTitle)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    Text(safeMuscleGroups)
                        .font(.system(size: 14, weight: .semibold, design: .default).italic())
                        .foregroundColor(.gray)
                }

                Spacer()

                // Handle com opacidade animada
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 20))
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .opacity(handleOpacity)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if offset < 0 {
                            offset = min(0, offset + value.translation.width)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            offset = value.translation.width < -35 ? -70 : 0
                        }
                    }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        longPress?() // Notifica o pai
                    }
            )
            .onTapGesture {
                if offset < 0 {
                    withAnimation(.spring()) { offset = 0 }
                } else {
                    onTap?()
                }
            }
        }
    }
}

// MARK: - Previews
#Preview {
    let template = ExerciseTemplate(
        templateId: "test_1",
        name: "Supino Reto",
        muscleGroup: .chest,
        equipment: "Barra",
        imageName: nil
    )
    
    let plan = WorkoutPlan(title: "Treino A")
    let planExercise = PlanExercise(order: 0, plan: plan, template: template)
    plan.exercises.append(planExercise)
    
    return VStack(spacing: 16) {
        WorkoutPlanCard(plan: plan, onTap: nil, onDelete: nil)
    }
    .padding()
    .background(Color.black)
}
