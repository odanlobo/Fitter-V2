//
//  WatchApp.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import HealthKit

@main
struct Fitter_V2_Watch_AppApp: App {
    @StateObject private var connectivity = ConnectivityManager.shared
    @StateObject private var dataManager = WatchDataManager.shared
    @StateObject private var motionManager = MotionManager.shared
    
    init() {
        // Solicitar autorização do HealthKit ao inicializar o Watch app
        requestHealthKitAuthorization()
    }
    
    var body: some Scene {
        WindowGroup {
            if connectivity.isAuthenticated {
                WatchView()
                    .environmentObject(dataManager)
                    .environmentObject(motionManager)
                    .environmentObject(connectivity)
            } else {
                PendingLoginView()
                    .environmentObject(dataManager)
                    .environmentObject(connectivity)
            }
        }
    }
    
    // MARK: - HealthKit Authorization
    
    private func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit não está disponível no Watch")
            return
        }
        
        let healthStore = HKHealthStore()
        
        // Tipos de dados que o Watch vai compartilhar
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        // Tipos de dados que o Watch vai ler
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            if let error = error {
                print("❌ Erro ao solicitar autorização do HealthKit no Watch: \(error.localizedDescription)")
            } else {
                print("✅ Autorização do HealthKit no Watch: \(success ? "concedida" : "negada")")
            }
        }
    }
}
