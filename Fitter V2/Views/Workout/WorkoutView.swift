//
//  WorkoutView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

// WorkoutView.swift

import SwiftUI
import SwiftData

struct WorkoutView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WorkoutViewModel? = nil
    @State private var showCreateWorkout = false
    @State private var selectedPlan: WorkoutPlan?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var editMode: EditMode = .inactive // ou .active se quiser já com handles visíveis
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let viewModel = viewModel {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        VStack(spacing: 20) {
                            // Header
                            HStack {
                                Text("Treinos")
                                    .font(.system(size: 42, weight: .bold, design: .default).italic())
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    showCreateWorkout = true 
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .padding(8)
                                }
                            }
                            .padding(.horizontal)
                            
                            if viewModel.plans.isEmpty {
                                EmptyWorkoutView(onCreateTap: {
                                    showCreateWorkout = true 
                                })
                                .onAppear {
                                    print("📋 Lista vazia - Usuario: \(String(describing: authViewModel.currentUser?.id))")
                                }
                            } else {
                                WorkoutsPlansList(
                                    plans: viewModel.plans,
                                    onMove: viewModel.move,
                                    onSelect: { selectedPlan = $0 },
                                    onCreate: { showCreateWorkout = true },
                                    onDelete: { plan in
                                        selectedPlan = nil
                                        print("🎯 Delete solicitado para: \(plan.title)")
                                        Task { @MainActor in
                                            do {
                                                try await viewModel.deletePlanById(plan.id)
                                                print("✅ Delete concluído com sucesso")
                                            } catch {
                                                print("❌ Erro na UI ao deletar: \(error)")
                                                errorMessage = error.localizedDescription
                                                showError = true
                                            }
                                        }
                                    },
                                    onRefresh: {
                                        Task {
                                            do {
                                                try await viewModel.loadPlansForCurrentUser()
                                                print("🔄 Lista atualizada via pull to refresh")
                                            } catch {
                                                errorMessage = error.localizedDescription
                                                showError = true
                                            }
                                        }
                                    },
                                    editMode: $editMode
                                )
                                .onAppear {
                                    print("📋 Exibindo \(viewModel.plans.count) planos")
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .onAppear {
                            if viewModel == nil {
                                print("🔄 Inicializando WorkoutViewModel...")
                                let vm = WorkoutViewModel(modelContext: modelContext)
                                vm.updateUser(authViewModel.currentUser)
                                print("👤 Usuario atual: \(String(describing: authViewModel.currentUser?.id))")
                                Task { 
                                    do {
                                        try await vm.loadPlansForCurrentUser()
                                        print("✅ Dados carregados, assignando ViewModel")
                                        // Só atribui o ViewModel DEPOIS de carregar os dados
                                        await MainActor.run {
                                            viewModel = vm
                                        }
                                    } catch {
                                        print("❌ Erro ao carregar planos: \(error)")
                                    }
                                }
                            }
                        }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showCreateWorkout) {
                if let viewModel = viewModel {
                    CreateWorkoutView(viewModel: viewModel)
                }
            }
            .navigationDestination(item: $selectedPlan) { plan in
                DetailWorkoutView(plan: plan)
            }
            .alert("Erro", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: authViewModel.currentUser) { newUser in
                viewModel?.updateUser(newUser)
                Task {
                    do {
                        try await viewModel?.loadPlansForCurrentUser()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .onChange(of: showCreateWorkout) { isShowing in
                // Quando volta da tela de criação (showCreateWorkout muda para false)
                if !isShowing {
                    Task {
                        do {
                            try await viewModel?.loadPlansForCurrentUser()
                            print("🔄 Lista atualizada automaticamente após criação")
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subviews
private struct EmptyWorkoutView: View {
    let onCreateTap: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Quando você for criando seus treinos, eles irão aparecer aqui.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
        .padding(.horizontal)
        
        CreateButton(action: onCreateTap)
        
        Spacer()
    }
}

#Preview("Mock isolado") {
    WorkoutView()
        .withMockData()
        .environmentObject(LoginViewModel.preview)
}

