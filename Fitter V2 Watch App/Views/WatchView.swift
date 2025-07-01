//
//  WatchView.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import WatchConnectivity

struct WatchView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @StateObject private var connectivity = ConnectivityManager.shared
    
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
                            Image(systemName: dataManager.isConnectedToPhone ? "iphone" : "iphone.slash")
                                .foregroundColor(dataManager.isConnectedToPhone ? .green : .gray)
                        }
                        .padding(.horizontal)
                        
                        // Planos de Treino
                        if !dataManager.workoutPlans.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Treinos")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                ForEach(dataManager.workoutPlans) { plan in
                                    NavigationLink(destination: WatchWorkoutDetailView(plan: plan)) {
                                        WatchWorkoutCard(plan: plan)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                
                                Text("Nenhum treino disponível")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                
                                if !dataManager.isConnectedToPhone {
                                    Text("Conecte com o iPhone")
                                        .foregroundColor(.orange)
                                        .font(.caption2)
                                }
                            }
                            .padding()
                        }
                        
                        // Dados de Sensor Pendentes (para debug)
                        if !dataManager.pendingSensorData.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dados Pendentes: \(dataManager.pendingSensorData.count)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal)
                                
                                Button("Sincronizar") {
                                    Task {
                                        await dataManager.syncSensorDataToPhone()
                                    }
                                }
                                .font(.caption2)
                                .padding(.horizontal)
                            }
                        }
                        
                        // Botão de teste para adicionar dados de sensor
                        Button("Teste: Adicionar Dados") {
                            let sensorData = WatchSensorData(
                                type: .setCompleted,
                                heartRate: Int.random(in: 120...180),
                                calories: Double.random(in: 5...15),
                                reps: Int.random(in: 8...15),
                                weight: Double.random(in: 20...100)
                            )
                            dataManager.addSensorData(sensorData)
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Watch Workout Card
struct WatchWorkoutCard: View {
    let plan: WatchWorkoutPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(plan.muscleGroups)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
            
            Text("\(plan.exercises.count) exercícios")
                .font(.caption2)
                .foregroundColor(.green)
        }
        .padding(8)
        .background(Color(.darkGray))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Watch Workout Detail View
struct WatchWorkoutDetailView: View {
    let plan: WatchWorkoutPlan
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(plan.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(plan.muscleGroups)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Divider()
                
                ForEach(plan.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text(exercise.equipment)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
    }
}
