import Foundation
import HealthKit
import Combine

// MARK: - Protocols

/// Protocolo para facilitar testes e mocks do HealthKitManager
protocol HealthKitManagerProtocol {
    /// Verifica se o HealthKit está disponível no dispositivo
    var isHealthKitAvailable: Bool { get }
    
    /// Verifica se as permissões necessárias foram concedidas
    var isAuthorized: Bool { get }
    
    /// Publisher para mudanças de autorização
    var authorizationStatusPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Solicita autorização para acessar dados do HealthKit
    func requestAuthorization() async throws -> Bool
    
    /// Inicia captura de heart rate em tempo real
    func startHeartRateMonitoring() async throws
    
    /// Para captura de heart rate
    func stopHeartRateMonitoring()
    
    /// Inicia captura de calorias em tempo real
    func startCaloriesMonitoring() async throws
    
    /// Para captura de calorias
    func stopCaloriesMonitoring()
    
    /// Obtém dados de heart rate para um período específico
    func fetchHeartRateData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample]
    
    /// Obtém dados de calorias para um período específico
    func fetchCaloriesData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample]
    
    /// Salva dados de heart rate no HealthKit
    func saveHeartRateData(_ heartRate: Double, date: Date) async throws
    
    /// Salva dados de calorias no HealthKit
    func saveCaloriesData(_ calories: Double, date: Date) async throws
    
    /// Cria uma sessão de workout no HealthKit
    func startWorkoutSession(workoutType: HKWorkoutActivityType, startDate: Date) async throws -> HKWorkoutSession
    
    /// Finaliza uma sessão de workout
    func endWorkoutSession(_ session: HKWorkoutSession, endDate: Date) async throws -> HKWorkout
    
    /// Obtém estatísticas de workout para um período
    func fetchWorkoutStatistics(from startDate: Date, to endDate: Date) async throws -> HKStatisticsCollection
}

// MARK: - Error Types

/// Erros específicos do HealthKitManager
enum HealthKitManagerError: LocalizedError {
    case healthKitNotAvailable
    case notAuthorized
    case authorizationDenied
    case invalidData
    case saveFailed(Error)
    case fetchFailed(Error)
    case sessionError(Error)
    case monitoringError(Error)
    
    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit não está disponível neste dispositivo"
        case .notAuthorized:
            return "Autorização para HealthKit não foi concedida"
        case .authorizationDenied:
            return "Acesso ao HealthKit foi negado pelo usuário"
        case .invalidData:
            return "Dados inválidos para salvar no HealthKit"
        case .saveFailed(let error):
            return "Falha ao salvar dados: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Falha ao buscar dados: \(error.localizedDescription)"
        case .sessionError(let error):
            return "Erro na sessão de workout: \(error.localizedDescription)"
        case .monitoringError(let error):
            return "Erro no monitoramento: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .healthKitNotAvailable:
            return "Verifique se o dispositivo suporta HealthKit"
        case .notAuthorized, .authorizationDenied:
            return "Vá em Configurações > Privacidade > Saúde e conceda permissão para o Fitter"
        case .invalidData:
            return "Verifique se os dados estão no formato correto"
        case .saveFailed, .fetchFailed, .sessionError, .monitoringError:
            return "Tente novamente. Se o problema persistir, reinicie o app"
        }
    }
}

// MARK: - HealthKitManager Implementation

/// Serviço centralizado para toda interação com HealthKit
/// 
/// **Responsabilidades:**
/// - Autorização e verificação de disponibilidade
/// - Captura de heart rate e calorias em tempo real
/// - Persistência de dados no HealthKit
/// - Criação e gerenciamento de sessões de workout
/// - Busca de dados históricos
///
/// **Integração:**
/// - Usado pelos Use Cases de Lifecycle (StartWorkout, EndWorkout, etc.)
/// - Integra com Core Data para persistência local
/// - Sincroniza com Apple Watch via WatchSessionManager
final class HealthKitManager: NSObject, HealthKitManagerProtocol {
    
    // MARK: - Properties
    
    /// Instância do HealthKit store
    private let healthStore = HKHealthStore()
    
    /// Tipos de dados que o app precisa acessar
    private let requiredTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.workoutType()
    ]
    
    /// Tipos de dados que o app pode escrever
    private let writableTypes: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.workoutType()
    ]
    
    /// Publisher para mudanças de autorização
    private let authorizationSubject = CurrentValueSubject<Bool, Never>(false)
    
    /// Sessão de workout ativa
    private var activeWorkoutSession: HKWorkoutSession?
    
    /// Observadores de heart rate
    private var heartRateObservers: [HKObserverQuery] = []
    
    /// Observadores de calorias
    private var caloriesObservers: [HKObserverQuery] = []
    
    // MARK: - Publishers para dados em tempo real

    /// Publisher para dados de heart rate em tempo real
    private let heartRateSubject = PassthroughSubject<Double, Never>()
    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    /// Publisher para dados de calorias em tempo real
    private let caloriesSubject = PassthroughSubject<Double, Never>()
    var caloriesPublisher: AnyPublisher<Double, Never> {
        caloriesSubject.eraseToAnyPublisher()
    }

    /// Publisher para dados de workout session
    private let workoutSessionSubject = PassthroughSubject<HKWorkoutSession?, Never>()
    var workoutSessionPublisher: AnyPublisher<HKWorkoutSession?, Never> {
        workoutSessionSubject.eraseToAnyPublisher()
    }
    
    // MARK: - WatchSessionManager Integration

    /// Referência para WatchSessionManager (injetada)
    private weak var watchSessionManager: WatchSessionManagerProtocol?

    /// Configura integração com WatchSessionManager
    func setupWatchIntegration(_ watchSessionManager: WatchSessionManagerProtocol) {
        self.watchSessionManager = watchSessionManager
        print("✅ HealthKit: Integração com WatchSessionManager configurada")
    }
    
    // MARK: - Computed Properties
    
    /// Verifica se o HealthKit está disponível no dispositivo
    var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    /// Verifica se as permissões necessárias foram concedidas
    var isAuthorized: Bool {
        return authorizationSubject.value
    }
    
    /// Publisher para mudanças de autorização
    var authorizationStatusPublisher: AnyPublisher<Bool, Never> {
        return authorizationSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAuthorizationStatus()
    }
    
    // MARK: - Setup Methods
    
    /// Configura o status inicial de autorização
    private func setupAuthorizationStatus() {
        guard isHealthKitAvailable else {
            authorizationSubject.send(false)
            return
        }
        
        Task {
            let isAuthorized = await checkAuthorizationStatus()
            authorizationSubject.send(isAuthorized)
        }
    }
    
    /// Verifica o status atual de autorização
    private func checkAuthorizationStatus() async -> Bool {
        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: writableTypes, read: requiredTypes) { status, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao verificar autorização: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                
                let isAuthorized = status == .unnecessary
                continuation.resume(returning: isAuthorized)
            }
        }
    }
    
    // MARK: - Authorization
    
    /// Solicita autorização para acessar dados do HealthKit
    func requestAuthorization() async throws -> Bool {
        guard isHealthKitAvailable else {
            throw HealthKitManagerError.healthKitNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: writableTypes, read: requiredTypes) { success, error in
                if let error = error {
                    print("❌ HealthKit: Erro na autorização: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.authorizationDenied)
                    return
                }
                
                if success {
                    print("✅ HealthKit: Autorização concedida")
                    self.authorizationSubject.send(true)
                    continuation.resume(returning: true)
                } else {
                    print("❌ HealthKit: Autorização negada")
                    self.authorizationSubject.send(false)
                    continuation.resume(throwing: HealthKitManagerError.authorizationDenied)
                }
            }
        }
    }
    
    // MARK: - Heart Rate Monitoring
    
    /// Inicia captura de heart rate em tempo real
    func startHeartRateMonitoring() async throws {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitManagerError.invalidData
        }
        
        // Para observadores existentes
        stopHeartRateMonitoring()
        
        // Cria novo observador
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] query, completion, error in
            if let error = error {
                print("❌ HealthKit: Erro no monitoramento de heart rate: \(error.localizedDescription)")
                completion()
                return
            }
            
            // Busca dados mais recentes
            Task {
                await self?.fetchLatestHeartRate()
            }
            
            completion()
        }
        
        // Habilita background delivery
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if let error = error {
                print("❌ HealthKit: Erro ao habilitar background delivery: \(error.localizedDescription)")
            } else if success {
                print("✅ HealthKit: Background delivery habilitado para heart rate")
            }
        }
        
        healthStore.execute(query)
        heartRateObservers.append(query)
        
        print("✅ HealthKit: Monitoramento de heart rate iniciado")
    }
    
    /// Para captura de heart rate
    func stopHeartRateMonitoring() {
        heartRateObservers.forEach { healthStore.stop($0) }
        heartRateObservers.removeAll()
        print("🛑 HealthKit: Monitoramento de heart rate parado")
    }
    
    /// Busca o heart rate mais recente
    private func fetchLatestHeartRate() async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-60), end: nil, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if let error = error {
                print("❌ HealthKit: Erro ao buscar heart rate: \(error.localizedDescription)")
                return
            }
            
            if let sample = samples?.first as? HKQuantitySample {
                let heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                print("💓 HealthKit: Heart rate atual: \(Int(heartRate)) BPM")
                
                // ✅ NOVO: Enviar para Publisher
                self.heartRateSubject.send(heartRate)
                
                // ✅ NOVO: Enviar para WatchSessionManager se disponível
                if let watchSessionManager = self.watchSessionManager {
                    Task {
                        await watchSessionManager.updateHealthData(heartRate: Int(heartRate), calories: nil)
                    }
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Calories Monitoring
    
    /// Inicia captura de calorias em tempo real
    func startCaloriesMonitoring() async throws {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitManagerError.invalidData
        }
        
        // Para observadores existentes
        stopCaloriesMonitoring()
        
        // Cria novo observador
        let query = HKObserverQuery(sampleType: caloriesType, predicate: nil) { [weak self] query, completion, error in
            if let error = error {
                print("❌ HealthKit: Erro no monitoramento de calorias: \(error.localizedDescription)")
                completion()
                return
            }
            
            // Busca dados mais recentes
            Task {
                await self?.fetchLatestCalories()
            }
            
            completion()
        }
        
        // Habilita background delivery
        healthStore.enableBackgroundDelivery(for: caloriesType, frequency: .immediate) { success, error in
            if let error = error {
                print("❌ HealthKit: Erro ao habilitar background delivery: \(error.localizedDescription)")
            } else if success {
                print("✅ HealthKit: Background delivery habilitado para calorias")
            }
        }
        
        healthStore.execute(query)
        caloriesObservers.append(query)
        
        print("✅ HealthKit: Monitoramento de calorias iniciado")
    }
    
    /// Para captura de calorias
    func stopCaloriesMonitoring() {
        caloriesObservers.forEach { healthStore.stop($0) }
        caloriesObservers.removeAll()
        print("🛑 HealthKit: Monitoramento de calorias parado")
    }
    
    /// Busca as calorias mais recentes
    private func fetchLatestCalories() async {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-60), end: nil, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: caloriesType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if let error = error {
                print("❌ HealthKit: Erro ao buscar calorias: \(error.localizedDescription)")
                return
            }
            
            if let sample = samples?.first as? HKQuantitySample {
                let calories = sample.quantity.doubleValue(for: .kilocalorie())
                print("🔥 HealthKit: Calorias atuais: \(Int(calories)) kcal")
                
                // ✅ NOVO: Enviar para Publisher
                self.caloriesSubject.send(calories)
                
                // ✅ NOVO: Enviar para WatchSessionManager se disponível
                if let watchSessionManager = self.watchSessionManager {
                    Task {
                        await watchSessionManager.updateHealthData(heartRate: nil, calories: calories)
                    }
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Data Fetching
    
    /// Obtém dados de heart rate para um período específico
    func fetchHeartRateData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitManagerError.invalidData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao buscar heart rate: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.fetchFailed(error))
                    return
                }
                
                let heartRateSamples = samples as? [HKQuantitySample] ?? []
                print("✅ HealthKit: Buscados \(heartRateSamples.count) samples de heart rate")
                continuation.resume(returning: heartRateSamples)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Obtém dados de calorias para um período específico
    func fetchCaloriesData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitManagerError.invalidData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            
            let query = HKSampleQuery(sampleType: caloriesType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao buscar calorias: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.fetchFailed(error))
                    return
                }
                
                let caloriesSamples = samples as? [HKQuantitySample] ?? []
                print("✅ HealthKit: Buscados \(caloriesSamples.count) samples de calorias")
                continuation.resume(returning: caloriesSamples)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Data Saving
    
    /// Salva dados de heart rate no HealthKit
    func saveHeartRateData(_ heartRate: Double, date: Date) async throws {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitManagerError.invalidData
        }
        
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: heartRate)
        let sample = HKQuantitySample(type: heartRateType, quantity: quantity, start: date, end: date)
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.save(sample) { success, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao salvar heart rate: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.saveFailed(error))
                    return
                }
                
                if success {
                    print("✅ HealthKit: Heart rate salvo: \(Int(heartRate)) BPM")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitManagerError.saveFailed(NSError(domain: "HealthKit", code: -1, userInfo: nil)))
                }
            }
        }
    }
    
    /// Salva dados de calorias no HealthKit
    func saveCaloriesData(_ calories: Double, date: Date) async throws {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitManagerError.invalidData
        }
        
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: caloriesType, quantity: quantity, start: date, end: date)
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.save(sample) { success, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao salvar calorias: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.saveFailed(error))
                    return
                }
                
                if success {
                    print("✅ HealthKit: Calorias salvas: \(Int(calories)) kcal")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitManagerError.saveFailed(NSError(domain: "HealthKit", code: -1, userInfo: nil)))
                }
            }
        }
    }
    
    // MARK: - Workout Sessions
    
    /// Cria uma sessão de workout no HealthKit
    func startWorkoutSession(workoutType: HKWorkoutActivityType, startDate: Date) async throws -> HKWorkoutSession {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutType
        configuration.locationType = .indoor
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                session.startActivity(with: startDate)
                
                self.activeWorkoutSession = session
                print("✅ HealthKit: Sessão de workout iniciada")
                continuation.resume(returning: session)
            } catch {
                print("❌ HealthKit: Erro ao iniciar sessão: \(error.localizedDescription)")
                continuation.resume(throwing: HealthKitManagerError.sessionError(error))
            }
        }
    }
    
    /// Finaliza uma sessão de workout
    func endWorkoutSession(_ session: HKWorkoutSession, endDate: Date) async throws -> HKWorkout {
        return try await withCheckedThrowingContinuation { continuation in
            session.end()
            
            session.endActivity(with: endDate)
            
            // Busca o workout finalizado
            let predicate = HKQuery.predicateForWorkouts(with: session.workoutConfiguration.activityType)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao buscar workout: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.sessionError(error))
                    return
                }
                
                if let workout = samples?.first as? HKWorkout {
                    self.activeWorkoutSession = nil
                    print("✅ HealthKit: Sessão de workout finalizada")
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: HealthKitManagerError.sessionError(NSError(domain: "HealthKit", code: -1, userInfo: nil)))
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Statistics
    
    /// Obtém estatísticas de workout para um período
    func fetchWorkoutStatistics(from startDate: Date, to endDate: Date) async throws -> HKStatisticsCollection {
        guard isAuthorized else {
            throw HealthKitManagerError.notAuthorized
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitManagerError.invalidData
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let interval = DateComponents(minute: 1)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage, anchorDate: startDate, intervalComponents: interval)
            
            query.initialResultsHandler = { _, statisticsCollection, error in
                if let error = error {
                    print("❌ HealthKit: Erro ao buscar estatísticas: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitManagerError.fetchFailed(error))
                    return
                }
                
                if let statisticsCollection = statisticsCollection {
                    print("✅ HealthKit: Estatísticas obtidas")
                    continuation.resume(returning: statisticsCollection)
                } else {
                    continuation.resume(throwing: HealthKitManagerError.fetchFailed(NSError(domain: "HealthKit", code: -1, userInfo: nil)))
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Cleanup
    
    /// Limpa recursos e para monitoramento
    func cleanup() {
        stopHeartRateMonitoring()
        stopCaloriesMonitoring()
        
        if let session = activeWorkoutSession {
            session.end()
            activeWorkoutSession = nil
        }
        
        print("🧹 HealthKit: Recursos limpos")
    }
}

// MARK: - Mock Implementation

/// Implementação mock do HealthKitManager para testes e previews
class MockHealthKitManager: HealthKitManagerProtocol {
    
    var isHealthKitAvailable: Bool = true
    var isAuthorized: Bool = true
    var authorizationStatusPublisher: AnyPublisher<Bool, Never> = Just(true).eraseToAnyPublisher()
    
    var shouldThrowError = false
    var mockHeartRate: Double = 75.0
    var mockCalories: Double = 150.0
    
    func requestAuthorization() async throws -> Bool {
        if shouldThrowError {
            throw HealthKitManagerError.authorizationDenied
        }
        return true
    }
    
    func startHeartRateMonitoring() async throws {
        if shouldThrowError {
            throw HealthKitManagerError.monitoringError(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        print("✅ Mock HealthKit: Monitoramento de heart rate iniciado")
    }
    
    func stopHeartRateMonitoring() {
        print("🛑 Mock HealthKit: Monitoramento de heart rate parado")
    }
    
    func startCaloriesMonitoring() async throws {
        if shouldThrowError {
            throw HealthKitManagerError.monitoringError(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        print("✅ Mock HealthKit: Monitoramento de calorias iniciado")
    }
    
    func stopCaloriesMonitoring() {
        print("🛑 Mock HealthKit: Monitoramento de calorias parado")
    }
    
    func fetchHeartRateData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        if shouldThrowError {
            throw HealthKitManagerError.fetchFailed(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        return []
    }
    
    func fetchCaloriesData(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        if shouldThrowError {
            throw HealthKitManagerError.fetchFailed(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        return []
    }
    
    func saveHeartRateData(_ heartRate: Double, date: Date) async throws {
        if shouldThrowError {
            throw HealthKitManagerError.saveFailed(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        print("✅ Mock HealthKit: Heart rate salvo: \(Int(heartRate)) BPM")
    }
    
    func saveCaloriesData(_ calories: Double, date: Date) async throws {
        if shouldThrowError {
            throw HealthKitManagerError.saveFailed(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        print("✅ Mock HealthKit: Calorias salvas: \(Int(calories)) kcal")
    }
    
    func startWorkoutSession(workoutType: HKWorkoutActivityType, startDate: Date) async throws -> HKWorkoutSession {
        if shouldThrowError {
            throw HealthKitManagerError.sessionError(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        // Retorna uma sessão mock (não funcional, apenas para testes)
        fatalError("Mock workout session not implemented")
    }
    
    func endWorkoutSession(_ session: HKWorkoutSession, endDate: Date) async throws -> HKWorkout {
        if shouldThrowError {
            throw HealthKitManagerError.sessionError(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        // Retorna um workout mock (não funcional, apenas para testes)
        fatalError("Mock workout not implemented")
    }
    
    func fetchWorkoutStatistics(from startDate: Date, to endDate: Date) async throws -> HKStatisticsCollection {
        if shouldThrowError {
            throw HealthKitManagerError.fetchFailed(NSError(domain: "Mock", code: -1, userInfo: nil))
        }
        // Retorna estatísticas mock (não funcional, apenas para testes)
        fatalError("Mock statistics not implemented")
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let heartRateUpdated = Notification.Name("heartRateUpdated")
    static let caloriesUpdated = Notification.Name("caloriesUpdated")
    static let healthKitAuthorizationChanged = Notification.Name("healthKitAuthorizationChanged")
} 