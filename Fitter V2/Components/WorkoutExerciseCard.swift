//
//  WorkoutExerciseCard.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//

import SwiftUI
import SwiftData

struct WorkoutExerciseCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var offset: CGFloat = 0
    @State private var confirmDelete = false

    let exercise: PlanExercise
    let onReplace: () -> Void
    let onDelete: () -> Void
    var onTap: (() -> Void)? = nil
    
    // Computa a opacidade do handle a partir do offset
    private var handleOpacity: Double {
        let progress = min(abs(offset) / 120, 1)   // 0 à 1
        return 1 - progress                       // 1 → 0
    }

    var body: some View {
        ZStack {
            // MARK: – Fundo com botões de ação
            HStack(spacing: 8) {
                Spacer()

                Button(action: onReplace) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 20))
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44) // mantém o frame
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: { confirmDelete = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                        .fontWeight(.heavy)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44) // mantém o frame
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .padding(.horizontal)

            // MARK: – Card principal
            HStack(spacing: 12) {
                // Imagem ou placeholder
                if let imageName = exercise.template?.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.gray)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Nome e equipamento
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.template?.name ?? "Exercício")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(exercise.template?.equipment ?? "")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                // 3️⃣ Handle com opacidade animada
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 20))
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .opacity(handleOpacity)     // usa a variável acima
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
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
                            offset = max(value.translation.width, -120)
                        } else if offset < 0 {
                            offset = min(0, offset + value.translation.width)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            offset = (value.translation.width < -60) ? -120 : 0
                        }
                    }
            )
            .onTapGesture {
                if offset < 0 {
                    // Se o card estiver aberto, apenas feche-o
                    withAnimation(.spring()) {
                        offset = 0
                    }
                } else if let onTap = onTap {
                    // Se o card estiver fechado e tiver uma ação onTap, execute-a
                    onTap()
                }
            }
        }
        .alert("Remover Exercício?", isPresented: $confirmDelete) {
            Button("Cancelar", role: .cancel) {
                withAnimation(.spring()) { offset = 0 }
            }
            Button("Remover", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
    }
}

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

    return VStack(spacing: 16) {
        WorkoutExerciseCard(
            exercise: planExercise,
            onReplace: { print("Substituir") },
            onDelete: { print("Deletar") }
        )
    }
    .padding()
    .background(Color.black)
}
