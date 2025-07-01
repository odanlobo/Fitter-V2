//
//  WorkoutPlanCard.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 15/05/25.
//
//  Refatorado seguindo o padrão dos novos cards reordenáveis do app Fitter.
//  - Visual moderno, drag handle sempre visível
//  - Callbacks para tap e delete
//  - Sem lógica de negócio, apenas UI
//  - Comentários e documentação em português

import SwiftUI
import CoreData

/// Card visual para exibir um plano de treino, pronto para listas reordenáveis.
/// - Exibe título, grupos musculares e drag handle.
/// - Permite swipe para exclusão e tap para detalhes.
struct WorkoutPlanCard: View {
    /// Plano de treino a ser exibido
    let plan: CDWorkoutPlan
    /// Callback ao tocar no card
    var onTap: (() -> Void)? = nil
    /// Callback ao solicitar exclusão
    var onDelete: (() -> Void)? = nil

    @GestureState private var dragOffset: CGFloat = 0

    /// Grupos musculares do plano, formatados para exibição
    var safeMuscleGroups: String {
        let order: [MuscleGroup] = [.chest, .back, .legs, .biceps, .triceps, .shoulders, .core]
        let exercises = plan.exercisesArray
        guard !exercises.isEmpty else { return "" }
        let groups: Set<MuscleGroup> = Set(exercises.compactMap { exercise in
            guard let muscleGroupString = exercise.template?.muscleGroup else { return nil }
            return MuscleGroup(rawValue: muscleGroupString)
        })
        return order.filter { groups.contains($0) }.map { $0.displayName }.joined(separator: " + ")
    }

    /// Opacidade do drag handle durante o arrasto
    var linesOpacity: Double {
        let progress = min(max(abs(dragOffset) / 80, 0), 1)
        return 1.0 - progress
    }

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Exibe o título do plano (padrão displayTitle)
                    Text(plan.displayTitle)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    if !safeMuscleGroups.isEmpty {
                        Text(safeMuscleGroups)
                            .font(.system(size: 14, weight: .semibold, design: .default).italic())
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                // Drag handle sempre visível
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(linesOpacity)
                    .animation(.easeInOut(duration: 0.18), value: linesOpacity)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Excluir", systemImage: "trash")
            }
        }
    }
}

// MARK: - Previews
#Preview {
    // Usa o contexto de preview com dados mockados
    let viewContext = PreviewCoreDataStack.shared.viewContext
    
    // Busca um plano existente dos dados mockados
    let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
    request.fetchLimit = 1
    
    if let plan = try? viewContext.fetch(request).first {
        return VStack(spacing: 16) {
            WorkoutPlanCard(
                plan: plan,
                onTap: { print("Plano selecionado: \(plan.displayTitle)") },
                onDelete: { print("Delete solicitado para: \(plan.displayTitle)") }
            )
        }
        .padding()
        .background(Color.black)
    } else {
        // Fallback caso não encontre dados mockados
        return VStack {
            Text("Nenhum plano encontrado nos dados de preview")
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black)
    }
}
