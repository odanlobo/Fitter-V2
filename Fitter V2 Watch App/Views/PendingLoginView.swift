//
//  PendingLoginView.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct PendingLoginView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var connectivity: ConnectivityManager
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                
                Text("Faça login no iPhone")
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Abra o app no seu iPhone e faça login para sincronizar os dados.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                // Status de conexão
                HStack(spacing: 8) {
                    Image(systemName: sessionManager.isConnectedToPhone ? "iphone" : "iphone.slash")
                        .foregroundColor(sessionManager.isConnectedToPhone ? .green : .red)
                    
                    Text(sessionManager.isConnectedToPhone ? "Conectado" : "Desconectado")
                        .font(.caption2)
                        .foregroundColor(sessionManager.isConnectedToPhone ? .green : .red)
                }
                .padding(.top)
            }
            .padding()
        }
    }
}

// MARK: - Preview
struct PendingLoginView_Previews: PreviewProvider {
    static var previews: some View {
        PendingLoginView()
            .environmentObject(WatchSessionManager())
            .environmentObject(ConnectivityManager.shared)
    }
} 

