# ESTRUTURA DO PROJETO FITTER V2

Este documento descreve a organização completa do projeto Fitter V2, incluindo todas as pastas, subpastas e arquivos.

## 📱 Fitter V2/ (App iOS Principal)

### 🎨 Assets.xcassets/
Recursos visuais do aplicativo iOS:
- **AccentColor.colorset/** - Definição da cor de destaque
  - `Contents.json`
- **AppIcon.appiconset/** - Ícones do aplicativo
  - `Contents.json`
  - `icon 1.png`, `icon 2.png`, `icon.png`
- **Icon Apple.imageset/** - Ícone para login com Apple
  - `Contents.json`
  - `Icon Apple 1.png`, `Icon Apple 2.png`, `Icon Apple.png`
- **Icon FB.imageset/** - Ícone para login com Facebook
  - `Contents.json`
  - `Icon FB 1.png`, `Icon FB 2.png`, `Icon FB.png`
- **Icon Google.imageset/** - Ícone para login com Google
  - `Contents.json`
  - `Icon Google 1.png`, `Icon Google 2.png`, `Icon Google.png`
- **logo.imageset/** - Logo do aplicativo
  - `Contents.json`
  - `logo  1.png`, `logo  2.png`, `logo .png`

### 🧩 Components/
Componentes reutilizáveis da interface:
- `BackButton.swift` - Botão de voltar
- `CreateButton.swift` - Botão de criação
- `ExerciseCard.swift` - Card de exercício
- `ImportWorkoutCard.swift` - Card para importar treino
- `UploadButton.swift` - Botão de upload
- `WorkoutPlanCard.swift` - Card de plano de treino

### 📋 Models/
Modelos de dados específicos do iOS:
- `FirebaseExercise.swift` - Modelo de exercício do Firebase

### 🔐 Services/
Serviços específicos do iOS:
- **Auth/** - Serviços de autenticação
  - `AppleSignInService.swift` - Implementação do login Apple
  - `AppleSignInServiceProtocol.swift` - Protocolo do login Apple
  - `BiometricAuthService.swift` - Implementação da autenticação biométrica
  - `BiometricAuthServiceProtocol.swift` - Protocolo da autenticação biométrica
  - `FacebookSignInService.swift` - Implementação do login Facebook
  - `FacebookSignInServiceProtocol.swift` - Protocolo do login Facebook
  - `GoogleSignInService.swift` - Implementação do login Google
  - `GoogleSignInServiceProtocol.swift` - Protocolo do login Google
- `AuthService.swift` - Serviço principal de autenticação

### 🔄 Sync/
Sincronização específica do iOS:
- `CloudSyncManager.swift` - Gerenciador de sincronização com nuvem
- `PhoneSessionManager.swift` - Gerenciador de sessão do telefone

### 🖼️ Views/
Telas da interface do usuário:
- **Auth/** - Telas de autenticação
  - `CreateAccountView.swift` - Tela de criação de conta
  - `LoginView.swift` - Tela de login
- **History/** - Telas de histórico
  - `HistoryView.swift` - Tela de histórico de treinos
- **Home/** - Tela inicial
  - `HomeView.swift` - Tela principal do app
- **MainTab/** - Navegação principal
  - `MainTabView.swift` - Controlador de abas principais
- **Profile/** - Telas de perfil
  - `ProfileView.swift` - Tela de perfil do usuário
- **Workout/** - Telas de treino
  - `ListExerciseView.swift` - Lista de exercícios
  - `WorkoutEditorView.swift` - Editor de treino
  - `WorkoutView.swift` - Tela de treino ativo
- `PaywallView.swift` - Tela de assinatura/paywall

### 🎛️ ViewsModel/
ViewModels para gerenciamento de estado:
- `BaseViewModel.swift` - ViewModel base
- `CreateAccountViewModel.swift` - ViewModel para criação de conta
- `ListExerciseViewModel.swift` - ViewModel para lista de exercícios
- `LoginViewModel.swift` - ViewModel para login
- `WorkoutViewModel.swift` - ViewModel para treinos

### 📄 Arquivos de Configuração
- `Fitter V2.entitlements` - Permissões do iOS
- `GoogleService-Info.plist` - Configuração do Google Services
- `iOSApp.swift` - Arquivo principal do app iOS

## ⌚ Fitter V2 Watch App/ (App watchOS)

### 🎨 Assets.xcassets/
Recursos visuais do Apple Watch:
- **AccentColor.colorset/** - Cor de destaque
- **AppIcon.appiconset/** - Ícone do app Watch
- **logo.imageset/** - Logo para o Watch

### 📁 Data/
Dados específicos do Watch (vazio atualmente)

### 🎛️ Managers/
Gerenciadores específicos do Watch:
- `MotionManager.swift` - Gerenciador de movimento/sensores
- `WatchSessionManager.swift` - Gerenciador de sessão do Watch
- `WorkoutPhaseManager.swift` - Gerenciador de fases do treino

### 📱 Views/
Telas do Apple Watch:
- `PendingLoginView.swift` - Tela de login pendente
- `WatchView.swift` - Tela principal do Watch

### 📄 Arquivos de Configuração
- `Fitter V2 Watch App.entitlements` - Permissões do watchOS
- `WatchApp.swift` - Arquivo principal do app Watch

## 🔗 Shared/ (Código Compartilhado)

### 💾 CoreData 2/
Persistência de dados:
- `CoreDataAdapter.swift` - Adaptador do Core Data
- `CoreDataModels.swift` - Modelos do Core Data
- **FitterModel.xcdatamodeld/** - Modelo de dados
  - **FitterModel.xcdatamodel/** - Arquivo do modelo
    - `contents` - Definições das entidades

### 🎛️ Manager/
Gerenciadores compartilhados:
- `ConnectivityManager.swift` - Gerenciador de conectividade
- `SessionManager.swift` - Gerenciador de sessão

### 📋 Models/
Modelos de dados compartilhados:
- `MuscleGroup.swift` - Modelo de grupo muscular
- `SensorData.swift` - Dados de sensores
- `SubscriptionType.swift` - Tipos de assinatura

### 🌐 Network/
Monitoramento de rede:
- `NetworkMonitor.swift` - Monitor de conexão de rede

### 💾 Persistence/
Controladores de persistência:
- `PersistenceController.swift` - Controlador principal de persistência

### 🔗 Protocols/
Protocolos compartilhados:
- `ExerciseDisplayable.swift` - Protocolo para exibição de exercícios

### 📦 Repository/
Repositórios de dados:
- `FirestoreExerciseRepository.swift` - Repositório de exercícios no Firestore

### ⚙️ Services/
Serviços compartilhados:
- `CoreDataService.swift` - Serviço do Core Data
- `HealthKitManager.swift` - Gerenciador do HealthKit
- `ImportWorkoutService.swift` - Serviço de importação de treinos
- `RevenueCatService.swift` - Serviço de assinaturas (RevenueCat)
- `SubscriptionManager.swift` - Gerenciador de assinaturas
- `TimerService.swift` - Serviço de cronômetro
- `WorkoutDataService.swift` - Serviço de dados de treino

### 🔄 Sync/
Sincronização:
- `CloudSyncStatus.swift` - Status de sincronização com nuvem

### 🎯 UseCases/
Casos de uso (Clean Architecture):
- `AuthUseCase.swift` - Casos de uso de autenticação
- `CreateWorkoutUseCase.swift` - Criar treino
- `DeleteWorkoutUseCase.swift` - Deletar treino
- `EndExerciseUseCase.swift` - Finalizar exercício
- `EndSetUseCase.swift` - Finalizar série
- `EndWorkoutUseCase.swift` - Finalizar treino
- `FetchFBExercisesUseCase.swift` - Buscar exercícios do Firebase
- `FetchWorkoutUseCase.swift` - Buscar treino
- `ImportWorkoutUseCase.swift` - Importar treino
- `ReorderExerciseUseCase.swift` - Reordenar exercícios
- `ReorderWorkoutUseCase.swift` - Reordenar treinos
- `StartExerciseUseCase.swift` - Iniciar exercício
- `StartSetUseCase.swift` - Iniciar série
- `StartWorkoutUseCase.swift` - Iniciar treino
- `SyncWorkoutUseCase.swift` - Sincronizar treino
- `UpdateWorkoutUseCase.swift` - Atualizar treino


## 📄 Arquivos de Configuração do Projeto
- `Fitter V2.entitlements` - Permissões principais
- `Fitter-V2-Info.plist` - Informações do app iOS
- `Fitter-V2-Watch-App-Info.plist` - Informações do app Watch

## 📋 Documentação
- `ESTRUTURA.md` - Este arquivo (estrutura do projeto)
- `FLUXO_CRIAR_TREINO.md` - Fluxo de criação de treino
- `FLUXO_LOGIN.md` - Fluxo de login
- `FLUXO_TREINO_COMPLETO.md` - Fluxo completo de treino
- `GUIA_APP_STORE_CONNECT.md` - Guia para App Store Connect
- `README_ASSINATURAS.md` - Documentação de assinaturas
- `README.md` - Documentação principal
- `REFATORAÇÃO.md` - Lista de refatorações
- `REMOVER_ANTES_LANCAMENTO.md` - Itens para remover antes do lançamento
- `RESUMO_REFATORAÇÃO.md` - Resumo das refatorações

## 🔧 Arquivos do Xcode
- **Fitter V2.xcodeproj/** - Projeto Xcode
  - `project.pbxproj` - Configurações do projeto
  - **project.xcworkspace/** - Workspace
  - **xcuserdata/** - Dados específicos do usuário

---

## 🏗️ Arquitetura do Projeto

O projeto segue a **Clean Architecture** com separação clara de responsabilidades:

1. **Presentation Layer** (Views, ViewModels, Components)
2. **Domain Layer** (UseCases, Models, Protocols)
3. **Data Layer** (Services, Repository, Persistence)
4. **Infrastructure** (Managers, Network, Sync)

### 📱 Plataformas Suportadas
- **iOS** - Aplicativo principal
- **watchOS** - Aplicativo Apple Watch
- **Shared** - Código compartilhado entre plataformas 