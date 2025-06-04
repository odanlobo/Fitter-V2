//
//  CreateButton.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 15/05/25.
//

import SwiftUI

struct CreateButton: View {
    var action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Criar Treino")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.white.opacity(0.12), radius: 12, x: 0, y: 6)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            CreateButton {
                print("Criar novo treino")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
