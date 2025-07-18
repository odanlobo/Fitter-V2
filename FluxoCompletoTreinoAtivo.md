# Fluxo Completo do Treino Ativo

## Diagrama em Texto com Referência de Arquivos

---

## Sumário

- [Princípios-Chave](#princípios-chave)
- [Todos os Arquivos do Contexto de Treino Ativo](#todos-os-arquivos-do-contexto-de-treino-ativo)
- [Dados Técnicos](#dados-técnicos)
- [Fluxo Detalhado do Treino Ativo](#fluxo-detalhado-do-treino-ativo)
    - [Início do Treino](#1-início-do-treino)
    - [Início de Exercício](#2-início-de-exercício)
    - [Início de Série](#3-início-de-série)
    - [Execução da Série + Detecção Automática de Fim de Série](#4-execução-da-série--detecção-automática-de-fim-de-série)
    - [Finalização de Série (Manual ou Automática) + Loop para Nova Série](#5-finalização-de-série-manual-ou-automática--loop-para-nova-série)
    - [Troca da Ordem de Exercícios – Reatividade e Pausa/Ativação](#6-troca-da-ordem-de-exercícios--reatividade-e-pausaativação)
    - [Finalização de Exercício](#7-finalização-de-exercício)
    - [Finalização de Treino](#8-finalização-de-treino)
- [Fluxo Técnico de Dados e Pipeline de Captação](#fluxo-técnico-de-dados-e-pipeline-de-captação)
- [Premium vs Não-Premium: Diferenças no Fluxo](#premium-vs-não-premium-diferenças-no-fluxo)
- [Estrutura CoreData para Sensores, ML e Histórico](#estrutura-coredata-para-sensores-ml-e-histórico)
- [Observações Finais](#observações-finais)

---

## Princípios-Chave

- **Pré-requisito:** Ter pelo menos 1 treino criado e o usuário obrigatoriamente autenticado (login concluído).
- Sincronização em tempo real entre Apple Watch e iPhone via WCSession.
- UI reativa refletindo sensores, ML, permissões premium em tempo real.
- Chunking eficiente: 100 amostras por chunk (50Hz execução, 20Hz descanso).
- Permissões premium controladas via RevenueCat e publishers.
- Clean Architecture: UseCases, Services, Managers separados.
- Captura automática de localização (opcional para todos).
- Persistência resiliente: upgrade premium libera acesso imediato ao histórico.
- Mudanças de ordem de exercícios são imediatamente refletidas no fluxo.

---

## Todos os Arquivos do Contexto de Treino Ativo

Esta seção lista **TODOS** os arquivos envolvidos no fluxo completo de um treino ativo, organizados por categoria funcional:

### 📱 **Aplicações Principais (Entry Points)**
- `Fitter V2/iOSApp.swift` - Entry point iOS, setup global, permissões
- `Fitter V2 Watch App/WatchApp.swift` - Entry point Watch, configuração inicial

### 🎨 **Views e UI Components**

#### Views Principais
- `Fitter V2/Views/Home/HomeView.swift` - Tela inicial, acesso aos treinos
- `Fitter V2/Views/Workout/WorkoutView.swift` - Lista e gerenciamento de treinos
- `Fitter V2/Views/Workout/WorkoutSessionView.swift` - **[🚧 A IMPLEMENTAR]** Interface principal do treino ativo
- `Fitter V2 Watch App/Views/WatchView.swift` - Interface Watch do treino
- `Fitter V2 Watch App/Views/WatchWorkoutSessionView.swift` - **[🚧 A IMPLEMENTAR]** Interface específica treino Watch
- `Fitter V2 Watch App/Views/PendingLoginView.swift` - Tela de aguardo sincronização

#### Componentes de UI (Cards e Botões) - Gerais
- `Fitter V2/Components/ExerciseCard.swift` - Card de exercício na lista
- `Fitter V2/Components/WorkoutPlanCard.swift` - Card do plano de treino
- `Fitter V2/Components/ImportWorkoutCard.swift` - Card para importar treino
- `Fitter V2/Components/CreateButton.swift` - Botão de criar treino
- `Fitter V2/Components/UploadButton.swift` - Botão de upload
- `Fitter V2/Components/BackButton.swift` - Botão de voltar

#### Componentes de UI - Treino Ativo **[🚧 A IMPLEMENTAR]**
- `Fitter V2/Components/Workout/WorkoutStatusCard.swift` - Card de status geral do treino
- `Fitter V2/Components/Workout/ExerciseSessionCard.swift` - Card do exercício ativo
- `Fitter V2/Components/Workout/SetCard.swift` - Card individual de série
- `Fitter V2/Components/Workout/RestTimerCard.swift` - Card do timer de descanso
- `Fitter V2/Components/Workout/AutoDetectionModal.swift` - Modal de detecção automática
- `Fitter V2/Components/Workout/TimerSelectionSheet.swift` - Sheet de seleção de timer
- `Fitter V2/Components/Workout/DecisionModal.swift` - Modal de decisão pós-timer
- `Fitter V2/Components/Workout/MissingFieldsModal.swift` - Modal de campos obrigatórios

### 🧠 **ViewModels (Estado Reativo)**
- `Fitter V2/ViewsModel/WorkoutSessionViewModel.swift` - ViewModel principal do treino ativo
- `Fitter V2/ViewsModel/WorkoutViewModel.swift` - ViewModel geral de treinos
- `Fitter V2/ViewsModel/ListExerciseViewModel.swift` - ViewModel da lista de exercícios
- `Fitter V2/ViewsModel/BaseViewModel.swift` - ViewModel base com funcionalidades comuns

### 🔄 **Use Cases (Lógica de Negócio)**
- `Shared/UseCases/StartWorkoutUseCase.swift` - Iniciar treino
- `Shared/UseCases/EndWorkoutUseCase.swift` - Finalizar treino
- `Shared/UseCases/StartExerciseUseCase.swift` - Iniciar exercício
- `Shared/UseCases/EndExerciseUseCase.swift` - Finalizar exercício
- `Shared/UseCases/StartSetUseCase.swift` - Iniciar série
- `Shared/UseCases/EndSetUseCase.swift` - Finalizar série
- `Shared/UseCases/UpdateDataToMLUseCase.swift` - Processamento ML dos dados
- `Shared/UseCases/FetchWorkoutUseCase.swift` - Buscar dados do treino
- `Shared/UseCases/UpdateWorkoutUseCase.swift` - Atualizar treino
- `Shared/UseCases/ReorderExerciseUseCase.swift` - Reordenar exercícios
- `Shared/UseCases/ImportWorkoutUseCase.swift` - Importar treino
- `Shared/UseCases/SyncWorkoutUseCase.swift` - Sincronizar treino

### 🎛️ **Managers (Coordenação e Estado)**
- `Shared/Manager/SessionManager.swift` - Gerenciador global da sessão
- `Shared/Manager/WorkoutPhaseManager.swift` - Gerenciador de fases (execução/descanso)
- `Shared/Manager/ConnectivityManager.swift` - Gerenciador de conectividade
- `Fitter V2/Sync/PhoneSessionManager.swift` - Sincronização iPhone ↔ Watch
- `Fitter V2 Watch App/Managers/WatchSessionManager.swift` - Sincronização Watch ↔ iPhone
- `Fitter V2 Watch App/Managers/MotionManager.swift` - Captação sensores Watch

### 🔧 **Services (Serviços Especializados)**
- `Shared/Services/TimerService.swift` - Cronômetros e timers
- `Shared/Services/WorkoutDataService.swift` - Persistência de dados do treino
- `Shared/Services/CoreDataService.swift` - Serviços Core Data gerais
- `Shared/Services/HealthKitManager.swift` - Integração HealthKit (heart rate, calorias)
- `Shared/Services/LocationManager.swift` - Captação de localização
- `Shared/Services/MLModelManager.swift` - Processamento machine learning
- `Shared/Services/SubscriptionManager.swift` - Gerenciamento premium/assinaturas
- `Shared/Services/RevenueCatService.swift` - Integração RevenueCat
- `Shared/Services/ImportWorkoutService.swift` - Importação de treinos

### 📊 **Models e Data (Estruturas de Dados)**
- `Shared/Models/SensorData.swift` - Estrutura dos dados de sensores
- `Shared/Models/MuscleGroup.swift` - Grupos musculares
- `Shared/Models/SubscriptionType.swift` - Tipos de assinatura
- `Shared/Models/WeightUnit.swift` - Unidades de peso
- `Fitter V2/Models/FirebaseExercise.swift` - Modelo exercício Firebase

### 🗄️ **Persistência e Core Data**
- `Shared/Persistence/PersistenceController.swift` - Controlador principal Core Data
- `Shared/CoreData 2/CoreDataAdapter.swift` - Adaptador para conversões Core Data
- `Shared/CoreData 2/CoreDataModels.swift` - Modelos Core Data
- `Shared/CoreData 2/FitterModel.xcdatamodeld/` - Schema Core Data

### 🔗 **Protocolos e Interfaces**
- `Shared/Protocols/ExerciseDisplayable.swift` - Protocol para exibição de exercícios
- `Fitter V2/Services/Auth/AppleSignInServiceProtocol.swift` - Protocol Apple Sign-In
- `Fitter V2/Services/Auth/GoogleSignInServiceProtocol.swift` - Protocol Google Sign-In
- `Fitter V2/Services/Auth/FacebookSignInServiceProtocol.swift` - Protocol Facebook Sign-In
- `Fitter V2/Services/Auth/BiometricAuthServiceProtocol.swift` - Protocol autenticação biométrica

### 🌐 **Network e Conectividade**
- `Shared/Network/NetworkMonitor.swift` - Monitor de conectividade de rede

### 🔄 **Sincronização e Cloud**
- `Shared/Sync/CloudSyncStatus.swift` - Status da sincronização cloud
- `Fitter V2/Sync/CloudSyncManager.swift` - Gerenciador sincronização cloud

### 🔐 **Autenticação (Pré-requisito)**
> **Nota:** Estes arquivos são pré-requisitos para o treino ativo. O usuário já deve estar autenticado antes de iniciar qualquer treino.

- `Shared/UseCases/AuthUseCase.swift` - Use case de autenticação
- `Fitter V2/Services/AuthService.swift` - Serviço principal de autenticação
- `Fitter V2/Services/Auth/AppleSignInService.swift` - Login com Apple
- `Fitter V2/Services/Auth/GoogleSignInService.swift` - Login com Google
- `Fitter V2/Services/Auth/FacebookSignInService.swift` - Login com Facebook
- `Fitter V2/Services/Auth/BiometricAuthService.swift` - Autenticação biométrica

### 🗃️ **Repository (Acesso a Dados)**
- `Fitter V2/Repository/FirestoreExerciseRepository.swift` - Repository exercícios Firestore

### 🎨 **Assets e Recursos**
- `Fitter V2/Assets.xcassets/` - Assets iOS (ícones, cores, imagens)
- `Fitter V2 Watch App/Assets.xcassets/` - Assets Watch

### ⚙️ **Configuração**
- `Fitter V2/Fitter V2.entitlements` - Entitlements iOS
- `Fitter V2 Watch App/Fitter V2 Watch App.entitlements` - Entitlements Watch
- `Fitter V2/GoogleService-Info.plist` - Configuração Firebase
- `Fitter-V2-Info.plist` - Info.plist iOS
- `Fitter-V2-Watch-App-Info.plist` - Info.plist Watch

### 🔧 **Utilitários**
- `Shared/Utilities/` - Diretório com utilitários compartilhados

---

## 📋 **Resumo de Arquivos por Funcionalidade**

### **Fluxo Principal do Treino Ativo:**
1. **Início:** `StartWorkoutUseCase.swift` → `WorkoutSessionViewModel.swift` → `WorkoutSessionView.swift`
2. **Sensores:** `MotionManager.swift` → `WatchSessionManager.swift` → `PhoneSessionManager.swift`
3. **Dados:** `SensorData.swift` → `UpdateDataToMLUseCase.swift` → `MLModelManager.swift`
4. **Persistência:** `WorkoutDataService.swift` → `CoreDataAdapter.swift` → `PersistenceController.swift`
5. **UI Reativa:** `WorkoutSessionViewModel.swift` → Componentes UI → Publishers

### **Arquivos Críticos (Núcleo do Sistema):**
- `WorkoutSessionViewModel.swift` - Orquestração principal
- `SessionManager.swift` - Coordenação global
- `WorkoutPhaseManager.swift` - Estado execução/descanso
- `MotionManager.swift` - Captação sensores Watch
- `PhoneSessionManager.swift` / `WatchSessionManager.swift` - Sincronização
- `TimerService.swift` - Cronômetros e timers
- `HealthKitManager.swift` - Métricas vitais

### **Dependências Externas Principais:**
- **Core Data:** Persistência local (`FitterModel.xcdatamodeld`)
- **WatchConnectivity:** Sincronização iPhone ↔ Watch
- **HealthKit:** Heart rate, calorias, métricas vitais
- **CoreMotion:** Sensores de movimento (Watch)
- **RevenueCat:** Controle de assinatura premium
- **Firebase Firestore:** Exercícios e sincronização cloud

### **Estado de Implementação:**
- ✅ **Pré-requisitos:** Autenticação, Use Cases, ViewModels, Managers, Services, Models
- 🚧 **Em Desenvolvimento:** Views específicas de treino ativo, componentes UI
- 📋 **Planejado:** Componentes avançados de UI, modais, sheets

---

## Dados Técnicos

- Execução: 50Hz (0,02s), descanso: 20Hz (0,05s).  
- Sensores: acel., giro, gravidade, orientação, magnético.
- Chunking: 100 amostras/transferência.
- Detecção automática de fase (MotionManager → WorkoutPhaseManager).
- Heart rate/calorias: HealthKit, atualização a cada 2s.
- Localização opcional salva na sessão/histórico.
- Pipeline: sensores → ML → publishers → ViewModel → UI.
- Premium: RevenueCat/publishers, upgrade instantâneo ao histórico.
- Mudança de ordem: sempre pausa exercício/série ativo, inicia o topo da lista.

---

## Fluxo Detalhado do Treino Ativo

> **🔐 PRÉ-REQUISITO OBRIGATÓRIO:** Todo o fluxo abaixo pressupõe que o usuário já está **autenticado e logado** no sistema. A autenticação é um pré-requisito, não parte do fluxo de treino ativo.

### 1. **Início do Treino**

- Usuário toca "Iniciar Treino" (pode ser na HomeView pelo WorkoutStatusCard ou pelo WorkoutPlanCard):

- iPhone/Watch: Trigger inicia StartWorkoutUseCase.swift
    - Cria CDCurrentSession (WorkoutDataService/CoreDataAdapter)
    - Inicializa cronômetro global (TimerService.swift)
    - Inicia sensores (MotionManager.swift)
    - Inicia WorkoutPhaseManager.swift
    - Sincroniza contexto com WatchSessionManager.swift
    - Inicia captura contínua de frequência cardíaca e calorias:
        - HealthKitManager configura HKAnchoredObjectQuery para heartRate (BPM) e inicia coleta contínua.
        - HealthKitManager configura HKLiveWorkoutBuilder/HKLiveWorkoutDataSource para activeEnergyBurned (kcal).
        - Cada nova amostra recebida atualiza arrays temporários em memória:
            - heartRateTimeline: [timestamp: Double, value: Double]
            - caloriesTimeline: [timestamp: Double, value: Double]

- Sequência automática:
    - Executa StartExerciseUseCase.swift para o PRIMEIRO exercício da lista em exerciseListSection
    - Imediatamente executa StartSetUseCase.swift para a PRIMEIRA série do exercício ativo

- UI (WorkoutSessionView):
    - Exibe ExerciseSessionCard do primeiro exercício
    - Exibe primeiro SetCard já iniciado para input de peso e repetições.

### 2. **Início do Exercício**

- Quando novo exercício é iniciado (normal ou por troca de ordem):
    - StartExerciseUseCase.swift
        - Cria CDCurrentExercise, atualiza contexto/session
        - Inicia cronômetro do exercício (TimerService)
    - StartSetUseCase.swift é chamado imediatamente para iniciar a primeira série do novo exercício
    - UI atualiza ExerciseSessionCard com dados do novo exercício e primeira série aberta para input

### 3. **Início do Série**

    - Quando um novo exercício é iniciado (automaticamente no início do treino ou manualmente durante a execução), o sistema inicia **automaticamente a primeira série** do exercício. Isso garante que **sempre exista ao menos um SetCard visível na UI**, representando a primeira série em andamento.

    - Para a primeira série:
        - `StartSetUseCase.swift` é executado:
            - Cria `CDCurrentSet` com `order = 1` e status inicial (não finalizada).
            - Persiste dados básicos da série.
            - Inicia o cronômetro da série no `TimerService.swift`.
            - Ativa sensores no `MotionManager.swift` e captura de heart rate/calorias pelo `HealthKitManager.swift`.
        - A UI exibe o primeiro `SetCard` no `ExerciseSessionCard`, permitindo que o usuário configure os detalhes antes de executar a série:
            - Pode editar o peso desejado.
            - Pode definir a meta de repetições (`targetReps`).
            - Se premium, o campo RC (`actualReps`) é atualizado automaticamente pelo algoritmo ML à medida que o usuário executa a série.
            - Se não-premium, o campo RC permanece sempre como `0` (não exibindo repetições automáticas).

    - Durante esta fase inicial da série, o sistema não força a contagem imediata de tempo para analytics — o tempo do cronômetro já está rodando, mas a expectativa é que o usuário configure os campos necessários antes de iniciar fisicamente a execução da série.

    - Além disso, o usuário pode:
        - Adicionar novas séries a qualquer momento usando o botão “Adicionar Série +”.
            - Cada clique chama `StartSetUseCase.swift`, criando e exibindo um novo `SetCard` abaixo dos existentes.
            - Para não-premium, o número máximo de séries por exercício é 3; ao exceder, a UI exibe um modal/call-to-action para upgrade premium.
        - Editar individualmente os campos de cada série já adicionada (peso, target reps, RC se manual).

    - Ou seja: a primeira série é sempre criada e iniciada por padrão, mas a UI oferece flexibilidade para o usuário ajustar todos os detalhes antes de efetivamente começar a execução — tornando a experiência fluida e não “urgente”.


### 4. **Execução da Série + Detecção Automática de Fim de Série**

- Durante a série:
    - MotionManager.swift (Watch): coleta sensores (50Hz), bufferiza, envia chunks (100 amostras) via WatchSessionManager.swift
    - Detecção automática:
        - MotionManager detecta descanso, chama updatePhase(.rest) em WorkoutPhaseManager.swift
        - WorkoutPhaseManager atualiza fase, notifica WatchSessionManager.swift
        - WatchSessionManager envia evento para PhoneSessionManager.swift (iPhone)
        - PhoneSessionManager → WorkoutSessionViewModel.swift exibe modal para usuário confirmar fim de série (ou segue fluxo manual)
    - HealthKitManager.swift: coleta/atualiza heart rate/calorias a cada 2s
    - UI permite editar peso, repetições, finalizar manualmente ou automaticamente a série

### 5. **Finalização de Série (Manual ou Automática) + Loop para Nova Série**

- Uma série em andamento pode ser finalizada de várias formas, dependendo do contexto e da ação do usuário:

✅ **Manual via UI**  
  - O usuário toca no botão de status no `SetCard` (checkmark) para marcar a série como concluída manualmente.  
  - Atualiza o status de `CDCurrentSet` para finalizada.  
  - Encerra cronômetro da série no `TimerService.swift`.

✅ **Detecção Automática**  
  - Algoritmo (MotionManager) detecta pausa de movimento.  
  - Dispara modal na UI para o usuário confirmar se terminou.  
  - Se confirmado, atualiza status e encerra a série.  
  - Inicia o timer de descanso descontando os 10s de espera.

✅ **Início de Timer de Descanso**  
  - O usuário toca no botão “Iniciar Timer” no `workoutStatusSection`.  
  - Ação implícita: considera que o usuário terminou a execução da série atual.  
  - Atualiza o status da série no `CDCurrentSet` para finalizada.  
  - Encerra cronômetro da série (`TimerService.swift`) e inicia o cronômetro de descanso no mesmo serviço.  
  - Atualiza a UI para estado de descanso.

- Após a finalização da série, independente do método:
  - `EndSetUseCase.swift` é chamado:  
    - Atualiza `CDCurrentSet` para status finalizada (temporário).  
    - Persiste os dados completos no histórico criando um novo `CDHistorySet`:  
      - Reps (`targetReps`)  
      - Peso  
      - RC (`actualReps`)  
      - Repetições Processadas (`repsCounterData`)  
      - Dados de sensores brutos  
      - Heart rate/calorias:  
        - Serializa os arrays temporários (`heartRateTimeline` e `caloriesTimeline`) em JSON convertido para `Data` e preenche os atributos `heartRateData` e `caloriesData`.  
        - Preenche também `startTime` e `endTime` com as horas reais da série.  
    - Encerra o cronômetro da série no `TimerService.swift`.  
    - Remove ou reseta o `CDCurrentSet` para preparar para uma nova série.  
  - A UI atualiza o `SetCard` para status finalizado (checkmark).

---

### 6. **Troca da Ordem de Exercícios – Reatividade e Pausa/Ativação**

- Usuário reordena exercícios em exerciseListSection (drag-and-drop):
    - Se houver série/exercício em andamento:
        - UI exibe modal de confirmação: "Deseja iniciar outro exercício? Série atual será pausada."
        - Se confirmado:
            - Exercício/série ativo é pausado (status atualizado em CDCurrentExercise/CDCurrentSet)
            - StartExerciseUseCase é chamado para o exercício agora em primeiro na lista
            - StartSetUseCase é chamado para iniciar a primeira série do novo exercício
            - UI atualiza ExerciseSessionCard para refletir o novo exercício e série
    - Persistência e lógica garantem continuidade/resumibilidade do exercício pausado se usuário retornar depois

### 7. **Finalização de Exercício**

- Quando o exercício é finalizado (todas as séries concluídas ou manualmente):
  - `EndExerciseUseCase.swift` é chamado:  
    - Atualiza/persiste `CDCurrentExercise` (status, estatísticas, cronômetro)  
    - Agrega os dados das séries (`CDHistorySet`) do exercício para compor a evolução geral do exercício.  
    - Serializa os arrays agregados em JSON convertido para `Data` e preenche os atributos `heartRateData` e `caloriesData` no `CDHistoryExercise`.  
    - Preenche `startTime` e `endTime` com as horas reais do exercício.  
  - UI marca exercício como concluído em `exerciseListSection`.  
  - Se houver exercícios restantes, fluxo segue para o próximo automaticamente (`StartExerciseUseCase → StartSetUseCase`), senão segue para finalização de treino.

---

### 8. **Finalização de Treino**

- Quando o treino é finalizado:
  - `EndWorkoutUseCase.swift` é chamado:  
    - Atualiza/persiste `CDCurrentSession` como finalizada.  
    - Calcula estatísticas finais, encerra sensores, timers, HealthKit.  
    - Agrega os dados de todos os `CDHistoryExercise` para compor a evolução geral do treino.  
    - Serializa os arrays agregados em JSON convertido para `Data` e preenche os atributos `heartRateData` e `caloriesData` no `CDWorkoutHistory`.  
    - Preenche `startTime` e `endTime` com as horas reais do treino.  
  - UI exibe resumo/fim de treino.  
  - Contexto final é sincronizado com Watch (se aplicável).

## 📈 Atualização do `HealthKitManager.swift`

- Responsável também por configurar e gerenciar:
  - `HKAnchoredObjectQuery` para capturar `heartRate` (BPM) continuamente, convertendo `HKQuantity` para count/min.
  - `HKLiveWorkoutBuilder` + `HKLiveWorkoutDataSource` para monitorar `activeEnergyBurned` (kcal) continuamente.
- Ambos os fluxos escrevem em arrays temporários em memória com a estrutura:

```swift
struct MetricSample {
    let timestamp: Double // segundos desde startTime do nível
    let value: Double
}
```
- Arrays temporários durante o treino:
  - heartRateTimeline: [MetricSample]
  - caloriesTimeline: [MetricSample]

### 📦 Persistência no Core Data

- Ao finalizar cada nível (série, exercício ou treino), os arrays temporários são serializados para JSON e armazenados nos seguintes níveis:
  - `CDHistorySet`
  - `CDHistoryExercise`
  - `CDWorkoutHistory`

- Formato do JSON salvo nos atributos binários:

```json
{
  "startTime": "2025-07-17T14:30:00Z",
  "samples": [
    { "timestamp": 0.0, "value": 123 },
    { "timestamp": 1.0, "value": 124 }
  ]
}
```

- `startTime` é a hora real (Date) de início do nível correspondente.
- `timestamp` é o número de segundos decorridos desde `startTime`.

- Atributos persistidos nas entidades:

```swift
@NSManaged var startTime: Date?
@NSManaged var endTime: Date?
@NSManaged var heartRateData: Data?
@NSManaged var caloriesData: Data?
```

- Definidos com `allowsExternalBinaryDataStorage = YES`.
- O `WorkoutDataService` é responsável por serializar/deserializar os arrays temporários e armazenar/ler os binários para histórico.

## Fluxo Técnico de Dados e Pipeline de Captação

[Watch: MotionManager.swift] (captura, chunking) 
    → [WatchSessionManager.swift] (envio) 
    → [PhoneSessionManager.swift] (recebe, processa) 
    → [UpdateDataToMLUseCase.swift] (orquestra processamento) 
    → [MLModelManager.swift] (ML, rep counting)
    → [WorkoutSessionViewModel.swift] (estado reativo, publishers)
    → [WorkoutSessionView.swift] (UI, gráficos, feedback)
    ↔ [CoreDataAdapter.swift] / [WorkoutDataService.swift] (persistência)
    → [SubscriptionManager.swift] (controle premium/free via publishers)
    → [LocationManager.swift] (localização opcional)
    → [HealthKitManager.swift] (heart rate/calorias, captura e envio)


### 🗄️ Estrutura CoreData para Sensores, ML e Histórico

O sistema utiliza entidades temporárias (`CDCurrent*`) durante o treino ativo e migra os dados para entidades históricas (`CDHistory*`) ao final de cada série, exercício ou treino.  
A persistência é resiliente: suporta downgrade (premium → free) e upgrade (free → premium) sem perda de dados.

---

### 📊 Entidades Temporárias (durante o treino ativo)

- **`CDCurrentSession`**
  - Sessão ativa do treino.
  - Relaciona-se com exercícios e séries atuais.
  - Armazena: início, localização opcional, cronômetro global, status atual.

- **`CDCurrentExercise`**
  - Exercício ativo atual.
  - Relacionado às séries desse exercício.
  - Guarda: nome, ordem, status parcial, cronômetro do exercício.

- **`CDCurrentSet`**
  - Série do exercício ativo.
  - Armazena:
    - `order`: número da série
    - `weight`: peso definido
    - `targetReps`: objetivo de repetições
    - `actualReps`: detectadas manualmente ou via ML
    - `status`: finalizada/não finalizada
  - Durante execução, a timeline (`repsCounterData`) e os sensores brutos (`sensorData`) ficam em **cache na memória**.
  - Durante execução, também ficam em cache os arrays de métricas cardíacas e calóricas:
    - `heartRateTimeline: [MetricSample]`
    - `caloriesTimeline: [MetricSample]`

---

### 🪵 Entidades Históricas (após finalização)

Quando uma série, exercício ou treino é concluído, os dados são migrados para as entidades históricas:

- **`CDHistorySession`**
  - Sessão completa no histórico.
  - Inclui: informações globais, localização (se permitida), permissões no momento da conclusão.

- **`CDHistoryExercise`**
  - Exercícios finalizados da sessão.
  - Relacionado às séries concluídas.
  - Armazena evolução agregada das métricas cardíacas e calóricas serializadas.

- **`CDHistorySet`**
  - Séries finalizadas.
  - Salva todos os detalhes:
    - `actualReps`
    - `weight`, `targetReps`, `order`
    - `repsCounterData`: JSON da timeline do movimento detectado pelo ML.
    - `heartRateData`: batimentos ao longo da série (JSON serializado em `Data`).
    - `caloriesData`: calorias gastas (JSON serializado em `Data`).
    - `sensorData`: chunks brutos (opcional, para análise).

---

### 📈 Captura de Frequência Cardíaca e Calorias

Durante o treino ativo:
- `HealthKitManager` inicia:
  - `HKAnchoredObjectQuery` para capturar `heartRate` (BPM) continuamente.
  - `HKLiveWorkoutBuilder` com `HKLiveWorkoutDataSource` para `activeEnergyBurned` (kcal) continuamente.
- Ambas as métricas alimentam arrays temporários em memória com a seguinte estrutura:

```swift
struct MetricSample {
    let timestamp: Double // segundos desde startTime do nível
    let value: Double
}
```

Ao finalizar um nível (série, exercício ou treino), os arrays são serializados em JSON e salvos nos atributos binários correspondentes, junto a startTime e endTime.

### 🌟 Upgrade Premium

- Todos os dados detalhados são sempre coletados e salvos, independentemente do status premium.
- Para usuários free, a UI não exibe a contage de Repetições (RC) e nem gráficos/timelines detalhados.
- Upgrade premium dá **acesso imediato** a todo histórico detalhado já salvo.

---

### 🛡️ Persistência Resiliente

- Projetada para manter integridade mesmo com mudanças de permissões:
  - Downgrade: apenas oculta visualização premium, dados permanecem.
  - Upgrade: libera acesso instantâneo.
- Campos opcionais (como repsCounterData, heartRateData, caloriesData) são preenchidos quando possível.
- O sistema nunca descarta dados coletados.

---

### 📊 Visualização no Histórico

- Na visualização histórica:
  - Os binários (heartRateData e caloriesData) são deserializados para reconstruir os arrays [MetricSample] para cada nível.
  - A UI exibe gráficos de linha mostrando a evolução ao longo de:
    - Cada série (CDHistorySet)
    - Cada exercício (CDHistoryExercise)
    - Treino completo (CDWorkoutHistory)
  - Métricas exibidas: Frequência cardíaca (BPM) e Calorias gastas (kcal).

### Resumo

| Entidade             | Quando é usada    | O que contém                                               |
|----------------------|-------------------|------------------------------------------------------------|
| `CDCurrentSession`   | Durante treino    | Sessão ativa, status global, link com exercícios.          |
| `CDCurrentExercise`  | Durante treino    | Exercício ativo, status, link com séries.                  |
| `CDCurrentSet`       | Durante treino    | Série ativa, básicos (`weight`, `targetReps`, `actualReps`)|
| `CDHistorySession`   | Histórico         | Sessão finalizada, localização, permissões no momento.     |
| `CDHistoryExercise`  | Histórico         | Exercícios finalizados com status e séries.                |
| `CDHistorySet`       | Histórico         | Séries finalizadas com todos os detalhes, incluindo ML.    |

## Observações Finais

- Início do treino SEMPRE executa em sequência: StartWorkoutUseCase → StartExerciseUseCase → StartSetUseCase para o primeiro exercício/série da lista atual.

- Mudanças de ordem na exerciseListSection pausam exercício/série ativo, atualizam o card da currentExerciseSection e iniciam o exercício que ficou em primeiro na lista.

- Lógica reativa: qualquer alteração (ordem, entrada manual, conclusão automática, premium, hardware) é refletida instantaneamente na UI e sincronizada via ViewModel/UseCases.

- Todo o pipeline, desde sensores até persistência, está desacoplado, resiliente e preparado para expansão futura.

# WorkoutSessionView – Estrutura de UI e Lógica de Início do Treino

---

## Estrutura de `WorkoutSessionView`

A `WorkoutSessionView` é a tela principal para acompanhamento e execução do treino ativo.  
Sua estrutura é dividida em quatro seções principais, compondo uma experiência flexível, responsiva e personalizável para cada usuário.

---

### 1. **headerSection**

- **Botão Voltar (esquerda):**
  - Retorna para `HomeView`
  - Mantém o treino ativo ao sair da tela

- **Título Central:**
  - Exibe o nome do treino (`autoTitle` de `CDWorkoutPlan` selecionado)
  - Dinâmico, refletindo sempre o plano iniciado

- **Botão Configuração (`ellipsis.circle.fill`, direita):**
  - Abre sheet/modal de configuração rápida do treino (ex: definir séries padrão por exercício, editar plano)
  - Permite ao usuário personalizar detalhes do treino a qualquer momento

---

### 2. **workoutStatusSection**

- **WorkoutStatusCard:**
  - Relatório geral do treino ativo:
    - Nome do treino
    - Grupos musculares
    - Progresso do treino (exercícios/séries)
    - Cronômetro global (tempo total da sessão, controlado por `TimerService.swift`)
    - Calorias gastas totais (dados de `HealthKitManager.swift`)
    - Heart rate ao vivo (dados de `HealthKitManager.swift`)
  - **Diferença de contexto:**
    - Na `HomeView.swift` (estado “ActiveWorkout”): exibe botão “Ver” ao lado do nome do treino, levando à `WorkoutSessionView`
    - Na `WorkoutSessionView.swift`: esse botão é ocultado

- **Botões de Ação (abaixo do card):**
  - **PAUSAR:** Pausa o cronômetro global do treino
  - **FINALIZAR:** Finaliza imediatamente o treino ativo
  - Ambos na mesma linha para acesso rápido

- **Botão "INICIAR TIMER":**
  - Abaixo dos botões principais
  - Inicia timer de descanso padrão (1:30 min por default)
  - Ação rápida para intervalos/pausas durante o treino

---

### 3. **currentExerciseSection**

- **ExerciseSessionCard:**
  - Card dinâmico para o exercício atual (determinado pela ordem em `exerciseListSection`)
  - Exibe:
    - Nome do exercício atual
    - Lista de SetCards (séries) definidas pelo usuário (mínimo 1)
  - **SetCard (dentro de ExerciseSessionCard):**
    - Número da série (reflete atributo `order` em `CDCurrentSet`)
    - Campo Peso (editável, salva em `weight` de `CDCurrentSet`)
    - Campo Repetições (editável, salva em `targetReps` de `CDCurrentSet`)
    - Campo RC (Reps Counter, editável, salva em `actualReps` de `CDCurrentSet`)
    - Campo Status (botão círculo):
      - Vazio = não finalizada
      - Preenchido + checkmark = série finalizada (manual ou automática)
      - Clique encerra a série (atualiza status/persistência)
  - **Botão "Adicionar Série +":**
    - Sempre visível abaixo da última série
    - Adiciona nova série (limitado a 3 para não-premium; ilimitado para premium)
    - Exibe modal/call-to-action ao exceder o limite para não-premium

---

### 4. **exerciseListSection**

- Lista todos os exercícios do treino
- **Cards de exercícios (`ExerciseCard.swift`):**
  - Separação entre exercícios concluídos e ativos
  - Exercício ativo é destacado
  - **Drag-and-drop** habilitado para reordenar exercícios não concluídos
    - Exige confirmação se houver série em andamento (exibe modal: “Iniciar outro exercício? Série atual será pausada”)
    - Troca rápida pausa o exercício atual, inicia o novo selecionado

---

## **Lógica de Início e Controle do Treino**

### 1. **Início do Treino**

- Usuário clica em "Iniciar Treino":
  - Pode ser pelo card principal (`WorkoutStatusCard` em estado `NextWorkout` na `HomeView.swift`)
  - Ou pelo card do treino (`WorkoutPlanCard.swift` em `HomeView.swift` ou `WorkoutView.swift`)
- No Watch, lógica equivalente: treino iniciado diretamente exibe o primeiro exercício e primeira série
- **Imediatamente:**
  - Primeiro exercício da lista (`exerciseListSection`) é exibido no `ExerciseSessionCard`
  - Primeira série do exercício já é iniciada, aguardando input do usuário

### 2. **Durante a Série**

- Usuário pode inserir peso, repetições e RC (reps counter) manualmente ou por detecção automática (premium)
- Pode clicar no botão de configuração (ellipsis) a qualquer momento para definir número padrão de séries
- Pode usar botão "Adicionar Série +" para inserir mais séries (respeita limites premium)

### 3. **Troca de Exercício**

- Usuário pode reordenar a lista via drag-and-drop (`exerciseListSection`)
  - Se tentar começar outro exercício com uma série em andamento, exibe modal de confirmação:
    - “Deseja iniciar outro exercício? Série atual será pausada.”
  - Se confirmado:
    - Exercício ativo fica pausado (status persistido)
    - Novo exercício selecionado é exibido no `ExerciseSessionCard`
    - Primeira série do novo exercício é iniciada

### 4. **Finalização e Loop de Séries**

- A cada finalização de série:
  - Marca a série como concluída (manual ou automaticamente, botão checkmark)
  - Se há séries restantes ou usuário adiciona nova, repete loop (nova série iniciada)
  - Ao finalizar todas as séries ou usuário clicar “Finalizar Exercício”, parte para o próximo exercício
  - Usuário pode navegar livremente entre exercícios não concluídos (com modais de confirmação)
- Ao finalizar todos os exercícios, fluxo finaliza o treino

---

## **Referência de Arquivos na View**

- **WorkoutSessionView.swift:** Composição da tela, integração com ViewModel, gerenciamento de navegação e interação UI.
- **WorkoutSessionViewModel.swift:** Estado da UI, publishers, lógica de exibição/habilitação de botões e limites premium.
- **WorkoutStatusCard.swift:** Card de status e relatórios do treino.
- **ExerciseSessionCard.swift:** Card do exercício atual, lista dinâmica de SetCards.
- **SetCard.swift:** Cada série do exercício, inputs editáveis, status e checkmark.
- **ExerciseCard.swift:** Cards da lista de exercícios, suporte a drag-and-drop.
- **HomeView.swift/WorkoutView.swift:** Fluxo de navegação e seleção de treinos.
- **WorkoutPlanCard.swift:** Card dos planos na Home/WorkoutView, inicia o fluxo ao tocar.

---

## **Observações Técnicas**

- Todos os dados editados/refletidos nos cards de série são sincronizados com CoreData via ViewModel/UseCases.
- Limites premium (número de séries) são controlados na ViewModel, exibindo modais/call-to-action ao atingir o máximo.
- Troca de exercícios ativa persistência de status atual antes da transição.
- UI e ViewModel sempre reagem a permissões premium (RevenueCat/publishers).
- Permissões de hardware (HealthKit, localização) afetam status dos cards em tempo real.
- Cronômetros, timers e progresso são sempre controlados e exibidos pelo `TimerService.swift`.

---

> **Este design garante UX intuitiva, performance, flexibilidade para upgrades, e arquitetura escalável para manutenção futura.**
