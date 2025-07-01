//
//  UploadButton.swift
//  Fitter V2
//
//
//  Created by Daniel Lobo on 26/06/25.

// MARK: - UploadButton.swift
// Componente de botão para upload/importação de treinos existentes
// Responsável apenas pela UI e callbacks, sem lógica de negócio
// Padrão Clean Architecture - Fitter App V2
//
// Contextos: Importação de treinos via câmera, galeria de fotos ou arquivos (PDF, CSV, imagem)
// Features: Botão principal, sheet de opções, preparado para integração futura com lógica de upload
//
// ✅ Integração:
// ✅ Callbacks específicos para cada tipo de importação (onCameraAction, onPhotosAction, onFilesAction)
// ✅ Interface preparada para integração com ImportWorkoutUseCase e ImportWorkoutService
// ✅ UI responsiva e moderna com apresentação via sheet
//

import SwiftUI

/// Botão para importar treinos existentes (UI apenas)
struct UploadButton: View {
    /// Callback para importação via câmera
    var onCameraAction: (() -> Void)?
    /// Callback para importação via galeria de fotos
    var onPhotosAction: (() -> Void)?
    /// Callback para importação via arquivos
    var onFilesAction: (() -> Void)?
    /// Callback para ação principal (pode ser usado para tracking ou lógica extra)
    var action: (() -> Void)?

    @GestureState private var isPressed = false
    @State private var showSheet = false

    var body: some View {
        Button(action: { showSheet = true }) {
            HStack(spacing: 10) {
                Text("Importar Treino")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color.white.opacity(0.12), radius: 12, x: 0, y: 6)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .sheet(isPresented: $showSheet) {
            UploadOptionsSheet(
                showSheet: $showSheet,
                onCameraAction: onCameraAction,
                onPhotosAction: onPhotosAction,
                onFilesAction: onFilesAction
            )
            .presentationDetents([.fraction(0.33)])
            .presentationBackground(Color.gray.opacity(0.95))
            .presentationCornerRadius(30)
        }
    }
}

/// Sheet de opções de upload (UI apenas)
private struct UploadOptionsSheet: View {
    @Binding var showSheet: Bool
    let onCameraAction: (() -> Void)?
    let onPhotosAction: (() -> Void)?
    let onFilesAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.white)
                .frame(width: 40, height: 6)
                .padding(.top, 12)
                .padding(.bottom, 8)
            HStack(spacing: 24) {
                UploadOptionButton(
                    icon: "camera.fill",
                    label: "Câmera",
                    action: {
                        onCameraAction?()
                        showSheet = false
                    }
                )
                UploadOptionButton(
                    icon: "photo.fill.on.rectangle.fill",
                    label: "Fotos",
                    action: {
                        onPhotosAction?()
                        showSheet = false
                    }
                )
                UploadOptionButton(
                    icon: "folder.fill",
                    label: "Arquivos",
                    action: {
                        onFilesAction?()
                        showSheet = false
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            Spacer()
        }
        .background(Color.black.opacity(0.6))
    }
}

/// Botão de opção individual para upload (UI apenas)
private struct UploadOptionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 110, height: 120)
            .background(Color.gray.opacity(1))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            UploadButton(
                onCameraAction: { print("Câmera selecionada") },
                onPhotosAction: { print("Fotos selecionadas") },
                onFilesAction: { print("Arquivos selecionados") },
                action: { print("Botão principal tocado") }
            )
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
