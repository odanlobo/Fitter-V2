# 🚀 Guia de Migração: Models Swift → Core Data

## ✅ **Migração Concluída: Opção A - Core Data Only**

### 📁 **Arquivos Removidos:**
- ✅ `AppUser.swift`
- ✅ `CurrentSession.swift`
- ✅ `CurrentExercise.swift`
- ✅ `CurrentSet.swift`
- ✅ `WorkoutPlan.swift`
- ✅ `PlanExercise.swift`
- ✅ `WorkoutHistory.swift`
- ✅ `HistoryExercise.swift`
- ✅ `HistorySet.swift`

### 📝 **Arquivos Migrados/Atualizados:**
- ✅ `CoreDataModels.swift` - Extensões com toda lógica de negócio
- ✅ `Model.xcdatamodeld/contents` - Modelo Core Data completo
- 🔄 `WorkoutPlanAdapter.swift` - **PRECISA SER REMOVIDO/ATUALIZADO**

---

## 🔄 **Mapeamento de Mudanças:**

### **Modelos Swift → Core Data:**
| Antigo Swift Model | Novo Core Data Model |
|-------------------|---------------------|
| `AppUser` | `CDAppUser` |
| `WorkoutPlan` | `CDWorkoutPlan` |
| `PlanExercise` | `CDPlanExercise` |
| `ExerciseTemplate` | `CDExerciseTemplate` |
| `CurrentSession` | `CDCurrentSession` |
| `CurrentExercise` | `CDCurrentExercise` |
| `CurrentSet` | `CDCurrentSet` |
| `WorkoutHistory` | `CDWorkoutHistory` |
| `HistoryExercise` | `CDHistoryExercise` |
| `HistorySet` | `CDHistorySet` |

---

## 🛠️ **Próximas Tarefas de Refatoração:**

### 🎯 **1. Remover Adapters (Prioridade Alta)**
- [ ] Deletar `WorkoutPlanAdapter.swift`
- [ ] Atualizar referências para usar Core Data diretamente

### 🎯 **2. Atualizar ViewModels**
- [ ] `WorkoutViewModel.swift` - Trocar `[WorkoutPlan]` por `[CDWorkoutPlan]`
- [ ] `LoginViewModel.swift` - Trocar `AppUser` por `CDAppUser`
- [ ] `CreateAccountViewModel.swift` - Trocar callback `AppUser` por `CDAppUser`

### 🎯 **3. Atualizar Views**
- [ ] `CreateWorkoutView.swift` - Usar `CDWorkoutPlan(context:)`
- [ ] `DetailWorkoutView.swift` - Aceitar `CDWorkoutPlan`
- [ ] `WorkoutView.swift` - `selectedPlan: CDWorkoutPlan?`
- [ ] `WorkoutPlanCard.swift` - Aceitar `CDWorkoutPlan`
- [ ] `WorkoutsPlansList.swift` - Usar `[CDWorkoutPlan]`

### 🎯 **4. Atualizar Services**
- [ ] `AuthService.swift` - Método `currentUser` retornar `CDAppUser`
- [ ] `SessionManager.swift` - Usar `CDAppUser` e `CDWorkoutPlan`

### 🎯 **5. Atualizar Repository**
- [ ] `WorkoutRepository.swift` - Métodos usar Core Data diretamente
- [ ] `WorkoutRepositoryProtocol.swift` - Interfaces com Core Data models

### 🎯 **6. Atualizar Connectivity**
- [ ] `ConnectivityManager.swift` - Converter `CDWorkoutPlan` para `WatchWorkoutPlan`

---

## 💡 **Métodos Úteis Adicionados:**

### **CDAppUser:**
```swift
// Business Logic
func startWorkout(with plan: CDWorkoutPlan, context: NSManagedObjectContext) -> CDCurrentSession?
func endWorkout(context: NSManagedObjectContext)

// Safe Properties
var safeId: UUID
var safeName: String
var workoutPlansArray: [CDWorkoutPlan]
```

### **CDWorkoutPlan:**
```swift
// Business Logic
func validateForSave() throws

// Safe Properties
var safeTitle: String
var exercisesArray: [CDPlanExercise]
var muscleGroupsString: String  // "Peito + Costas"
var isValid: Bool
```

### **CDCurrentSession:**
```swift
// Business Logic
func startSession(context: NSManagedObjectContext)
func endSession()
func nextExercise(context: NSManagedObjectContext)
func convertToHistory(context: NSManagedObjectContext) -> CDWorkoutHistory

// Properties
var duration: TimeInterval
```

### **CDCurrentSet:**
```swift
// Business Logic
func startSet()
func endSet()
func updateSensorData(...)
func updateHealthData(heartRate: Int?, caloriesBurned: Double?)

// Properties
var totalAcceleration: Double
var totalRotation: Double
```

---

## 🚨 **Padrões de Atualização:**

### **Antes (Swift Models):**
```swift
let plan = WorkoutPlan(title: "Treino A")
user.startWorkout(with: plan)
```

### **Depois (Core Data):**
```swift
let plan = CDWorkoutPlan(context: context)
plan.title = "Treino A"
plan.id = UUID()
user.startWorkout(with: plan, context: context)
```

### **Fetching - Antes:**
```swift
@Published var plans: [WorkoutPlan] = []
```

### **Fetching - Depois:**
```swift
@Published var plans: [CDWorkoutPlan] = []
// OU usar @FetchRequest em SwiftUI
```

---

## ⚡ **Benefícios da Migração:**

1. **📱 Persistência Robusta** - Core Data automático
2. **☁️ iCloud Sync** - Configurado no modelo
3. **🔄 Background Processing** - Contextos múltiplos
4. **📊 Performance** - Otimizações automáticas
5. **🛡️ Crash Safety** - Transações atômicas
6. **🧹 Código Limpo** - Menos conversões e adapters

---

## 🎯 **Status da Migração:**

- ✅ **Etapa 1:** Modelos Core Data criados
- ✅ **Etapa 2:** Lógica de negócio migrada
- ✅ **Etapa 3:** Arquivos Swift removidos
- 🔄 **Etapa 4:** Atualizar referências (EM ANDAMENTO)
- ⏳ **Etapa 5:** Testes e validação

---

**Data:** $(date)
**Status:** 🟡 Migração de Modelos Completa - Refatoração de Referências Pendente 