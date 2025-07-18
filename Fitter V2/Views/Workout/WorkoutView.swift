//
//  WorkoutView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

// WorkoutView.swift

import SwiftUI
import CoreData

struct WorkoutView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var viewModel = WorkoutViewModel()
    @State private var showCreateWorkout = false
    @State private var selectedPlan: CDWorkoutPlan?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Treinos")
                            .font(.system(size: 36, weight: .bold, design: .default).italic())
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    if viewModel.plans.isEmpty {
                        // Card de mensagem
                        HStack {
                            Text("Quando você criar seus treinos\neles irão aparecer aqui")
                                .foregroundColor(Color.gray.opacity(0.7))
                                .font(.system(size: 20, weight: .regular, design: .default))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 68)
                                .frame(maxWidth: .infinity)
                        }
                        .background(Color.gray.opacity(0.22))
                        .cornerRadius(20)
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(viewModel.plans) { plan in
                            WorkoutPlanCard(
                                plan: plan,
                                onTap: { selectedPlan = plan },
                                onDelete: { /* handled by swipe/context menu */ }
                            )
                            .padding(.horizontal, 8)
                        }
                    }

                    // Botão CRIAR TREINO
                    CreateButton(action: { showCreateWorkout = true })
                        .padding(.horizontal, 16)

                    // Botão FAZER UPLOAD
                    UploadButton {
                        print("Fazer upload")
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showCreateWorkout) {
                WorkoutEditorView.createMode(viewModel: viewModel)
            }
            .navigationDestination(item: $selectedPlan) { plan in
                WorkoutEditorView.editMode(plan: plan, viewModel: viewModel)
            }
            .alert("Erro", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                print("🎯 WorkoutView.onAppear - Usuário recebido: \(String(describing: authViewModel.currentUser?.safeName))")
                viewModel.updateUser(authViewModel.currentUser)
            }
        }
    }
}

