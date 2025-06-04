//
//  iOSApp.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import HealthKit
import WatchConnectivity
import CoreData
import FirebaseCore
import FacebookCore
import SwiftData

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

@main
struct iOSApp: App {
    // Gerenciador de conectividade global
    @StateObject private var connectivityManager = ConnectivityManager.shared
    @StateObject private var authViewModel = LoginViewModel()
    
    init() {
        // register app delegate for Firebase setup
        @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
        // Solicitar autorização do HealthKit assim que o app iniciar
        requestHealthKitAuthorization()
    }
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.isAuthenticated {
                MainTabView()
                    .environmentObject(authViewModel)
            } else {
                LoginView()
                    .environmentObject(authViewModel)
            }
        }
        .modelContainer(PersistenceController.shared.container)
    }
    
    private func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit não está disponível neste dispositivo")
            return
        }
        
        let healthStore = HKHealthStore()
        
        // Definir os tipos que queremos ler e compartilhar
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            if let error = error {
                print("Erro ao solicitar autorização do HealthKit: \(error.localizedDescription)")
            } else {
                print("Autorização do HealthKit: \(success ? "concedida" : "negada")")
            }
        }
    }
}
