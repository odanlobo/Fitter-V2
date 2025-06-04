//
//  BackButton.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 12/05/25.
//

import SwiftUI

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "arrow.backward")
                .imageScale(.large)
                .font(.system(size: 24))
                .fontWeight(.heavy)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        BackButton()
    }
}
