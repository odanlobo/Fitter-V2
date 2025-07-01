//
//  HomeView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import CoreData
import Network

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo preto
                Color.black
                    .ignoresSafeArea()
                
                VStack {
                    HStack {
                        Text("Home")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Status de Conectividade
                    VStack(spacing: 20) {
                        // Status da Internet
                        HStack {
                            Image(systemName: connectivity.isOnline ? "wifi" : "wifi.slash")
                                .foregroundColor(connectivity.isOnline ? .green : .red)
                                .font(.title2)
                            
                            Text(connectivity.isOnline ? "Online" : "Offline")
                                .foregroundColor(.white)
                                .font(.headline)
                            
                            if let connectionType = connectivity.connectionType {
                                Text("(\(connectionType.localizedDescription))")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        
                        // Status do Apple Watch
                        HStack {
                            Image(systemName: connectivity.isReachable ? "applewatch" : "applewatch.slash")
                                .foregroundColor(connectivity.isReachable ? .green : .red)
                                .font(.title2)
                            
                            Text("Watch \(connectivity.isReachable ? "Conectado" : "Desconectado")")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        
                        // Status de Autenticação
                        HStack {
                            Image(systemName: connectivity.isAuthenticated ? "person.fill.checkmark" : "person.fill.xmark")
                                .foregroundColor(connectivity.isAuthenticated ? .green : .red)
                                .font(.title2)
                            
                            Text(connectivity.isAuthenticated ? "Autenticado" : "Não Autenticado")
                            .foregroundColor(.white)
                                .font(.headline)
                        }
                        
                        // Botão de Teste de Conectividade
                        Button(action: {
                            Task {
                                await connectivity.sendPing()
                            }
                        }) {
                            HStack {
                                Image(systemName: "network")
                                Text("Testar Conectividade")
                            }
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environment(\.managedObjectContext, PreviewCoreDataStack.shared.viewContext)
            .environmentObject(LoginViewModel.preview)
    }
}

// MARK: - Extensions
extension NWInterface.InterfaceType {
    var localizedDescription: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Celular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Outro"
        @unknown default: return "Desconhecido"
        }
    }
}
