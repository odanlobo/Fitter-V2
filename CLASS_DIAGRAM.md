# Diagrama de Classes - Fitter V2

Este diagrama serve como guia para o desenvolvimento do app Fitter V2, mostrando a arquitetura de dados e relacionamentos entre entidades Core Data.

## Visão Geral da Arquitetura

### 🟦 **Entidades "Vivas" (Estado Ativo) - Core Data**
- **CDCurrentSession**: Treino em andamento
- **CDCurrentExercise**: Exercício atual sendo executado  
- **CDCurrentSet**: Série atual sendo executada

### 🟢 **Entidades de Planejamento - Core Data**
- **CDWorkoutPlan**: Planos de treino criados pelo usuário
- **CDPlanExercise**: Exercícios dentro de um plano
- **CDExerciseTemplate**: Templates/cadastros de exercícios

### 🟣 **Entidades de Histórico - Core Data**
- **CDWorkoutHistory**: Histórico de treinos concluídos
- **CDHistoryExercise**: Exercícios executados no histórico
- **CDHistorySet**: Séries executadas com dados de sensores

### 🔧 **Gerenciamento - Singleton Classes**
- **SessionManager**: Gerenciador singleton para controlar sessões ativas
- **WorkoutManager**: Gerenciador para planos de treino e exercícios
- **ConnectivityManager**: Sincronização entre iPhone e Apple Watch

### 🏗️ **Infraestrutura**
- **CoreDataStack**: Configuração e acesso ao Core Data
- **DataSeeder**: População inicial de exercícios
- **WorkoutRepository**: Acesso a dados de treinos

## Relacionamentos Principais

1. **CDAppUser** (1) ↔ (0..1) **CDCurrentSession** - Um usuário só pode ter uma sessão ativa
2. **CDCurrentSession** (1) ↔ (1) **CDWorkoutPlan** - Cada sessão executa um plano
3. **CDCurrentSession** (1) ↔ (0..1) **CDCurrentExercise** - Um exercício ativo por vez
4. **CDCurrentExercise** (1) ↔ (0..1) **CDCurrentSet** - Uma série ativa por vez
5. **Conversão**: Quando o treino termina, as entidades "vivas" são convertidas para histórico

## Fluxo de Conversão
- **CDCurrentSession** → **CDWorkoutHistory**
- **CDCurrentExercise** → **CDHistoryExercise** 
- **CDCurrentSet** → **CDHistorySet** (com todos os dados de sensores)

---

## Diagrama de Classes

```mermaid
classDiagram
    %% ENTIDADES PRINCIPAIS CORE DATA
    
    class CDAppUser {
        +UUID id
        +String name
        +String? email
        +Date birthDate
        +Double height
        +Double weight
        +String? provider
        +String providerId
        +String? profilePictureURL
        +String? locale
        +String? gender
        +Date createdAt
        +Date updatedAt
        +Date? lastLoginDate
        +Set~CDWorkoutPlan~ workoutPlans
        +Set~CDWorkoutHistory~ workoutHistory
        +CDCurrentSession? currentSession
        +startWorkout()
        +endWorkout()
    }
    
    %% ENTIDADES "VIVAS" (Estado Ativo) - CORE DATA
    class CDCurrentSession {
        <<Core Data Entity>>
        +UUID id
        +Date startTime
        +Date? endTime
        +CDWorkoutPlan plan
        +CDAppUser user
        +CDCurrentExercise? currentExercise
        +Int32 currentExerciseIndex
        +startSession()
        +endSession()
        +nextExercise()
        +convertToHistory()
    }
    
    class CDCurrentExercise {
        <<Core Data Entity>>
        +UUID id
        +CDExerciseTemplate template
        +CDCurrentSession session
        +CDCurrentSet? currentSet
        +Int32 currentSetIndex
        +Date startTime
        +Date? endTime
        +startExercise()
        +endExercise()
        +nextSet()
        +convertToHistory()
    }
    
    class CDCurrentSet {
        <<Core Data Entity>>
        +UUID id
        +CDCurrentExercise exercise
        +Int32 order
        +Int32 targetReps
        +Double weight
        +Date? startTime
        +Date? endTime
        +Date timestamp
        +Int32? actualReps
        +Double? restTime
        +Double rotationX
        +Double rotationY
        +Double rotationZ
        +Double accelerationX
        +Double accelerationY
        +Double accelerationZ
        +Double gravityX
        +Double gravityY
        +Double gravityZ
        +Double attitudeRoll
        +Double attitudePitch
        +Double attitudeYaw
        +Int32? heartRate
        +Double? caloriesBurned
        +startSet()
        +endSet()
        +updateSensorData()
        +updateHealthData()
        +convertToHistory()
    }
    
    %% GERENCIAMENTO - SINGLETON CLASSES
    class SessionManager {
        <<Singleton ObservableObject>>
        +CDCurrentSession? currentSession
        +Bool isSessionActive
        +startSession()
        +endSession()
        +nextExercise()
        +nextSet()
        +updateSensorData()
        +updateHealthData()
    }
    
    class WorkoutManager {
        <<Singleton ObservableObject>>
        +[CDWorkoutPlan] workoutPlans
        +[CDExerciseTemplate] exercises
        +loadWorkoutPlans()
        +createWorkoutPlan()
        +updateWorkoutPlan()
        +deleteWorkoutPlan()
        +loadExerciseTemplates()
        +filteredExercises()
    }
    
    class ConnectivityManager {
        <<Singleton ObservableObject>>
        +WCSession session
        +sendSessionContext()
        +sendSensorData()
        +handleWatchMessage()
        +syncWorkoutData()
    }
    
    %% ENTIDADES DE PLANEJAMENTO - CORE DATA
    class CDWorkoutPlan {
        <<Core Data Entity>>
        +UUID id
        +String title
        +Date createdAt
        +Set~CDPlanExercise~ exercises
        +Int32 order
        +CDAppUser? user
        +String muscleGroupsString
        +Bool isValid
        +validateForSave()
    }
    
    class CDPlanExercise {
        <<Core Data Entity>>
        +UUID id
        +Int32 order
        +CDWorkoutPlan? plan
        +CDExerciseTemplate? template
    }
    
    class CDExerciseTemplate {
        <<Core Data Entity>>
        +UUID id
        +String templateId
        +String name
        +String muscleGroup
        +String? legSubgroup
        +String equipment
        +String? gripVariation
        +String? imageName
    }
    
    %% ENTIDADES DE HISTÓRICO - CORE DATA
    class CDWorkoutHistory {
        <<Core Data Entity>>
        +UUID id
        +Date date
        +Set~CDHistoryExercise~ exercises
        +CDAppUser? user
    }
    
    class CDHistoryExercise {
        <<Core Data Entity>>
        +UUID id
        +Int32 order
        +String name
        +Set~CDHistorySet~ sets
        +CDWorkoutHistory? history
    }
    
    class CDHistorySet {
        <<Core Data Entity>>
        +UUID id
        +Int32 order
        +CDHistoryExercise? exercise
        +Int32 reps
        +Int32? repsCounter
        +Double weight
        +Date? startTime
        +Date? endTime
        +Date timestamp
        +Double? restTime
        +Double rotationX
        +Double rotationY
        +Double rotationZ
        +Double accelerationX
        +Double accelerationY
        +Double accelerationZ
        +Double gravityX
        +Double gravityY
        +Double gravityZ
        +Double attitudeRoll
        +Double attitudePitch
        +Double attitudeYaw
        +Int32? heartRate
        +Double? caloriesBurned
        +updateSensorData()
        +updateHealthData()
        +startSet()
        +endSet()
        +updateRestTime()
        +updateRepsCounter()
    }
    
    %% INFRAESTRUTURA
    class CoreDataStack {
        <<Singleton>>
        +NSPersistentContainer persistentContainer
        +NSManagedObjectContext viewContext
        +newBackgroundContext()
        +save()
        +saveContext()
        +seedInitialDataIfNeeded()
    }
    
    class DataSeeder {
        <<Utility>>
        +seedIfNeeded()
        +clearAllTemplates()
        +forceSeed()
        +generatePrePopulatedDatabase()
    }
    
    class WorkoutRepository {
        <<Singleton>>
        +[CDWorkoutPlan] workoutPlans
        +fetchWorkoutPlans()
        +createWorkoutPlan()
        +updateWorkoutPlan()
        +deleteWorkoutPlan()
    }
    
    %% ENUMS
    class MuscleGroup {
        <<enumeration>>
        chest
        back
        legs
        biceps
        triceps
        shoulders
        core
    }
    
    class LegSubgroup {
        <<enumeration>>
        quadriceps
        hamstrings
        calves
        glutes
    }
    
    %% RELACIONAMENTOS PRINCIPAIS
    
    %% AppUser Relationships
    CDAppUser ||--o{ CDWorkoutPlan : "possui"
    CDAppUser ||--o{ CDWorkoutHistory : "possui"
    CDAppUser ||--o| CDCurrentSession : "tem sessão ativa"
    
    %% Session Manager
    SessionManager ||--o| CDCurrentSession : "gerencia"
    WorkoutManager ||--o{ CDWorkoutPlan : "gerencia"
    ConnectivityManager ||--|| SessionManager : "sincroniza"
    
    %% Current Session Relationships (Estado Vivo)
    CDCurrentSession ||--|| CDWorkoutPlan : "executa"
    CDCurrentSession ||--o| CDCurrentExercise : "exercício atual"
    CDCurrentExercise ||--|| CDExerciseTemplate : "baseado em"
    CDCurrentExercise ||--o| CDCurrentSet : "série atual"
    CDCurrentSet ||--|| CDCurrentExercise : "pertence a"
    
    %% Planning Relationships
    CDWorkoutPlan ||--o{ CDPlanExercise : "contém"
    CDPlanExercise }o--|| CDExerciseTemplate : "usa template"
    CDExerciseTemplate ||--|| MuscleGroup : "grupo muscular"
    CDExerciseTemplate ||--o| LegSubgroup : "subgrupo pernas"
    
    %% Historical Relationships
    CDWorkoutHistory ||--o{ CDHistoryExercise : "contém exercícios"
    CDHistoryExercise ||--o{ CDHistorySet : "contém séries"
    
    %% Infrastructure Relationships
    CoreDataStack ||--|| DataSeeder : "usa para popular"
    WorkoutManager ||--|| WorkoutRepository : "delega para"
    WorkoutRepository ||--|| CoreDataStack : "acessa"
    
    %% Conversion Process (CurrentSession -> WorkoutHistory)
    CDCurrentSession -.-> CDWorkoutHistory : "converte para histórico"
    CDCurrentExercise -.-> CDHistoryExercise : "converte para histórico"
    CDCurrentSet -.-> CDHistorySet : "converte para histórico"
    
    %% Styling para destacar entidades ativas vs históricas
    classDef activeState fill:#e1f5fe,stroke:#01579b,stroke-width:3px
    classDef historicalData fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef planning fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef management fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef infrastructure fill:#f1f8e9,stroke:#33691e,stroke-width:2px
    
    class CDCurrentSession,CDCurrentExercise,CDCurrentSet activeState
    class CDWorkoutHistory,CDHistoryExercise,CDHistorySet historicalData
    class CDWorkoutPlan,CDPlanExercise,CDExerciseTemplate planning
    class SessionManager,WorkoutManager,ConnectivityManager management
    class CoreDataStack,DataSeeder,WorkoutRepository infrastructure
```

---

## Implementação Atual vs. Planejada

### ✅ **Implementado (Core Data Only):**
- `CDAppUser` - ✨ Core Data entity com currentSession
- `CDWorkoutPlan` - ✨ Core Data entity
- `CDPlanExercise` - ✨ Core Data entity  
- `CDExerciseTemplate` - ✨ Core Data entity
- `CDWorkoutHistory` - ✨ Core Data entity
- `CDHistoryExercise` - ✨ Core Data entity
- `CDHistorySet` - ✨ Core Data entity
- `CDCurrentSession` - ✨ Core Data entity
- `CDCurrentExercise` - ✨ Core Data entity
- `CDCurrentSet` - ✨ Core Data entity
- `MuscleGroup` enum - ✨ Centralizado
- `LegSubgroup` enum - ✨ Implementado
- `SessionManager` - ✨ Singleton ObservableObject
- `WorkoutManager` - ✨ Singleton ObservableObject
- `ConnectivityManager` - ✨ iPhone-Watch sync
- `CoreDataStack` - ✨ Configuração robusta + DataSeeder
- `DataSeeder` - ✨ Sistema híbrido (JSON + banco pré-populado)
- `WorkoutRepository` - ✨ Repository pattern

### 🎯 **Status:** Arquitetura 100% Core Data Completa!

---

## Notas de Desenvolvimento

1. **Core Data Only**: Migração completa removendo modelos Swift
2. **Estado Ativo**: As entidades `CD*Current*` representam o estado "vivo" do treino
3. **Conversão**: Dados das entidades ativas são convertidos para histórico via CoreDataAdapter
4. **Sensores**: Todos os dados de sensores coletados em `CDCurrentSet` e `CDHistorySet`
5. **Sincronização**: ConnectivityManager gerencia sync iPhone-Watch com IDs corretos
6. **Performance**: CoreDataStack com banco pré-populado opcional
7. **Singleton Pattern**: Managers implementam ObservableObject para SwiftUI
8. **Repository Pattern**: WorkoutRepository centraliza acesso a dados

---

## Arquivos Criados/Atualizados

### 📁 **Estrutura Final:**
```
Shared/
├── CoreData 2/
│   ├── CoreDataStack.swift          ✅ Stack principal + seeding
│   ├── CoreDataModels.swift         ✅ Extensions com business logic
│   ├── CoreDataAdapter.swift        ✅ Conversão Current→History + Watch sync
│   └── Model.xcdatamodeld/          ✅ Modelo Core Data completo
├── Manager/
│   ├── SessionManager.swift         ✅ Gerencia sessões ativas
│   ├── WorkoutManager.swift         ✅ Gerencia planos e exercícios
│   └── ConnectivityManager.swift    ✅ Sync iPhone-Watch
├── Repository/
│   └── WorkoutRepository.swift      ✅ Repository pattern
├── Models/
│   └── MuscleGroup.swift           ✅ Enums centralizados
├── Utilities/
│   └── DataSeeder.swift            ✅ População inicial + versionamento
└── Resources/
    └── exercises.json              ✅ Dados de exercícios atualizados
```

---

**Data de Atualização:** $(date)  
**Versão:** 3.0 - Core Data Only  
**Status:** ✅ Migração Completa + Sincronização iPhone-Watch + Sistema Híbrido de População 