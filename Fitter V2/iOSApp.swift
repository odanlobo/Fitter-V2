//
//  iOSApp.swift
//  Fitter V2
//
//  📱 ENTRY POINT PRINCIPAL - CLEAN ARCHITECTURE COM INJEÇÃO DE DEPENDÊNCIAS
//  
//  🎯 RESPONSABILIDADES CENTRAIS:
//  • Configurar infraestrutura compartilhada (Core Data, Firebase, HealthKit, RevenueCat)
//  • Implementar injeção de dependências completa seguindo Clean Architecture
//  • Instanciar Use Cases com dependências corretas em ordem hierárquica
//  • Centralizar ViewModels como @StateObject para gerenciamento de estado
//  • Gerenciar fluxo de autenticação e controle de inatividade de segurança
//  
//  🏗️ ARQUITETURA IMPLEMENTADA:
//  • Clean Architecture com separação clara de camadas
//  • Dependency Injection via protocolos para testabilidade
//  • Infraestrutura → Services → Use Cases → ViewModels → Views
//  • Estado reativo com @StateObject e @EnvironmentObject
//  • Async/await para operações não-bloqueantes
//  
//  🔒 RECURSOS DE SEGURANÇA:
//  • Verificação automática de inatividade (7 dias) com logout automático
//  • Dados sempre vinculados ao usuário autenticado
//  • Integração com Keychain para dados sensíveis
//  • Conformidade com diretrizes de privacidade Apple
//  
//  🔄 INTEGRAÇÃO COM SISTEMAS EXTERNOS:
//  • HealthKit: Dados vitais em tempo real durante treinos
//  • Firebase: Autenticação, Firestore para sincronização
//  • RevenueCat: Sistema de assinaturas e compras in-app
//  • Apple Watch: Sincronização via WatchConnectivity
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import HealthKit
import WatchConnectivity
import CoreData
import FirebaseCore
import FacebookCore
import RevenueCat

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        return true
    }
    
    func application(_ app: UIApplication,
                    open url: URL,
                    options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        ApplicationDelegate.shared.application(
            app,
            open: url,
            sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
            annotation: options[UIApplication.OpenURLOptionsKey.annotation]
        )
    }
}

// MARK: - Main App

/**
 * FitterApp - Entry point principal do aplicativo iOS
 * 
 * ARQUITETURA: Clean Architecture com injeção de dependências completa
 * RESPONSABILIDADES:
 * - Configurar infraestrutura compartilhada (Core Data, Firebase, HealthKit)
 * - Criar e injetar serviços via dependency injection
 * - Instanciar Use Cases com dependências corretas
 * - Centralizar ViewModels como @StateObject
 * - Gerenciar fluxo de autenticação e inatividade
 * 
 * INTEGRAÇÃO COM README_FLUXO_DADOS.md:
 * - HealthKitManager para dados vitais
 * - AuthUseCase para login obrigatório + logout por inatividade
 * - Use Cases de Lifecycle para fluxo granular Watch ↔ iPhone
 * 
 * SEGURANÇA:
 * - Verificação automática de inatividade (7 dias)
 * - Logout automático por segurança
 * - Dados sempre vinculados ao usuário autenticado
 */
@main
struct FitterApp: App {
    
    // MARK: - App Delegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // MARK: - 1. Infraestrutura Compartilhada
    
    /// Core Data - Fonte única de persistência
    /// PersistenceController otimizado para modelo FitterModel com suporte a Binary Data
    private let persistence = PersistenceController.shared
    
    /// Service de infraestrutura para operações CRUD genéricas
    /// Abstração do Core Data com interface testável e injeção de dependências
    private let coreDataService: CoreDataServiceProtocol
    
    /// Manager de sincronização em nuvem
    /// Singleton para coordenação global de sincronização com Firestore
    private let cloudSyncManager = CloudSyncManager.shared
    
    /// Service de autenticação (email/senha)
    /// Implementa AuthServiceProtocol para operações básicas Firebase Auth
    private let authService: AuthServiceProtocol
    
    /// Manager dedicado para HealthKit
    /// Gerencia permissões e coleta de dados vitais durante treinos
    private let healthKitManager: HealthKitManagerProtocol
    
    /// Service centralizado de timers
    /// Controla timers de descanso, duração de séries e exercícios
    private let timerService: TimerServiceProtocol
    
    /// Manager de sessão iPhone ↔ Apple Watch
    /// Responsável por sincronização em tempo real de dados de treino com Apple Watch
    private let phoneSessionManager: PhoneSessionManagerProtocol
    
    /// Manager dedicado para localização de treinos
    /// Captura localização no início dos treinos
    private let locationManager: LocationManagerProtocol
    
    // MARK: - 2. Repositórios Específicos
    
    /// Repository para exercícios Firebase
    /// Interface com Firestore para catálogo de exercícios pré-definidos
    private let exerciseRepository: FirestoreExerciseRepositoryProtocol
    
    // MARK: - 3. Services Especializados
    
    /// Service especializado para entidades de treino
    /// Responsável por operações CRUD específicas de workout com integração ao Core Data
    private let workoutDataService: WorkoutDataServiceProtocol
    
    /// Service de importação de treinos (imagem, PDF, CSV)
    /// Responsável por parsing e extração de dados de arquivos via OCR, PDFKit e CSV
    private let importService: ImportWorkoutServiceProtocol
    
    // MARK: - 4. Use Cases - Autenticação
    
    /// Use Case de autenticação (orquestração de todos provedores)
    /// Centraliza login/logout via Apple, Google, Facebook, Email e Biometria
    /// Integrado com SubscriptionManager para controle de assinaturas
    private let authUseCase: AuthUseCaseProtocol
    
    // MARK: - 5. Use Cases - Exercícios Firebase
    
    /// Use Case para busca de exercícios Firebase
    /// Consome FirestoreExerciseRepository para catálogo de exercícios remotos
    private let fetchFBExercisesUseCase: FetchFBExercisesUseCaseProtocol
    
    // MARK: - 6. Use Cases - Workout CRUD
    
    /// Use Case para criação de treinos
    /// Integrado com sincronização automática via CloudSyncManager
    private let createWorkoutUseCase: CreateWorkoutUseCaseProtocol
    
    /// Use Case para busca de treinos
    /// Fonte de dados principal para listagem de treinos do usuário
    private let fetchWorkoutUseCase: FetchWorkoutUseCaseProtocol
    
    /// Use Case para edição de treinos
    /// Mantém histórico de modificações e sincronização em tempo real
    private let updateWorkoutUseCase: UpdateWorkoutUseCaseProtocol
    
    /// Use Case para exclusão de treinos
    /// Implementa soft delete com possibilidade de recuperação
    private let deleteWorkoutUseCase: DeleteWorkoutUseCaseProtocol
    
    /// Use Case para reordenação de treinos
    /// Permite reorganização da lista com persistência automática
    private let reorderWorkoutUseCase: ReorderWorkoutUseCaseProtocol
    
    /// Use Case para reordenação de exercícios
    /// Gestão da ordem dos exercícios dentro de cada treino
    private let reorderExerciseUseCase: ReorderExerciseUseCaseProtocol
    
    /// Use Case para sincronização
    /// Motor central de sincronização com Firestore para todas as entidades
    private let syncWorkoutUseCase: SyncWorkoutUseCaseProtocol
    
    /// Use Case para importação de treinos
    /// Suporte a importação via câmera, arquivos e outros apps de fitness
    private let importWorkoutUseCase: ImportWorkoutUseCaseProtocol
    
    // MARK: - 7. Use Cases - Workout Lifecycle
    
    /// Use Case para iniciar treino
    /// Transição do planejamento para execução ativa do treino
    private let startWorkoutUseCase: StartWorkoutUseCaseProtocol
    
    /// Use Case para finalizar treino
    /// Consolidação de dados e transferência para histórico
    private let endWorkoutUseCase: EndWorkoutUseCaseProtocol
    
    /// Use Case para iniciar exercício
    /// Controle granular de início de cada exercício individual
    private let startExerciseUseCase: StartExerciseUseCaseProtocol
    
    /// Use Case para finalizar exercício
    /// Processamento de dados de sensores e métricas do exercício
    private let endExerciseUseCase: EndExerciseUseCaseProtocol
    
    /// Use Case para iniciar série
    /// Controle preciso de cada série com timer e contadores
    private let startSetUseCase: StartSetUseCaseProtocol
    
    /// Use Case para finalizar série
    /// Consolidação de repetições, peso e dados de sensores
    private let endSetUseCase: EndSetUseCaseProtocol
    
    // MARK: - 8. Services de Assinatura
    
    /// Service do RevenueCat para assinaturas
    /// Interface direta com App Store Connect para compras e verificações
    private let revenueCatService: RevenueCatServiceProtocol
    
    /// Manager de assinaturas (orquestrador)
    /// Centraliza lógica de negócio para funcionalidades premium
    private let subscriptionManager: SubscriptionManagerProtocol
    
    // MARK: - 8.1. Services de Machine Learning
    
    /// Manager de modelos ML (não implementado)
    /// Responsável por carregar e gerenciar modelos Core ML para detecção automática
    private let mlModelManager: MLModelManagerProtocol
    
    /// Use Case para processamento de dados ML
    /// Integra dados de sensores com modelos ML para detecção automática de repetições
    private let updateDataToMLUseCase: UpdateDataToMLUseCaseProtocol
    
    // MARK: - 9. ViewModels Centralizados
    
    /// ViewModel de autenticação (login/cadastro)
    /// Gerencia estado de autenticação e navegação entre telas de login
    /// Conectado ao AuthUseCase para orquestração de provedores
    @StateObject private var authViewModel: LoginViewModel
    
    /// ViewModel de lista de exercícios Firebase
    /// Fornece catálogo de exercícios para seleção durante criação de treinos
    /// Integrado com cache local para performance offline
    @StateObject private var listExerciseViewModel: ListExerciseViewModel
    
    /// ViewModel principal de treinos
    /// Centraliza estado de todos os treinos do usuário
    /// Conectado a todos os Use Cases de CRUD e Lifecycle
    @StateObject private var workoutViewModel: WorkoutViewModel
    
    /// ViewModel de sessão de treino ativa
    /// Gerencia estado em tempo real durante execução de treinos
    /// Integrado com Apple Watch, HealthKit e detecção automática via ML
    @StateObject private var workoutSessionViewModel: WorkoutSessionViewModel
    
    // MARK: - Initializer
    
    /**
     * Inicializador principal do FitterApp
     * 
     * ARQUITETURA CLEAN: Implementa injeção de dependências completa
     * - Infraestrutura → Services → Use Cases → ViewModels
     * - Cada camada recebe dependências da camada anterior
     * - Protocolos garantem testabilidade e baixo acoplamento
     * 
     * ORDEM DE INICIALIZAÇÃO:
     * 0. RevenueCat (obrigatório antes de tudo)
     * 1. Infraestrutura compartilhada (Core Data, Auth, HealthKit)
     * 2. Services de assinatura (RevenueCat + SubscriptionManager)
     * 2.1. Services de Machine Learning (MLModelManager + UpdateDataToMLUseCase)
     * 3. Repositórios específicos (Firebase Collections)
     * 4. Services especializados (WorkoutDataService)
     * 5-8. Use Cases (Auth, CRUD, Lifecycle)
     * 8.1. Managers de sessão (PhoneSessionManager - dependem de Use Cases)
     * 9. ViewModels centralizados (@StateObject)
     * 
     * DEPENDÊNCIAS CRÍTICAS:
     * - CoreDataService → todos os Use Cases de persistência
     * - AuthService → AuthUseCase → todos os ViewModels
     * - SubscriptionManager → controle de funcionalidades premium
     * - CloudSyncManager → sincronização automática
     * 
     * LOGS: Cada etapa produz logs para debugging e monitoramento
     */
    init() {
        print("🚀 [FitterApp] Inicializando infraestrutura Clean Architecture...")
        
        // 0. Configurar RevenueCat (ANTES de tudo)
        configureRevenueCat()
        
        // 1. Infraestrutura compartilhada
        self.coreDataService = CoreDataService(
            persistenceController: persistence
        )
        self.authService = AuthService(coreDataService: coreDataService)
        self.healthKitManager = HealthKitManager()
        self.timerService = TimerService()
        self.locationManager = LocationManager()
        
        // 2. Services de Assinatura
        self.revenueCatService = RevenueCatService()
        self.subscriptionManager = SubscriptionManager(
            revenueCatService: revenueCatService,
            cloudSyncManager: cloudSyncManager,
            coreDataService: coreDataService
        )
        
        // 2.1. Services de Machine Learning
        self.mlModelManager = MLModelManager()
        self.updateDataToMLUseCase = UpdateDataToMLUseCase(
            mlModelManager: mlModelManager,
            subscriptionManager: subscriptionManager
        )
        
        // 3. Repositórios específicos
        self.exerciseRepository = FirestoreExerciseRepository()
        
        // 4. Services especializados
        self.workoutDataService = WorkoutDataService(
            coreDataService: coreDataService,
            adapter: CoreDataAdapter()
        )
        self.importService = ImportWorkoutService()
        
        // 5. Use Cases - Autenticação
        self.authUseCase = AuthUseCase(
            authService: authService,
            subscriptionManager: subscriptionManager
        )
        
        // 6. Use Cases - Exercícios Firebase
        self.fetchFBExercisesUseCase = FetchFBExercisesUseCase(repository: exerciseRepository)
        
        // 7. Use Cases - Workout CRUD
        self.syncWorkoutUseCase = SyncWorkoutUseCase(cloudSyncManager: cloudSyncManager)
        
        self.createWorkoutUseCase = CreateWorkoutUseCase(
            workoutDataService: workoutDataService,
            subscriptionManager: subscriptionManager,
            syncUseCase: syncWorkoutUseCase
        )
        
        self.fetchWorkoutUseCase = FetchWorkoutUseCase(
            workoutDataService: workoutDataService
        )
        
        self.updateWorkoutUseCase = UpdateWorkoutUseCase(
            workoutDataService: workoutDataService,
            syncUseCase: syncWorkoutUseCase
        )
        
        self.deleteWorkoutUseCase = DeleteWorkoutUseCase(
            workoutDataService: workoutDataService,
            syncUseCase: syncWorkoutUseCase
        )
        
        self.reorderWorkoutUseCase = ReorderWorkoutUseCase(
            workoutDataService: workoutDataService,
            syncUseCase: syncWorkoutUseCase
        )
        
        self.reorderExerciseUseCase = ReorderExerciseUseCase(
            workoutDataService: workoutDataService,
            syncUseCase: syncWorkoutUseCase
        )
        
        // 8. Use Cases - Workout Lifecycle
        self.startWorkoutUseCase = StartWorkoutUseCase(
            workoutDataService: workoutDataService,
            syncWorkoutUseCase: syncWorkoutUseCase,
            locationManager: locationManager
        )
        
        self.endWorkoutUseCase = EndWorkoutUseCase(
            workoutDataService: workoutDataService,
            syncWorkoutUseCase: syncWorkoutUseCase,
            locationManager: locationManager
        )
        
        self.startExerciseUseCase = StartExerciseUseCase(
            workoutDataService: workoutDataService
        )
        
        self.endExerciseUseCase = EndExerciseUseCase(
            workoutDataService: workoutDataService
        )
        
        self.startSetUseCase = StartSetUseCase(
            workoutDataService: workoutDataService,
            subscriptionManager: subscriptionManager
        )
        
        self.endSetUseCase = EndSetUseCase(
            workoutDataService: workoutDataService,
            syncUseCase: syncWorkoutUseCase
        )
        
        self.importWorkoutUseCase = ImportWorkoutUseCase(
            importService: importService,
            workoutDataService: workoutDataService,
            subscriptionManager: subscriptionManager,
            syncUseCase: syncWorkoutUseCase,
            fetchFBExercisesUseCase: fetchFBExercisesUseCase
        )
        
        // 8.1. Session Managers (após Use Cases - dependem de Use Cases)
        self.phoneSessionManager = PhoneSessionManager(
            coreDataService: coreDataService,
            workoutDataService: workoutDataService,
            syncWorkoutUseCase: syncWorkoutUseCase,
            updateDataToMLUseCase: updateDataToMLUseCase
        )
        
        // 9. ViewModels centralizados
        self._authViewModel = StateObject(wrappedValue: LoginViewModel(useCase: authUseCase))
        self._listExerciseViewModel = StateObject(wrappedValue: ListExerciseViewModel(
            fetchExercisesUseCase: fetchFBExercisesUseCase,
            coreDataService: coreDataService,
            authUseCase: authUseCase
        ))
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(
            createUseCase: createWorkoutUseCase,
            fetchUseCase: fetchWorkoutUseCase,
            updateUseCase: updateWorkoutUseCase,
            deleteUseCase: deleteWorkoutUseCase,
            reorderWorkoutUseCase: reorderWorkoutUseCase,
            reorderExerciseUseCase: reorderExerciseUseCase,
            syncUseCase: syncWorkoutUseCase,
            fetchFBExercisesUseCase: fetchFBExercisesUseCase,
            coreDataService: coreDataService,
            authUseCase: authUseCase
        ))
        self._workoutSessionViewModel = StateObject(wrappedValue: WorkoutSessionViewModel(
            startWorkoutUseCase: startWorkoutUseCase,
            endWorkoutUseCase: endWorkoutUseCase,
            startExerciseUseCase: startExerciseUseCase,
            endExerciseUseCase: endExerciseUseCase,
            startSetUseCase: startSetUseCase,
            endSetUseCase: endSetUseCase,
            fetchWorkoutUseCase: fetchWorkoutUseCase,
            timerService: timerService,
            phoneSessionManager: phoneSessionManager,
            healthKitManager: healthKitManager,
            subscriptionManager: subscriptionManager,
            coreDataService: coreDataService,
            authUseCase: authUseCase
        ))
        
        print("✅ [FitterApp] Infraestrutura Clean Architecture inicializada com sucesso")
    }
    
    // MARK: - Body
    
    /**
     * Interface principal do aplicativo
     * 
     * FLUXO DE NAVEGAÇÃO:
     * - Tela de Login (não autenticado) → MainTabView (autenticado)
     * - Verificação de autenticação reativa via @StateObject authViewModel
     * - Configuração automática do HealthKit no primeiro acesso
     * 
     * GERENCIAMENTO DE ESTADO:
     * - @EnvironmentObject para compartilhamento global de ViewModels
     * - authViewModel: Estado de autenticação e dados do usuário
     * - listExerciseViewModel: Catálogo de exercícios Firebase
     * - workoutViewModel: Estado principal dos treinos
     * - workoutSessionViewModel: Estado de treino ativo em tempo real
     * - subscriptionManager: Controle de funcionalidades premium
     * 
     * LIFECYCLE:
     * - onAppear: Executa handleAppLaunch() para verificar inatividade
     * - setupHealthKitAuthorization: Configura permissões de dados vitais
     * 
     * ARQUITETURA:
     * - Scene-based app structure (iOS 14+)
     * - Environment Objects para injeção de dependências na UI
     * - Task async para operações não-bloqueantes
     */
    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    MainTabView()
                        .onAppear {
                            Task {
                                await handleAppLaunch()
                            }
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
            .environmentObject(listExerciseViewModel)
            .environmentObject(workoutViewModel)
            .environmentObject(workoutSessionViewModel)
            .environmentObject(subscriptionManager as! SubscriptionManager)
            .onAppear {
                setupHealthKitAuthorization()
                setupLocationAuthorization()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /**
     * Configura RevenueCat com chave API
     * 
     * RESPONSABILIDADE: Configuração única do SDK RevenueCat no app launch
     * SEGURANÇA: Chave API deve ser obtida do RevenueCat Dashboard
     * INTEGRAÇÃO: Conforme README_ASSINATURAS.md seção 5
     * 
     * ARQUITETURA:
     * - Chamado antes de qualquer outra inicialização
     * - Necessário para funcionamento do SubscriptionManager
     * - Configura ambiente de produção por padrão
     */
    private func configureRevenueCat() {
        // ⚠️ IMPORTANTE: Substitua pela sua chave API real do RevenueCat Dashboard
        let revenueCatAPIKey = "YOUR_REVENUECAT_PUBLIC_API_KEY"
        
        Purchases.configure(withAPIKey: revenueCatAPIKey)
        print("✅ [FitterApp] RevenueCat configurado com sucesso")
    }
    
    /**
     * Configura autorização do HealthKit via HealthKitManager
     * 
     * RESPONSABILIDADE: Delegar configuração para HealthKitManager dedicado
     * INTEGRAÇÃO: Conforme README_FLUXO_DADOS.md para dados vitais em tempo real
     * 
     * DADOS SOLICITADOS:
     * - Heart Rate (frequência cardíaca durante treinos)
     * - Active Energy (calorias queimadas)
     * - Workout Sessions (sessões de treino)
     * - Body Mass (peso corporal para cálculos)
     * 
     * PRIVACIDADE:
     * - Permissões solicitadas de forma transparente
     * - Dados mantidos localmente e sincronizados apenas se autorizado
     * - Conformidade com diretrizes Apple Health
     */
    private func setupHealthKitAuthorization() {
        Task {
            do {
                let isAuthorized = try await healthKitManager.requestAuthorization()
                print(isAuthorized ? "✅ [FitterApp] HealthKit autorizado com sucesso" : "⚠️ [FitterApp] HealthKit não autorizado")
            } catch {
                print("❌ [FitterApp] Erro ao configurar HealthKit: \(error.localizedDescription)")
            }
        }
    }
    
    /**
     * Configura autorização de localização via LocationManager
     * 
     * RESPONSABILIDADE: Delegar configuração para LocationManager dedicado
     * INTEGRAÇÃO: Captura localização opcional no início dos treinos
     * 
     * OPÇÕES APRESENTADAS AO USUÁRIO:
     * - Permitir Sempre: Captura localização em background
     * - Durante o Uso do App: Captura apenas quando app está ativo
     * - Não Permitir: Funcionalidades não são afetadas
     * 
     * PRIVACIDADE:
     * - Modal nativo da Apple com opções claras
     * - Localização é opcional e não bloqueia funcionalidades
     * - Dados mantidos localmente no Core Data
     * - Conformidade com diretrizes de privacidade Apple
     */
    private func setupLocationAuthorization() {
        Task {
            let status = await locationManager.requestLocationPermission()
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("✅ [FitterApp] Localização autorizada: \(status)")
            case .denied, .restricted:
                print("⚠️ [FitterApp] Localização negada: \(status) - App funcionará normalmente")
            case .notDetermined:
                print("🔄 [FitterApp] Localização pendente: \(status)")
            @unknown default:
                print("❓ [FitterApp] Status de localização desconhecido: \(status)")
            }
        }
    }
    
    /**
     * Gerencia ações no launch do app quando usuário está autenticado
     * 
     * RESPONSABILIDADES:
     * - Verificar inatividade de 7 dias (logout automático por segurança)
     * - Atualizar lastAppOpenDate
     * - Sincronização inicial de dados
     * 
     * SEGURANÇA: Conforme arquitetura de login obrigatório + logout por inatividade
     */
    private func handleAppLaunch() async {
        print("🔍 [FitterApp] Verificando inatividade do usuário...")
        
        do {
            let shouldLogout = authUseCase.checkInactivityTimeout()
            if shouldLogout {
                print("⏰ [FitterApp] Logout automático: usuário inativo por mais de 7 dias")
                try await authUseCase.logoutDueToInactivity()
            } else {
                // Atualizar data do último acesso
                authUseCase.updateLastAppOpenDate()
                print("✅ [FitterApp] LastAppOpenDate atualizada")
                
                // Sincronização inicial de dados
                await performInitialSync()
            }
        } catch {
            print("❌ [FitterApp] Erro ao verificar inatividade: \(error.localizedDescription)")
        }
    }
    
    /**
     * Executa sincronização inicial de dados
     * 
     * RESPONSABILIDADE: Sincronizar dados essenciais no launch do app
     * 
     * FLUXO DE SINCRONIZAÇÃO:
     * - Verifica dados pendentes no Core Data
     * - Agenda upload via CloudSyncManager
     * - Download de mudanças remotas do Firestore
     * - Resolução de conflitos por timestamp
     * 
     * PERFORMANCE:
     * - Execução em background para não bloquear UI
     * - Retry automático em caso de falhas de rede
     * - Cache local para funcionamento offline
     * 
     * INTEGRAÇÃO:
     * - Conectado ao SyncWorkoutUseCase
     * - Suporte a múltiplos tipos de entidades
     * - Monitoramento de progress para UX
     */
    private func performInitialSync() async {
        print("🔄 [FitterApp] Iniciando sincronização de dados...")
        
        // Sincronizar dados de treinos
        do {
            if let currentUser = authViewModel.currentUser {
                // Sincronizar o usuário primeiro
                try await syncWorkoutUseCase.execute(currentUser)
                // Depois executar sincronização completa de todas as entidades pendentes
                try await syncWorkoutUseCase.syncAllPendingEntities()
                print("✅ [FitterApp] Sincronização de treinos concluída")
            }
        } catch {
            print("⚠️ [FitterApp] Erro na sincronização: \(error.localizedDescription)")
        }
    }
}
