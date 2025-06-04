//
//  HistoryView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo preto
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Título centralizado
                    Text("Histórico")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                    
                    // Conteúdo aqui
                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    HistoryView()
}
