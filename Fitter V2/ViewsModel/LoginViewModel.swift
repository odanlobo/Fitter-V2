//
//  LoginViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import Foundation
import FirebaseAuth
import CoreData
import Combine

@MainActor
class LoginViewModel: BaseViewModel {
    
    // MARK: - Inicialização
    
    /// Inicializa LoginViewModel com dependency injection
    /// - Parameters:
    ///   - coreDataService: Serviço Core Data
    ///   - authUseCase: Use Case de autenticação
    override init(
        coreDataService: CoreDataServiceProtocol = CoreDataService(),
        authUseCase: AuthUseCaseProtocol = AuthUseCase(authService: AuthService())
    ) {
        super.init(coreDataService: coreDataService, authUseCase: authUseCase)
        
        #if DEBUG
        // Se já tiver usuário (ex: vindo do Preview), não sobrescreve!
        if currentUser != nil { 
            print("🎯 LoginViewModel.init - Mantendo usuário existente: \(currentUser?.safeName ?? "nil")")
            isPreviewMode = true
            return 
        }
        #endif

        print("🔐 LoginViewModel inicializado com AuthUseCase")
    }
    
    /// Inicializador de conveniência para iOSApp.swift
    /// - Parameter useCase: Use Case de autenticação já configurado
    convenience init(useCase: AuthUseCaseProtocol) {
        self.init(authUseCase: useCase)
    }
    
    // MARK: - Métodos de Login
    
    /// Realiza login com email e senha
    /// - Parameters:
    ///   - email: Email do usuário
    ///   - password: Senha do usuário
    func signIn(email: String, password: String) async {
        guard !email.isEmpty else {
            showError(message: "Por favor, insira seu email")
            return
        }
        
        guard !password.isEmpty else {
            showError(message: "Por favor, insira sua senha")
            return
        }
        
        let credentials = AuthCredentials.email(email, password: password)
        await login(with: credentials)
    }
    
    /// Login com Apple ID
    func signInWithApple() async {
        print("🍎 [LoginViewModel] Iniciando login com Apple...")
        
        // ✅ ARQUITETURA CORRETA: AuthUseCase.signIn(with:) chama AppleSignInService internamente
        let credentials = AuthCredentials(provider: .apple, email: nil, password: nil, token: nil, biometricData: nil)
        await login(with: credentials)
    }
    
    /// Login com Google
    func signInWithGoogle() async {
        print("🔍 [LoginViewModel] Iniciando login com Google...")
        
        // ✅ ARQUITETURA CORRETA: AuthUseCase.signIn(with:) chama GoogleSignInService internamente
        let credentials = AuthCredentials(provider: .google, email: nil, password: nil, token: nil, biometricData: nil)
        await login(with: credentials)
    }
    
    /// Login com Facebook
    func signInWithFacebook() async {
        print("📘 [LoginViewModel] Iniciando login com Facebook...")
        
        // ✅ ARQUITETURA CORRETA: AuthUseCase.signIn(with:) chama FacebookSignInService internamente
        let credentials = AuthCredentials(provider: .facebook, email: nil, password: nil, token: nil, biometricData: nil)
        await login(with: credentials)
    }
    
}
