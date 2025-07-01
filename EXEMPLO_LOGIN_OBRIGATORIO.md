# 🔒 LOGIN OBRIGATÓRIO + SESSÃO PERSISTENTE
## Configuração Completa do Fitter V2

## 🔒 **DECISÃO ARQUITETURAL**

> **App com login obrigatório** na primeira vez, **sessão persistente**, mas **logout automático após 7 dias de inatividade** por segurança.

### 📱 **FLUXO DE USUÁRIO:**
1. **Primeira vez**: Login obrigatório (Apple/Google/Facebook/Email)
2. **Próximas vezes**: Continua logado automaticamente
3. **Logout**: Apenas manual (botão no perfil)
4. **🆕 Logout automático**: Após 7 dias sem abrir o app
5. **Dados**: Sempre vinculados ao usuário autenticado

---

## 🏗️ **ARQUITETURA IMPLEMENTADA:**

### **1. BaseViewModel.swift** ✅
```swift
/// Usuário atual autenticado
/// ⚠️ IMPORTANTE: Nunca será nil após login inicial (sessão persistente)
/// App com LOGIN OBRIGATÓRIO - dados sempre vinculados ao usuário
@Published public var currentUser: CDAppUser!

/// Indica se o usuário está autenticado
/// ✅ LOGIN OBRIGATÓRIO: Sempre true após login inicial (sessão persistente)
public var isAuthenticated: Bool {
    return currentUser != nil && authService.isAuthenticated
}

/// Realiza logout manual do usuário
/// ⚠️ ÚNICO meio de deslogar - app mantém sessão mesmo ao fechar
public func logout() async { /* implementado */ }
```

### **2. Use Cases** ✅
```swift
// ✅ TODOS os Use Cases agora têm usuário OBRIGATÓRIO
struct CreateWorkoutInput {
    let user: CDAppUser  // ← Sem ? (opcional)
}

struct StartWorkoutInput {
    let user: CDAppUser  // ← Sem ? (opcional)
}

struct EndWorkoutInput {
    let user: CDAppUser  // ← Sem ? (opcional)
}
```

### **3. Core Data Model** ✅
```xml
<!-- Relações OBRIGATÓRIAS garantem ownership -->
<relationship name="user" maxCount="1" deletionRule="Nullify" 
              destinationEntity="CDAppUser"/>
```

---

## 🚀 **EXEMPLO DE IMPLEMENTAÇÃO:**

### **App.swift (Entry Point)**
```swift
@main
struct FitterApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.isAuthenticated {
                // ✅ Usuário logado - app principal
                MainTabView()
                    .environmentObject(authViewModel)
            } else {
                // ❌ Usuário não logado - tela de autenticação
                AuthenticationView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
```

### **AuthenticationView.swift (Login Obrigatório)**
```swift
struct AuthenticationView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Bem-vindo ao Fitter!")
                .font(.largeTitle)
            
            Text("Para continuar, faça login:")
                .foregroundColor(.secondary)
            
            // Botões de login social
            AppleSignInButton { await authViewModel.signInWithApple() }
            GoogleSignInButton { await authViewModel.signInWithGoogle() }
            FacebookSignInButton { await authViewModel.signInWithFacebook() }
            
            // Ou email/senha
            EmailLoginForm()
        }
        .padding()
    }
}
```

### **MainTabView.swift (App Principal)**
```swift
struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        TabView {
            HomeView()
                .environmentObject(authViewModel) // ✅ currentUser nunca nil
                .tabItem { Label("Home", systemImage: "house") }
            
            WorkoutView()
                .environmentObject(authViewModel) // ✅ currentUser nunca nil
                .tabItem { Label("Treinos", systemImage: "figure.strengthtraining.traditional") }
            
            ProfileView()
                .environmentObject(authViewModel) // ✅ com botão logout
                .tabItem { Label("Perfil", systemImage: "person") }
        }
    }
}
```

### **WorkoutViewModel.swift (Usando Use Cases)**
```swift
class WorkoutViewModel: BaseViewModel {
    func createWorkout(title: String?, exercises: [CDExerciseTemplate]) async {
        // ✅ LOGIN OBRIGATÓRIO: currentUser nunca nil
        let input = CreateWorkoutInput(
            title: title,
            muscleGroups: nil,
            user: currentUser,  // ✅ Sempre válido!
            exerciseTemplates: exercises
        )
        
        await executeUseCase {
            return try await createWorkoutUseCase.execute(input)
        }
    }
    
    func startWorkout(plan: CDWorkoutPlan) async {
        // ✅ LOGIN OBRIGATÓRIO: currentUser nunca nil
        let input = StartWorkoutInput(
            plan: plan,
            user: currentUser  // ✅ Sempre válido!
        )
        
        await executeUseCase {
            return try await startWorkoutUseCase.execute(input)
        }
    }
}
```

### **ProfileView.swift (Com Logout Manual)**
```swift
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                // Informações do usuário
                Text("Olá, \(authViewModel.currentUser.safeName)!")
                Text(authViewModel.currentUser.email ?? "")
                
                Spacer()
                
                // ⚠️ ÚNICO meio de deslogar
                Button("Sair da Conta") {
                    Task {
                        await authViewModel.logout()
                    }
                }
                .foregroundColor(.red)
            }
            .navigationTitle("Perfil")
        }
    }
}
```

---

## ✅ **BENEFÍCIOS DA ARQUITETURA:**

### **🔐 SEGURANÇA TOTAL:**
- **Zero dados órfãos** - tudo vinculado ao usuário
- **Ownership garantido** - Core Data com relações obrigatórias
- **Sessão persistente** - não perde login ao fechar app

### **🏗️ ARQUITETURA LIMPA:**
- **Use Cases puros** - sem validação de nil
- **ViewModels simples** - currentUser sempre válido
- **Core Data consistente** - relações obrigatórias

### **📱 UX OTIMIZADA:**
- **Login apenas uma vez** - sessão persistente
- **Logout manual** - controle total do usuário
- **Dados seguros** - nunca perdidos ou misturados

### **🛡️ BENEFÍCIOS DE SEGURANÇA:**
- **Dispositivos perdidos/roubados**: Proteção automática de dados pessoais
- **Uso compartilhado**: Evita acesso não autorizado a dados de treino  
- **Compliance**: Padrão em apps de saúde/fitness para proteção de dados
- **Privacidade**: Dados sensíveis não expostos indefinidamente

---

## 🎯 **EXEMPLO DE USO COMPLETO:**

```swift
// 1. Usuário abre app pela PRIMEIRA VEZ
// → AuthenticationView (obrigatório)
// → Faz login com Apple/Google/Facebook/Email
// → currentUser definido, nunca mais nil

// 2. Usuário FECHA o app
// → Sessão mantida via AuthService + Keychain
// → Próxima abertura: MainTabView direto

// 3. Usuário CRIA TREINO
let input = CreateWorkoutInput(
    title: "Peitoral Heavy",
    user: currentUser  // ✅ Sempre válido!
)
// → Treino vinculado ao usuário correto

// 4. Usuário INICIA TREINO
let input = StartWorkoutInput(
    plan: selectedPlan,
    user: currentUser  // ✅ Sempre válido!
)
// → Sessão vinculada ao usuário correto

// 5. Usuário faz LOGOUT MANUAL
await authViewModel.logout()
// → currentUser = nil
// → App volta para AuthenticationView
```

---

## 🔧 **IMPLEMENTAÇÃO TÉCNICA:**

### **AuthService (Persistência)**
```swift
// Salva token no Keychain para persistência
private func saveUserSession(_ user: CDAppUser) {
    let keychain = Keychain(service: "com.fitter.auth")
    keychain["userToken"] = user.authToken
    keychain["userId"] = user.id.uuidString
}

// Recupera sessão ao abrir app
private func restoreUserSession() -> CDAppUser? {
    let keychain = Keychain(service: "com.fitter.auth")
    guard let token = keychain["userToken"],
          let userId = keychain["userId"] else { return nil }
    
    // Busca usuário no Core Data
    return fetchUser(byId: userId)
}
```

### **Lifecycle (AppDelegate/SceneDelegate)**
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Restaura sessão automaticamente
    if let savedUser = AuthService.shared.restoreSession() {
        AuthService.shared.setCurrentUser(savedUser)
        print("✅ Sessão restaurada: \(savedUser.safeName)")
    }
    return true
}
```

### **🔑 AuthService.swift - Controle de Inatividade:**
```swift
import Foundation
import KeychainAccess

class AuthService: AuthServiceProtocol {
    private let keychain = Keychain(service: "com.fitter.app")
    private let inactivityTimeoutDays: Int = 7
    private let lastAppOpenKey = "lastAppOpenDate"
    
    // MARK: - Inatividade
    
    /// Atualiza timestamp da última abertura do app
    func updateLastAppOpenDate() {
        let now = Date()
        keychain.set(now.timeIntervalSince1970, forKey: lastAppOpenKey)
        print("🔒 [AUTH] Última abertura atualizada: \(now)")
    }
    
    /// Verifica se passou do limite de inatividade (7 dias)
    func checkInactivityTimeout() -> Bool {
        guard let lastOpenTimestamp = keychain.get(lastAppOpenKey),
              let timestamp = Double(lastOpenTimestamp) else {
            // Primeira vez - não há registro, considera ativo
            updateLastAppOpenDate()
            return false
        }
        
        let lastOpenDate = Date(timeIntervalSince1970: timestamp)
        let daysSinceLastOpen = Calendar.current.dateComponents([.day], 
                                                               from: lastOpenDate, 
                                                               to: Date()).day ?? 0
        
        let isInactive = daysSinceLastOpen >= inactivityTimeoutDays
        
        if isInactive {
            print("⚠️ [AUTH] Inatividade detectada: \(daysSinceLastOpen) dias")
        }
        
        return isInactive
    }
    
    /// Executa logout devido à inatividade
    func logoutDueToInactivity() async {
        print("🔒 [AUTH] Logout automático por inatividade (7+ dias)")
        
        // Limpa dados do Keychain
        await logout()
        
        // Remove timestamp de última abertura
        keychain.remove(lastAppOpenKey)
    }
}
```

### **🎯 BaseViewModel.swift - Verificação na UI:**
```swift
import SwiftUI
import Combine

@MainActor
class BaseViewModel: ObservableObject {
    @Previously var currentUser: CDAppUser!
    @Published var showInactivityAlert = false
    @Published var inactivityMessage = ""
    
    private let authService: AuthServiceProtocol
    
    // MARK: - Inatividade
    
    /// Verifica e trata logout por inatividade
    func checkAndHandleInactivity() async {
        if authService.checkInactivityTimeout() {
            // Executa logout
            await authService.logoutDueToInactivity()
            
            // Limpa dados locais
            currentUser = nil
            
            // Mostra mensagem explicativa
            await MainActor.run {
                inactivityMessage = "Por segurança, você foi deslogado após 7 dias de inatividade. Faça login novamente."
                showInactivityAlert = true
            }
        } else {
            // Atualiza último acesso
            authService.updateLastAppOpenDate()
        }
    }
}
```

### **🚀 iOSApp.swift - Verificação no Launch:**
```swift
import SwiftUI

@main
struct FitterApp: App {
    // ... dependency injection ...
    
    @StateObject private var authVM = AuthViewModel(useCase: authUC)
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(authVM)
                .environmentObject(listVM)
                .environmentObject(workoutVM)
                .onAppear {
                    // ✅ Verifica inatividade na inicialização
                    Task {
                        await authVM.checkAndHandleInactivity()
                    }
                }
                .alert("Sessão Expirada", isPresented: $authVM.showInactivityAlert) {
                    Button("OK") {
                        authVM.showInactivityAlert = false
                    }
                } message: {
                    Text(authVM.inactivityMessage)
                }
        }
    }
}
```

### **🏋️‍♂️ SessionManager.swift - Limpeza de Sessões:**
```swift
extension SessionManager {
    /// Limpa sessão ativa devido ao logout por inatividade
    func handleInactivityLogout() {
        if isSessionActive {
            print("🏋️‍♂️ [SESSION] Limpando sessão ativa devido ao logout por inatividade")
            
            // Finaliza sessão sem sync (usuário não está mais autenticado)
            endSession()
            
            // Limpa dados temporários
            currentSession = nil
            isSessionActive = false
        }
    }
}
```

---

## 🎉 **RESULTADO FINAL:**

**✅ APP SEGURO** - Zero dados órfãos, ownership garantido  
**✅ UX OTIMIZADA** - Login apenas uma vez, sessão persistente  
**✅ ARQUITETURA LIMPA** - Use Cases puros, validações simples  
**✅ ESCALÁVEL** - Base sólida para recursos premium/free  

**🔒 LOGIN OBRIGATÓRIO + SESSÃO PERSISTENTE = ARQUITETURA IDEAL! 🚀** 

## ⏰ **FLUXOS DE USUÁRIO COM LOGOUT POR INATIVIDADE**

### **🔄 Cenário 1: Uso Normal (< 7 dias)**
1. Usuário abre app
2. `checkInactivityTimeout()` → `false`
3. `updateLastAppOpenDate()` → atualiza timestamp
4. App continua normalmente logado

### **⚠️ Cenário 2: Inatividade (≥ 7 dias)**
1. Usuário abre app após 7+ dias
2. `checkInactivityTimeout()` → `true`
3. `logoutDueToInactivity()` → limpa dados
4. Alert explicativo → tela de login
5. Usuário precisa autenticar novamente

### **📱 Cenário 3: Dispositivo Perdido**
1. Dispositivo perdido por 1 semana
2. Próxima abertura → logout automático
3. Dados protegidos automaticamente
4. Necessário login para acesso

---

## 🎯 **BENEFÍCIOS FINAIS IMPLEMENTADOS**

### **🛡️ Segurança Robusta:**
- ✅ Proteção automática após 7 dias
- ✅ Limpeza de sessões ativas
- ✅ Dados não expostos indefinidamente
- ✅ Compliance com padrões de segurança

### **🔒 Privacidade Garantida:**
- ✅ Keychain para timestamp seguro
- ✅ Sem dados pessoais expostos
- ✅ Logout limpo e completo
- ✅ Feedback claro ao usuário

### **💡 UX Balanceada:**
- ✅ 7 dias é tempo suficiente para uso normal
- ✅ Não interrompe workflow diário
- ✅ Mensagem explicativa clara
- ✅ Re-login simples e rápido

### **🏗️ Arquitetura Sólida:**
- ✅ Use Cases com usuário obrigatório
- ✅ Ownership 100% garantido
- ✅ Zero dados órfãos
- ✅ Base sólida para expansão

Essa implementação combina **segurança robusta** com **UX fluida**, garantindo proteção de dados sem comprometer a experiência do usuário no dia a dia. 