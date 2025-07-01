//
//  BaseViewModel.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import Combine
import CoreData
import SwiftUI

/// ViewModel base com estados e comportamentos comuns para toda a aplicação
/// 
/// Responsabilidades:
/// - Estados de UI (loading, error, processing)
/// - Tratamento de erros consistente  
/// - Orquestração de Use Cases (SEM lógica de negócio)
/// - Observação do estado de autenticação
/// 
/// ⚡ Clean Architecture:
/// - Injeção de dependências via inicializador
/// - Foco APENAS em lógica de UI/apresentação
/// - Toda persistência DEVE passar pelos Use Cases
/// - ViewContext apenas para SwiftUI binding (somente leitura)
@MainActor
open class BaseViewModel: ObservableObject {
    
    // MARK: - Estados de UI
    
    /// Indica se uma operação assíncrona está em andamento
    @Published public var isLoading: Bool = false
    
    /// Controla se o alerta de erro deve ser exibido
    @Published public var showError: Bool = false
    
    /// Mensagem de erro para exibir ao usuário
    @Published public var errorMessage: String = ""
    
    /// Indica se há uma operação em progresso que pode ser cancelada
    @Published public var isProcessing: Bool = false
    
    /// Usuário atual autenticado
    /// ⚠️ IMPORTANTE: Nunca será nil após login inicial (sessão persistente)
    /// App com LOGIN OBRIGATÓRIO - dados sempre vinculados ao usuário
    @Published public var currentUser: CDAppUser!
    
    // MARK: - Dependências Injetadas
    
    /// Serviço de operações Core Data
    protected let coreDataService: CoreDataServiceProtocol
    
    /// Serviço de autenticação (será migrado para AuthUseCase no item 34)
    protected let authService: AuthService
    
    // MARK: - Estado de Preview
    
    #if DEBUG
    /// Indica se o ViewModel está rodando em modo Preview (SwiftUI Previews)
    protected var isPreviewMode: Bool = false
    #endif
    
    // MARK: - Combine
    
    /// Set para armazenar Combine cancellables
    protected var cancellables = Set<AnyCancellable>()
    
    // MARK: - Inicialização
    
    /// Inicializa BaseViewModel com dependências injetadas
    /// - Parameters:
    ///   - coreDataService: Serviço para operações Core Data
    ///   - authService: Serviço de autenticação
    public init(
        coreDataService: CoreDataServiceProtocol = CoreDataService(),
        authService: AuthService = AuthService.shared
    ) {
        self.coreDataService = coreDataService
        self.authService = authService
        
        setupUserObserver()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Métodos de UI
    
    /// Exibe uma mensagem de erro para o usuário
    /// - Parameter message: Mensagem de erro a ser exibida
    public func showError(message: String) {
        errorMessage = message
        showError = true
        print("❌ Erro: \(message)")
    }
    
    /// Limpa o estado de erro atual
    public func clearError() {
        showError = false
        errorMessage = ""
    }
    
    /// Executa uma operação assíncrona com indicador de loading
    /// - Parameter operation: Operação a ser executada
    /// - Returns: Resultado da operação ou nil em caso de erro
    public func withLoading<T>(_ operation: @escaping () async throws -> T) async -> T? {
        isLoading = true
        defer { isLoading = false }
        
        do {
            return try await operation()
        } catch let error as AuthError {
            showError(message: error.localizedDescription)
            return nil
        } catch let error as CoreDataError {
            showError(message: error.localizedDescription)
            return nil
        } catch {
            showError(message: "Erro inesperado: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Executa uma operação assíncrona com indicador de processamento
    /// - Parameter operation: Operação a ser executada
    /// - Returns: Resultado da operação ou nil em caso de erro
    public func withProcessing<T>(_ operation: @escaping () async throws -> T) async -> T? {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            return try await operation()
        } catch let error as AuthError {
            showError(message: error.localizedDescription)
            return nil
        } catch let error as CoreDataError {
            showError(message: error.localizedDescription)
            return nil
        } catch {
            showError(message: "Erro inesperado: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Orquestração de Use Cases
    
    /// Executa um Use Case com tratamento de loading e erros
    /// - Parameter useCase: Use Case a ser executado
    /// - Returns: Resultado do Use Case ou nil em caso de erro
    public func executeUseCase<T>(_ useCase: @escaping () async throws -> T) async -> T? {
        return await withLoading {
            return try await useCase()
        }
    }
    
    /// Executa um Use Case com indicador de processamento
    /// - Parameter useCase: Use Case a ser executado  
    /// - Returns: Resultado do Use Case ou nil em caso de erro
    public func executeUseCaseWithProcessing<T>(_ useCase: @escaping () async throws -> T) async -> T? {
        return await withProcessing {
            return try await useCase()
        }
    }
    
    // MARK: - Métodos de Autenticação
    
    /// Realiza login do usuário
    /// - Parameter credentials: Credenciais de login
    public func login(with credentials: LoginCredentials) async {
        let user = try await authService.signIn(credentials)
        self.currentUser = user
    }
    
    /// Realiza logout manual do usuário
    /// ⚠️ ÚNICO meio de deslogar - app mantém sessão mesmo ao fechar
    public func logout() async {
        try await authService.signOut()
        self.currentUser = nil
    }
    
    // MARK: - Métodos Privados
    
    /// Configura observador do usuário atual
    private func setupUserObserver() {
        #if DEBUG
        // Em modo preview, não configura listener
        if isPreviewMode { return }
        #endif
        
        // ✅ LOGIN OBRIGATÓRIO: Inicializa com usuário atual do AuthService
        // Se não houver usuário, app mostrará tela de login
        currentUser = authService.currentUser
        
        // TODO: Substituir por AuthUseCase no item 34
        // Observa mudanças no estado de autenticação
        NotificationCenter.default
            .publisher(for: .authStateChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    // ✅ SESSÃO PERSISTENTE: Atualiza apenas se usuário válido
                    if let user = self?.authService.currentUser {
                        self?.currentUser = user
                    }
                    // Se user for nil, mantém o anterior até logout manual
                }
            }
            .store(in: &cancellables)
    }
    
    // Adicionar método de verificação de inatividade
    func checkAndHandleInactivity() async {
        if authService.checkInactivityTimeout() {
            await authService.logoutDueToInactivity()
            
            // Limpar dados locais sensíveis
            currentUser = nil
            
            // Mostrar mensagem explicativa
            await MainActor.run {
                showError(
                    title: "Sessão Expirada", 
                    message: "Por segurança, você foi deslogado após 7 dias de inatividade. Faça login novamente."
                )
            }
        } else {
            // Atualiza último acesso
            authService.updateLastAppOpenDate()
        }
    }
}

// MARK: - Computed Properties
extension BaseViewModel {
    
    /// Indica se o usuário está autenticado
    /// ✅ LOGIN OBRIGATÓRIO: Sempre true após login inicial (sessão persistente)
    public var isAuthenticated: Bool {
        return currentUser != nil && authService.isAuthenticated
    }
    
    /// Indica se há alguma operação em andamento
    public var isBusy: Bool {
        return isLoading || isProcessing
    }
    
    /// Acesso ao contexto principal APENAS para SwiftUI binding
    /// ⚠️ IMPORTANTE: Usar apenas para @FetchRequest e observação
    /// Para operações de persistência, use Use Cases apropriados
    public var viewContext: NSManagedObjectContext {
        return coreDataService.viewContext
    }
}

// MARK: - Preview Support
#if DEBUG
extension BaseViewModel {
    
    /// Configura o ViewModel para modo preview
    /// - Parameter mockUser: Usuário mock para usar no preview
    public func configureForPreview(mockUser: CDAppUser? = nil) {
        isPreviewMode = true
        
        if let user = mockUser {
            currentUser = user
            print("🎯 BaseViewModel configurado para preview com usuário: \(user.safeName)")
        } else {
            // Tenta buscar usuário do contexto de preview
            let context = PreviewCoreDataStack.shared.viewContext
            let fetch: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
            if let user = try? context.fetch(fetch).first {
                currentUser = user
                print("🎯 BaseViewModel configurado para preview com usuário do mock: \(user.safeName)")
            } else {
                print("⚠️ BaseViewModel preview: Nenhum usuário mock encontrado")
            }
        }
    }
    
    /// Cria instância para preview com dependências mockadas
    /// - Parameters:
    ///   - mockUser: Usuário mock
    ///   - mockCoreDataService: CoreDataService mock para testes
    /// - Returns: BaseViewModel configurado para preview
    public static func previewInstance(
        with mockUser: CDAppUser? = nil,
        mockCoreDataService: CoreDataServiceProtocol? = nil
    ) -> BaseViewModel {
        let coreDataService = mockCoreDataService ?? CoreDataService(
            persistenceController: PreviewCoreDataStack.shared.persistenceController
        )
        
        let vm = BaseViewModel(coreDataService: coreDataService)
        vm.configureForPreview(mockUser: mockUser)
        return vm
    }
}
#endif

// MARK: - Notifications
extension Notification.Name {
    /// Notificação para mudanças no estado de autenticação
    static let authStateChanged = Notification.Name("authStateChanged")
} 