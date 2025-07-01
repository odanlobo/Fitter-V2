//
//  CreateAccountViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import Foundation
import CoreData

@MainActor
class CreateAccountViewModel: ObservableObject {
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    var onAccountCreated: ((CDAppUser?) -> Void)?
    
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
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AuthService.shared.createAccount(name: name, email: email, password: password)
            let user = AuthService.shared.currentUser
            onAccountCreated?(user)
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
