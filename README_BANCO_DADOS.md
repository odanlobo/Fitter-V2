# README_BANCO_DADOS.md

---

## Sumário

1. [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
2. [Core Data - Modelo Local](#core-data---modelo-local)
3. [Firebase/Firestore - Nuvem](#firebasefirestore---nuvem)
4. [Sistema de Sincronização](#sistema-de-sincronização)
5. [Integração Apple Watch](#integração-apple-watch)
6. [Arquivos e Responsabilidades](#arquivos-e-responsabilidades)
7. [Fluxos de Dados](#fluxos-de-dados)
8. [Persistência e Performance](#persistência-e-performance)
9. [Autenticação e Ownership](#autenticação-e-ownership)
10. [Estrutura de Dados dos Sensores](#estrutura-de-dados-dos-sensores)
11. [Sistema de Assinaturas](#sistema-de-assinaturas)
12. [Migração e Versionamento](#migração-e-versionamento)

---

## 1. Visão Geral da Arquitetura

O **Fitter V2** implementa uma arquitetura de dados híbrida que combina **Core Data local** com **Firebase/Firestore na nuvem**, garantindo sincronização bidirecional, performance offline e integração com Apple Watch.

### **🏗️ Princípios Arquiteturais:**
- **Core Data como fonte de verdade local** - Interface única via Use Cases
- **Firebase/Firestore para exercícios e sync** - Biblioteca global de exercícios
- **External Storage para Binary Data** - Dados de sensores otimizados
- **Login obrigatório** - Todos os dados vinculados ao usuário autenticado
- **Clean Architecture** - Separação clara de responsabilidades
- **Sincronização inteligente** - Apenas mudanças necessárias

### **📊 Diagrama da Arquitetura:**

```markdown
┌─────────────────────────────────────────────────────────┐
│                   CAMADA PRESENTATION                   │
│  Views (SwiftUI) + ViewModels (BaseViewModel)           │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│                   CAMADA DOMAIN                         │
│  Use Cases (AuthUseCase, CreateWorkoutUseCase, etc.)    │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│                   CAMADA DATA                           │
├─────────────────┬───────────────────┬───────────────────┤
│  Core Data      │   Firebase        │   Apple Watch     │
│  (Local)        │   (Nuvem)         │   (Sensores)      │
│                 │                   │                   │
│ • CDAppUser     │ • Exercises       │ • MotionManager   │
│ • CDWorkoutPlan │ • User Profiles   │ • SensorData      │
│ • CDCurrent*    │ • Videos          │ • HealthKit       │
│ • CDHistory*    │ • Thumbnails      │ • WCSession       │
└─────────────────┴───────────────────┴───────────────────┘
```

---

## 2. Core Data - Modelo Local

### **📋 Modelo de Dados Atualizado (FitterModel.xcdatamodeld)**

O Core Data serve como **fonte de verdade local** com 10 entidades organizadas por responsabilidade:

#### **🟦 Entidades "Current" (Estado Ativo)**

**`CDCurrentSession`** - Treino em andamento
```swift
// Atributos principais
id: UUID                    // Identificador único
startTime: Date             // Início da sessão
endTime: Date?              // Fim da sessão (nil = ativo)
currentExerciseIndex: Int32 // Exercício atual
isActive: Bool              // Status ativo/inativo

// Relacionamentos OBRIGATÓRIOS
user: CDAppUser             // Usuário dono (login obrigatório)
plan: CDWorkoutPlan         // Plano sendo executado
currentExercise: CDCurrentExercise? // Exercício atual
```

**`CDCurrentExercise`** - Exercício atual
```swift
// Controle de execução
id: UUID
startTime: Date
endTime: Date?
currentSetIndex: Int32
isActive: Bool (indexed)

// Relacionamentos
session: CDCurrentSession
template: CDExerciseTemplate
currentSet: CDCurrentSet?
```

**`CDCurrentSet`** - Série atual
```swift
// Dados da série
id: UUID
order: Int32
targetReps: Int32
actualReps: Int32?
weight: Double
startTime: Date?
endTime: Date?
restTime: Double?
isActive: Bool (indexed)

// ⚠️ IMPORTANTE: SEM dados de sensores
// Dados leves apenas para controle de UI
```

#### **🟢 Entidades de Planejamento**

**`CDWorkoutPlan`** - Planos de treino
```swift
// Sistema de títulos duais
id: UUID
autoTitle: String          // "Treino A", "Treino B" (gerado)
title: String?             // Título personalizado (opcional)
createdAt: Date
order: Int32
muscleGroups: String       // Concatenados para busca

// Sincronização
cloudSyncStatus: Int16     // pending(0), synced(1)
lastCloudSync: Date?

// Relacionamentos
user: CDAppUser            // OBRIGATÓRIO
exercises: Set<CDPlanExercise>
currentSessions: Set<CDCurrentSession>
```

**`CDPlanExercise`** - Exercícios do plano
```swift
id: UUID
order: Int32               // Ordem no plano
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos
plan: CDWorkoutPlan
template: CDExerciseTemplate
```

**`CDExerciseTemplate`** - Templates de exercícios
```swift
// Identificação
id: UUID                   // Local
templateId: String         // Firebase ID

// Dados do exercício
name: String (indexed)
muscleGroup: String (indexed)
legSubgroup: String?       // NOVO: Subgrupo pernas
equipment: String
gripVariation: String?
description: String?       // NOVO: Descrição
videoURL: String?          // NOVO: URL do vídeo
createdAt: Date?
updatedAt: Date?

// Sincronização
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos
currentExercises: Set<CDCurrentExercise>
planExercises: Set<CDPlanExercise>
```

#### **🟣 Entidades de Histórico**

**`CDWorkoutHistory`** - Treinos concluídos
```swift
id: UUID
date: Date (indexed)

// Dados de sensores (External Storage)
sensorData: Data?          // Timeline completa
heartRateData: Data?       // Dados HealthKit
caloriesData: Data?        // Dados HealthKit

// Sincronização
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos
user: CDAppUser            // OBRIGATÓRIO
exercises: Set<CDHistoryExercise>
```

**`CDHistoryExercise`** - Exercícios executados
```swift
id: UUID
name: String (indexed)
order: Int32

// Dados de sensores por exercício (External Storage)
heartRateData: Data?
caloriesData: Data?

// Sincronização
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos
history: CDWorkoutHistory
sets: Set<CDHistorySet>
```

**`CDHistorySet`** - Séries com dados completos
```swift
// Dados básicos (iguais ao CDCurrentSet)
id: UUID
order: Int32
targetReps: Int32
actualReps: Int32?
weight: Double
startTime: Date?
endTime: Date?
timestamp: Date (indexed)
restTime: Double?

// Dados de sensores (External Storage)
repsCounterData: Data?     // Timeline ML processada
heartRateData: Data?       // HealthKit por série
caloriesData: Data?        // HealthKit por série

// Sincronização
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos
exercise: CDHistoryExercise
```

#### **👤 Entidade de Usuário**

**`CDAppUser`** - Dados do usuário autenticado
```swift
// Identificação e auth
id: UUID
name: String
email: String?
providerId: String         // Firebase Auth ID
provider: String?          // Google, Facebook, Apple
profilePictureURL: URI?

// Dados pessoais
birthDate: Date?
gender: String?
height: Double?
weight: Double?
locale: String?

// Controle de sessão
createdAt: Date
updatedAt: Date
lastLoginDate: Date? (indexed) // Logout automático 7 dias

// Sistema de assinaturas
subscriptionType: Int16    // free(0), premium(1)
subscriptionStartDate: Date?
subscriptionValidUntil: Date? (indexed)

// Sincronização
cloudSyncStatus: Int16
lastCloudSync: Date?

// Relacionamentos (Cascade delete)
workoutPlans: Set<CDWorkoutPlan>
workoutHistories: Set<CDWorkoutHistory>
currentSession: CDCurrentSession?
```

---

## 3. Firebase/Firestore - Nuvem

### **🔥 Estrutura Firebase**

#### **Collections Principais:**

**`exercisesList/` - Biblioteca Global de Exercícios**
```javascript
{
  "templateId": "chest_bench_press_001",
  "name": "Supino Reto",
  "muscleGroup": "Peitoral",
  "legSubgroup": null,
  "equipment": "Barra",
  "gripVariation": "Pronada",
  "description": "Exercício fundamental para peitorais...",
  "videoURL": "https://storage.googleapis.com/videos/supino_reto.mp4",
  "thumbnailURL": "https://storage.googleapis.com/thumbs/supino_reto.jpg",
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-12-20T10:30:00Z"
}
```

**`users/{uid}/` - Perfis de Usuário**
```javascript
{
  "name": "João Silva",
  "email": "joao@email.com",
  "photoURL": "https://photo.url",
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-12-20T10:30:00Z",
  "subscriptionType": "premium",
  "subscriptionValidUntil": "2025-01-01T00:00:00Z"
}
```

**`users/{uid}/workoutPlans/` - Planos Sincronizados**
```javascript
{
  "autoTitle": "Treino A",
  "title": "Treino Peitoral Heavy",
  "muscleGroups": "Peitoral,Tríceps",
  "createdAt": "2024-12-20T10:00:00Z",
  "exercises": [
    {
      "templateId": "chest_bench_press_001",
      "order": 0
    },
    {
      "templateId": "chest_incline_press_001", 
      "order": 1
    }
  ]
}
```

#### **Firebase Storage:**
- **`/videos/`** - Vídeos de exercícios (streaming)
- **`/thumbnails/`** - Miniaturas otimizadas
- **`/user-data/{uid}/`** - Dados específicos do usuário

---

## 4. Sistema de Sincronização

### **🔄 CloudSyncManager - Arquitetura**

#### **Estados de Sincronização:**
```swift
enum CloudSyncStatus: Int16 {
    case pending = 0  // ⏳ Aguardando sync
    case synced = 1   // ✅ Sincronizado
}
```

#### **Protocolo Syncable:**
```swift
protocol Syncable {
    var cloudSyncStatus: Int16 { get set }
    var lastCloudSync: Date? { get set }
    
    func toFirestoreData() -> [String: Any]
    static func fromFirestoreData(_ data: [String: Any]) -> Self?
}
```

#### **Fluxo de Sincronização:**

**1. Upload (Local → Firestore):**
```markdown
1. Use Case modifica entidade local
2. cloudSyncStatus = .pending
3. CloudSyncManager detecta mudança
4. Converte para formato Firestore
5. Upload assíncrono
6. Success: cloudSyncStatus = .synced
7. Failure: mantém .pending para retry
```

**2. Download (Firestore → Local):**
```markdown
1. Listener Firebase detecta mudança
2. CloudSyncManager recebe dados
3. Converte para entidade Core Data
4. Merge inteligente (timestamp-based)
5. cloudSyncStatus = .synced
6. Notifica UI via publisher
```

#### **Estratégias de Conflito:**
- **Timestamp-based:** Mais recente vence
- **User ownership:** Usuário logado tem prioridade
- **Merge automático:** Para campos não conflitantes
- **Manual resolution:** Para conflitos críticos

### **📂 Arquivos do Sistema de Sync:**

**`CloudSyncManager.swift`** - Gerenciador principal
```swift
class CloudSyncManager {
    // Sincronização genérica
    func sync<T: Syncable>(_ entity: T) async throws
    
    // Filas de operação
    private var uploadQueue: [Syncable] = []
    private var deleteQueue: [String] = []
    
    // Retry com back-off
    private func retryWithBackoff(_ operation: @escaping () async throws -> Void)
}
```

**`CloudSyncStatus.swift`** - Estados e controle
```swift
extension CDWorkoutPlan: Syncable {
    func toFirestoreData() -> [String: Any] {
        return [
            "autoTitle": autoTitle,
            "title": title,
            "muscleGroups": muscleGroups,
            "createdAt": createdAt,
            "exercises": exercises.map { $0.toFirestoreData() }
        ]
    }
}
```

---

## 5. Integração Apple Watch

### **⌚ Arquitetura de Dados Watch**

#### **Coleta de Sensores:**
```swift
// MotionManager.swift (Watch)
struct SensorDataSample {
    let timestamp: TimeInterval
    let acceleration: CMAcceleration     // X, Y, Z
    let rotation: CMRotationRate         // X, Y, Z
    let gravity: CMAcceleration          // X, Y, Z
    let attitude: CMAttitude             // Roll, Pitch, Yaw
    let magneticField: CMMagneticField?  // X, Y, Z (opcional)
}
```

#### **Chunking e Transferência:**
```swift
// Estratégia de envio eficiente
struct SensorDataChunk {
    let sessionId: UUID
    let exerciseId: UUID
    let setId: UUID
    let phase: WorkoutPhase              // execution(50Hz), rest(20Hz)
    let samples: [SensorDataSample]      // Máx 100 amostras
    let metadata: ChunkMetadata
}

// WatchSessionManager envia chunks via WCSession
func sendChunk(_ chunk: SensorDataChunk) {
    let chunkData = try JSONEncoder().encode(chunk)
    session.transferFile(chunkData, metadata: chunk.metadata)
}
```

#### **Pipeline de Processamento:**
```markdown
[Apple Watch]
      ↓ (captura 50Hz/20Hz)
[Buffer 100 amostras]
      ↓ (chunk completo)
[WCSession transferFile]
      ↓ (iPhone recebe)
[PhoneSessionManager]
      ↓ (processamento ML)
[Timeline + Métricas]
      ↓ (serialização)
[Core Data External Storage]
```

### **📊 Dados HealthKit:**
```swift
// HealthKitManager.swift
struct HealthMetrics {
    let heartRate: [Double]              // BPM timeline
    let calories: [Double]               // Calorias timeline
    let timestamps: [Date]               // Sincronizados
    let workoutType: HKWorkoutActivityType
}

// Integração com Core Data
extension CDHistorySet {
    var healthMetrics: HealthMetrics? {
        guard let heartData = heartRateData,
              let caloriesData = caloriesData else { return nil }
        
        return try? JSONDecoder().decode(HealthMetrics.self, from: heartData)
    }
}
```

---

## 6. Arquivos e Responsabilidades

### **🏗️ Camada de Dados (Clean Architecture)**

#### **Core Data:**
- **`PersistenceController.swift`** - Configuração NSPersistentContainer + External Storage
- **`CoreDataService.swift`** - CRUD genérico para qualquer entidade
- **`WorkoutDataService.swift`** - CRUD especializado para workout entities
- **`CoreDataAdapter.swift`** - Serialização SensorData ↔ Binary Data
- **`CoreDataModels.swift`** - Extensions das entidades (sem lógica de negócio)

#### **Firebase:**
- **`FirestoreExerciseRepository.swift`** - Repository direto para exercícios
- **`FirebaseExercise.swift`** - Modelo Firebase + conversão CDExerciseTemplate
- **`CloudSyncManager.swift`** - Sincronização genérica Firestore

#### **Apple Watch:**
- **`MotionManager.swift`** - Captura de sensores com frequência variável
- **`WatchSessionManager.swift`** - WCSession + transferência de chunks
- **`PhoneSessionManager.swift`** - Recepção e processamento iPhone
- **`SessionManager.swift`** - Coordenação global de sessão

#### **Autenticação:**
- **`AuthUseCase.swift`** - Orquestração de auth + inicialização dados
- **`AuthService.swift`** - Firebase Auth + providers sociais

---

## 7. Fluxos de Dados

### **🔄 Fluxo 1: Criação de Treino**

```markdown
1. UI (WorkoutEditorView)
   ↓ Usuário seleciona exercícios Firebase
   
2. ViewModel (WorkoutViewModel)
   ↓ Usa CreateWorkoutUseCase
   
3. Use Case (CreateWorkoutUseCase)
   ↓ user: CDAppUser OBRIGATÓRIO
   
4. WorkoutDataService
   ↓ Cria CDWorkoutPlan + CDPlanExercise
   ↓ cloudSyncStatus = .pending
   
5. CloudSyncManager
   ↓ Upload automático para Firestore
   ↓ users/{uid}/workoutPlans/{id}
   
6. WatchSessionManager
   ↓ Sincroniza planos para Apple Watch
```

### **🏋️‍♂️ Fluxo 2: Treino Ativo (Completo)**

```markdown
1. StartWorkoutUseCase
   ↓ Cria CDCurrentSession
   ↓ Ativa MotionManager (Watch)
   ↓ user: CDAppUser OBRIGATÓRIO
   
2. Loop de Execução:
   ┌─ StartSetUseCase → CDCurrentSet
   │  ↓ Captura sensores 50Hz
   │  ↓ Chunks a cada 100 amostras
   │  ↓ WCSession transferFile
   │  ↓ PhoneSessionManager processa ML
   │  
   └─ EndSetUseCase → dados temporários
   
3. EndWorkoutUseCase
   ↓ Converte Current → History
   ↓ CDWorkoutHistory + External Storage
   ↓ Preserva timeline completa
   ↓ cloudSyncStatus = .pending
   
4. CloudSyncManager
   ↓ Sincroniza histórico (metadados apenas)
   ↓ Binary Data permanece local
```

### **📥 Fluxo 3: Importação de Treino**

```markdown
1. UploadButton (UI)
   ↓ Seleciona arquivo/câmera
   
2. ImportWorkoutUseCase
   ↓ ImportWorkoutService parseia
   ↓ Identifica exercícios vs Firebase
   ↓ Aplica limites premium/free
   
3. WorkoutDataService
   ↓ Cria CDWorkoutPlan(s)
   ↓ CDPlanExercise com exercícios identificados
   ↓ cloudSyncStatus = .pending
   
4. CloudSyncManager
   ↓ Upload automático
   ↓ Sincronização completa
```

### **🔄 Fluxo 4: Sincronização Bidirecional**

```markdown
Local → Firestore (Upload):
1. Use Case modifica entidade
2. cloudSyncStatus = .pending
3. CloudSyncManager detecta
4. Upload assíncrono
5. Success: .synced

Firestore → Local (Download):
1. Firestore listener
2. CloudSyncManager recebe
3. Merge com timestamp
4. Atualiza Core Data
5. Notifica UI
```

---

## 8. Persistência e Performance

### **⚡ External Storage (Binary Data)**

#### **Configuração:**
```swift
// PersistenceController.swift
container.persistentStoreDescriptions.first?.setOption(true as NSNumber, 
                                                       forKey: NSPersistentHistoryTrackingKey)
container.persistentStoreDescriptions.first?.setOption(true as NSNumber, 
                                                       forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

// External Storage para Binary Data
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSBinaryStoreSecureDecodingKey)
```

#### **Vantagens External Storage:**
- **Performance:** Binary data não carregado em memória
- **Especo:** Arquivos grandes gerenciados pelo sistema
- **Backup:** iCloud backup automático (opcional)
- **Streaming:** Dados grandes acessados sob demanda

### **📊 Otimizações de Performance:**

#### **Índices Estratégicos:**
```swift
// Atributos indexados para queries frequentes
name: String (indexed)           // Busca de exercícios
muscleGroup: String (indexed)    // Filtros de grupo muscular  
date: Date (indexed)             // Ordenação histórico
isActive: Bool (indexed)         // Filtros de estado
lastLoginDate: Date? (indexed)   // Logout automático
subscriptionValidUntil: Date? (indexed) // Verificação premium
timestamp: Date (indexed)        // Timeline ordenada
```

#### **Fetch Requests Otimizados:**
```swift
// CoreDataService.swift
func fetchActiveWorkouts() -> NSFetchRequest<CDWorkoutPlan> {
    let request = CDWorkoutPlan.fetchRequest()
    request.predicate = NSPredicate(format: "user == %@ AND cloudSyncStatus == %d", 
                                   currentUser, CloudSyncStatus.synced.rawValue)
    request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkoutPlan.order, ascending: true)]
    request.fetchBatchSize = 20
    return request
}
```

#### **Lazy Loading:**
```swift
// Relacionamentos carregados sob demanda
@NSManaged public var exercises: NSSet? // Lazy por padrão
@NSManaged public var sets: NSSet?      // Lazy por padrão

// Conversões para SwiftUI
var exercisesArray: [CDPlanExercise] {
    return (exercises?.allObjects as? [CDPlanExercise])?.sorted { $0.order < $1.order } ?? []
}
```

---

## 9. Autenticação e Ownership

### **🔐 Login Obrigatório + Ownership**

#### **Estratégia Arquitetural:**
- **Login obrigatório** na primeira abertura
- **Sessão persistente** via Keychain (7 dias)
- **Todos os dados vinculados** ao usuário autenticado
- **Relacionamentos obrigatórios** no Core Data

#### **Implementação:**
```swift
// BaseViewModel.swift
@Published public var currentUser: CDAppUser! // NUNCA nil após login

// Use Cases sempre recebem usuário
struct CreateWorkoutInput {
    let user: CDAppUser  // ← SEM opcional
    let title: String?
    let exercises: [CDExerciseTemplate]
}

// Core Data - relacionamentos obrigatórios
<relationship name="user" maxCount="1" deletionRule="Nullify" 
              destinationEntity="CDAppUser"/> <!-- SEM optional="YES" -->
```

#### **Fluxo de Autenticação:**
```markdown
1. App Launch
   ↓ AuthService.restoreSession()
   
2. Se sessão válida:
   ↓ currentUser = savedUser
   ↓ MainTabView
   
3. Se sem sessão:
   ↓ AuthenticationView
   ↓ Login obrigatório
   
4. Após login:
   ↓ currentUser = authenticatedUser
   ↓ CloudSyncManager.configure(userId)
   ↓ RevenueCatService.configure(userId)
   ↓ MainTabView
```

#### **Logout Automático (7 dias):**
```swift
// AuthService.swift
func checkInactivityTimeout() -> Bool {
    let lastOpen = keychain.get("lastAppOpenDate")
    let daysSince = Calendar.current.dateComponents([.day], 
                                                   from: lastOpenDate, 
                                                   to: Date()).day ?? 0
    return daysSince >= 7
}

func logoutDueToInactivity() async {
    // Para treino ativo se houver
    await sessionManager.handleInactivityLogout()
    
    // Limpa dados premium
    await subscriptionManager.clearSubscriptionData()
    
    // Limpa sync
    await cloudSyncManager.disconnect()
    
    // Logout completo
    await logout()
}
```

---

## 10. Estrutura de Dados dos Sensores

### **📊 SensorData - Modelo Otimizado**

#### **Estrutura Principal:**
```swift
// SensorData.swift
struct SensorDataSample: Codable {
    let timestamp: TimeInterval
    
    // Acelerômetro (m/s²)
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    
    // Giroscópio (rad/s)
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    
    // Gravidade (m/s²)
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    
    // Orientação (rad)
    let roll: Double
    let pitch: Double
    let yaw: Double
    
    // Campo magnético (opcional - μT)
    let magneticFieldX: Double?
    let magneticFieldY: Double?
    let magneticFieldZ: Double?
}

struct SensorDataTimeline: Codable {
    let sessionId: UUID
    let exerciseId: UUID
    let setId: UUID
    let startTime: Date
    let endTime: Date
    let phase: WorkoutPhase          // execution/rest
    let samplingRate: Double         // 50Hz ou 20Hz
    let samples: [SensorDataSample]  // Timeline completa
    
    // Metadados ML processados
    let detectedReps: Int?
    let confidence: Double?
    let patterns: [RepetitionPattern]?
}
```

#### **Serialização External Storage:**
```swift
// CoreDataAdapter.swift
extension SensorDataTimeline {
    func toBinaryData() throws -> Data {
        return try JSONEncoder().encode(self)
    }
    
    static func fromBinaryData(_ data: Data) throws -> SensorDataTimeline {
        return try JSONDecoder().decode(SensorDataTimeline.self, from: data)
    }
}

// Uso em CDHistorySet
extension CDHistorySet {
    var sensorTimeline: SensorDataTimeline? {
        get {
            guard let data = repsCounterData else { return nil }
            return try? SensorDataTimeline.fromBinaryData(data)
        }
        set {
            repsCounterData = try? newValue?.toBinaryData()
        }
    }
}
```

#### **Frequência de Captura:**
```swift
enum WorkoutPhase: String, Codable {
    case execution  // 50Hz (0.02s) - máxima precisão
    case rest       // 20Hz (0.05s) - economia bateria
    
    var samplingInterval: TimeInterval {
        switch self {
        case .execution: return 0.02  // 50Hz
        case .rest: return 0.05       // 20Hz
        }
    }
}
```

### **⌚ Pipeline Apple Watch:**

#### **1. Captura (MotionManager):**
```swift
// MotionManager.swift (Watch)
class MotionManager {
    private var sampleBuffer: [SensorDataSample] = []
    private let chunkSize = 100
    
    func startCapture(phase: WorkoutPhase) {
        motionManager.accelerometerUpdateInterval = phase.samplingInterval
        motionManager.gyroUpdateInterval = phase.samplingInterval
        motionManager.deviceMotionUpdateInterval = phase.samplingInterval
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            let sample = SensorDataSample(
                timestamp: motion.timestamp,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                // ... outros sensores
            )
            
            self?.processSample(sample)
        }
    }
    
    private func processSample(_ sample: SensorDataSample) {
        sampleBuffer.append(sample)
        
        if sampleBuffer.count >= chunkSize {
            let chunk = SensorDataChunk(samples: sampleBuffer)
            watchSessionManager.sendChunk(chunk)
            sampleBuffer.removeAll()
        }
    }
}
```

#### **2. Transferência (WCSession):**
```swift
// WatchSessionManager.swift (Watch)
func sendChunk(_ chunk: SensorDataChunk) {
    do {
        let chunkData = try JSONEncoder().encode(chunk)
        let tempURL = FileManager.default.temporaryDirectory
                      .appendingPathComponent("\(UUID().uuidString).json")
        
        try chunkData.write(to: tempURL)
        
        session.transferFile(tempURL, metadata: [
            "sessionId": chunk.sessionId.uuidString,
            "exerciseId": chunk.exerciseId.uuidString,
            "setId": chunk.setId.uuidString,
            "phase": chunk.phase.rawValue,
            "sampleCount": chunk.samples.count
        ])
        
    } catch {
        print("❌ Erro ao enviar chunk: \(error)")
    }
}
```

#### **3. Processamento (iPhone):**
```swift
// PhoneSessionManager.swift (iPhone)
func session(_ session: WCSession, didReceive file: WCSessionFile) {
    do {
        let chunkData = try Data(contentsOf: file.fileURL)
        let chunk = try JSONDecoder().decode(SensorDataChunk.self, from: chunkData)
        
        // Processar com ML em background
        Task.detached {
            let timeline = await self.processChunkWithML(chunk)
            await self.appendToCurrentSet(timeline)
        }
        
    } catch {
        print("❌ Erro ao processar chunk: \(error)")
    }
}

private func processChunkWithML(_ chunk: SensorDataChunk) async -> SensorDataTimeline {
    // Aqui seria aplicado o modelo Core ML para:
    // - Detectar repetições
    // - Calcular confiabilidade
    // - Identificar padrões
    
    return SensorDataTimeline(
        sessionId: chunk.sessionId,
        exerciseId: chunk.exerciseId,
        setId: chunk.setId,
        samples: chunk.samples,
        detectedReps: MLProcessor.detectReps(chunk.samples),
        confidence: MLProcessor.calculateConfidence(chunk.samples),
        patterns: MLProcessor.identifyPatterns(chunk.samples)
    )
}
```

---

## 11. Sistema de Assinaturas

### **💰 Integração RevenueCat + Core Data**

#### **Modelo de Assinatura:**
```swift
// SubscriptionType.swift
enum SubscriptionType: Int16, CaseIterable {
    case free = 0
    case premium = 1
    
    var maxWorkouts: Int? {
        switch self {
        case .free: return 4
        case .premium: return nil  // Ilimitado
        }
    }
    
    var maxExercisesPerWorkout: Int? {
        switch self {
        case .free: return 6
        case .premium: return nil  // Ilimitado
        }
    }
    
    var maxSetsPerExercise: Int? {
        switch self {
        case .free: return 3
        case .premium: return nil  // Ilimitado
        }
    }
}
```

#### **Integração Core Data:**
```swift
// CDAppUser - campos de assinatura
subscriptionType: Int16            // SubscriptionType.rawValue
subscriptionStartDate: Date?       // Início da assinatura
subscriptionValidUntil: Date? (indexed) // Validade (para verificação rápida)
```

#### **RevenueCatService Integration:**
```swift
// RevenueCatService.swift
class RevenueCatService: ObservableObject {
    @Published var isPremium: Bool = false
    @Published var customerInfo: CustomerInfo?
    
    func configure(userId: String) async {
        Purchases.configure(withAPIKey: apiKey, appUserID: userId)
        
        // Listener para mudanças
        Purchases.shared.getCustomerInfo { [weak self] info, error in
            self?.updateSubscriptionStatus(info)
        }
    }
    
    private func updateSubscriptionStatus(_ info: CustomerInfo?) {
        let isPremiumActive = info?.entitlements.active["premium"] != nil
        
        Task { @MainActor in
            self.isPremium = isPremiumActive
            
            // Atualizar Core Data
            await self.updateUserSubscription(isPremium: isPremiumActive)
        }
    }
    
    private func updateUserSubscription(isPremium: Bool) async {
        // Atualizar CDAppUser com status atual
        await coreDataService.updateUser { user in
            user.subscriptionType = isPremium ? SubscriptionType.premium.rawValue : SubscriptionType.free.rawValue
            user.subscriptionValidUntil = isPremium ? Date().addingTimeInterval(365*24*60*60) : nil
        }
    }
}
```

#### **Controle de Limites:**
```swift
// CreateWorkoutUseCase.swift
func execute(_ input: CreateWorkoutInput) async throws -> CDWorkoutPlan {
    let user = input.user
    let currentWorkoutCount = user.workoutPlans.count
    
    // Verificar limite de treinos
    if !subscriptionManager.isPremium {
        if currentWorkoutCount >= SubscriptionType.free.maxWorkouts! {
            throw WorkoutError.maxWorkoutsReached
        }
        
        if input.exerciseTemplates.count > SubscriptionType.free.maxExercisesPerWorkout! {
            throw WorkoutError.maxExercisesReached
        }
    }
    
    // Criar treino normalmente...
}
```

---

## 12. Migração e Versionamento

### **🔄 Migração Core Data**

#### **Estratégia de Migração:**
```swift
// PersistenceController.swift
lazy var persistentContainer: NSPersistentContainer = {
    let container = NSPersistentContainer(name: "FitterModel")
    
    // Migração automática habilitada
    let description = container.persistentStoreDescriptions.first!
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    
    // External Storage para Binary Data
    description.setOption(true as NSNumber, forKey: NSBinaryStoreSecureDecodingKey)
    
    container.loadPersistentStores { description, error in
        if let error = error {
            print("❌ Core Data failed to load: \(error.localizedDescription)")
        }
    }
    
    return container
}()
```

#### **Versionamento de Modelos:**
- **FitterModel v1:** Modelo inicial
- **FitterModel v2:** Adição External Storage
- **FitterModel v3:** Sistema de assinaturas
- **FitterModel v4:** Login obrigatório + ownership

#### **Migração de Dados Legacy:**
```swift
// CoreDataAdapter.swift
extension CoreDataAdapter {
    static func migrateLegacySensorData() async {
        // Migrar dados antigos para novo formato
        let oldFormat = fetchLegacyData()
        
        for oldData in oldFormat {
            let newFormat = SensorDataTimeline(
                sessionId: oldData.sessionId,
                samples: convertSamples(oldData.rawSamples),
                detectedReps: nil, // Será processado posteriormente
                confidence: nil,
                patterns: nil
            )
            
            try await saveToExternalStorage(newFormat)
        }
    }
}
```

### **🔥 Versionamento Firebase**

#### **Compatibilidade de Esquemas:**
```javascript
// Firestore - backward compatibility
{
  "version": "2.0",
  "templateId": "chest_bench_press_001",
  "name": "Supino Reto",
  
  // Campos novos (v2.0)
  "description": "Exercício fundamental...",
  "videoURL": "https://storage.googleapis.com/...",
  
  // Campos legacy (v1.0) - mantidos para compatibilidade
  "imageName": null  // Removido, mas mantido para apps antigos
}
```

#### **Migração de Vídeos:**
```swift
// FirestoreExerciseRepository.swift
func migrateToVideoFormat() async {
    let exercises = await fetchAllExercises()
    
    for exercise in exercises {
        if exercise.imageName != nil && exercise.videoURL == nil {
            // Buscar vídeo correspondente
            if let videoURL = await findVideoForExercise(exercise.templateId) {
                exercise.videoURL = videoURL
                exercise.imageName = nil  // Remover campo legacy
                
                await updateExercise(exercise)
            }
        }
    }
}
```

---

## 📊 Conclusão

A arquitetura de banco de dados do **Fitter V2** combina:

### **✅ Pontos Fortes:**
- **📱 Core Data local** - Performance e offline-first
- **☁️ Firebase/Firestore** - Biblioteca global e sync
- **⌚ Apple Watch** - Captura de sensores em tempo real
- **🔐 Login obrigatório** - Ownership e segurança garantidos
- **💾 External Storage** - Otimização para Binary Data
- **🔄 Sincronização inteligente** - Apenas mudanças necessárias
- **💰 Sistema premium** - Integração RevenueCat seamless
- **🏗️ Clean Architecture** - Separação clara de responsabilidades

### **📈 Benefícios:**
- **Performance otimizada** com índices estratégicos
- **Escalabilidade** via External Storage
- **Sincronização bidirecional** robusta
- **Offline-first** com sync inteligente
- **Login obrigatório** elimina dados órfãos
- **Upgrade instantâneo** para funcionalidades premium
- **Captura contínua** de dados de sensores
- **Integração nativa** com HealthKit

A arquitetura suporta tanto as funcionalidades atuais quanto futuras expansões, mantendo performance e consistência de dados em todos os devices e estados de conectividade.

---

**README_BANCO_DADOS.md - Documentação Completa 2025** 