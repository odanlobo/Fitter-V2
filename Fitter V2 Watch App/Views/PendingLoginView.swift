//
//  PendingLoginView.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct PendingLoginView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @StateObject private var connectivity = ConnectivityManager.shared
    
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
                    Image(systemName: dataManager.isConnectedToPhone ? "iphone" : "iphone.slash")
                        .foregroundColor(dataManager.isConnectedToPhone ? .green : .red)
                    
                    Text(dataManager.isConnectedToPhone ? "Conectado" : "Desconectado")
                        .font(.caption2)
                        .foregroundColor(dataManager.isConnectedToPhone ? .green : .red)
                }
                .padding(.top)
            }
            .padding()
        }
    }
} 

