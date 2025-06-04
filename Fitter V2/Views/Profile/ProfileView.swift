//
//  ProfileView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo preto
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Título centralizado
                    Text("Perfil")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                    
                    // Email do usuário autenticado
                    if let email = authViewModel.currentUser?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                    }
                    
                    Spacer()
                    
                    // Botão de Logout
                    Button(action: {
                        do {
                            try AuthService.shared.signOut()
                        } catch {
                            print("Erro ao fazer logout: \(error)")
                        }
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Sair")
                                .foregroundColor(.red)
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red, lineWidth: 2)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ProfileView()
}
