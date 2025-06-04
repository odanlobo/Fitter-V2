//
//  ListExerciseCard.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 24/05/25.
//

import SwiftUI
import SwiftData

/// Componente de card apenas selecionável para exercícios (usado em ListExerciseView, por ex.)
struct ListExerciseCard: View {
    let template: ExerciseTemplate
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var showingImagePopup = false

    var body: some View {
        ZStack {
            // Card principal
            HStack(spacing: 12) {
                // Imagem do exercício ou placeholder
                if let imageName = template.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            showingImagePopup = true
                        }
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.gray)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            showingImagePopup = true
                        }
                }

                // Nome e equipamento
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack {
                        Text(template.equipment)
                        if let grip = template.gripVariation {
                            Text("•")
                            Text("\(grip)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }

                Spacer()

                // Indicador de seleção
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
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
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onTap()
                }
            }

            // Popup da imagem
            if showingImagePopup {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                showingImagePopup = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                        .padding()
                    }

                    if let imageName = template.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.7)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.7)
                            .foregroundColor(.gray)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingImagePopup)
    }
}

// MARK: - Preview
struct ListExerciseCard_Previews: PreviewProvider {
    @State static private var selected = false
    static var previews: some View {
        let template = ExerciseTemplate(
            templateId: "preview_1",
            name: "Supino Reto",
            muscleGroup: .chest,
            equipment: "Barra",
            imageName: nil
        )
        VStack(spacing: 16) {
            ListExerciseCard(template: template, isSelected: selected) {
                // Placeholder for the onTap closure
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
