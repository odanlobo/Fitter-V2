//
//  LoginViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import Foundation
import FirebaseAuth

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var currentUser: AppUser?
    
    var isAuthenticated: Bool {
        authService.isAuthenticated
    }
    
    private let authService = AuthService.shared
    
    init() {
        // Inicializa o currentUser com o usuário do AuthService
        currentUser = authService.currentUser
    }
    
    /// Inicializador para preview/mock
    init(mockUser: AppUser) {
        self.currentUser = mockUser
    }
    
    static var preview: LoginViewModel {
        LoginViewModel(mockUser: PreviewData.mockUser)
    }
    
    func signIn(email: String, password: String) async {
        guard !email.isEmpty else {
            showError(message: "Por favor, insira seu email")
            return
        }
        
        guard !password.isEmpty else {
            showError(message: "Por favor, insira sua senha")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await authService.signIn(email: email, password: password)
            currentUser = authService.currentUser // Atualiza o usuário atual
            objectWillChange.send()
        } catch let error as AuthError {
            showError(message: error.localizedDescription)
        } catch {
            showError(message: "Erro inesperado ao fazer login")
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // Métodos para login social (a serem implementados conforme necessidade)
    func signInWithApple() {
        // Implementar login com Apple
    }
    
    func signInWithGoogle() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await authService.signInWithGoogle()
                currentUser = authService.currentUser // Atualiza o usuário atual
                objectWillChange.send()
            } catch let error as AuthError {
                showError(message: error.localizedDescription)
            } catch {
                showError(message: "Erro ao fazer login com Google")
            }
        }
    }
    
    func signInWithFacebook() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await authService.signInWithFacebook()
                currentUser = authService.currentUser // Atualiza o usuário atual
                objectWillChange.send()
            } catch let error as AuthError {
                showError(message: error.localizedDescription)
            } catch {
                showError(message: "Erro ao fazer login com Facebook")
            }
        }
    }
    
    func updateCurrentUser() {
        currentUser = authService.currentUser
        objectWillChange.send()
    }
}

