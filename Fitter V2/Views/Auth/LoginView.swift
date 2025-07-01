import SwiftUI

struct LoginView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = LoginViewModel()
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Logo na parte superior
                VStack {
                    Spacer().frame(height: 80)
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                
                // Conteúdo principal de login
                VStack(spacing: 32) {
                    Spacer().frame(height: 80)
                    
                    Text("LOGIN")
                        .font(.custom("HelveticaNeue-Bold", size: 30))
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 20) {
                        // Campo de Email
                        TextField("Email", text: $email)
                            .font(.custom("HelveticaNeue-Regular", size: 18))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(30)
                            .padding(.horizontal, 56)
                        
                        // Campo de Senha com botão para visibilidade
                        HStack {
                            if isPasswordVisible {
                                TextField("Senha", text: $password)
                                    .font(.custom("HelveticaNeue-Regular", size: 18))
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Senha", text: $password)
                                    .font(.custom("HelveticaNeue-Regular", size: 18))
                                    .autocorrectionDisabled()
                            }
                            
                            Button(action: {
                                isPasswordVisible.toggle()
                            }) {
                                Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(30)
                        .padding(.horizontal, 56)
                    }
                    
                    // Botão de login
                    Button(action: {
                        Task {
                            await viewModel.signIn(email: email, password: password)
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("ENTRAR")
                                .font(.custom("HelveticaNeue-Bold", size: 18))
                                .fontWeight(.heavy)
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(30)
                    .padding(.horizontal, 100)
                    .disabled(viewModel.isLoading)
                    
                    // Botões de login social
                    HStack(spacing: 35) {
                        Button(action: {
                            viewModel.signInWithApple()
                        }) {
                            Image("Icon Apple")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 70, height: 70)
                        }
                        
                        Button(action: {
                            viewModel.signInWithGoogle()
                        }) {
                            Image("Icon Google")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 70, height: 70)
                        }
                        
                        Button(action: {
                            viewModel.signInWithFacebook()
                        }) {
                            Image("Icon FB")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 70, height: 70)
                        }
                    }
                    .padding(.vertical, 10)
                    
                    // Navegação para tela de criação de conta
                    NavigationLink {
                        CreateAccountView()
                    } label: {
                        Text("Criar Conta")
                            .font(.custom("HelveticaNeue", size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 30)
                }
            }
            .alert("Erro", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .navigationBarHidden(true)
        }
    }
}
