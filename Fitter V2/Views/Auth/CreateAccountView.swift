//
//  CreateAccountView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import SwiftUI
import CoreData

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var viewModel = CreateAccountViewModel()
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 10) {
                // Header com botão de voltar
                HStack {
                    BackButton()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Título da tela
                HStack {
                    Text("Bem vindo ao Fitter!")
                        .font(.custom("Helvetica Neue Bold", size: 54))
                        .italic()
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.top, 10)
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Campos de entrada
                        VStack(spacing: 22) {
                            TextField("Nome", text: $name)
                                .font(.custom("HelveticaNeue-Regular", size: 20))
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(30)
                                .padding(.horizontal, 46)
                                .disabled(viewModel.isLoading)
                            
                            TextField("Email", text: $email)
                                .font(.custom("HelveticaNeue-Regular", size: 20))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(30)
                                .padding(.horizontal, 46)
                                .disabled(viewModel.isLoading)
                            
                            PasswordField(text: $password,
                                          isVisible: $isPasswordVisible,
                                          placeholder: "Senha")
                                .disabled(viewModel.isLoading)
                            
                            PasswordField(text: $confirmPassword,
                                          isVisible: $isConfirmPasswordVisible,
                                          placeholder: "Confirmar Senha")
                                .disabled(viewModel.isLoading)
                        }
                        .padding(.top, 30)
                        
                        // Botão de criação de conta
                        Button(action: {
                            Task {
                                await viewModel.createAccount(
                                    name: name,
                                    email: email,
                                    password: password,
                                    confirmPassword: confirmPassword
                                )
                            }
                        }) {
                            if viewModel.isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text("Criar Conta")
                                    .font(.custom("HelveticaNeue-Bold", size: 22))
                                    .fontWeight(.heavy)
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(30)
                        .padding(.horizontal, 110)
                        .disabled(viewModel.isLoading)
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .alert("Erro", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
        .onAppear {
            viewModel.onAccountCreated = { user in
                authViewModel.updateCurrentUser()
            }
        }
    }
}

private struct PasswordField: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    let placeholder: String
    
    var body: some View {
        HStack {
            if isVisible {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(placeholder, text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            
            Button(action: {
                isVisible.toggle()
            }) {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(.gray)
            }
        }
        .font(.custom("HelveticaNeue-Regular", size: 20))
        .foregroundColor(.black)
        .padding()
        .background(Color.white)
        .cornerRadius(30)
        .padding(.horizontal, 46)
    }
}
