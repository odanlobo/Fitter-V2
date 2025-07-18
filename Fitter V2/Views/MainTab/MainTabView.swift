//
//  MainTabView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

/**
 * MainTabView - Navegação principal do aplicativo
 * 
 * RESPONSABILIDADE:
 * - Container de navegação por abas (Home, Treinos, Histórico, Perfil)
 * - Integração com AuthViewModel via @EnvironmentObject
 * - Interface simples e focada apenas em navegação
 * 
 * CLEAN ARCHITECTURE:
 * - NÃO possui ViewModel próprio (desnecessário para container simples)
 * - Usa @EnvironmentObject para ViewModels injetados via iOSApp.swift
 * - Delega toda lógica de negócio para Views filhas
 * 
 * NAVEGAÇÃO:
 * - TabView padrão com 4 abas bem definidas
 * - Seleção gerenciada automaticamente pelo sistema
 * - Reset automático via fluxo natural do iOSApp.swift (sem duplicação)
 */
struct MainTabView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    
    var body: some View {
        ZStack {
            // Fundo preto consistente com design do app
            Color.black
                .ignoresSafeArea()
            
            TabView {
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
            .tint(.white) // Cor dos ícones selecionados (Apple guidelines)
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(LoginViewModel.preview)
    }
}
