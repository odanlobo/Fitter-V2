import SwiftUI

struct PendingLoginView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Faça login no app Fitter em seu dispositivo iOS para continuar...")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.black))
    }
} 

#Preview {
    PendingLoginView()
}
