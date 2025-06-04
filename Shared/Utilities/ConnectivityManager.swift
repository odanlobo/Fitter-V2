//
//  ConnectivityManager.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import Foundation
import WatchConnectivity

@MainActor
class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()
    
    @Published var lastReceived: String?
    @Published var isReachable = false
    @Published var counter: Int = 0
    @Published var isAuthenticated: Bool = false
    
    private let session: WCSession
    
    #if os(iOS)
    private let authService = AuthService.shared
    #endif
    
    private override init() {
        self.session = WCSession.default
        super.init()
        
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
        
        #if os(iOS)
        // No iOS, inicializa o estado de autenticação
        self.isAuthenticated = authService.isAuthenticated
        #endif
    }
    
    // Função para enviar status de autenticação para o Watch
    #if os(iOS)
    func sendAuthStatusToWatch() {
        guard session.activationState == .activated else { return }
        
        Task { @MainActor in
            isAuthenticated = authService.isAuthenticated
            let message = ["isAuthenticated": isAuthenticated]
            session.sendMessage(message, replyHandler: nil) { error in
                print("Erro ao enviar status de autenticação: \(error.localizedDescription)")
            }
        }
    }
    #endif
    
    func incrementCounter() async {
        counter += 1
        await syncCounter()
    }
    
    func decrementCounter() async {
        counter -= 1
        await syncCounter()
    }
    
    private func syncCounter() async {
        guard session.activationState == .activated else { return }
        
        session.sendMessage(["counter": counter], replyHandler: { _ in }, errorHandler: { error in
            print("Erro ao sincronizar contador: \(error.localizedDescription)")
        })
    }
    
    func sendPing() async {
        guard session.activationState == .activated else {
            print("Sessão não está ativada")
            return
        }
        
        session.sendMessage(["ping": "ping"], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.lastReceived = reply["pong"] as? String
            }
        }, errorHandler: { error in
            print("Erro ao enviar ping: \(error.localizedDescription)")
        })
    }
    
    #if os(iOS)
    func handleLogoutRequest() async {
        do {
            try authService.signOut()
            await sendAuthStatusToWatch()
        } catch {
            print("Erro ao fazer logout: \(error.localizedDescription)")
        }
    }
    #endif
}

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("Erro na ativação do WCSession: \(error.localizedDescription)")
                return
            }
            
            self.isReachable = session.isReachable
            
            #if os(iOS)
            // Envia o status de autenticação assim que a sessão é ativada
            if activationState == .activated {
                self.sendAuthStatusToWatch()
            }
            #endif
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let ping = message["ping"] as? String {
                self.lastReceived = ping
                session.sendMessage(["pong": "pong"], replyHandler: nil) { error in
                    print("Erro ao enviar pong: \(error.localizedDescription)")
                }
            } else if let counter = message["counter"] as? Int {
                self.counter = counter
            } else if let isAuthenticated = message["isAuthenticated"] as? Bool {
                self.isAuthenticated = isAuthenticated
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if let ping = message["ping"] as? String {
                self.lastReceived = ping
                replyHandler(["pong": "pong"])
            } else if let counter = message["counter"] as? Int {
                self.counter = counter
                replyHandler([:])
            } else if message["request"] as? String == "authStatus" {
                #if os(iOS)
                replyHandler(["isAuthenticated": authService.isAuthenticated])
                #else
                replyHandler(["isAuthenticated": isAuthenticated])
                #endif
            } else if message["request"] as? String == "logout" {
                #if os(iOS)
                Task {
                    await handleLogoutRequest()
                }
                replyHandler(["success": true])
                #else
                replyHandler(["error": "Operação não permitida no Watch"])
                #endif
            }
        }
    }
    
    // Necessário para iOS
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
        }
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
        }
        session.activate()
    }
    #endif
}
