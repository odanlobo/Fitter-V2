//
//  LoginViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

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
class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var currentUser: CDAppUser?
    
    var isAuthenticated: Bool {
        return authService.isAuthenticated
    }
    
    private let authService = AuthService.shared
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var isPreviewMode = false
    
    init() {
        #if DEBUG
        // Se já tiver usuário (ex: vindo do Preview), não sobrescreve!
        if currentUser != nil { 
            print("🎯 LoginViewModel.init - Mantendo usuário existente: \(currentUser?.safeName ?? "nil")")
            isPreviewMode = true
            return 
        }
        #endif

        // Inicializa o currentUser com o usuário do AuthService apenas se não estiver em preview
        if !isPreviewMode {
            currentUser = authService.currentUser
            
            #if DEBUG
            if currentUser != nil {
                print("🎯 LoginViewModel.init - Usuário do AuthService: \(currentUser?.safeName ?? "nil")")
            } else {
                print("⚠️ LoginViewModel.init - Nenhum usuário do AuthService (normal em preview)")
            }
            #endif

            // Adiciona listener para mudanças de autenticação apenas se não estiver em preview
            setupAuthListener()
        }
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    private func setupAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in
                guard let self = self, !self.isPreviewMode else { return }
                self.currentUser = self.authService.currentUser
                self.objectWillChange.send()
            }
        }
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
        if !isPreviewMode {
            currentUser = authService.currentUser
            objectWillChange.send()
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension LoginViewModel {
    static var preview: LoginViewModel {
        let vm = LoginViewModel()
        vm.isPreviewMode = true // Marca como preview mode
        // Usa contexto do banco mockado para pegar um usuário fake
        let context = PreviewCoreDataStack.shared.viewContext
        let fetch: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        if let user = try? context.fetch(fetch).first {
            vm.currentUser = user
            print("🎯 LoginViewModel.preview - Usuário configurado: \(user.safeName)")
        } else {
            print("⚠️ LoginViewModel.preview - Nenhum usuário encontrado no contexto de preview")
        }
        return vm
    }
    static var emptyPreview: LoginViewModel {
        let vm = LoginViewModel()
        vm.isPreviewMode = true
        vm.currentUser = nil // Sem usuário
        return vm
    }
}
#endif
