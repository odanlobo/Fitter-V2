//
//  CreateAccountViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import Foundation
import CoreData

@MainActor
class CreateAccountViewModel: BaseViewModel {
    
    // MARK: - Properties
    
    var onAccountCreated: ((CDAppUser?) -> Void)?
    
    // MARK: - Inicialização
    
    /// Inicializa CreateAccountViewModel com dependency injection
    /// - Parameters:
    ///   - coreDataService: Serviço Core Data
    ///   - authUseCase: Use Case de autenticação
    override init(
        coreDataService: CoreDataServiceProtocol = CoreDataService(),
        authUseCase: AuthUseCaseProtocol = AuthUseCase(authService: AuthService())
    ) {
        super.init(coreDataService: coreDataService, authUseCase: authUseCase)
        
        print("📝 CreateAccountViewModel inicializado com AuthUseCase")
    }
    
    // MARK: - Métodos de Criação de Conta
    
    /// Cria uma nova conta de usuário
    /// - Parameters:
    ///   - name: Nome do usuário
    ///   - email: Email do usuário
    ///   - password: Senha do usuário
    ///   - confirmPassword: Confirmação da senha
    func createAccount(
        name: String,
        email: String,
        password: String,
        confirmPassword: String
    ) async {
        // Validações básicas
        guard !name.isEmpty else {
            showError(message: "Por favor, insira seu nome")
            return
        }
        
        guard !email.isEmpty else {
            showError(message: "Por favor, insira seu email")
            return
        }
        
        guard !password.isEmpty else {
            showError(message: "Por favor, insira uma senha")
            return
        }
        
        guard password == confirmPassword else {
            showError(message: "As senhas não coincidem")
            return
        }
        
        guard password.count >= 6 else {
            showError(message: "A senha deve ter pelo menos 6 caracteres")
            return
        }
        
        // Cria registro de usuário
        let registration = AuthRegistration(
            name: name,
            email: email,
            password: password,
            provider: .email,
            agreeToTerms: true,
            allowMarketing: false
        )
        
        // Executa criação com loading
        if let result = await executeUseCase({
            try await authUseCase.signUp(with: registration)
        }) {
            currentUser = result.user
            onAccountCreated?(result.user)
            print("✅ Conta criada com sucesso: \(result.user.safeName)")
        }
    }
}

#if DEBUG
// MARK: - Preview Support
extension CreateAccountViewModel {
    
    /// Cria instância para preview
    /// - Returns: CreateAccountViewModel configurado para preview
    static func previewInstance() -> CreateAccountViewModel {
        let vm = CreateAccountViewModel()
        vm.configureForPreview()
        return vm
    }
}
#endif
