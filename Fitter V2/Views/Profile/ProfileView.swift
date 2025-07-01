//
//  ProfileView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
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
                    
                    // Informações do usuário autenticado
                    if let user = authViewModel.currentUser {
                        VStack(spacing: 12) {
                            // Nome do usuário
                            Text(user.safeName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                            
                            // Email do usuário
                            if !user.safeEmail.isEmpty {
                                Text(user.safeEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.15))
                        )
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Botão de Logout
                    Button(action: {
                        do {
                            try AuthService.shared.signOut()
                            // Limpa os dados locais ao fazer logout
                            try? viewContext.save()
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

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environment(\.managedObjectContext, PreviewCoreDataStack.shared.viewContext)
            .environmentObject(LoginViewModel.preview)
    }
}
