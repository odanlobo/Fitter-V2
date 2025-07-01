//
//  WorkoutExerciseCard.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//

// MARK: - WorkoutExerciseCard.swift
// Componente reordenável para exercícios salvos localmente
// Responsável apenas pela UI e callbacks, sem lógica de negócio
// Padrão Clean Architecture - Fitter App V2
//
// Contextos: Criação, edição e treino ativo
// Features: Drag & drop, swipe actions (Substituir/Deletar), drag handle sempre visível
// Compatível com ExerciseDisplayable
//
// Pendências:
// - [ ] Integrar ExerciseCardContent/ExerciseCardMediaView quando disponíveis (itens 36-37 do REFATORAÇÃO.md)

import SwiftUI

/// Card reordenável para exercícios salvos localmente (CDPlanExercise, CDCurrentExercise, etc)
/// Compatível com Clean Architecture e ExerciseDisplayable
struct WorkoutExerciseCard: View {
    // MARK: - Propriedades
    /// Exercício a ser exibido (deve conformar ExerciseDisplayable)
    let exercise: ExerciseDisplayable
    /// Índice do exercício na lista
    let index: Int
    /// Indica se o exercício está ativo (destaque visual)
    let isActive: Bool
    /// Indica se é o primeiro item (UX de borda/cantos)
    let isFirst: Bool
    /// Indica se é o último item (UX de borda/cantos)
    let isLast: Bool
    /// Modo de exibição do card (creation, editableList, activeWorkout, etc)
    let displayMode: ExerciseCardDisplayMode
    /// Callback para reordenação (drag & drop)
    let onMove: (_ from: Int, _ to: Int) -> Void
    /// Callback para deleção via swipe
    let onDelete: (_ index: Int) -> Void
    /// Callback para substituição via swipe
    let onSubstitute: (_ index: Int) -> Void
    /// Callback para tap no card (abrir detalhes, editar, etc)
    let onTap: (_ exercise: ExerciseDisplayable) -> Void
    
    // MARK: - Estado interno
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            cardContent
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
                        .shadow(color: isActive ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.04), radius: isActive ? 6 : 2, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.accentColor : Color(.separator), lineWidth: isActive ? 2 : 1)
                )
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    // Drag & drop será controlado pela lista (ex: ForEach com .onMove)
                }
        )
        .onTapGesture {
            onTap(exercise)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(index)
            } label: {
                Label("Deletar", systemImage: "trash")
            }
            Button {
                onSubstitute(index)
            } label: {
                Label("Substituir", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(.blue)
        }
    }
    
    /// Conteúdo visual principal do card
    private var cardContent: some View {
        HStack(spacing: 12) {
            // Thumbnail/vídeo (placeholder por enquanto)
            Group {
                if let url = exercise.videoURL, !url.isEmpty {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: 56, height: 56)
                            .cornerRadius(8)
                        Image(systemName: "play.rectangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.accentColor)
                    }
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.10))
                            .frame(width: 56, height: 56)
                            .cornerRadius(8)
                        Image(systemName: "figure.strengthtraining.traditional")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                    }
                }
            }
            // Conteúdo textual principal
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if isActive {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    }
                }
                Text(exercise.muscleGroup)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(exercise.equipment)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // Drag handle sempre visível
            Image(systemName: "line.horizontal.3")
                .foregroundColor(.gray)
                .padding(.trailing, 2)
        }
        .padding(.vertical, 10)
        .padding(.leading, 8)
        .padding(.trailing, 4)
    }
}

// MARK: - Preview
#if DEBUG
/// Preview usando dados mock do MockDataProvider
struct WorkoutExerciseCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            WorkoutExerciseCard(
                exercise: MockDataProvider.examplePlanExercise,
                index: 0,
                isActive: true,
                isFirst: true,
                isLast: false,
                displayMode: .creation,
                onMove: { _,_ in },
                onDelete: { _ in },
                onSubstitute: { _ in },
                onTap: { _ in }
            )
            WorkoutExerciseCard(
                exercise: MockDataProvider.examplePlanExercise,
                index: 1,
                isActive: false,
                isFirst: false,
                isLast: true,
                displayMode: .editableList,
                onMove: { _,_ in },
                onDelete: { _ in },
                onSubstitute: { _ in },
                onTap: { _ in }
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
    }
}
#endif 