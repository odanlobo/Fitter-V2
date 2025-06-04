//
//  MainTabView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Fundo preto
            Color.black
                .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                // Tab da tela principal
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                // Tab do Treinos
                WorkoutView()
                    .tabItem {
                        Label("Treinos", systemImage: "figure.run")
                    }
                    .tag(1)
                
                // Tab do Histórico
                HistoryView()
                    .tabItem {
                        Label("Histórico", systemImage: "clock.fill")
                    }
                    .tag(2)
                
                // Tab do Perfil
                ProfileView()
                    .tabItem {
                        Label("Perfil", systemImage: "person.fill")
                    }
                    .tag(3)
            }
            .tint(.white) // Cor dos ícones selecionados
        }
        .onChange(of: authViewModel.currentUser) { newUser in
            if newUser != nil {
                selectedTab = 0 // Sempre volta para Home ao logar
            }
        }
    }
}

// MARK: - Preview
#Preview("Com dados mock") {
    MainTabView()
        .withMockData()
        .environmentObject(LoginViewModel.preview)
}

#Preview("Sem dados") {
    MainTabView()
        .modelContainer(for: WorkoutPlan.self, inMemory: true)
        .environmentObject(LoginViewModel(mockUser: PreviewData.mockUser))
}
