//
//  HomeView.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo preto
                Color.black
                    .ignoresSafeArea()
                
                VStack {
                    HStack {
                        Text("Home")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    HStack(spacing: 40) {
                        Button(action: {
                            Task {
                                await connectivity.decrementCounter()
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                        
                        Text("\(connectivity.counter)")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                        
                        Button(action: {
                            Task {
                                await connectivity.incrementCounter()
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    HomeView()
}
