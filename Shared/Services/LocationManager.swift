//
//  LocationManager.swift
//  Fitter V2
//
//  🗺️ LOCATION MANAGER - CLEAN ARCHITECTURE COM TRATAMENTO DE PERMISSÕES
//  
//  🎯 RESPONSABILIDADES:
//  • Solicitar permissão de localização de forma transparente
//  • Capturar localização durante início de treinos (opcional)
//  • Funcionar corretamente quando usuário nega permissão
//  • Integrar com CDCurrentSession e CDWorkoutHistory
//  • Seguir diretrizes de privacidade da Apple
//  
//  🔒 PRIVACIDADE E UX:
//  • Permissão é completamente opcional
//  • App funciona normalmente sem localização
//  • Explicação clara do uso da localização
//  • Não bloqueia fluxo de treino
//  
//  🏗️ ARQUITETURA:
//  • Protocol para testabilidade e DI
//  • Publishers para estado reativo
//  • Async/await para operações não-bloqueantes
//  • Error handling robusto
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Location Manager Protocol

/// Protocol para gerenciamento de localização
/// Permite injeção de dependências e testabilidade
protocol LocationManagerProtocol: ObservableObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var isLocationAuthorized: Bool { get }
    var currentLocation: CLLocation? { get }
    var lastError: Error? { get }
    
    // Publishers para estado reativo
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    var locationPublisher: AnyPublisher<CLLocation?, Never> { get }
    
    func requestPermission() async -> Bool
    func requestSingleLocation() async -> CLLocation?
    func startMonitoring()
    func stopMonitoring()
}

// MARK: - Location Manager Errors

enum LocationManagerError: LocalizedError {
    case permissionDenied
    case locationNotAvailable
    case timeout
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permissão de localização negada pelo usuário"
        case .locationNotAvailable:
            return "Localização não disponível no momento"
        case .timeout:
            return "Timeout ao obter localização"
        case .unknownError(let error):
            return "Erro de localização: \(error.localizedDescription)"
        }
    }
}

// MARK: - Location Manager Implementation

/// Manager dedicado para captura de localização durante treinos
/// 
/// **Filosofia de Design:**
/// - Localização é OPCIONAL e não bloqueia funcionalidades
/// - Permissão solicitada de forma transparente e educativa
/// - App funciona perfeitamente sem localização
/// - Dados de localização enriquecem a experiência quando disponíveis
/// 
/// **Integração:**
/// - Usado pelo StartWorkoutUseCase para capturar localização no início do treino
/// - Dados salvos em CDCurrentSession e migrados para CDWorkoutHistory
/// - Publishers permitem UI reativa baseada no status de permissão
final class LocationManager: NSObject, LocationManagerProtocol {
    
    // MARK: - Properties
    
    /// Core Location manager
    private let locationManager = CLLocationManager()
    
    /// Status atual de autorização
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// Localização atual capturada
    @Published private(set) var currentLocation: CLLocation?
    
    /// Último erro ocorrido
    @Published private(set) var lastError: Error?
    
    /// Cancellables para publishers
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer para timeout de localização
    private var locationTimeout: Timer?
    
    /// Continuation para operações async
    private var locationContinuation: CheckedContinuation<CLLocation?, Error>?
    
    // MARK: - Computed Properties
    
    /// Verifica se localização está autorizada
    var isLocationAuthorized: Bool {
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    /// Publisher para status de autorização
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }
    
    /// Publisher para localização
    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        $currentLocation.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
        updateAuthorizationStatus()
    }
    
    // MARK: - Setup
    
    /// Configura o location manager
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10.0 // Atualizar a cada 10 metros
        
        print("📍 [LocationManager] Configurado com precisão de 10 metros")
    }
    
    /// Atualiza status de autorização inicial
    private func updateAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
        print("📍 [LocationManager] Status inicial: \(authorizationStatusDescription)")
    }
    
    // MARK: - Permission Management
    
    /// Solicita permissão de localização ao usuário
    /// 
    /// **Fluxo:**
    /// 1. Verifica se já está autorizado
    /// 2. Solicita permissão quando em uso (não sempre)
    /// 3. Aguarda resposta do usuário via delegate
    /// 4. Retorna resultado sem bloquear o app
    /// 
    /// - Returns: True se autorizado, false caso contrário
    func requestPermission() async -> Bool {
        // Já autorizado
        if isLocationAuthorized {
            print("✅ [LocationManager] Localização já autorizada")
            return true
        }
        
        // Negado permanentemente
        if authorizationStatus == .denied {
            print("❌ [LocationManager] Localização negada permanentemente")
            lastError = LocationManagerError.permissionDenied
            return false
        }
        
        // Solicitar permissão
        print("🔄 [LocationManager] Solicitando permissão de localização...")
        
        return await withCheckedContinuation { continuation in
            // Configurar observador para mudança de status
            let cancellable = $authorizationStatus
                .dropFirst() // Ignora valor atual
                .sink { status in
                    switch status {
                    case .authorizedWhenInUse, .authorizedAlways:
                        print("✅ [LocationManager] Permissão concedida")
                        continuation.resume(returning: true)
                    case .denied, .restricted:
                        print("❌ [LocationManager] Permissão negada")
                        self.lastError = LocationManagerError.permissionDenied
                        continuation.resume(returning: false)
                    default:
                        break
                    }
                }
            
            // Armazenar cancellable temporariamente
            cancellables.insert(cancellable)
            
            // Solicitar permissão
            locationManager.requestWhenInUseAuthorization()
            
            // Timeout após 10 segundos
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                cancellable.cancel()
                if !self.isLocationAuthorized {
                    print("⏰ [LocationManager] Timeout na solicitação de permissão")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Location Capture
    
    /// Solicita uma única localização (para início de treino)
    /// 
    /// **Uso Típico:**
    /// - Chamado pelo StartWorkoutUseCase no início do treino
    /// - Não bloqueia o treino se falhar
    /// - Timeout de 15 segundos para não prejudicar UX
    /// 
    /// - Returns: CLLocation se obtida, nil se falhar ou não autorizado
    func requestSingleLocation() async -> CLLocation? {
        // Verificar autorização
        guard isLocationAuthorized else {
            print("⚠️ [LocationManager] Localização não autorizada - continuando sem localização")
            return nil
        }
        
        // Verificar disponibilidade
        guard CLLocationManager.locationServicesEnabled() else {
            print("⚠️ [LocationManager] Serviços de localização desabilitados")
            lastError = LocationManagerError.locationNotAvailable
            return nil
        }
        
        print("🔄 [LocationManager] Solicitando localização única...")
        
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            
            // Configurar timeout de 15 segundos
            locationTimeout = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
                print("⏰ [LocationManager] Timeout ao obter localização")
                self.lastError = LocationManagerError.timeout
                continuation.resume(returning: nil)
                self.locationContinuation = nil
            }
            
            // Solicitar localização
            locationManager.requestLocation()
        }
    }
    
    /// Inicia monitoramento contínuo de localização
    /// 
    /// **Nota:** Usado apenas se necessário para funcionalidades avançadas
    /// Por padrão, o app usa apenas localização única no início do treino
    func startMonitoring() {
        guard isLocationAuthorized else {
            print("⚠️ [LocationManager] Não é possível monitorar - permissão não concedida")
            return
        }
        
        print("🔄 [LocationManager] Iniciando monitoramento contínuo")
        locationManager.startUpdatingLocation()
    }
    
    /// Para monitoramento contínuo
    func stopMonitoring() {
        print("⏹️ [LocationManager] Parando monitoramento")
        locationManager.stopUpdatingLocation()
        locationTimeout?.invalidate()
        locationTimeout = nil
    }
    
    // MARK: - Utility
    
    /// Descrição legível do status de autorização
    private var authorizationStatusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Não determinado"
        case .restricted: return "Restrito"
        case .denied: return "Negado"
        case .authorizedAlways: return "Autorizado sempre"
        case .authorizedWhenInUse: return "Autorizado quando em uso"
        @unknown default: return "Desconhecido"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    /// Resposta à mudança de autorização
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 [LocationManager] Status alterado para: \(authorizationStatusDescription)")
        authorizationStatus = status
        
        // Limpar erro se autorizado
        if isLocationAuthorized {
            lastError = nil
        }
    }
    
    /// Localização obtida com sucesso
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        print("✅ [LocationManager] Localização obtida: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("📏 [LocationManager] Precisão: ±\(location.horizontalAccuracy)m")
        
        currentLocation = location
        lastError = nil
        
        // Resolver continuation se existir
        if let continuation = locationContinuation {
            locationTimeout?.invalidate()
            locationTimeout = nil
            continuation.resume(returning: location)
            locationContinuation = nil
        }
        
        // Parar updates para economizar bateria (single location)
        locationManager.stopUpdatingLocation()
    }
    
    /// Erro ao obter localização
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [LocationManager] Erro: \(error.localizedDescription)")
        
        let locationError: LocationManagerError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .permissionDenied
            case .locationUnknown, .network:
                locationError = .locationNotAvailable
            default:
                locationError = .unknownError(error)
            }
        } else {
            locationError = .unknownError(error)
        }
        
        lastError = locationError
        
        // Resolver continuation com nil se existir
        if let continuation = locationContinuation {
            locationTimeout?.invalidate()
            locationTimeout = nil
            continuation.resume(returning: nil)
            locationContinuation = nil
        }
    }
} 