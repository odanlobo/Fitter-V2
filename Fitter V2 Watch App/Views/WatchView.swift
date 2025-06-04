//
//  WatchView.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import WatchConnectivity

struct WatchView: View {
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack {
                    HStack {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Text("Contador")
                            .foregroundColor(.gray)
                            .font(.caption)
                        
                        HStack(spacing: 20) {
                            Button(action: {
                                Task {
                                    await connectivity.decrementCounter()
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                            
                            Text("\(connectivity.counter)")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                            
                            Button(action: {
                                Task {
                                    await connectivity.incrementCounter()
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    WatchView()
}
