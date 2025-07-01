//
//  ListExerciseCard.swift
//  Fitter V2
//
//  RESPONSABILIDADE: Componente base não reordenável para exercícios Firebase
//  CONTEXTOS: Lista de seleção de exercícios, visualização de detalhes
//  FEATURES: Thumbnail sempre visível, play button para vídeos, design responsivo
//
//  REFATORAÇÃO ITEM 34/101:
//  ✅ Componente autocontido sem dependencies externas
//  ✅ Suporte completo a videoURL do FirebaseExercise
//  ✅ Compatibilidade total com ListExerciseCard.swift
//  ✅ Design responsivo e play button contextual
//  ✅ Preparado para substituir ListExerciseCard na ListExerciseView (item 77)

import SwiftUI
import AVKit

// MARK: - ListExerciseCard

/// Componente de card para exercícios Firebase com suporte completo a vídeo
struct ListExerciseCard: View {
    
    // MARK: - Properties
    
    let exercise: FirebaseExercise
    let isSelected: Bool
    let onTap: () -> Void
    let onVideoTap: (() -> Void)?
    
    @State private var showingVideoModal = false
    @State private var localIsSelected: Bool
    
    // MARK: - Computed Properties
    
    /// Verifica se deve mostrar play button
    private var shouldShowPlayButton: Bool {
        exercise.hasVideo
    }
    
    /// URL para thumbnail (mesma do vídeo - player gerará thumbnail)
    private var thumbnailURL: String? {
        exercise.videoURL
    }
    
    // MARK: - Initializer
    
    init(
        exercise: FirebaseExercise,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onVideoTap: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        self.isSelected = isSelected
        self.onTap = onTap
        self.onVideoTap = onVideoTap
        self._localIsSelected = State(initialValue: isSelected)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Card principal
            cardContent
            
            // Modal de vídeo
            if showingVideoModal {
                videoModal
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingVideoModal)
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        HStack(spacing: 12) {
            // Thumbnail/vídeo do exercício
            thumbnailView
            
            // Nome e equipamento
            exerciseInfo
            
            Spacer()
            
            // Indicador de seleção
            selectionIndicator
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
                localIsSelected.toggle()
                onTap()
            }
        }
        .onChange(of: isSelected) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                localIsSelected = newValue
            }
        }
    }
    
    // MARK: - Thumbnail View
    
    private var thumbnailView: some View {
        ZStack {
            // Container com aspect ratio
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
            
            // Thumbnail ou ícone fallback
            Group {
                if let thumbnailURL = thumbnailURL, !thumbnailURL.isEmpty {
                    // AsyncImage para thumbnail do vídeo
                    AsyncImage(url: URL(string: thumbnailURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        // Loading placeholder
                        Image(systemName: "video.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Ícone padrão quando sem vídeo
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }
            
            // Play button overlay
            if shouldShowPlayButton {
                Button(action: {
                    onVideoTap?()
                    showingVideoModal = true
                }) {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Exercise Info
    
    private var exerciseInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.safeName)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            HStack {
                Text(exercise.equipment)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                if let grip = exercise.gripVariation, !grip.isEmpty {
                    Text("•")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text(grip)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Indicador de vídeo disponível
                if exercise.hasVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Selection Indicator
    
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 24, height: 24)
            
            if localIsSelected {
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: localIsSelected)
    }
    
    // MARK: - Video Modal
    
    private var videoModal: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    showingVideoModal = false
                }
            
            VStack(spacing: 20) {
                // Header com close button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.safeName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(exercise.safeDescription)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingVideoModal = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Video player
                if let videoURL = exercise.videoURL, !videoURL.isEmpty,
                   let url = URL(string: videoURL) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: UIScreen.main.bounds.height * 0.4)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                } else {
                    // Fallback quando sem vídeo
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: UIScreen.main.bounds.height * 0.4)
                        .overlay(
                            VStack {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("Vídeo não disponível")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
                        )
                        .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Display Mode Support

/// Enum para diferentes modos de exibição do card
enum ExerciseCardDisplayMode: CaseIterable {
    case firebaseList      // Lista de seleção Firebase (não reordenável)
    case details          // Visualização de detalhes (read-only)
    case preview          // Modo preview para desenvolvimento
    
    var allowsVideoModal: Bool {
        switch self {
        case .firebaseList, .details, .preview:
            return true
        }
    }
    
    var showsVideoIndicator: Bool {
        switch self {
        case .firebaseList, .details, .preview:
            return true
        }
    }
}

// MARK: - Convenience Initializers

extension ListExerciseCard {
    
    /// Inicializador para modo Firebase list (padrão)
    init(
        exercise: FirebaseExercise,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        self.init(
            exercise: exercise,
            isSelected: isSelected,
            onTap: onTap,
            onVideoTap: nil
        )
    }
    
    /// Inicializador para modo details com callback de vídeo customizado
    static func detailsMode(
        exercise: FirebaseExercise,
        onVideoTap: @escaping () -> Void
    ) -> ListExerciseCard {
        return ListExerciseCard(
            exercise: exercise,
            isSelected: false,
            onTap: {},
            onVideoTap: onVideoTap
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ListExerciseCard_Previews: PreviewProvider {
    @State static private var selected = false
    
    static var previews: some View {
        VStack(spacing: 16) {
            // Exercise com vídeo
            ListExerciseCard(
                exercise: FirebaseExercise.mockChestExercise,
                isSelected: selected,
                onTap: {
                    selected.toggle()
                }
            )
            
            // Exercise sem vídeo
            ListExerciseCard(
                exercise: FirebaseExercise.mockBackExercise,
                isSelected: false,
                onTap: {}
            )
            
            // Exercise selecionado
            ListExerciseCard(
                exercise: FirebaseExercise.mockLegExercise,
                isSelected: true,
                onTap: {}
            )
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif 