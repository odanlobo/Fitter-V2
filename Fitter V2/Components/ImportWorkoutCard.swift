/*
 * ImportWorkoutCard.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Componente visual para exibir status de importação de treino.
 *                   Interface idêntica ao WorkoutPlanCard mas com progress view animado.
 *
 * ESTRUTURA:
 * - Layout HStack idêntico ao WorkoutPlanCard (86px altura)
 * - Área de texto à esquerda (título + status)
 * - Gráfico de pizza animado à direita (no lugar das 3 linhas)
 * - Visual moderno com bordas e sombras consistentes
 *
 * UX DE IMPORTAÇÃO:
 * - Aparece na WorkoutView durante processamento
 * - Progresso visual com percentual e mensagens de status
 * - Após 100% faz transição suave para WorkoutPlanCard
 * - Estados: .importing, .processing, .success, .error
 *
 * INTEGRAÇÃO:
 * - Usado como substituto temporário do WorkoutPlanCard
 * - Interface preparada para ImportWorkoutUseCase
 * - Callbacks para cancelar importação e tratar erro
 *
 * REFATORAÇÃO ITEM 41/105:
 * ✅ Componente visual para status de importação
 * ✅ Estrutura similar ao WorkoutPlanCard
 * ✅ Gráfico de pizza animado no lugar do drag handle
 * ✅ Feedback visual durante processamento backend
 * ✅ Clean Architecture - apenas UI, sem lógica de negócio
 */

import SwiftUI

// MARK: - ImportWorkoutStatus

enum ImportWorkoutStatus {
    case importing(progress: Double)    // 0.0 - 0.3: Lendo arquivo
    case processing(progress: Double)   // 0.3 - 0.8: Parseando dados
    case creating(progress: Double)     // 0.8 - 1.0: Criando treino
    case success                        // 1.0: Concluído
    case error(String)                  // Erro com mensagem
    
    var progress: Double {
        switch self {
        case .importing(let progress), .processing(let progress), .creating(let progress):
            return progress
        case .success:
            return 1.0
        case .error:
            return 0.0
        }
    }
    
    var statusMessage: String {
        switch self {
        case .importing:
            return "Lendo arquivo..."
        case .processing:
            return "Extraindo exercícios..."
        case .creating:
            return "Criando treino..."
        case .success:
            return "Treino criado!"
        case .error(let message):
            return message
        }
    }
    
    var statusColor: Color {
        switch self {
        case .importing, .processing, .creating:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}

// MARK: - ImportWorkoutCard

/// Card visual para exibir status de importação de treino.
/// Interface idêntica ao WorkoutPlanCard mas com progress view no lugar do drag handle.
struct ImportWorkoutCard: View {
    /// Título do treino sendo importado
    let title: String
    /// Status atual da importação
    let status: ImportWorkoutStatus
    /// Callback ao tocar no card (ver detalhes, erro, etc)
    var onTap: (() -> Void)? = nil
    /// Callback para cancelar importação
    var onCancel: (() -> Void)? = nil
    
    @State private var animateProgress = false
    
    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                // Área de texto (título + status) - idêntica ao WorkoutPlanCard
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(status.statusMessage)
                        .font(.system(size: 14, weight: .semibold, design: .default).italic())
                        .foregroundColor(status.statusColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Progress View (no lugar das 3 linhas do WorkoutPlanCard)
                progressView
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .frame(height: 86) // Altura idêntica ao WorkoutPlanCard
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(status.statusColor.opacity(0.5), lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .animation(.easeInOut(duration: 0.3), value: status.progress)
        .onAppear {
            animateProgress = true
        }
    }
    
    // MARK: - Progress View
    
    /// Gráfico de pizza animado que substitui o drag handle
    @ViewBuilder
    private var progressView: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 32, height: 32)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: animateProgress ? status.progress : 0)
                .stroke(status.statusColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: status.progress)
            
            // Status icon ou percentual
            Group {
                switch status {
                case .importing, .processing, .creating:
                    // Percentual durante importação
                    Text("\(Int(status.progress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                
                case .success:
                    // Checkmark quando sucesso
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                
                case .error:
                    // X quando erro
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                }
            }
        }
        .scaleEffect(animateProgress ? 1.0 : 0.8)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animateProgress)
    }
}

// MARK: - Extensions for Convenience

extension ImportWorkoutCard {
    
    /// Método de conveniência para estado de importing
    static func importing(title: String, progress: Double, onTap: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) -> ImportWorkoutCard {
        return ImportWorkoutCard(
            title: title,
            status: .importing(progress: progress),
            onTap: onTap,
            onCancel: onCancel
        )
    }
    
    /// Método de conveniência para estado de processing
    static func processing(title: String, progress: Double, onTap: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) -> ImportWorkoutCard {
        return ImportWorkoutCard(
            title: title,
            status: .processing(progress: progress),
            onTap: onTap,
            onCancel: onCancel
        )
    }
    
    /// Método de conveniência para estado de creating
    static func creating(title: String, progress: Double, onTap: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) -> ImportWorkoutCard {
        return ImportWorkoutCard(
            title: title,
            status: .creating(progress: progress),
            onTap: onTap,
            onCancel: onCancel
        )
    }
    
    /// Método de conveniência para estado de success
    static func success(title: String, onTap: (() -> Void)? = nil) -> ImportWorkoutCard {
        return ImportWorkoutCard(
            title: title,
            status: .success,
            onTap: onTap,
            onCancel: nil
        )
    }
    
    /// Método de conveniência para estado de error
    static func error(title: String, message: String, onTap: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) -> ImportWorkoutCard {
        return ImportWorkoutCard(
            title: title,
            status: .error(message),
            onTap: onTap,
            onCancel: onCancel
        )
    }
}

// MARK: - Previews

#Preview("Estados de Importação") {
    VStack(spacing: 16) {
        // Estado: Importing (0-30%)
        ImportWorkoutCard.importing(
            title: "Treino Push",
            progress: 0.2,
            onTap: { print("Tap importing") },
            onCancel: { print("Cancel importing") }
        )
        
        // Estado: Processing (30-80%)
        ImportWorkoutCard.processing(
            title: "Treino Pull",
            progress: 0.6,
            onTap: { print("Tap processing") },
            onCancel: { print("Cancel processing") }
        )
        
        // Estado: Creating (80-100%)
        ImportWorkoutCard.creating(
            title: "Treino Legs",
            progress: 0.9,
            onTap: { print("Tap creating") },
            onCancel: { print("Cancel creating") }
        )
        
        // Estado: Success
        ImportWorkoutCard.success(
            title: "Treino Full Body",
            onTap: { print("Tap success") }
        )
        
        // Estado: Error
        ImportWorkoutCard.error(
            title: "Treino Upper",
            message: "Erro ao processar arquivo",
            onTap: { print("Tap error") },
            onCancel: { print("Cancel error") }
        )
    }
    .padding()
    .background(Color.black)
}

#Preview("Transição para WorkoutPlanCard") {
    VStack(spacing: 16) {
        Text("ImportWorkoutCard")
            .foregroundColor(.white)
            .font(.headline)
        
        // ImportWorkoutCard em estado final
        ImportWorkoutCard.success(
            title: "Treino Importado",
            onTap: { print("Importação concluída") }
        )
        
        Text("↓ Transição suave ↓")
            .foregroundColor(.gray)
            .font(.caption)
        
        Text("WorkoutPlanCard")
            .foregroundColor(.white)
            .font(.headline)
        
        // Exemplo visual da transição (mock WorkoutPlanCard)
        ZStack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Treino Importado")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    Text("Peito + Tríceps")
                        .font(.system(size: 14, weight: .semibold, design: .default).italic())
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
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
    }
    .padding()
    .background(Color.black)
}

// MARK: - Exemplos de Uso

/*
 // EXEMPLO 1: Durante importação
 @State private var importProgress: Double = 0.0
 @State private var importStatus: ImportWorkoutStatus = .importing(progress: 0.0)
 
 ImportWorkoutCard(
     title: "Treino PDF",
     status: importStatus,
     onTap: { 
         // Mostrar detalhes da importação
         showImportDetails = true
     },
     onCancel: {
         // Cancelar importação
         cancelImport()
     }
 )
 
 // EXEMPLO 2: Fluxo completo com Timer
 Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
     if importProgress < 1.0 {
         importProgress += 0.02
         
         if importProgress < 0.3 {
             importStatus = .importing(progress: importProgress)
         } else if importProgress < 0.8 {
             importStatus = .processing(progress: importProgress)
         } else {
             importStatus = .creating(progress: importProgress)
         }
     } else {
         importStatus = .success
         timer.invalidate()
         
         // Transição para WorkoutPlanCard após 1 segundo
         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
             showImportCard = false
             // Exibir WorkoutPlanCard normal
         }
     }
 }
 
 // EXEMPLO 3: Tratamento de erro
 do {
     let result = try await importWorkoutUseCase.execute(from: source)
     importStatus = .success
 } catch {
     importStatus = .error(error.localizedDescription)
 }
 */ 