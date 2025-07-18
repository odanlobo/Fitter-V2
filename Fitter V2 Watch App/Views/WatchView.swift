//
//  WatchView.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import WatchConnectivity

struct WatchView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var motionManager: MotionManager
    @EnvironmentObject var connectivity: ConnectivityManager
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        HStack {
                            Image("logo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 22)
                            Spacer()
                            
                            // Status de conexão
                            Image(systemName: sessionManager.isConnectedToPhone ? "iphone" : "iphone.slash")
                                .foregroundColor(sessionManager.isConnectedToPhone ? .green : .gray)
                        }
                        .padding(.horizontal)
                        
                        // Planos de Treino
                        if let context = sessionManager.sessionContext, !context.isActive {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Treinos")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                // TODO: Implementar lista de treinos usando WorkoutDataService
                                Text("Lista de treinos em implementação")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                    .padding(.horizontal)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                
                                Text("Nenhum treino disponível")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                
                                if !sessionManager.isConnectedToPhone {
                                    Text("Conecte com o iPhone")
                                        .foregroundColor(.orange)
                                        .font(.caption2)
                                }
                            }
                            .padding()
                        }
                        
                        // Status do Sensor
                        VStack(alignment: .leading, spacing: 4) {
                            if motionManager.isRecording {
                                Text("Capturando dados (\(Int(motionManager.currentPhase == .execution ? 50 : 20))Hz)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            
                            // Frequência Cardíaca
                            if let heartRate = sessionManager.currentHeartRate {
                                Text("FC: \(heartRate) bpm")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            
                            // Calorias
                            if let calories = sessionManager.currentCalories {
                                Text("Calorias: \(Int(calories)) kcal")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Botões de Controle (para debug)
                        HStack {
                            Button(motionManager.isRecording ? "Parar" : "Iniciar") {
                                Task {
                                    if motionManager.isRecording {
                                        motionManager.stopMotionUpdates()
                                    } else {
                                        await motionManager.startMotionUpdates()
                                    }
                                }
                            }
                            .foregroundColor(motionManager.isRecording ? .red : .green)
                            .font(.caption2)
                            
                            Spacer()
                            
                            // Debug: Status da Sessão
                            Button("Status") {
                                print(sessionManager.sessionStats)
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct WatchView_Previews: PreviewProvider {
    static var previews: some View {
        WatchView()
            .environmentObject(WatchSessionManager())
            .environmentObject(MotionManager(
                sessionManager: WatchSessionManager(),
                phaseManager: WorkoutPhaseManager()
            ))
            .environmentObject(ConnectivityManager.shared)
            .environmentObject(WorkoutPhaseManager())
    }
}
