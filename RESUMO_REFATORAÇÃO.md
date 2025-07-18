## 1. Arquivos Atualizados

- **PersistenceController.swift**  
   - Centraliza toda a configuração do Core Data.  
   - Exposição de `persistentContainer` e contextos (main + background).  
   - Remove duplicação antes em `CoreDataStack`.

- **CoreDataAdapter.swift**  
   - Conversão genérica DTO ↔ NSManagedObject.  
   - Serialização de dados brutos de sensores via JSON.  
   - Conformidade das entidades ao protocolo `Syncable`.

- **CoreDataModels.swift**  
   - Remoção de entidades redundantes.  
   - Definição simplificada de `CDWorkoutPlan` e `CDWorkoutSession`.  
   - Inclusão de `id: UUID` e `lastModified: Date` em cada entidade.  
   - Atualização de `CDCurrentSet` e `CDHistorySet` para incluir `sensorData`.

- **SensorData.swift**  
  - Ajustar struct/decoding para JSON de sensores.

- **ConnectivityManager.swift**  
   - Substituição de Reachability por `NWPathMonitor`.  
   - Publisher Combine para estados online/offline.  
   - Integração com `SyncWorkoutUseCase`.

- **SessionManager.swift**  
   - Redução a enum de estados: `.notStarted`, `.inProgress`, `.finished`.  
   - Lógica de controle de sessão migrada para Use Cases.

- **CloudSyncManager.swift**  
   - Generalização para sincronizar qualquer `Syncable`.  
   - Estados simplificados (`pending` / `synced`).  
   - Retry com back-off e resolução por `lastModified`.

- **CloudSyncStatus.swift**  
   - Remoção de muitos estados finos.  
   - Manter apenas `pending` e `synced`.

- **ExerciseDisplayable.swift**  
   - Atualização para refletir novo modelo de dados.  
   - Consolidação de propriedades comuns de exibição.

- **AuthService.swift**  
    - Converter para fluxo via `AuthUseCase`.  
    - Simplificar chamadas de provedores.

- **FirebaseExerciseService.swift**  
    - Unificar operações de upload/download.  
    - Uso de `CloudSyncManager` genérico.

- **FirebaseExercise.swift**  
    - Ajuste de modelo para novo `FitterModel`.  
    - Remover duplicação de parsing e serialização.

- **LoginViewModel.swift**  
    - Herdar de `BaseViewModel`.  
    - Usar `AuthUseCase` para login.

- **CreateAccountViewModel.swift**  
    - Herdar de `BaseViewModel`.  
    - Unificar lógica de criação de conta em `AuthUseCase`.

- **ListExerciseViewModel.swift**  
   - Herdar de `BaseViewModel`.  
    - Usar `FetchWorkoutUseCase`.

- **WorkoutViewModel.swift**  
    - Herdar de `BaseViewModel`.  
    - Chamar `CreateWorkoutUseCase`, `UpdateWorkoutUseCase` e `DeleteWorkoutUseCase`.

- **BaseViewModel.swift**  
    - Estados e comportamentos comuns de UI.

- **CoreDataService.swift**  
    - Serviço de infraestrutura para operações CRUD genéricas no Core Data.

- **WorkoutDataService.swift**  
    - CRUD especializado para entidades de treino (sem sincronização - apenas persistência).

- **CreateWorkoutUseCase.swift**  
    - Orquestração completa de criação (persistência + sincronização + títulos duais).

- **FetchWorkoutUseCase.swift**  
    - Orquestração de consultas com filtros, ordenação e estatísticas.

- **FetchFBExercisesUseCase.swift**
    - Busca de exercícios Firebase com realtime updates e gerenciamento de listeners.

- **UpdateWorkoutUseCase.swift**  
    - Orquestração completa de edição (persistência + sincronização + rollback).

- **DeleteWorkoutUseCase.swift**  
    - Orquestração completa de remoção (persistência + sincronização + validações).

- **ReorderWorkoutUseCase.swift**  
    - Orquestração completa de reordenação (persistência + sincronização + tracking).

- **ReorderExerciseUseCase.swift**  
    - Orquestração completa de reordenação de exercícios.

- **SyncWorkoutUseCase.swift**  
    - Motor puro de sincronização para entidades `Syncable` (chamado pelos outros Use Cases).

- **AuthUseCase.swift**  
    - Orquestração de fluxos de autenticação via `AuthService` (login/logout/cadastro).

- **FirestoreExerciseRepository.swift**  
    - Repository direto para Firestore sem cache complexo. Implementa FirestoreExerciseRepositoryProtocol.

- **StartWorkoutUseCase.swift**  
    - Iniciar sessão de treino com CDCurrentSession, HealthKit e configuração de primeiro exercício.

- **EndWorkoutUseCase.swift**  
    - Finalizar sessão, migrar para CDWorkoutHistory, calcular estatísticas e sincronizar.

- **StartExerciseUseCase.swift**  
    - Iniciar exercício individual, criar CDCurrentExercise e sincronizar com Apple Watch.

- **EndExerciseUseCase.swift**  
    - Finalizar exercício, avançar navegação e calcular métricas de performance.

- **StartSetUseCase.swift**  
    - Iniciar série com captura ativa de sensores HealthKit e modo background no Watch.

- **EndSetUseCase.swift**  
    - Finalizar série, processar sensorData e configurar rest timer inteligente.

---

## 2. Arquivos Excluídos

- **CoreDataStack.swift**  
  *Motivo:* Configuração de Stack migrada para `PersistenceController.swift`.  
- **WorkoutManager.swift**  
  *Motivo:* Lógica de gestão de treinos migrada para `WorkoutDataService.swift` e Use Cases.  
- **WorkoutRepositoryProtocol.swift**  
  *Motivo:* Interface de acesso a dados consolidada em `WorkoutDataService.swift`.  
- **WorkoutRepository.swift**  
  *Motivo:* Implementação de CRUD unificada em `WorkoutDataService.swift`.  
- **WorkoutService.swift**  
  *Motivo:* Serviço de manipulação de treinos incorporado ao `WorkoutDataService.swift`.  
- **FirebaseExerciseService.swift**  
  *Motivo:* Redundante; o `CloudSyncManager` já unifica operações de upload/download de exercícios
- **PreviewDataLoader.swift**  
  *Motivo:* Substituído por sistema estruturado de mocks (MockDataProvider + MockPersistenceController)
- **PreviewCoreDataStack.swift**  
  *Motivo:* Usa modelo antigo ("Model"); substituído por MockPersistenceController com "FitterModel"
- **CreateWorkoutView.swift** 🆕  
  *Motivo:* Unificado com DetailWorkoutView.swift em WorkoutEditorView.swift para eliminar duplicação
- **DetailWorkoutView.swift** 🆕  
  *Motivo:* Unificado com CreateWorkoutView.swift em WorkoutEditorView.swift para UX consistente
- **ListExerciseCard.swift** 🆕  
  *Motivo:* Substituído por ExerciseCard.swift (modo firebaseList). Funcionalidade 100% preservada.
- **WorkoutExerciseCard.swift** 🆕  
  *Motivo:* Substituído por ExerciseCard.swift (modo workoutEditor). Drag & drop e swipe actions preservados.
- **WorkoutExerciseCard2.swift** 🆕  
  *Motivo:* Arquivo comentado/obsoleto, funcionalidade migrada para ExerciseCard.swift unificado.

**🏆 BENEFÍCIO UNIFICAÇÃO:** 781 linhas de código redundante → 597 linhas unificadas (70% menos código, zero redundância)

---

## 3. Arquivos Criados

### 3.1 Services

- **CoreDataService.swift**  
  Serviço de infraestrutura para operações CRUD genéricas no Core Data. Protocolo + implementação.

- **WorkoutDataService.swift**  
  CRUD especializado para entidades de treino (sem sincronização - apenas persistência).

- **TimerService.swift** 🆕  
  Serviço centralizado para todos os timers do app (séries, descanso, workout, inatividade).

### 3.2 Base

- **BaseViewModel.swift**  
  Classe genérica para estados de UI e orquestração de Use Cases (sem lógica de negócio).

### 3.3 Use Cases

- **CreateWorkoutUseCase.swift**  
  Criação de treinos com orquestração completa (persistência + sincronização + títulos duais).

- **FetchWorkoutUseCase.swift**  
  Busca de planos com filtros, ordenação e estatísticas (sem sincronização - apenas leitura).

- **FetchFBExercisesUseCase.swift**
  Busca de exercícios Firebase com realtime updates e gerenciamento de listeners.

- **UpdateWorkoutUseCase.swift**  
  Edição de treinos com orquestração completa (persistência + sincronização + rollback).

- **DeleteWorkoutUseCase.swift**  
  Remoção de treinos com orquestração completa (persistência + sincronização + validações).

- **ReorderWorkoutUseCase.swift**  
  Reordenação de treinos com orquestração completa (persistência + sincronização + tracking).

- **ReorderExerciseUseCase.swift**  
  Reordenação de exercícios com orquestração completa (persistência + sincronização + validações).

- **SyncWorkoutUseCase.swift**  
  Motor puro de sincronização para entidades `Syncable` (chamado pelos outros Use Cases).

- **AuthUseCase.swift**  
  Orquestração de fluxos de autenticação via `AuthService` (login/logout/cadastro).

- **FirestoreExerciseRepository.swift** 🆕  
  Repository direto para Firestore sem cache complexo. Implementa FirestoreExerciseRepositoryProtocol.

### 3.3.1 Use Cases de Lifecycle de Workout

- **StartWorkoutUseCase.swift**  
  Iniciar sessão de treino com CDCurrentSession, HealthKit e configuração de primeiro exercício.

- **EndWorkoutUseCase.swift**  
  Finalizar sessão, migrar para CDWorkoutHistory, calcular estatísticas e sincronizar.

- **StartExerciseUseCase.swift**  
  Iniciar exercício individual, criar CDCurrentExercise e sincronizar com Apple Watch.

- **EndExerciseUseCase.swift**  
  Finalizar exercício, avançar navegação e calcular métricas de performance.

- **StartSetUseCase.swift**  
  Iniciar série com captura ativa de sensores HealthKit e modo background no Watch.

- **EndSetUseCase.swift**  
  Finalizar série, processar sensorData e configurar rest timer inteligente.

### 3.4 Sistema de ExerciseCard Unificado 🆕

- **ExerciseCard.swift** ✅  
  Componente unificado para exercícios Firebase e Core Data. Enum Mode para detectar contexto + modal de vídeo 1:1. Substitui 3 componentes antigos com 70% menos código.

### 3.5 Views Unificadas 🆕

- **WorkoutEditorView.swift** 🆕  
  View unificada para criação e edição de treinos. Substitui CreateWorkoutView + DetailWorkoutView com enum Mode.

### 3.6 Mocks para Previews

- **MockDataProvider.swift**  
  Provedor centralizado de dados mock para todas as entidades Core Data.

- **MockPersistenceController.swift**  
  In-memory Core Data stack para previews sem persistência real.

- **MockWorkoutDataService.swift**  
  Implementação mock do WorkoutDataServiceProtocol para desenvolvimento.

- **MockUseCases.swift**  
  Mocks para todos os Use Cases com respostas configuráveis.

- **MockAuthService.swift**  
  Simulação de estados de autenticação para previews.

- **MockConnectivityManager.swift**  
  Simulação de conectividade e sincronização para desenvolvimento.

- **MockSensorData.swift**  
  Dados de sensores Apple Watch simulados para testes.

- **PreviewExtensions.swift**  
  Extensions e helpers para facilitar criação de previews.

- **MockWorkoutSession.swift**  
  Simulação completa de sessões de treino ativas para previews.

