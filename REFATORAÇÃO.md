# Plano de Refatoração do Projeto Fitter

**Importante:** Esta refatoração **NÃO** inclui o uso de **CloudKit**. Toda sincronização em nuvem será realizada via **Firestore**, e a comunicação com o Apple Watch ocorrerá por **WatchConnectivity** e Core Data.

## 🔒 ARQUITETURA: LOGIN OBRIGATÓRIO + SESSÃO PERSISTENTE + LOGOUT POR INATIVIDADE

> **DECISÃO FINAL:** App com login obrigatório na primeira vez, sessão persistente, mas logout automático após 7 dias de inatividade por segurança.

### **📱 FLUXO:**
1. **Primeira vez**: Login obrigatório
2. **Próximas vezes**: Continua logado automaticamente
3. **Logout manual**: Botão no perfil
4. **🆕 Logout automático**: Após 7 dias sem abrir o app
5. **Dados**: Sempre vinculados ao usuário autenticado

### **🏗️ IMPLICAÇÕES TÉCNICAS:**
- **BaseViewModel.currentUser**: `CDAppUser!` (nunca nil após login)
- **Use Cases**: Todos com `user: CDAppUser` (obrigatório, sem ?)
- **Core Data**: Relações obrigatórias garantem ownership
- **AuthService**: Persistência via Keychain, restaura sessão automaticamente
- **🆕 Inatividade**: `lastAppOpenDate` no Keychain, verificação no app launch
- **🆕 Segurança**: Logout automático + limpeza de sessões ativas após 7 dias

### **🛡️ BENEFÍCIOS DE SEGURANÇA:**
- **Dispositivos perdidos/roubados**: Proteção automática de dados pessoais
- **Uso compartilhado**: Evita acesso não autorizado a dados de treino
- **Compliance**: Padrão em apps de saúde/fitness para proteção de dados
- **Privacidade**: Dados sensíveis não expostos indefinidamente

## Estratégia de Injeção de Dependências

> Usar apenas **@StateObject** no `App` e **@EnvironmentObject** nas Views, removendo qualquer outra forma de injeção.

1. No `iOSApp` (entry point):
   ```swift
    @main
    struct FitterApp: App {
    // 1. Instanciar infra‐estrutura compartilhada
    let persistence        = PersistenceController.shared
    let coreDataService    = CoreDataService(
                             viewContext: persistence.viewContext,
                             backgroundContext: persistence.backgroundContext
                           )
    let cloudSyncManager   = CloudSyncManager.shared
    let authService        = AuthService() as AuthServiceProtocol

    // 2. Criar repositórios específicos
    let exerciseRepository = FirestoreExerciseRepository(syncManager: cloudSyncManager)

    // 3. Construir Use Cases, injetando exatamente o que precisam
    let fetchFBExercisesUC = FetchFBExercisesUseCase(repository: exerciseRepository)
    let authUC             = AuthUseCase(service: authService)
    let syncWorkoutUC      = SyncWorkoutUseCase(syncManager: cloudSyncManager)

    let workoutDataService = WorkoutDataService(coreDataService: coreDataService)
    let createWorkoutUC    = CreateWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let fetchWorkoutUC     = FetchWorkoutUseCase(workoutDataService: workoutDataService)
    let updateWorkoutUC    = UpdateWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let deleteWorkoutUC    = DeleteWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let reorderWorkoutUC   = ReorderWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let reorderExerciseUC  = ReorderExerciseUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )

    // 3.2. Use Cases de Lifecycle de Workout (novo)
    let startWorkoutUC     = StartWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let endWorkoutUC       = EndWorkoutUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )
    let startExerciseUC    = StartExerciseUseCase(
                              workoutDataService: workoutDataService
                            )
    let endExerciseUC      = EndExerciseUseCase(
                              workoutDataService: workoutDataService
                            )
    let startSetUC         = StartSetUseCase(
                              workoutDataService: workoutDataService
                            )
    let endSetUC           = EndSetUseCase(
                              workoutDataService: workoutDataService,
                              syncUseCase: syncWorkoutUC
                            )

    // 4. Criar ViewModels como @StateObject, passando os Use Cases
    @StateObject private var authVM = AuthViewModel(useCase: authUC)
    @StateObject private var listVM = ListExerciseViewModel(fetchUseCase: fetchFBExercisesUC)
    @StateObject private var workoutVM = WorkoutViewModel(
      createUseCase: createWorkoutUC,
      fetchUseCase: fetchWorkoutUC,
      updateUseCase: updateWorkoutUC,
      deleteUseCase: deleteWorkoutUC,
      reorderWorkoutUseCase: reorderWorkoutUC,
      reorderExerciseUseCase: reorderExerciseUC,
      syncUseCase: syncWorkoutUC
    )

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(authVM)
                .environmentObject(listVM)
                .environmentObject(workoutVM)
            }
        }
    }

2. Nas Views filhas, sempre use:
   ```swift
   struct AnyView: View {
  @EnvironmentObject var viewModel: AnyViewModel
  // …
}

3. Remova de todas as subviews:
   - @StateObject local de ViewModels
   - Inicializações via init(vm:)
   - @ObservedObject para injeção de ViewModels

Para acompanhar o progresso da refatoração, use a lista cronológica abaixo e marque cada item quando concluído.

________________________________________________________

**📊 PROGRESSO:** 43/105 itens concluídos (41%)

**🔧 PENDÊNCIAS:** 34/78 pendências concluídas (44%)
________________________________________________________

## 0. Ordem Cronológica de Refatoração (105 itens)

> Siga esta sequência rigorosamente. Marque cada item com [x] quando concluído.

1. [x] 🗑️ **Excluir** CoreDataStack.swift  
2. [x] 🗑️ **Excluir** WorkoutManager.swift  
3. [x] 🗑️ **Excluir** WorkoutRepositoryProtocol.swift  
4. [x] 🗑️ **Excluir** WorkoutRepository.swift  
5. [x] 🗑️ **Excluir** WorkoutService.swift  

6. [x] 🔄 **Atualizar** CoreDataModels.swift  
   - ✅ Incluir `sensorData` em `CDCurrentSet` e `CDHistorySet`
   - ✅ Métodos `sensorDataObject` e `updateSensorData()` implementados
   - ✅ Computed properties básicas: `duration`, `muscleGroupsString`, `muscleGroupsList`
   - ✅ Propriedades convenientes: `safeId`, `safeTitle`, `safeName` etc.
   - ✅ Conversões Set → Array para SwiftUI: `exercisesArray`, `setsArray` etc.
   - ✅ **LIMPEZA ARQUITETURAL:** Removidas validações e lógica de negócio
   - ✅ Arquivo focado apenas em extensões Core Data (Clean Architecture)

7. [x] 🔄 **Atualizar** PersistenceController.swift  
   - ✅ Adaptado para o novo modelo `FitterModel`
   - ✅ External Storage configurado para Binary Data (sensorData)
   - ✅ Migração automática habilitada (Model → FitterModel)
   - ✅ Métodos específicos: `saveWithSensorData()`, `newSensorDataContext()`
   - ✅ Logs detalhados para debug de migração e serialização JSON
   - ✅ **CONFORME REGRAS:** Removido CloudKit, preparado para Firestore sync

8. [x] 🔄 **Atualizar** CoreDataAdapter.swift  
   - ✅ Serialização/deserialização `sensorData` JSON implementada
   - ✅ Métodos principais: `serializeSensorData()`, `deserializeSensorData()`
   - ✅ Integração Apple Watch: `createHistorySetFromWatch()`, `createCurrentSetFromWatch()`
   - ✅ Conversores Dictionary ↔ SensorData para sync Firestore
   - ✅ CloudSyncStatus simplificado (pending/synced)
   - ✅ **CONFORME REGRAS:** Sem CloudKit/iCloud, preparado para Firestore
   - ✅ **MIGRAÇÃO DE DADOS:** `migrateLegacySensorData()` implementado com lógica completa
   - ✅ **EXTERNAL STORAGE:** `allowsExternalBinaryDataStorage` configurado e validado
   - ✅ **VALIDAÇÃO COMPLETA:** `validateExternalBinaryDataStorage()` para debug
   - **PENDÊNCIAS:** ✅ **TODAS RESOLVIDAS!**
     - [x] ✅ **Implementar migração de dados existentes** - método completo implementado
     - [x] ✅ **Ajustar serialização para External Storage** - já configurado no FitterModel + funcionando
     - [ ] Cobrir com testes → **Aguarda itens 86-88** (sistema de testes unitários)

9. [~] 🔄 **Atualizar** SensorData.swift  
   - ✅ Struct otimizada para Binary Data (Core Data External Storage)
   - ✅ Métodos principais: `toBinaryData()`, `fromBinaryData()`
   - ✅ Versionamento e validação para armazenamento seguro
   - ✅ Dictionary conversion para sync Firestore
   - ✅ Mock data e debugging tools implementados
   - ✅ **ELIMINAÇÃO:** 18 atributos → 2 campos JSON (89% menos complexidade)
   - **PENDÊNCIAS:**
     - [ ] Implementar integração com WatchSensorData quando disponível - linha 132
     - [ ] Remover métodos legacy de compatibilidade após migração completa - linha 241

10. [x] 🔄 **Atualizar** CloudSyncStatus.swift  
    - ✅ Simplificação de 5 → 2 estados (60% menos complexidade)
    - ✅ Enum atualizado: `.pending` (novos/modificados/erros) e `.synced` (sincronizados)
    - ✅ Protocolo `Syncable` simplificado (era `CloudSyncable`)
    - ✅ Métodos essenciais: `markForSync()`, `markAsSynced()`, `needsSync`
    - ✅ `SyncEvent` e `SyncAction` otimizados para logging/debug
    - ✅ **ELIMINAÇÃO:** ConflictResolutionStrategy removido (será retry automático)
    - ✅ **COMPATIBILIDADE:** Correções temporárias em CloudSyncManager para item 11
    - ✅ **BENEFÍCIO:** Performance, manutenibilidade e UI mais simples

11. [~] 🔄 **Atualizar** CloudSyncManager.swift  
    - ✅ Generalização completa: CDWorkoutPlan específico → genérico para qualquer Syncable
    - ✅ PersistenceController: Substituição do CoreDataStack descontinuado
    - ✅ Estados simplificados: Apenas .pending/.synced (89% menos complexidade)
    - ✅ Retry automático: Falhas retornam para .pending (sem estado error permanente)
    - ✅ Resolução de conflitos por lastModified (local > remoto = upload)
    - ✅ **ELIMINAÇÃO:** CloudConflictResolver removido (era complexidade desnecessária)
    - ✅ Suporte multi-entidade: CDWorkoutPlan, CDUser + estrutura para outras  
    - ✅ Upload/Download otimizados: Métodos específicos + delete genérico
    - ✅ **PERFORMANCE:** Menos queries, contextos otimizados, melhor UX
    - ✅ **TÍTULOS DUAIS:** Atualizações `safeTitle` → `displayTitle` aplicadas (linhas 225, 242)
    - **PENDÊNCIAS:**
      - [ ] Adicionar suporte para CDExercise (upload/download) - linha 110
      - [ ] Adicionar suporte para CDHistorySession (upload/download) - linha 167
      - [ ] Implementar sincronização de CDCurrentSet/CDHistorySet - linha 294
      - [ ] Adicionar coleções Firestore para outras entidades - linha 455

12. [x] 🔄 **Atualizar** ConnectivityManager.swift  
    - ✅ NWPathMonitor: Substituição da detecção de conectividade básica por monitoramento preciso
    - ✅ Publisher Combine: Estados reativos online/offline + Watch reachable para UI
    - ✅ PersistenceController: Substituição do CoreDataStack descontinuado
    - ✅ **ELIMINAÇÃO:** WorkoutRepository removido (foi excluído nos itens 1-5)
    - ✅ **LIMPEZA ARQUITETURAL:** Removidas properties de teste (`lastReceived`, `counter`)
    - ✅ **OTIMIZAÇÃO:** Mantidas apenas properties essenciais (`isReachable`, `isAuthenticated`)
    - ✅ Processamento assíncrono: Dados de sensores Watch → iPhone otimizados
    - ✅ Conectividade inteligente: Auto-sync quando online + reachable
    - ✅ WCSessionDelegate otimizado: Logs detalhados + respostas com timestamp
    - ✅ **PERFORMANCE:** Contextos otimizados + processamento background
    - ✅ **UI MELHORADA:** HomeView agora mostra status completo de conectividade
    - ✅ **TÍTULOS DUAIS:** Atualização `safeTitle` → `displayTitle` aplicada (linha 212)
    - **PENDÊNCIAS:** ✅ **TODAS RESOLVIDAS!**
      - [x] ✅ **Substituir por WorkoutDataService** (implementado item 16) - linha 64
      - [x] ✅ **Integrar com SyncWorkoutUseCase** (implementado item 23) - linha 66, 147  
      - [x] ✅ **Observar mudanças nos treinos via WorkoutDataService** - linha 129
      - [x] ✅ **Integrar com SessionManager/WorkoutDataService** - linhas 305, 313
      - [x] ✅ **Implementar processamento otimizado de dados de movimento** - linha 384
      - [x] ✅ **Salvar dados de descanso para análise** - linha 396

13. [x] 🔄 **Atualizar** SessionManager.swift ✅ 
    - ✅ Dependência atualizada: `CoreDataStack` → `PersistenceController`
    - ✅ Estados reduzidos: Removidos `pauseSession()` e `resumeSession()` vazios
    - ✅ Preparação para Use Cases: TODOs adicionados para futuras migrações
    - ✅ **LIMPEZA ARQUITETURAL:** Foco em coordenação de estado, não lógica de negócio
    - ✅ Integração com Watch mantida e otimizada com logs informativos
    - ✅ Documentação em português e organização com seções MARK
    - ✅ **TÍTULOS DUAIS:** Atualizações `safeTitle` → `displayTitle` aplicadas (linhas 71, 197, 230, 285)
    - ✅ **FLUXO GRANULAR CORRIGIDO:** Removidos `nextExercise()` e `nextSet()` que violavam arquitetura
    - ✅ **REFERÊNCIAS USE CASES:** Documentação clara sobre uso dos Use Cases corretos
    - ✅ **LOGIN OBRIGATÓRIO:** `currentUser: CDAppUser!` implementado conforme arquitetura
    - ✅ **CONFIGURAÇÃO USUÁRIO:** Métodos `setCurrentUser()` e `clearCurrentUser()` adicionados
    - ✅ **LOGOUT POR INATIVIDADE:** `handleInactivityLogout()` com limpeza completa
    - **PENDÊNCIAS CONCLUÍDAS:** 
      - [x] ✅ **Migrar `startWorkout()` para StartWorkoutUseCase** → **Item 24 CONCLUÍDO**
      - [x] ✅ **Migrar `endWorkout()` para EndWorkoutUseCase** → **Item 25 CONCLUÍDO**
      - [x] ✅ **Migrar `nextExercise()` para StartExerciseUseCase** → **Item 26 CONCLUÍDO**
      - [x] ✅ **Migrar `endExercise()` para EndExerciseUseCase** → **Item 27 CONCLUÍDO**
      - [x] ✅ **Remover `nextSet()` - será StartSetUseCase/EndSetUseCase** → **Itens 28-29**
      - [x] ✅ **Implementar LOGIN OBRIGATÓRIO** → **Conforme EXEMPLO_LOGIN_OBRIGATORIO.md**
    - **PENDÊNCIAS RESTANTES:** 
      - [ ] Migrar `updateSensorData()`, `updateHealthData()` para Use Cases específicos
      - [ ] Integrar com AuthService.currentUser → **Aguarda item 53** (AuthUseCase)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)

14. [~] 🆕 **Criar** BaseViewModel.swift  
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** Remoção de `.shared`, dependências via inicializador
    - ✅ Estados comuns de UI: `isLoading`, `showError`, `errorMessage`, `isProcessing`  
    - ✅ Métodos de orquestração: `executeUseCase()`, `executeUseCaseWithProcessing()`
    - ✅ Tratamento de erros: `showError()`, `clearError()`, `withLoading()`, `withProcessing()`
    - ✅ **ARQUITETURA CORRETA:** ViewModels NÃO fazem persistência direta
    - ✅ ViewContext apenas para SwiftUI binding (@FetchRequest, observação)
    - ✅ **CLEAN ARCHITECTURE:** Toda persistência OBRIGATORIAMENTE via Use Cases
    - ✅ Preview support com injeção de dependências mockadas
    - ✅ Computed properties: `isAuthenticated`, `isBusy`, `currentUser`
    - **BENEFÍCIOS:** Facilita testes, evita bypass de Use Cases, separação clara
    - **PENDÊNCIAS:**
      - [ ] Substituir AuthService por AuthUseCase → **Aguarda item 53** (AuthUseCase)
      - [ ] Adicionar injeção de dependência para Use Cases futuros
      - [ ] 🆕 Implementar `checkAndHandleInactivity()` para logout automático
      - [ ] 🆕 Integrar verificação de 7 dias de inatividade no app launch → **Aguarda item 53** (AuthUseCase)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)

15. [x] 🆕 **Criar** CoreDataService.swift  
    - ✅ **SEPARAÇÃO DE RESPONSABILIDADES:** Camada de infraestrutura independente da UI
    - ✅ Protocolo `CoreDataServiceProtocol` para facilitar testes e mocks
    - ✅ Operações CRUD genéricas: `save()`, `saveBackground()`, `fetch()`, `create()`, `delete()`
    - ✅ Gerenciamento de contextos: `viewContext` e `backgroundContext` encapsulados
    - ✅ Tratamento de erros específicos: `CoreDataError` enum com casos detalhados
    - ✅ Operações avançadas: `performBackgroundTask()`, `object(with:)`
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** PersistenceController injetado via inicializador
    - ✅ **CLEAN ARCHITECTURE:** Abstração do Core Data para Use Cases
    - ✅ Logs detalhados para debug de operações CRUD
    - ✅ Async/await support para operações background
    - **BENEFÍCIOS:** Testabilidade, separação de camadas, reutilização
    - **PENDÊNCIAS:**
      - [ ] Adicionar operações em lote (batch operations) para performance
      - [x] ~~**Extrair toda lógica de `sensorData` para um adapter**~~ ✅ **RESOLVIDO** - WorkoutDataService delega para CoreDataAdapter
      - [x] ~~Garantir que o CoreDataService não manipule `Data` brutos~~ ✅ **RESOLVIDO** - Delegação implementada
      - [ ] Adicionar helpers para testes de integração e mocks
      - [ ] Otimizações para grandes volumes de dados (paginação, fetch limits)

16. [x] 🆕 **Criar** WorkoutDataService.swift ✅
    - ✅ **ARQUITETURA LIMPA:** CRUD unicamente (sem sync) - Use Cases farão a orquestração
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** `CoreDataServiceProtocol` e `CoreDataAdapter` via inicializador
    - ✅ **ENTIDADES CORRETAS:** Alinhado 100% com Core Data Model (FitterModel.xcdatamodel)
    - ✅ **PROTOCOLO CORRETO:** `WorkoutDataServiceProtocol` com métodos essenciais (nextExercise removido)
    - ✅ **LOGIN OBRIGATÓRIO:** Todos os métodos fetch com `user: CDAppUser` obrigatório (sem ?)
    - ✅ **OWNERSHIP GARANTIDO:** Zero possibilidade de dados órfãos, usuário sempre vinculado
    - ✅ **OPERAÇÕES IMPLEMENTADAS:** 
      - CDWorkoutPlan: create, fetch, update, delete, reorder
      - CDCurrentSession: create, fetch, update, delete (sessões ativas)
      - CDCurrentExercise: create, update (exercícios ativos) ✅ **nextExercise REMOVIDO**
      - CDCurrentSet: create, fetch, update, delete, deleteAll (séries ativas)
      - CDWorkoutHistory: create, fetch, delete (histórico completo)
      - CDHistorySet: create, fetch (por exercício/template), delete (séries históricas)
      - CDPlanExercise: add/remove/reorder (exercícios em planos)
    - ✅ **CORREÇÃO CRÍTICA:** ❌ CDWorkoutSession → ✅ CDCurrentSession/CDWorkoutHistory
    - ✅ **CORREÇÃO CRÍTICA:** ❌ CDExercise → ✅ CDExerciseTemplate/CDPlanExercise/CDCurrentExercise/CDHistoryExercise  
    - ✅ **FLUXO GRANULAR:** Removido `nextExercise()` que violava Clean Architecture
    - ✅ **SERIALIZAÇÃO DELEGADA:** `CoreDataAdapter.serializeSensorData()` antes de persistir
    - ✅ **DESERIALIZAÇÃO DELEGADA:** `CoreDataAdapter.deserializeSensorData()` ao buscar
    - ✅ **TRATAMENTO DE ERROS:** `WorkoutDataError` enum com 6 casos específicos
    - ✅ **CAMPOS CORRETOS:** targetReps, actualReps, order, timestamp, cloudSyncStatus etc.
    - ✅ **RELACIONAMENTOS CORRETOS:** CDCurrentSet → CDCurrentExercise → CDCurrentSession
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug
    - ✅ **EXTENSION HELPERS:** `getSensorData()` para Current/History Sets
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - **BENEFÍCIOS:** 89% menos complexidade sensor data, compatibilidade total com Core Data
    - **PENDÊNCIAS:**
      - [ ] Implementar testes unitários e de integração com mocks
      - [ ] Adicionar validações de negócio específicas se necessário
      - [ ] Otimizar fetch requests com paginação para grandes volumes
    

17. [x] 🆕 **Criar** CreateWorkoutUseCase.swift  
    - ✅ `create()` via WorkoutDataService implementado
    - ✅ Integrado com `SyncWorkoutUseCase.execute()` (item 23) ✅ **RESOLVIDO**
    - ✅ **CLEAN ARCHITECTURE:** Use Case com orquestração de operações
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** CreateWorkoutUseCaseProtocol para testabilidade
    - ✅ **VALIDAÇÃO DE ENTRADA:** CreateWorkoutInput com validações específicas
    - ✅ **TRATAMENTO DE ERROS:** CreateWorkoutError enum com casos específicos
    - ✅ **FLUXO COMPLETO:** Validação → Resolução título → Criação → Exercícios → Sincronização → Resultado
    - ✅ **ROLLBACK:** Limpeza automática em caso de falha parcial
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug
    - ✅ **MÉTODO DE CONVENIÊNCIA:** createQuickWorkout() e createAutoWorkout() para casos simples
    - ✅ **SYNC STATUS:** Enum para controlar estados de sincronização
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **SISTEMA DUAL DE TÍTULOS:** autoTitle sempre "Treino X" + customTitle totalmente livre
    - ✅ **GERAÇÃO AUTOMÁTICA DE TÍTULOS:** "Treino A", "Treino B"... "Treino A1", "Treino B1"... (padrão infinito)
    - ✅ **TÍTULO PERSONALIZADO LIVRE:** "Peitoral Heavy", "Push Day", "Leg Killer"... (sem palavra "Treino")
    - ✅ **EXIBIÇÃO INTELIGENTE:** "Peitoral Heavy (Treino A)" ou apenas "Treino A"
    - ✅ **CORE DATA ATUALIZADO:** Campo autoTitle adicionado ao CDWorkoutPlan
    - ✅ **PROPRIEDADES COMPUTED:** displayTitle, compactTitle, hasCustomTitle, safeCustomTitle

18. [x] 🆕 **Criar** FetchWorkoutUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Use Case com operações de consulta otimizadas
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataServiceProtocol via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** FetchWorkoutUseCaseProtocol para testabilidade
    - ✅ **OPERAÇÕES PRINCIPAIS:** fetchAllWorkouts, fetchWorkoutById, fetchWorkoutsByMuscleGroup, fetchWorkoutStatistics
    - ✅ **TRATAMENTO DE ERROS:** FetchWorkoutError enum com casos específicos
    - ✅ **COMPATIBILIDADE TÍTULOS DUAIS:** Usa displayTitle, compactTitle, hasCustomTitle
    - ✅ **FUNCIONALIDADES AVANÇADAS:** Filtros por grupos musculares, ordenação configurável, estatísticas
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** Extension com métodos simplificados
    - ✅ **VALIDAÇÃO DE ENTRADA:** Input structs com validações específicas
    - ✅ **HELPER METHODS:** Filtros, ordenação e estatísticas privados organizados
    - ✅ **LOGIN OBRIGATÓRIO:** Removido erro userNotProvided, inputs com user obrigatório

19. [x] 🆕 **Criar** UpdateWorkoutUseCase.swift  
    - ✅ `update()` via WorkoutDataService implementado
    - ✅ `SyncWorkoutUseCase.execute()` integrado
    - ✅ **CLEAN ARCHITECTURE:** Use Case com orquestração de operações de atualização
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** UpdateWorkoutUseCaseProtocol para testabilidade
    - ✅ **OPERAÇÕES COMPLETAS:** Título personalizado, grupos musculares, exercícios
    - ✅ **COMPATIBILIDADE TÍTULOS DUAIS:** autoTitle nunca alterado, customTitle alterável
    - ✅ **VALIDAÇÃO DE ENTRADA:** UpdateWorkoutInput com validações específicas
    - ✅ **TRATAMENTO DE ERROS:** UpdateWorkoutError enum com casos específicos
    - ✅ **ROLLBACK:** Captura estado original e recuperação em falhas
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** updateCustomTitle(), updateMuscleGroups(), updateExercises()
    - ✅ **TRACKING DE MUDANÇAS:** Set<UpdateWorkoutChange> para saber o que foi alterado
    - ✅ **SYNC STATUS:** Enum para controlar estados de sincronização
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro

20. [x] 🆕 **Criar** DeleteWorkoutUseCase.swift  
    - ✅ `delete()` via WorkoutDataService implementado
    - ✅ `SyncWorkoutUseCase.execute()` integrado
    - ✅ **CLEAN ARCHITECTURE:** Use Case com exclusão segura de planos de treino
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** DeleteWorkoutUseCaseProtocol para testabilidade
    - ✅ **VALIDAÇÕES DE SEGURANÇA:** Verificação de sessões ativas antes da exclusão
    - ✅ **COMPATIBILIDADE TÍTULOS DUAIS:** displayTitle nos logs e outputs
    - ✅ **VALIDAÇÃO DE ENTRADA:** DeleteWorkoutInput com validações específicas
    - ✅ **TRATAMENTO DE ERROS:** DeleteWorkoutError enum com 7 casos específicos
    - ✅ **TRACKING DETALHADO:** DeleteWorkoutDetails com informações completas
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** deleteWorkout(), forceDeleteWorkout(), deleteWorkoutOffline()
    - ✅ **VERIFICAÇÃO PRÉVIA:** canDeleteSafely() para UX preventiva
    - ✅ **SYNC STATUS:** Enum para controlar estados de sincronização
    - ✅ **EXCLUSÃO INTELIGENTE:** Aproveitamento de relações Cascade do Core Data
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro

21. [x] 🆕 **Criar** ReorderWorkoutUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Use Case de reordenação com orquestração completa
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataService + SyncWorkoutUseCase (opcional) via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** ReorderWorkoutUseCaseProtocol para testabilidade
    - ✅ **VALIDAÇÕES ROBUSTAS:** Lista vazia, duplicatas, ownership de usuário, IDs válidos
    - ✅ **TRATAMENTO DE ERROS:** ReorderWorkoutError enum com 6 casos específicos
    - ✅ **TRACKING DE MUDANÇAS:** OrderChange struct para monitorar alterações de posição
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** reorderUserWorkouts(), reorderWorkouts() para casos comuns
    - ✅ **SYNC STATUS:** Enum para controlar estados de sincronização (synced/pending/failed/disabled)
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug
    - ✅ **INTEGRAÇÃO:** Usa WorkoutDataService.reorderWorkoutPlans() existente
    - ✅ **PRESERVAÇÃO:** Títulos duais (autoTitle/customTitle) mantidos inalterados
    - ✅ **LOGIN OBRIGATÓRIO:** Input.user obrigatório, ownership sempre validado

22. [x] 🆕 **Criar** ReorderExerciseUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Use Case de reordenação com orquestração completa
    - ✅ **INJEÇÃO DE DEPENDÊNCIAS:** WorkoutDataService + SyncWorkoutUseCase (opcional) via inicializador
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** ReorderExerciseUseCaseProtocol para testabilidade
    - ✅ **VALIDAÇÕES ESPECÍFICAS:** Mesmo plano, templates válidos, sem duplicatas, IDs válidos
    - ✅ **TRATAMENTO DE ERROS:** ReorderExerciseError enum com 8 casos específicos
    - ✅ **TRACKING DE MUDANÇAS:** ExerciseOrderChange struct para monitorar alterações de posição
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** reorderExercisesInPlan(), reorderExercises() para casos comuns
    - ✅ **SYNC STATUS:** Enum para controlar estados de sincronização (synced/pending/failed/disabled)
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug
    - ✅ **INTEGRAÇÃO:** Usa WorkoutDataService.reorderPlanExercises() existente
    - ✅ **PRESERVAÇÃO:** Templates e relacionamentos mantidos inalterados

23. [x] 🆕 **Criar** SyncWorkoutUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Motor puro de sincronização centralizado
    - ✅ **INTEGRAÇÃO COM CLOUDSYNCMANAGER:** Orquestra scheduleUpload(), scheduleDeletion(), syncPendingChanges()
    - ✅ **PROTOCOLO + IMPLEMENTAÇÃO:** SyncWorkoutUseCaseProtocol para testabilidade
    - ✅ **INTERFACE COMPATÍVEL:** Método execute() esperado por todos os Use Cases CRUD
    - ✅ **ESTRATÉGIAS MÚLTIPLAS:** Upload, Download, Delete, FullSync, Auto
    - ✅ **TRATAMENTO DE ERROS:** SyncWorkoutError enum com 9 casos específicos
    - ✅ **VALIDAÇÃO DE ENTIDADES:** Suporte para CDWorkoutPlan, CDAppUser, CDExerciseTemplate, CDWorkoutHistory
    - ✅ **SINCRONIZAÇÃO EM LOTE:** executeBatch() para múltiplas entidades
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** syncWorkoutPlan(), syncUser(), scheduleUpload(), forceDownload()
    - ✅ **DEPENDENCY INJECTION:** CloudSyncManager injetado via inicializador
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **LOGS INFORMATIVOS:** Emojis e mensagens em português para debug

## 🏋️‍♂️ Use Cases de Lifecycle de Workout (Itens 24-29)

> **Objetivo:** Criar Use Cases granulares para controle preciso do ciclo de vida de treinos, exercícios e séries, com integração robusta ao HealthKit e captura de dados de sensores em background no Apple Watch.

## FLUXO CORRETO DE NAVEGAÇÃO (GRANULAR - MÚLTIPLAS SÉRIES):

StartWorkoutUseCase → CDCurrentSession + 1º exercício (opcional)
      ↓
StartExerciseUseCase → Próximo exercício + finaliza anterior
      ↓
╔═══ LOOP SÉRIES (3-4 séries por exercício) ═══╗
║ StartSetUseCase → Inicia série N               ║
║       ↓                                        ║
║ EndSetUseCase → Finaliza série N               ║
║       ↓                                        ║
║ StartSetUseCase → Inicia série N+1 (se houver)║
║       ↓                                        ║
║ EndSetUseCase → Finaliza série N+1             ║
║       ↓                                        ║
║ ... (repetir até completar todas as séries)   ║
╚════════════════════════════════════════════════╝
      ↓
EndExerciseUseCase → Finaliza exercício + decide próximo passo
      ↓
┌─ StartExerciseUseCase → Próximo exercício (se houver exercícios restantes)
│        ↓
│   (volta ao LOOP SÉRIES)
│
└─ EndWorkoutUseCase → Finaliza treino (se último exercício)

24. [x] 🆕 **Criar** StartWorkoutUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **VALIDAÇÕES ROBUSTAS:** Usuário autenticado, plano válido, sem sessão ativa
    - ✅ **OPERAÇÕES COMPLETAS:** Criar CDCurrentSession, configurar primeiro exercício automaticamente
    - ✅ **ERROR HANDLING:** StartWorkoutError enum com 10 casos específicos
    - ✅ **INTEGRAÇÃO WATCH:** Notificação automática via ConnectivityManager
    - ✅ **SINCRONIZAÇÃO:** Automática via SyncWorkoutUseCase
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** executeQuickStart(), startDefaultWorkout(), startWorkoutPlanOnly()
    - ✅ **RECOVERY:** recoverFromOrphanSession() para sessões órfãs
    - ✅ **PREPARAÇÃO HEALTHKIT:** Interface pronta para item 54 (HealthKitManager)
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - **PENDÊNCIAS:**
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [ ] Migração AuthService → AuthUseCase → **Aguarda item 53** (AuthUseCase)
      - [ ] Fluxo premium/free → **Aguarda itens 58-66** (sistema de assinaturas)

25. [x] 🆕 **Criar** EndWorkoutUseCase.swift  
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **MIGRAÇÃO COMPLETA:** CDCurrentSession → CDWorkoutHistory preservando sensorData
    - ✅ **ANALYTICS ROBUSTOS:** EndWorkoutStatistics com 10 métricas de performance
    - ✅ **ERROR HANDLING:** EndWorkoutError enum com 10 casos específicos
    - ✅ **OPERAÇÕES PRINCIPAIS:** Finalizar Current entities, migrar para History, calcular stats
    - ✅ **SINCRONIZAÇÃO:** Automática via SyncWorkoutUseCase com status tracking
    - ✅ **HEALTHKIT PREPARADO:** Interface pronta para item 54 (HealthKitManager)
    - ✅ **MIGRAÇÃO INTELIGENTE:** Preserva exercícios, séries e sensorData JSON
    - ✅ **CLEANUP:** Limpeza opcional de entidades temporárias
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** executeQuickEnd(), endDefaultWorkout(), endWorkoutOffline()
    - **PENDÊNCIAS:**
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [ ] Detecção de PRs comparando com histórico → **Aguarda analytics avançados**
      - [ ] Sistema de recompensas/achievements → **Aguarda itens 58-66** (monetização)

26. [x] 🆕 **Criar** StartExerciseUseCase.swift ✅  
    - ✅ **RESPONSABILIDADE:** Iniciar exercício individual dentro de uma sessão ativa
    - ✅ **OPERAÇÕES:** Criar CDCurrentExercise, configurar template, finalizar exercício anterior
    - ✅ **NAVIGATION:** Atualizar currentExerciseIndex na sessão ativa (corrige bug do WorkoutDataService.nextExercise)
    - ✅ **WATCH SYNC:** Enviar dados do exercício para Apple Watch via ConnectivityManager
    - ✅ **VALIDAÇÕES:** Sessão ativa, template válido, ordem correta, exercício não conflitante
    - ✅ **UX:** Notificações para Watch, feedback de progresso, métodos de conveniência
    - ✅ **ARQUITETURA LOGIN OBRIGATÓRIO:** `user: CDAppUser` sem opcional
    - ✅ **ERROR HANDLING:** StartExerciseError enum com 11 casos específicos
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **CORREÇÃO CRÍTICA:** Substitui WorkoutDataService.nextExercise() que estava quebrado
    - ✅ **NAVEGAÇÃO INTELIGENTE:** executeNextExercise(), getNextExerciseTemplate(), navegação por índice
    - ✅ **SINCRONIZAÇÃO:** Automática via SyncWorkoutUseCase com status tracking
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** startDefaultExercise(), startExerciseOffline(), startExerciseWithoutHealthKit()
    - ✅ **NAVIGATION HELPERS:** hasNextExercise(), remainingExercisesCount(), getRemainingExercises()
    - **PENDÊNCIAS:**
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [x] ✅ **createFirstSet() via StartSetUseCase** → **Item 28 CONCLUÍDO**  

27. [x] 🆕 **Criar** EndExerciseUseCase.swift ✅
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **FINALIZAÇÃO INTELIGENTE:** Finalizar CDCurrentExercise + decidir próximo passo
    - ✅ **NAVEGAÇÃO GRANULAR:** Determina se próximo exercício OU finalizar treino
    - ✅ **STATISTICS ROBUSTAS:** EndExerciseStatistics com 12 métricas de performance
    - ✅ **ERROR HANDLING:** EndExerciseError enum com 11 casos específicos
    - ✅ **NEXT STEP LOGIC:** NextStep enum (nextExercise/workoutComplete/waitingDecision)
    - ✅ **NAVIGATION HELPERS:** hasNextExercise(), remainingExercisesCount(), getRemainingExercises()
    - ✅ **ARQUITETURA LOGIN OBRIGATÓRIO:** `user: CDAppUser` sem opcional
    - ✅ **INTEGRAÇÃO WATCH:** Notificação Apple Watch com próximo passo
    - ✅ **HEALTHKIT PREPARADO:** Interface pronta para item 54 (HealthKitManager)
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** executeQuickEnd(), endExerciseOffline(), endExerciseManual()
    - ✅ **FLUXO GRANULAR:** Integrado ao novo fluxo de múltiplas séries por exercício
    - **PENDÊNCIAS:**
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [ ] Detecção de PRs comparando com histórico → **Aguarda analytics avançados**
      - [ ] Validar elegibilidade premium/free → **Aguarda itens 58-66** (monetização)

28. [x] 🆕 **Criar** StartSetUseCase.swift ✅
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **OPERAÇÕES PRINCIPAIS:** Criar CDCurrentSet, ativar sensores, iniciar tracking de duração
    - ✅ **VALIDAÇÕES ROBUSTAS:** Exercício ativo, dados de entrada, limites de assinatura
    - ✅ **ERROR HANDLING:** StartSetError enum com 12 casos específicos
    - ✅ **INTEGRAÇÃO WATCH:** MotionManager + WatchDataManager + ConnectivityManager
    - ✅ **HEALTHKIT PREPARADO:** Interface pronta para workout segments background (item 54)
    - ✅ **SENSOR ACTIVATION:** Heart rate, motion, calories em tempo real
    - ✅ **BACKGROUND MODE:** Captura mesmo com tela Watch apagada
    - ✅ **ANALYTICS ROBUSTOS:** StartSetAnalytics com 12 métricas de performance
    - ✅ **ARQUITETURA LOGIN OBRIGATÓRIO:** `user: CDAppUser` sem opcional
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** executeQuickStart(), executeWithDefaultSettings(), executeOffline()
    - ✅ **VALIDAÇÃO PREMIUM/FREE:** Preparado para limite de séries por assinatura
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - **PENDÊNCIAS:**
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [ ] Integração com MotionManager refatorado → **Aguarda item 49** (MotionManager)
      - [ ] Integração com WatchDataManager refatorado → **Aguarda item 50** (WatchDataManager)
      - [ ] Validação real de limite de séries → **Aguarda itens 58-66** (SubscriptionManager)
      - [ ] Contagem automática de repetições via Core ML → **Aguarda pipeline ML**
      - [ ] Feedback de execução e postura → **Aguarda modelos .mlmodel**

29. [x] 🆕 **Criar** EndSetUseCase.swift ✅
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** WorkoutDataService + SyncWorkoutUseCase via inicializador
    - ✅ **OPERAÇÕES PRINCIPAIS:** Finalizar CDCurrentSet, parar sensores, salvar sensorData
    - ✅ **SENSOR PROCESSING:** Serializar dados via CoreDataAdapter.serializeSensorData()
    - ✅ **ANALYTICS ROBUSTOS:** EndSetAnalytics com intensity score, form analysis, fatigue metrics
    - ✅ **🎯 REST TIMER AUTOMÁTICO:** RestTimerInfo com tipos inteligentes e duração otimizada
    - ✅ **🧠 TRIGGERS MÚLTIPLOS:** Manual, automático, timer explícito, timeout por inatividade
    - ✅ **🔄 FLUXO CONTÍNUO:** NextAction enum com ações automáticas pós-rest timer
    - ✅ **AUTO-SYNC:** Sincronização via SyncWorkoutUseCase + Watch sync preparado
    - ✅ **VALIDATION:** Validações robustas de entrada e estado de série ativa
    - ✅ **METHODS DE CONVENIÊNCIA:** executeQuickEnd(), executeAutoDetected(), executeWithRestNow(), executeOffline()
    - ✅ **ARQUITETURA LOGIN OBRIGATÓRIO:** `user: CDAppUser` sem opcional
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro detalhado
    - **PENDÊNCIAS:**
      - [ ] Integração com TimerService → **Aguarda item 52** (TimerService)
      - [ ] Integração com HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] Integração com MotionManager refatorado → **Aguarda item 49** (MotionManager)
      - [ ] Integração com WatchDataManager refatorado → **Aguarda item 50** (WatchDataManager)
      - [ ] Detecção automática por sensores → **Aguarda item 49** (MotionManager refatorado)
      - [ ] Validação premium/free → **Aguarda itens 58-66** (SubscriptionManager)

---

## 📊 Sistema de Exercícios Firebase - ABORDAGEM SIMPLIFICADA (Itens 30-33)

> **🎯 ESTRATÉGIA SIMPLES:** Exercícios + vídeos sempre da nuvem nas listas de seleção. Salvamento local APENAS quando exercício é adicionado ao treino e criação/edição é concluída.

> **✅ COMPATIBILIDADE TOTAL:** A migração para Clean Architecture manterá **100%** das funcionalidades existentes: filtros hierárquicos, priorização de equipamentos/pegadas, ordenação personalizada (selecionados primeiro), barra de pesquisa com animação scroll, toda a UX atual será preservada.

30. [x] 🆕 **Criar** FetchFBExercisesUseCase.swift ✅ 
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade
    - ✅ **DEPENDENCY INJECTION:** FirestoreExerciseRepository via inicializador
    - ✅ **OPERAÇÕES PRINCIPAIS:** fetchExercises() com filtros, searchExercises() por texto
    - ✅ **ABORDAGEM SIMPLIFICADA:** Busca direto do Firestore, sem cache local complexo
    - ✅ **MÍDIA PREPARADA:** Estrutura pronta para videoURL/thumbnailURL (item 32)
    - ✅ **ERROR HANDLING:** FetchFBExercisesError enum com casos específicos
    - ✅ **INPUT/OUTPUT:** Structs validados com FetchFBExercisesInput/Output
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro
    - ✅ **REPOSITORY PROTOCOL:** Interface preparada para item 31
    - **🎯 COMPATIBILIDADE FILTROS:** Estrutura preparada para filtros hierárquicos existentes
    - **🔍 COMPATIBILIDADE BUSCA:** Suporte a busca por nome, equipamento, pegada (item 66/77)
    - **📊 COMPATIBILIDADE ORDENAÇÃO:** Estrutura para ordenação personalizada (selecionados primeiro)
    - **PENDÊNCIAS:**
      - [x] ✅ Integração com FirestoreExerciseRepository → **Item 31 CONCLUÍDO**
      - [x] ✅ **CAMPOS FIREBASE:** Adicionar `description`, `createdAt`, `updatedAt` ao modelo → **Item 32 CONCLUÍDO**
      - [x] ✅ **REMOÇÃO:** Excluir campo `imageName` completamente → **Item 32 CONCLUÍDO**
      - [x] ✅ **LEGSUBGROUP:** Campo `legSubgroup` apenas para exercícios de perna → **Item 32 CONCLUÍDO**
      - [x] ✅ Campos videoURL/thumbnailURL → **Item 32 CONCLUÍDO**
      - [ ] Migração de ViewModels → **Itens 66-67 (ListExercise/WorkoutViewModel)**

### **🎯 RESUMO MIGRAÇÃO UX EXERCÍCIOS:**
- **✅ FILTROS LÓGICA:** Sistema hierárquico (grupo → equipamento → pegada) preservado no ViewModel
- **✅ PRIORIZAÇÃO:** Equipamentos e pegadas mantêm ordem preferencial existente  
- **✅ ORDENAÇÃO:** Selecionados primeiro (alfabético) + não selecionados (alfabético) preservada
- **✅ BUSCA:** Pesquisa por nome/equipamento/pegada com ordenação especial mantida
- **✅ UI DESIGN:** Layout visual, cores, pills, botões preservados
- **🔧 SCROLL UI:** Barra de pesquisa que esconde/mostra - **REESCREVER para funcionar**
- **🔧 ANIMAÇÕES:** Animações suaves de filtros e search bar - **REESCREVER para funcionar**
- **🔄 ARQUITETURA:** Troca FirebaseExerciseService → FetchFBExercisesUseCase + correção bugs UX

31. [x] 🔄 **Simplificar** FirestoreExerciseRepository.swift ✅  
    - ✅ **RESPONSABILIDADE:** Repository direto para Firestore sem cache inteligente
    - ✅ **OPERAÇÕES:** fetch(), search(), getVideoURL() - operações simples
    - ✅ **MÍDIA:** URLs diretas do Firebase Storage para streaming
    - ✅ **ARQUITETURA:** Protocol + Implementation básica, sem listeners complexos
    - ✅ **CLEAN ARCHITECTURE:** Repository implementa FirestoreExerciseRepositoryProtocol
    - ✅ **DEPENDENCY INJECTION:** Firestore injetado via inicializador
    - ✅ **MÉTODOS EXTRAS:** fetchExercise(by:), fetchExercises(by:) para casos específicos
    - ✅ **PREPARADO PARA VÍDEOS:** getVideoURL(), getThumbnailURL() aguardam item 32
    - ✅ **ERROR HANDLING:** FirestoreExerciseError enum com casos específicos
    - ✅ **PERFORMANCE:** Chunking para queries 'in' com múltiplos templateIds
    - ✅ **VÍDEO METHODS:** getVideoURL() e getThumbnailURL() implementados no item 32

32. [x] 🔄 **Atualizar** FirebaseExercise.swift ✅
    - ✅ **RESPONSABILIDADE:** Modelo simples alinhado com estrutura real do Firebase
    - ✅ **🆕 CAMPOS:** `description: String`, `createdAt: Date`, `updatedAt: Date`, `videoURL: String?`
    - ✅ **🔧 LEGSUBGROUP:** Campo `legSubgroup: String?` apenas para exercícios de perna
    - ✅ **🗑️ REMOÇÃO:** Excluir campo `imageName` completamente
    - ✅ **CONVERSÃO:** Método toCDExerciseTemplate() APENAS quando salvar no treino
    - ✅ **MÍDIA:** Propriedades hasVideo, hasThumbnail para UI condicional
    - ✅ **🎯 COMPATIBILIDADE FILTROS:** Manter propriedades displayEquipment, displayGripVariation
    - ✅ **🔍 COMPATIBILIDADE BUSCA:** Manter safeName, safeTemplateId para busca existente
    - ✅ **DEPENDÊNCIA:** Item 33.1 (Core Data Model atualizado) - CONCLUÍDO
    - ✅ **FIREBASE REAL:** Estrutura 100% alinhada com Firebase mostrado nas imagens
    - ✅ **PARSE DATAS:** Suporte a Timestamp e ISO8601 do Firebase
    - ✅ **MOCK DATA:** Dados de preview com exemplos reais

33. [~] 🗑️ **Excluir** FirebaseExerciseService.swift ✅
    - ✅ **MOTIVO:** Substituído pela abordagem simplificada com Repository direto
    - ✅ **LIMPEZA:** Arquivo excluído do projeto
    - **PENDÊNCIAS:**
      - [ ] Remover dependências em ListExerciseViewModel → **Item 66**
      - [ ] Remover dependências em WorkoutViewModel → **Item 67**

34 [x] 🔄 **Atualizar** FitterModel.xcdatamodel 🆕 ✅
    - ✅ **RESPONSABILIDADE:** Atualizar Core Data Model para Firebase alignment
    - ✅ **CDExerciseTemplate:** `description: String?`, `videoURL: String?`, `createdAt: Date?`, `updatedAt: Date?`
    - ✅ **🗑️ REMOÇÃO:** Excluir campo `imageName` completamente do CDExerciseTemplate
    - ✅ **🔧 LEGSUBGROUP:** Campo `legSubgroup: String?` apenas para exercícios de perna
    - ✅ **CDAppUser:** subscriptionType: Int16, subscriptionValidUntil: Date?, subscriptionStartDate: Date?
    - ✅ **MIGRAÇÃO:** Migração automática lightweight com valores padrão
    - ✅ **COMPATIBILIDADE:** Backwards compatibility com dados existentes
    - ✅ **ENUM:** SubscriptionType.swift criado com conformidade Core Data Int16

---

## 🎬 Sistema de Vídeo Cards Reutilizáveis (Itens 34-40) 🆕

> **Objetivo:** Criar componentes reutilizáveis para exibir exercícios com vídeos em 4 contextos diferentes: Lista Firebase (não reordenável), Criação/Edição de treino (reordenável), Detalhes do treino (read-only) e Treino ativo (futuro). Firebase Storage para vídeos streaming.

35. [x] 🆕 **Criar** ListExerciseCard.swift 🆕 ✅
    - ✅ **RESPONSABILIDADE:** Componente base não reordenável para exercícios Firebase
    - ✅ **CONTEXTOS:** Lista de seleção de exercícios, visualização de detalhes  
    - ✅ **FEATURES:** Thumbnail sempre visível, play button para vídeos, design responsivo
    - ✅ **PROPS:** exercise, displayMode, onTap, onVideoTap implementados
    - ✅ **INDEPENDÊNCIA:** Componente autocontido sem dependencies externas
    - ✅ **VÍDEO COMPLETO:** AsyncImage para thumbnails, VideoPlayer modal, fallbacks inteligentes
    - ✅ **COMPATIBILIDADE:** Interface idêntica ao antigo ListExerciseCard para substituição direta
    - ✅ **UX PREMIUM:** Indicador de vídeo, overlay play button, modal responsivo
    - **PENDÊNCIAS:**
      - [ ] Integração com ExerciseCardContent.swift → **Aguarda item 42** (ExerciseCardContent)
      - [ ] Substituir antigo ListExerciseCard.swift na ListExerciseView → **Aguarda item 82** (ListExerciseView)

36. [~] 🆕 **Atualizar** WorkoutExerciseCard.swift 🆕  
    - ✅ **RESPONSABILIDADE:** Componente reordenável para exercícios salvos localmente (CDPlanExercise, CDCurrentExercise, etc)
    - ✅ **CONTEXTOS:** Criação de treino, edição de treino, treino ativo
    - ✅ **FEATURES:** Drag & drop (por long press), delete action, todos recursos do ListExerciseCard
    - ✅ **REORDER:** Suporte a onMove, onDelete, integração com swipe actions e drag handle sempre visível
    - ✅ **VISUAL:** Drag handle ("line.horizontal.3") sempre exibido no canto direito do card
    - ✅ **SWIPE ACTIONS:** Swipe revela dois botões (Substituir e Deletar)
    - ✅ **ARQUITETURA:** Compatível com ExerciseDisplayable, Clean Architecture, sem lógica de negócio
    - ✅ **DOCUMENTAÇÃO:** Comentários e documentação em português seguindo padrão do projeto
    - ✅ **PREVIEW:** Compatível com MockDataProvider para previews
    - ✅ **SUBSTITUI:** Antigo WorkoutExerciseCard.swift (ver item 35.1)
    - **PENDÊNCIAS:**
      - [ ] Integrar ExerciseCardContent/ExerciseCardMediaView → **Aguarda itens 42-43** (ExerciseCardContent/ExerciseCardMediaView)
      - [ ] Migrar todas as views para o novo componente → **Aguarda itens 81-82** (Views que usam o componente)

37. [~] 🔄 **Atualizar** UploadButton.swift  
    - ✅ **RESPONSABILIDADE:** Permitir upload de treinos existentes pelo usuário (UI pronta)
    - ✅ **FEATURES:** Upload via câmera, galeria de fotos e arquivos (PDF, CSV, imagem) - opções já exibidas
    - ✅ **DESIGN:** Botão principal e sheet de opções com visual moderno e responsivo
    - ✅ **ARQUITETURA:** Componente puramente de UI, sem lógica de negócio, preparado para integração futura
    - ✅ **DOCUMENTAÇÃO:** Comentários e documentação em português seguindo padrão do projeto
    - ✅ **PREVIEW:** Compatível com preview SwiftUI
    - ✅ **CALLBACKS ESPECÍFICOS:** onCameraAction, onPhotosAction, onFilesAction para integração direta
    - ✅ **INTERFACE PREPARADA:** Pronto para uso com ImportWorkoutUseCase via dependency injection
    - **PENDÊNCIAS:**
      - [x] ✅ **Integrar lógica real de upload e parsing** → **Itens 39-41 CONCLUÍDOS** (ImportWorkout Use Cases/Services)
      - [x] ✅ **Conectar callbacks das opções a fluxos reais** → **CALLBACKS IMPLEMENTADOS** (onCameraAction, onPhotosAction, onFilesAction)
      - [ ] Integração efetiva na WorkoutView → **Aguarda refatoração das Views** (itens 80-82)

38. [x] 🔄 **Atualizar** WorkoutPlanCard.swift  
    - ✅ Refatorado seguindo o padrão dos novos cards reordenáveis (visual, drag handle, callbacks, sem lógica de negócio)
    - ✅ Documentação e comentários em português adicionados
    - ✅ Pronto para futura migração para ReorderableWorkoutCard.swift
    - ✅ Preview com dados mockados mantida
    - **DESTINO:** Após migração, será substituído por ReorderableWorkoutCard.swift
    - **FUTURO:** Excluir WorkoutPlanCard.swift após migração completa

39. [x] 🆕 **Criar** ImportWorkoutUseCase.swift ✅
    - ✅ **RESPONSABILIDADE:** Orquestrar todo o fluxo de importação de treinos a partir de arquivos (imagem, PDF, CSV)
    - ✅ **ARQUITETURA:** Use Case com orquestração de ImportWorkoutService + WorkoutDataService + SyncWorkoutUseCase
    - ✅ **CLEAN ARCHITECTURE:** Protocol + Implementation para testabilidade, dependency injection via inicializador
    - ✅ **TIPOS SUPORTADOS:** Imagem (OCR), PDF (parsing), CSV (planilhas) com validação de tipos UTType
    - ✅ **VALIDAÇÃO ROBUSTA:** Entrada, tamanho arquivo (10MB imagens, 50MB arquivos), dados parseados
    - ✅ **ERROR HANDLING:** ImportWorkoutError enum com 7 casos específicos de importação
    - ✅ **PARSING INTELIGENTE:** Detecção automática de grupos musculares e equipamentos
    - ✅ **TÍTULOS DUAIS:** autoTitle automático + customTitle extraído do arquivo ou personalizado
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** importFromCamera(), importFromFile(), importFromPhoto()
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro detalhado
    - ✅ **LOGIN OBRIGATÓRIO:** user: CDAppUser obrigatório conforme arquitetura do app
    - **PENDÊNCIAS:**
      - [x] ✅ **Integrar com ImportWorkoutService real** → **Item 40 CONCLUÍDO** (ImportWorkoutService)
      - [x] ✅ **Integrar validação Firebase de exercícios** → **Item 30 CONCLUÍDO** (FetchFBExercisesUseCase integrado)
      - [x] ✅ **Implementar sync real** → **Item 23 CONCLUÍDO** (SyncWorkoutUseCase integrado)

40. [x] 🆕 **Criar** ImportWorkoutService.swift ✅
    - ✅ **RESPONSABILIDADE:** Service completo para seleção, leitura e extração de dados de arquivos (imagem, PDF, CSV)
    - ✅ **ARQUITETURA:** Protocol + Implementation com parsers especializados (OCR, PDF, CSV)
    - ✅ **TECNOLOGIAS:** VisionKit (OCR), PDFKit (parsing PDF), Foundation (CSV parsing)
    - ✅ **TIPOS SUPORTADOS:** Imagem (.jpg/.png/.heic), PDF (.pdf), CSV (.csv) com validação UTType
    - ✅ **PARSING INTELIGENTE:** OCR para texto de fotos, PDF estruturado, CSV com cabeçalhos
    - ✅ **ERROR HANDLING:** ImportWorkoutServiceError enum com 9 casos específicos
    - ✅ **ASYNC/AWAIT:** Todas operações assíncronas com tratamento de erro detalhado
    - ✅ **PROTOCOLS SEPARADOS:** OCRParserProtocol, PDFParserProtocol, CSVParserProtocol
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** isOCRAvailable, supportedFileTypes, isFileTypeSupported
    - ✅ **VALIDAÇÃO ROBUSTA:** Verificação de capacidades, tipos de arquivo, dados extraídos
    - ✅ **CLEAN ARCHITECTURE:** Service puro sem lógica de negócio, retorna dados brutos
    - ✅ **INTEGRAÇÃO:** Interface preparada para ImportWorkoutUseCase usar via dependency injection
    - ✅ **EXEMPLOS USO:** Documentação completa com exemplos para todos os tipos suportados

41. [x] 🆕 **Criar** ImportWorkoutCard.swift ✅
    - ✅ **RESPONSABILIDADE:** Componente visual completo para exibir status de importação de treino
    - ✅ **ESTRUTURA:** Layout HStack idêntico ao WorkoutPlanCard (86px altura) com gráfico de pizza no lugar do drag handle
    - ✅ **UX AVANÇADA:** 5 estados (importing/processing/creating/success/error) com mensagens dinâmicas
    - ✅ **PROGRESS VIEW:** Círculo animado com percentual, checkmark (sucesso) e X (erro)
    - ✅ **INTEGRAÇÃO:** Interface preparada para WorkoutView como substituto temporário do WorkoutPlanCard
    - ✅ **TRANSIÇÃO SUAVE:** Visual consistente para transição automática após 100%
    - ✅ **MÉTODOS DE CONVENIÊNCIA:** .importing(), .processing(), .creating(), .success(), .error()
    - ✅ **CALLBACKS:** onTap para detalhes, onCancel para cancelar importação
    - ✅ **ANIMAÇÕES:** Spring animations, progress circle com easeInOut, scale effects
    - ✅ **CORES DINÂMICAS:** Blue (progresso), Green (sucesso), Red (erro) com bordas coloridas
    - ✅ **PREVIEWS COMPLETOS:** 2 previews com todos os estados e comparação visual WorkoutPlanCard
    - ✅ **EXEMPLOS DE USO:** Documentação completa com timers, error handling e integração

42. [ ] 🆕 **Criar** ExerciseCardContent.swift 🆕  
    - **RESPONSABILIDADE:** Componente central reutilizável com layout padrão
    - **LAYOUT:** Header (nome + drag handle), mídia central, footer (grupo + equipamento)
    - **ADAPTÁVEL:** Funciona com qualquer ExerciseDisplayable
    - **INTEGRAÇÃO:** ExerciseCardMediaView para área de vídeo/thumbnail

43. [ ] 🆕 **Criar** ExerciseCardMediaView.swift 🆕  
    - **RESPONSABILIDADE:** Componente inteligente de mídia contextual
    - **CONTEXTOS:** Thumbnail (lista), thumbnail + play (criação), vídeo inline (detalhes/ativo)
    - **STREAMING:** Vídeos via Firebase Storage URLs (sem download)
    - **PERFORMANCE:** Lazy loading, thumbnails primeiro
    - **OVERLAYS:** PlayButtonOverlay contextual

44. [ ] 🆕 **Criar** ExerciseVideoPlayerView.swift 🆕  
    - **RESPONSABILIDADE:** Player de vídeo otimizado com AVPlayer
    - **FEATURES:** Loading states, error handling, controles opcionais
    - **SIZES:** Adaptável (pequeno inline, grande fullscreen)
    - **CONFIG:** autoPlay, showControls, loop configuráveis
    - **FALLBACK:** Thumbnail quando vídeo indisponível

45. [ ] 🆕 **Criar** ExerciseThumbnailView.swift 🆕  
    - **RESPONSABILIDADE:** Visualização otimizada de thumbnails (gerados do vídeo)
    - **SOURCES:** Thumbnails gerados automaticamente do videoURL, placeholder padrão
    - **PERFORMANCE:** AsyncImage com cache, loading placeholder
    - **FALLBACK:** Ícone padrão quando vídeo/thumbnail indisponível
    - **🗑️ REMOÇÃO:** Não usar imageName - apenas videoURL para gerar thumbnails

46. [ ] 🆕 **Criar** PlayButtonOverlay.swift 🆕  
    - **RESPONSABILIDADE:** Overlay de play button contextual e responsivo
    - **VISUAL:** Design adaptável ao modo de exibição (grande/pequeno)
    - **BEHAVIOR:** Ações diferentes por contexto (inline play vs modal)
    - **ANIMATION:** Feedback visual em tap

47. [ ] 🆕 **Criar** ExerciseCardDisplayMode.swift 🆕  
    - **RESPONSABILIDADE:** Enum para diferentes modos de exibição de cards
    - **MODOS:** firebaseList, creation, editableList, details, activeWorkout
    - **PROPERTIES:** isReorderable, showVideoInline, allowsDeletion, videoSize
    - **CONTEXT:** Define comportamento específico para cada uso

---

## 🔄 Refatoração de Models, Protocols & Managers (Itens 41-44)

> **Objetivo:** Modernizar e organizar componentes de infraestrutura, protocolos de display e managers de hardware, garantindo Clean Architecture, injeção de dependências e separação clara de responsabilidades entre camadas.

48. [x] 🔄 **Atualizar** ExerciseDisplayable.swift ✅
    - ✅ **RESPONSABILIDADE:** Atualizar protocolo para refletir mudanças no modelo FitterModel
    - ✅ **COMPATIBILIDADE:** CDExerciseTemplate, CDPlanExercise, CDCurrentExercise, CDHistoryExercise
    - ✅ **PROPRIEDADES:** Padronizar displayName, muscleGroup, equipment, description
    - ✅ **🆕 MÍDIA:** videoURL, hasVideo, hasThumbnail para vídeo cards
    - ✅ **🗑️ REMOÇÃO:** Excluir campo `imageName` completamente do protocolo
    - ✅ **🔧 LEGSUBGROUP:** Campo `legSubgroup` apenas para exercícios de perna
    - ✅ **CLEAN ARCHITECTURE:** Separar lógica de display da lógica de negócio
    - ✅ **DEPENDÊNCIA:** Item 33.1 (Core Data Model com campos de vídeo) - CONCLUÍDO
    - **PENDÊNCIAS:**
      - [ ] Migrar ListExerciseCard.swift → **Item 77** (remover displayImageName)
      - [ ] Migrar WorkoutExerciseCard.swift → **Item 77** (remover displayImageName)
      - [ ] Corrigir previews nos ViewModels → **Itens 66-67** (remover imageName)

49. [ ] 🔄 **Atualizar** MotionManager.swift  
    - **RESPONSABILIDADE:** Modernizar captura de sensores para integração com Core Data
    - **SERIALIZAÇÃO:** Converter dados de movimento para JSON via CoreDataAdapter
    - **APPLE WATCH:** Otimizar coleta de dados em background e foreground
    - **PERFORMANCE:** Sampling rate otimizado, battery efficiency, memory management

50. [ ] 🔄 **Atualizar** WatchDataManager.swift  
    - **RESPONSABILIDADE:** Modernizar persistência e sincronização Watch-iPhone
    - **PERSISTÊNCIA:** Usar WorkoutDataService para operações CRUD no Watch
    - **CONECTIVIDADE:** Sync via WatchConnectivity com retry automático
    - **REAL-TIME:** Sincronização instantânea de dados críticos de treino

51. [ ] 🆕 **Criar** HealthKitManager.swift  
    - **RESPONSABILIDADE:** Centralizar toda interação com HealthKit em serviço dedicado
    - **OPERAÇÕES:** Autorização, leitura/escrita, background delivery, workout sessions
    - **TARGETS:** Métodos claros para uso em iOS e watchOS
    - **DEPENDENCY INJECTION:** Remover lógica HealthKit de Apps e ViewModels, injetar via DI

52. [ ] 🆕 **Criar** TimerService.swift 🆕  
    - **RESPONSABILIDADE:** Centralizar toda lógica de timers do app (séries, descanso, workout, inatividade)
    - **ARQUITETURA:** Protocol + Implementation com TimerController para cada tipo de timer
    - **TIPOS DE TIMER:** Duração série, descanso entre séries/exercícios, workout total, inatividade, timeout
    - **WATCH INTEGRATION:** Sincronização automática de timers entre Apple Watch e iPhone
    - **UI REACTIVA:** Combine Publishers para binding automático com Views
    - **AUTO-ACTIONS:** Callbacks automáticos (EndSet → StartSet, EndExercise → StartExercise)
    - **DEPENDENCY INJECTION:** Injetar nos Use Cases (StartSet, EndSet, StartExercise, EndExercise)
    - **FUNCIONALIDADES:** Pausar/retomar, cancelar, notificações locais, persistência de estado
    - **TESTABILIDADE:** Mock TimerService para testes automatizados
    - **BENEFÍCIOS:** Centralização, reutilização, consistência, Watch sync, UX fluída

---

## 🔑 Autenticação Modular & Login Social (Itens 46-51)

> **Objetivo:** Refatorar autenticação para Clean Architecture, separar responsabilidades e suportar todos provedores (Apple, Google, Facebook, Email, Biometria).

53. [ ] 🆕 **Criar** AuthUseCase.swift  
    - **RESPONSABILIDADE:** Orquestrar todos fluxos de autenticação (Apple, Google, Facebook, Email, Biometria)
    - **ARQUITETURA:** Injetar serviços via protocolo, ser único ponto de decisão de login/cadastro/logout
    - **INTEGRAÇÃO:** Preparar interface com SubscriptionManager para fluxo de usuário premium/free
    - **DETALHES ADICIONAIS:** Implementar login automático com biometria, guardar histórico de provedores utilizados
    - **🆕 LOGOUT POR INATIVIDADE:** Implementar controle de `lastAppOpenDate` e logout automático após 7 dias
    - **🆕 SEGURANÇA:** Métodos `checkInactivityTimeout()`, `logoutDueToInactivity()`, `updateLastAppOpenDate()`

54. [ ] 🆕 **Criar** protocolos para provedores de autenticação  
    - **RESPONSABILIDADE:** Definir interfaces limpas para cada provedor de login
    - **ARQUIVOS:** AppleSignInServiceProtocol, GoogleSignInServiceProtocol, FacebookSignInServiceProtocol, BiometricAuthServiceProtocol
    - **DETALHES:** Cada protocolo define interface limpa para login/logout e tratamento de erros do provedor
    - **TESTABILIDADE:** Permitir mocks para testes unitários e de UI

55. [ ] 🆕 **Criar** serviços para cada provedor  
    - **RESPONSABILIDADE:** Implementar serviços separados com responsabilidade única
    - **ARQUIVOS:** AppleSignInService, GoogleSignInService, FacebookSignInService, BiometricAuthService
    - **DETALHES:** Serviços sem lógica de UI, expor fluxos assíncronos prontos para usar no UseCase
    - **ARQUITETURA:** Clean Architecture, dependency injection, sem dependências cruzadas

55.1. [ ] 🔄 **Atualizar** AuthService.swift  
    - **RESPONSABILIDADE:** Implementar AuthServiceProtocol apenas para métodos CRUD (email/senha)
    - **REFATORAÇÃO:** Remover qualquer referência a UseCases, lógica de orquestração ou navegação
    - **DETALHES:** Garantir testabilidade, injeção de dependência e fácil mock
    - **LIMITAÇÕES:** Nenhuma chamada cruzada para provedores sociais

55.2. [ ] 🔗 **Integrar** biometria ao fluxo de login e bloqueio  
    - **RESPONSABILIDADE:** Configurar biometria independente do provedor de login
    - **OPERAÇÕES:** Oferecer ativação após login, fallback seguro, expiração de sessão
    - **UX:** Tela de configuração, ativação/desativação no perfil

---

## 🛡️ Biometria Avançada (FaceID/TouchID) (Itens 51-52)

> **Objetivo:** Implementar autenticação biométrica avançada independente do provedor de login, com fallbacks seguros, expiração de sessão e integração completa ao ciclo de vida do app.

56. [ ] 🆕 **Criar** BiometricAuthService.swift  
    - **RESPONSABILIDADE:** Interface completa com LAContext para autenticação biométrica
    - **OPERAÇÕES:** Autenticar, checar disponibilidade, validar fallback, gerenciar tokens seguros
    - **SEGURANÇA:** Salvar token seguro para login automático via Keychain
    - **INTEGRAÇÃO:** AuthUseCase, SessionManager, background/foreground lifecycle

57. [ ] 🔗 **Integrar** biometria ao fluxo de login e bloqueio do app  
    - **RESPONSABILIDADE:** Implementar fluxo completo de biometria no app
    - **OPERAÇÕES:** Ativação após login, desbloqueio com Face ID/Touch ID, fallback para senha
    - **UX:** Configuração na tela de perfil, onboarding de ativação, feedback visual
    - **COMPATIBILIDADE:** Suporte a dispositivos sem biometria, degradação elegante

---

## 💳 Sistema de Assinaturas & Monetização (Itens 53-62)

> **Objetivo:** Implementar sistema completo de assinaturas In-App (mensal/anual), controle granular de acesso premium, monetização via anúncios e integração robusta com StoreKit 2 para maximizar conversão e retenção.

58. [ ] 🆕 **Criar** SubscriptionService.swift  
    - **RESPONSABILIDADE:** Integração completa com StoreKit 2 para gestão de assinaturas
    - **OPERAÇÕES:** Listagem de produtos, compra, restore, validação de recibos, renovação automática
    - **ESTADOS:** Tratar todos estados (pendente, ativo, expirado, cancelado, grace period)
    - **REAL-TIME:** Callbacks para atualização de status em tempo real via StoreKit observers

59. [ ] 🆕 **Criar** SubscriptionManager.swift  
    - **RESPONSABILIDADE:** Orquestrar status de assinatura com persistência e sincronização
    - **OPERAÇÕES:** Gerenciar estado local, sync com CloudSyncManager, cache inteligente
    - **CORE DATA:** Atualizar CDAppUser no Core Data após alteração de assinatura
    - **FIRESTORE:** Sincronização automática com backend para controle server-side

60. [x] 🆕 **Criar** enum SubscriptionType em Shared/Models/SubscriptionType.swift ✅
    - ✅ **RESPONSABILIDADE:** Definir tipos de assinatura com compatibilidade Core Data
    - ✅ **ENUM:** SubscriptionType: Int16 { case none, monthly, yearly, lifetime }
    - ✅ **CORE DATA:** Atualizar CDAppUser com subscriptionType e subscriptionValidUntil
    - ✅ **COMPUTED PROPERTIES:** isSubscriber, isActive, daysUntilExpiration, subscriptionStatus
    - ✅ **CRIADO EM:** Item 33.1 junto com Core Data Model

60.1. [ ] 🔗 **Integrar** produtos In-App Purchase  
    - **RESPONSABILIDADE:** Configurar produtos no App Store Connect e integrar ao app
    - **PRODUTOS:** "fitter.monthly" (R$9,99/mês), "fitter.yearly" (R$99,99/ano), "fitter.lifetime" (R$199,99)
    - **AUTOMAÇÃO:** Buscar e validar produtos automaticamente no launch
    - **LOCALIZAÇÃO:** Suporte a múltiplas moedas e regiões

61. [ ] ⚙️ **Implementar** fluxo de compra, restore, upgrade, downgrade  
    - **RESPONSABILIDADE:** Fluxos completos de monetização com UX otimizada
    - **OPERAÇÕES:** Comprar, restaurar, migrar planos, cancelar, reativar assinatura
    - **ASYNC/AWAIT:** Métodos assíncronos claros com tratamento de erro robusto
    - **UX:** Loading states, confirmações, feedback de sucesso/erro

62. [x] ⚙️ **Configurar** produtos e persistência de assinaturas ✅
    - ✅ **RESPONSABILIDADE:** Configurar persistência de assinaturas no Core Data
    - ✅ **CORE DATA:** Campos incluídos no item 33.1 (subscriptionType, subscriptionValidUntil, subscriptionStartDate)
    - ✅ **ENUM:** SubscriptionType.swift criado com productIds para App Store
    - ✅ **MIGRATIONS:** Migração configurada no item 33.1
    - **PENDÊNCIAS:**
      - [ ] Sincronização automática com CloudSyncManager via SubscriptionManager

63. [ ] ⚙️ **Implementar** UI e lógica de acesso restrito  
    - **RESPONSABILIDADE:** Interface e controle de acesso baseado em assinatura
    - **PREMIUM FEATURES:** Liberação condicional para assinantes premium
    - **FREE TIER:** Banner/publicidade para usuários free, limitações claras
    - **MONETIZAÇÃO:** Placeholder para AdMob/AdServices integration

64. [ ] ⚙️ **Implementar** bloqueio de funcionalidades premium  
    - **RESPONSABILIDADE:** Validação de assinatura antes de acessar recursos premium
    - **FEATURES BLOQUEADAS:** Histórico completo, relatórios avançados, treinos ilimitados
    - **PAYWALL:** Telas de upgrade com call-to-action otimizado
    - **ANALYTICS:** Tracking de conversão e abandonos

65. [ ] ⚙️ **Implementar** alertas e tratamento de erros  
    - **RESPONSABILIDADE:** UX otimizada para todos os fluxos de assinatura
    - **MENSAGENS:** Alertas amigáveis, feedback claro, instruções de recuperação
    - **FALLBACKS:** Modo offline, retry automático, suporte ao usuário
    - **TRACKING:** Log de erros para otimização contínua

66. [ ] ⚙️ **Implementar** analytics e otimização de conversão  
    - **RESPONSABILIDADE:** Métricas de negócio para otimizar monetização
    - **KPIs:** Conversion rate, churn rate, LTV, trial-to-paid conversion
    - **A/B TESTING:** Paywall variants, pricing tests, messaging optimization
    - **REVENUE:** Revenue tracking, subscription analytics dashboard

---

## 🚀 Arquitetura de Bootstrap & Setup Global (Itens 62-63)

> **Objetivo:** Centralizar e profissionalizar a inicialização dos apps iOS e watchOS, configurando serviços críticos (Core Data, HealthKit, autenticação, sincronização) de forma desacoplada via dependency injection, eliminando singletons e preparando base escalável para Clean Architecture.

67. [ ] 🔄 **Atualizar** iOSApp.swift  
    - **RESPONSABILIDADE:** Modernizar entry point do app com Clean Architecture e DI
    - **CORE DATA:** Configurar PersistenceController como fonte única, substituir CoreDataStack
    - **DEPENDENCY INJECTION:** Criar e injetar todos serviços via Environment/StateObject
    - **VIEWMODELS:** Centralizar status global em BaseViewModel/AppViewModel
    - **HEALTHKIT:** Delegar autorização para HealthKitManager dedicado
    - **AUTHENTICATION:** Usar AuthUseCase para fluxos de login, não ViewModels diretos
    - **SUBSCRIPTION:** Integrar SubscriptionManager para controle premium/free
    - **TESTABILIDADE:** Preparar injeção de mocks para previews e testes
    - **🆕 LOGOUT POR INATIVIDADE:** Implementar verificação de 7 dias no `.onAppear`
    - **🆕 SEGURANÇA:** Integrar `checkAndHandleInactivity()` no launch do app
    - **PENDÊNCIAS:**
      - [ ] 🏗️ **USE CASES:** Injetar todos os Use Cases criados → **Aguarda itens 17-30** (Use Cases)
      - [ ] 🏗️ **AUTHENTICATIONE:** Usar AuthUseCase → **Aguarda item 53** (AuthUseCase)
      - [ ] 🏗️ **HEALTHKIT:** Integrar HealthKitManager → **Aguarda item 51** (HealthKitManager)
      - [ ] 🏗️ **SUBSCRIPTION:** Integrar SubscriptionManager → **Aguarda itens 58-66** (SubscriptionManager)
      - [ ] 🏗️ **BASEVIEWMODEL:** Usar BaseViewModel modernizado → **Aguarda item 14** (BaseViewModel AuthUseCase migration)

68. [ ] 🔄 **Atualizar** WatchApp.swift  
    - **RESPONSABILIDADE:** Modernizar app watchOS com arquitetura consistente ao iOS
    - **PERSISTENCE:** Configurar PersistenceController compartilhado ou referência Shared
    - **MANAGERS:** Injetar MotionManager, WatchDataManager, ConnectivityManager via DI
    - **HEALTHKIT:** Usar HealthKitManager dedicado via Environment
    - **NAVIGATION:** Padronizar fluxo (autenticado → WatchView, não autenticado → PendingLoginView)
    - **CONSISTENCY:** Manter consistência com app iOS para facilitar manutenção
    - **TESTING:** Preparar mocks e previews para desenvolvimento iterativo

---

## 🎯 Refatoração dos ViewModels para Clean Architecture (Itens 64-68)

> **Objetivo:** Modernizar, desacoplar e padronizar ViewModels para Clean Architecture, removendo dependências diretas de serviços singletons, implementando injeção de dependências e garantindo uso exclusivo de UseCases para lógica de negócio.

69. [ ] 🔄 **Atualizar** LoginViewModel.swift  
    - **RESPONSABILIDADE:** Herdar de BaseViewModel e modernizar para AuthUseCase
    - **DEPENDENCY INJECTION:** Injeção via init para AuthUseCase, testabilidade
    - **CLEAN ARCHITECTURE:** Remover chamadas diretas a AuthService
    - **UX:** Gerenciar loading, erro, sucesso com estados padronizados
    - **PENDÊNCIAS:**
      - [ ] 🏗️ **HERANÇA:** Herdar de BaseViewModel → **Aguarda item 14** (BaseViewModel AuthUseCase migration)
      - [ ] 🔄 **MIGRAÇÃO:** Substituir AuthService → **Aguarda item 53** (AuthUseCase)

70. [ ] 🔄 **Atualizar** CreateAccountViewModel.swift  
    - **RESPONSABILIDADE:** Herdar de BaseViewModel e usar AuthUseCase
    - **OPERATIONS:** Tratar loading, erro, sucesso de cadastro de forma consistente
    - **VALIDATION:** Validações client-side antes de chamar UseCase
    - **UX:** Feedback de criação de conta com mensagens padronizadas
    - **PENDÊNCIAS:**
      - [ ] 🏗️ **HERANÇA:** Herdar de BaseViewModel → **Aguarda item 14** (BaseViewModel AuthUseCase migration)
      - [ ] 🔄 **MIGRAÇÃO:** Substituir AuthService → **Aguarda item 53** (AuthUseCase)

71. [ ] 🔄 **Atualizar** ListExerciseViewModel.swift  
    - **RESPONSABILIDADE:** Modernizar para usar FetchFBExercisesUseCase mantendo filtros existentes
    - **🔄 MIGRAÇÃO CLEAN ARCHITECTURE:** Substituir FirebaseExerciseService.shared por FetchFBExercisesUseCase via DI
    - **🎯 MANTER FILTROS EXISTENTES:** Preservar sistema hierárquico (grupo → equipamento → pegada)
    - **📊 MANTER PRIORIZAÇÃO:** Equipamentos ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"] primeiro
    - **📊 MANTER PRIORIZAÇÃO:** Pegadas ["Pronada", "Supinada", "Neutra"] primeiro, resto alfabético
    - **🔍 MANTER ORDENAÇÃO:** Selecionados primeiro (alfabético), depois não selecionados (alfabético)
    - **🔍 MANTER BUSCA:** Nome > Equipamento > Pegada com ordenação especial durante busca
    - **DEPENDENCY INJECTION:** FetchFBExercisesUseCase via inicializador, herdar BaseViewModel
    - **OPERATIONS:** execute() para pull-to-refresh, exercisesPublisher() para realtime
    - **LIFECYCLE:** startListening() no onAppear, stopListening() no onDisappear
    - **PERFORMANCE:** Gerenciamento otimizado de listeners Firebase
    - **⚠️ DEPENDÊNCIA ATIVA:** Ainda usa `FirebaseExerciseService.shared` (linhas 26, 30)
    - **PENDÊNCIAS:**
      - [x] ✅ **ExerciseDisplayable:** Protocolo atualizado (item 48) - CONCLUÍDO
      - [ ] 🗑️ **REMOÇÃO:** Remover qualquer referência a `imageName` no código → **Aguarda item 48** (ExerciseDisplayable)
      - [ ] 🔧 **CAMPOS FIREBASE:** Atualizar para usar `description` em vez de instruções hardcoded → **Aguarda item 32** (FirebaseExercise)
      - [ ] 🔄 **MIGRAÇÃO:** Substituir FirebaseExerciseService → **Aguarda item 30** (FetchFBExercisesUseCase)
      - [ ] 🏗️ **HERANÇA:** Herdar de BaseViewModel → **Aguarda item 14** (BaseViewModel AuthUseCase migration)

72. [ ] 🔄 **Atualizar** WorkoutViewModel.swift  
    - **RESPONSABILIDADE:** Herdar de BaseViewModel e usar todos os Use Cases CRUD
    - **USE CASES:** Create, Fetch, Update, Delete, Reorder (workout e exercise)
    - **TÍTULOS DUAIS:** Compatibilidade com autoTitle/customTitle/displayTitle
    - **🔄 MIGRAÇÃO FIREBASE:** Substituir FirebaseExerciseService por FetchFBExercisesUseCase
    - **🎯 MANTER FUNCIONALIDADES:** Preservar toda lógica de exercícios Firebase existente
    - **⚠️ DEPENDÊNCIA ATIVA:** Usa extensivamente `FirebaseExerciseService` (8+ ocorrências)
    - **PENDÊNCIAS:** 
      - [x] ✅ **ExerciseDisplayable:** Protocolo atualizado (item 48) - CONCLUÍDO
      - [ ] Migrar createWorkoutPlan(autoTitle:customTitle:) → **Aguarda item 17** (CreateWorkoutUseCase)
      - [ ] Migrar ReorderWorkoutUseCase → **Aguarda item 21** (ReorderWorkoutUseCase)
      - [ ] Migrar todas chamadas FirebaseExerciseService → **Aguarda item 30** (FetchFBExercisesUseCase)
      - [ ] 🗑️ **REMOÇÃO:** Remover qualquer referência a `imageName` → **Aguarda item 48** (ExerciseDisplayable)
      - [ ] 🔧 **CAMPOS FIREBASE:** Atualizar para usar novos campos → **Aguarda item 32** (FirebaseExercise)
      - [ ] 🏗️ **HERANÇA:** Herdar de BaseViewModel → **Aguarda item 14** (BaseViewModel AuthUseCase migration)

73. [ ] 🔄 **Padronizar** todos os ViewModels para AuthUseCase exclusivo  
    - **RESPONSABILIDADE:** Garantir que Views nunca usem AuthService diretamente
    - **ARCHITECTURE:** Apenas AuthUseCase para operações de autenticação
    - **FALLBACK:** Lógica para múltiplos provedores via UseCase
    - **CONSISTENCY:** Padrão uniforme em todo o app

## 🎨 Refatoração das Views para Clean Architecture & DI (Itens 69-84)

> **Objetivo:** Modernizar todas as Views para usar padrões consistentes de dependency injection, remover @Environment direto de managedObjectContext, implementar @EnvironmentObject para ViewModels e garantir que toda lógica de negócio seja feita via UseCases.

74. [ ] 🔄 **Atualizar** CreateAccountView.swift  
    - **RESPONSABILIDADE:** Modernizar para padrões de DI e Clean Architecture
    - **DEPENDENCY INJECTION:** Substituir @Environment(\.managedObjectContext) por PersistenceController
    - **VIEWMODEL:** Usar @EnvironmentObject para AuthViewModel via DI
    - **ARCHITECTURE:** Remover @StateObject local, usar injeção externa

75. [ ] 🔄 **Atualizar** LoginView.swift  
    - **RESPONSABILIDADE:** Modernizar para AuthUseCase via BaseViewModel
    - **CLEAN ARCHITECTURE:** Remover @Environment(\.managedObjectContext)
    - **DEPENDENCY INJECTION:** Injetar LoginViewModel como @StateObject via DI
    - **UX:** Usar estados padronizados de loading/erro/sucesso

76. [ ] 🔄 **Atualizar** HomeView.swift  
    - **RESPONSABILIDADE:** Modernizar para SyncWorkoutUseCase
    - **OPERATIONS:** Substituir chamadas diretas ConnectivityManager por UseCase
    - **VIEWMODEL:** Usar @EnvironmentObject para AuthViewModel
    - **SYNC:** Integração com sistema de sincronização moderno

77. [ ] 🔄 **Atualizar** HistoryView.swift  
    - **RESPONSABILIDADE:** Modernizar exibição de histórico via WorkoutDataService
    - **DATA BINDING:** Adicionar binding com WorkoutDataService para histórico
    - **CLEANUP:** Remover ConnectivityManager se não usado
    - **PERFORMANCE:** Paginação e lazy loading para grandes volumes

78. [ ] 🔄 **Atualizar** MainTabView.swift  
    - **RESPONSABILIDADE:** Modernizar navegação principal com ViewModels injetados
    - **VIEWMODELS:** Usar @EnvironmentObject para AuthViewModel e BaseViewModel
    - **NAVIGATION:** Remover lógica de reset de aba, usar NavigationRouter se existir
    - **STATE MANAGEMENT:** Centralizar estado de navegação

79. [ ] 🔄 **Atualizar** ProfileView.swift  
    - **RESPONSABILIDADE:** Modernizar perfil para AuthUseCase
    - **DEPENDENCY INJECTION:** Injetar AuthUseCase em vez de AuthService.shared
    - **CLEANUP:** Remover @Environment(\.managedObjectContext)
    - **FEATURES:** Integração com configurações de biometria e assinatura

80. [ ] 🔄 **Atualizar** WorkoutView.swift  
    - **RESPONSABILIDADE:** Modernizar tela principal de treinos
    - **DEPENDENCY INJECTION:** Injetar WorkoutViewModel como @StateObject externo
    - **DATA LAYER:** Substituir binding CoreData direto por WorkoutDataService e UseCases
    - **REAL-TIME:** Integração com sistema de sincronização em tempo real

81. [ ] 🔄 **Atualizar** CreateWorkoutView.swift  
    - **RESPONSABILIDADE:** Modernizar criação de treinos
    - **DEPENDENCY INJECTION:** Receber WorkoutViewModel via DI
    - **CLEANUP:** Remover @Environment(\.managedObjectContext)
    - **SYNC:** Usar SyncWorkoutUseCase após salvar
    - **🆕 VÍDEO CARDS:** Usar WorkoutExerciseCard.swift para exercícios
    - **PENDÊNCIAS:**
      - [ ] 🔄 **VIEWMODEL:** Usar ViewModel refatorado → **Aguarda item 72** (WorkoutViewModel)
      - [ ] 🆕 **VÍDEO CARDS:** Usar WorkoutExerciseCard.swift → **Aguarda item 36** (WorkoutExerciseCard)

82. [ ] 🔄 **Atualizar** ListExerciseView.swift ⚠️ CORRIGIR BUGS UX
    - **RESPONSABILIDADE:** Refatoração completa com correção de scroll/animações quebradas
    - **🔧 CORRIGIR SCROLL ANIMATION:** Implementar barra de pesquisa que esconde/mostra corretamente com scroll
    - **🔧 CORRIGIR FILTROS UI:** Reescrever sistema visual de filtros hierárquicos com animações funcionais
    - **🔧 CORRIGIR SCROLL OFFSET:** Reimplementar ScrollOffsetKey e animações baseadas em progress (funcionando)
    - **🔧 CORRIGIR SEARCHBAR:** Reescrever SearchBar UIViewRepresentable com animações suaves funcionais
    - **🔧 CORRIGIR FILTROS VIEW:** Recriar FiltrosView com pills interativos e "Remover filtros" funcionais
    - **🔧 CORRIGIR HIDE KEYBOARD:** Reimplementar gesture para esconder teclado durante scroll (funcionando)
    - **🎯 MANTER APENAS LÓGICA:** Preservar apenas a lógica de filtros do ViewModel (que funciona)
    - **🎯 MANTER APENAS UI DESIGN:** Preservar apenas o design visual (pills, cores, layout)
    - **⚠️ REESCREVER ANIMAÇÕES:** Toda lógica de animação/scroll deve ser reescrita do zero para funcionar
    - **🎯 TECNOLOGIA SCROLL:** Usar `ScrollViewReader` + `onPreferenceChange` ou alternativa que funcione
    - **🎯 TESTE SCROLL:** Testar em simulador + dispositivo físico para garantir funcionamento
    - **🎯 PERFORMANCE:** Otimizar animações para não travar durante scroll rápido
    - **🎯 EDGE CASES:** Testar com lista vazia, poucos itens, muitos itens, orientação
    - **USE CASES:** Remover FirebaseExerciseService.shared, usar FetchFBExercisesUseCase
    - **DEPENDENCY INJECTION:** Injetar ListExerciseViewModel via DI  
    - **REAL-TIME:** Integração com listeners Firebase otimizados
    - **🆕 VÍDEO CARDS:** Usar novo ListExerciseCard.swift para exercícios Firebase
    - **PENDÊNCIAS:**
      - [x] ✅ **ExerciseDisplayable:** Protocolo atualizado (item 48) - CONCLUÍDO
      - [ ] 🗑️ **REMOÇÃO:** Remover qualquer referência a `displayImageName` → **Aguarda item 48** (ExerciseDisplayable)
      - [ ] 🗑️ **REMOÇÃO:** Remover antigo ListExerciseCard.swift → **Aguarda item 35** (novo ListExerciseCard)
      - [ ] 🔄 **MIGRAÇÃO:** Substituir antigo ListExerciseCard por novo → **Aguarda item 35** (novo ListExerciseCard)
      - [ ] 🔄 **VIEWMODEL:** Usar ViewModel refatorado → **Aguarda item 71** (ListExerciseViewModel)

83. [ ] 🔄 **Atualizar** DetailWorkoutView.swift  
    - **RESPONSABILIDADE:** Modernizar detalhes de treino
    - **TÍTULOS DUAIS:** ✅ displayTitle aplicado (linhas 28, 38, 116)
    - **PENDÊNCIAS:** 
      - [ ] Atualizar edição de título para usar customTitle (linha 54)
      - [ ] Integração com Update/Delete UseCases → **Aguarda item 19/20** (Update/DeleteWorkoutUseCase)
      - [ ] 🆕 VÍDEO CARDS: Usar ListExerciseCard.swift → **Aguarda item 35** (novo ListExerciseCard)

84. [ ] 🆕 **Criar** EditWorkoutView.swift 🆕  
    - **RESPONSABILIDADE:** Nova view para edição de treinos (separada de criação)
    - **VÍDEO CARDS:** Usar ReorderableExerciseVideoCard.swift com modo editableList
    - **OPERATIONS:** Editar título customTitle, reordenar exercícios, remover exercícios
    - **USE CASES:** UpdateWorkoutUseCase, ReorderExerciseUseCase
    - **NAVIGATION:** Acessível via DetailWorkoutView.swift

85. [ ] 🔄 **Atualizar** WorkoutPlanCard.swift  
    - **RESPONSABILIDADE:** Modernizar componente de card de treino
    - **TÍTULOS DUAIS:** 
      - [ ] Atualizar safeTitle → displayTitle (linhas 38, 98, 99)
    - **COMPONENTS:** Padronizar com design system
    - **PERFORMANCE:** Otimizar renderização para listas grandes

86. [ ] 🆕 **Criar** ActiveWorkoutView.swift 🆕 (futuro)  
    - **RESPONSABILIDADE:** Nova view para treinos ativos (próxima versão)
    - **VÍDEO CARDS:** Usar ReorderableExerciseVideoCard.swift com modo activeWorkout
    - **FEATURES:** Vídeos inline, reordenação durante treino, progressão em tempo real
    - **USE CASES:** Start/End Workout/Exercise/Set UseCases
    - **AGUARDA:** Itens 24-29 (Use Cases de Lifecycle)

87. [ ] 🆕 **Criar** NavigationRouter.swift (opcional)  
    - **RESPONSABILIDADE:** Centralizar navegação do app se necessário
    - **OPERATIONS:** Gerenciar deep links, tab switching, modal presentation
    - **STATE:** Integração com AuthUseCase para redirecionamentos
    - **TESTING:** Facilitar testes de navegação

## 📱 Sistema de Mocks & Testes para Desenvolvimento (Itens 83-101)

> **Objetivo:** Criar sistema robusto e profissional de dados mock para maximizar produtividade no desenvolvimento, garantir previews consistentes, facilitar testes de UI, eliminar dependências externas no Preview Canvas do Xcode e cobrir todos os fluxos críticos com testes unitários e de integração.

88. [ ] 🆕 **Criar** MockDataProvider.swift  
    - **RESPONSABILIDADE:** Provedor centralizado de dados mock para todas as entidades
    - **ENTIDADES:** Dados realistas para CDWorkoutPlan, CDExerciseTemplate, CDAppUser, CDWorkoutHistory
    - **CENÁRIOS:** Planos vazios, com exercícios, histórico completo, usuários premium/free
    - **TÍTULOS DUAIS:** Suporte completo a autoTitle/customTitle/displayTitle
    - **🆕 MÍDIA:** Firebase exercícios com videoURL/thumbnailURL mock

89. [ ] 🆕 **Criar** MockPersistenceController.swift  
    - **RESPONSABILIDADE:** In-memory Core Data stack otimizado para previews
    - **PERFORMANCE:** Pre-população automática com dados mock, contextos isolados
    - **ISOLATION:** Evitar conflitos entre previews simultâneos
    - **MEMORY:** Gestão otimizada de memória para desenvolvimento iterativo

90. [ ] 🆕 **Criar** MockWorkoutDataService.swift  
    - **RESPONSABILIDADE:** Implementação completa mock do WorkoutDataServiceProtocol
    - **OPERATIONS:** Simulação de CRUD sem persistência real, delays realistas
    - **ERROR STATES:** Estados de erro controlados para testar UI de error handling
    - **ASYNC/AWAIT:** Compatibilidade completa com contratos reais

91. [ ] 🆕 **Criar** MockUseCases.swift  
    - **RESPONSABILIDADE:** Mocks para todos Use Cases (CRUD, Auth, Sync, Lifecycle)
    - **SCENARIOS:** Respostas configuráveis para success/loading/error
    - **CONSISTENCY:** Dados de retorno consistentes com contratos reais
    - **TESTING:** Facilitar testes de integração UI-UseCase

92. [ ] 🆕 **Criar** MockAuthService.swift  
    - **RESPONSABILIDADE:** Simulação completa de estados de autenticação
    - **USERS:** Usuários mock com perfis diversos (premium/free, múltiplos provedores)
    - **FLOWS:** Simulação de login/logout/cadastro/biometria
    - **STATES:** Loading, erro, sucesso, expiração de sessão

93. [ ] 🆕 **Criar** MockConnectivityManager.swift  
    - **RESPONSABILIDADE:** Simulação de conectividade e sincronização
    - **STATES:** Online/offline, Apple Watch connected/disconnected
    - **SYNC:** Dados de sincronização simulados, retry scenarios
    - **CONTROL:** Controle manual de estados para preview testing

94. [ ] 🆕 **Criar** MockSensorData.swift  
    - **RESPONSABILIDADE:** Dados realistas de sensores Apple Watch
    - **METRICS:** Heart rate, calories, movimento, intensity variations
    - **WORKOUTS:** Simulação de diferentes tipos e intensidades de treino
    - **ANALYTICS:** Dados históricos para gráficos e estatísticas

95. [ ] 🆕 **Criar** PreviewExtensions.swift  
    - **RESPONSABILIDADE:** Extensions e utilities para otimizar criação de previews
    - **CONFIGURATIONS:** Configurações pré-definidas para diferentes cenários
    - **HELPERS:** ViewModels pré-configurados com dados mock
    - **SNAPSHOTS:** Estados de tela diversos (empty, loading, error, success)
    - **🆕 MÍDIA:** Helpers para previews com vídeo cards

96. [ ] 🔄 **Atualizar** todas as Views com Previews otimizadas  
    - **RESPONSABILIDADE:** Padronizar previews em todas as Views do app
    - **DATA:** Substituir dados hardcoded por MockDataProvider
    - **SCENARIOS:** Múltiplos cenários (loading, error, success, empty, premium/free)
    - **RESPONSIVE:** Preview para diferentes tamanhos de tela e orientações
    - **THEMES:** Dark/Light mode para todas as previews
    - **🆕 VÍDEO CARDS:** Previews com ListExerciseCard e WorkoutExerciseCard

97. [ ] 🆕 **Criar** MockWorkoutSession.swift  
    - **RESPONSABILIDADE:** Simulação completa de sessões de treino ativas
    - **PROGRESS:** Progresso realista de exercícios e séries
    - **REAL-TIME:** Dados de Apple Watch simulados em tempo real
    - **STATES:** Todos estados (iniciando, em progresso, pausado, finalizado)

98. [ ] 🗑️ **Excluir** PreviewDataLoader.swift  
    - **MOTIVO:** Substituído por sistema estruturado MockDataProvider + MockPersistenceController
    - **UPGRADE:** Dados hardcoded → sistema flexível e configurável
    - **COMPATIBILITY:** Campos obsoletos → alinhado com FitterModel

99. [ ] 🗑️ **Excluir** PreviewCoreDataStack.swift  
    - **MOTIVO:** Modelo antigo "Model" → novo "FitterModel"
    - **UPGRADE:** Funcionalidades limitadas → MockPersistenceController completo
    - **FLEXIBILITY:** Sistema rígido → múltiplos cenários configuráveis
    - **⚠️ INCONSISTÊNCIA:** Ainda existe e usa modelo "Model" antigo (linha 12)

100. [ ] 🆕 **Criar** testes unitários e mocks de autenticação  
    - **RESPONSABILIDADE:** Cobrir todos os fluxos de autenticação com testes completos
    - **DETALHES:** Criar mocks para todos protocolos de autenticação
    - **COBERTURA:** Login social, email, biometria, logout, erro, múltiplos provedores

101. [ ] 🧪 **Testar** flows de biometria em diferentes dispositivos e estados  
    - **RESPONSABILIDADE:** Garantir compatibilidade e robustez em todos cenários
    - **CENÁRIOS:** Dispositivos sem biometria, múltiplos usuários, expiração de sessão
    - **TESTES:** Bloqueio/desbloqueio, falhas de autenticação, background/foreground
    - **VALIDAÇÃO:** Performance, segurança, UX em diferentes estados do sistema

102. [ ] 🆕 **Criar** testes unitários e de UI para monetização  
    - **RESPONSABILIDADE:** Garantir qualidade e robustez do sistema de assinaturas
    - **COBERTURA:** StoreKit integration, subscription flows, edge cases
    - **SCENARIOS:** Compra, restore, upgrade, erro de rede, subscription expiry
    - **AUTOMATION:** CI/CD integration, regression testing

103. [ ] 🆕 **Criar** testes de integração para vídeo cards 🆕  
    - **RESPONSABILIDADE:** Validar comportamento dos componentes de vídeo
    - **COBERTURA:** ListExerciseCard, WorkoutExerciseCard, media loading
    - **SCENARIOS:** Different display modes, streaming, fallbacks, performance
    - **VISUAL:** Snapshot testing para garantir consistência visual

104. [ ] 🆕 **Criar** testes de performance para Firebase Storage 🆕  
    - **RESPONSABILIDADE:** Otimizar carregamento de vídeos e thumbnails
    - **METRICS:** Load times, memory usage, network efficiency, cache behavior
    - **SCENARIOS:** Slow connections, large videos, multiple simultaneous loads
    - **AUTOMATION:** Performance regression testing

105. [ ] ⚙️ **Implementar** CI/CD pipeline completo 🆕  
    - **RESPONSABILIDADE:** Automatizar todos os testes e validações
    - **STAGES:** Build, unit tests, UI tests, performance tests, deployment
    - **QUALITY:** Code coverage, static analysis, accessibility testing
    - **DELIVERY:** Automated TestFlight builds, release automation

---

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

### 3.4 Sistema de Vídeo Cards 🆕

- **ListExerciseCard.swift** ✅  
  Componente base não reordenável para exercícios Firebase. Thumbnail + play button contextual, modal de vídeo completo.

- **WorkoutExerciseCard.swift**  
  Componente reordenável para exercícios salvos localmente. Drag & drop + todos recursos do ListExerciseCard

- **ExerciseCardContent.swift**  
  Componente central reutilizável com layout padrão (header, mídia, footer). Funciona com qualquer ExerciseDisplayable.

- **ExerciseCardMediaView.swift**  
  Componente inteligente de mídia contextual. Thumbnail/vídeo conforme modo de exibição + lazy loading.

- **ExerciseVideoPlayerView.swift**  
  Player de vídeo otimizado com AVPlayer. Loading states, error handling, controles opcionais.

- **ExerciseThumbnailView.swift**  
  Visualização otimizada de thumbnails. Firebase Storage URLs + AsyncImage com cache + fallbacks.

- **PlayButtonOverlay.swift**  
  Overlay de play button contextual e responsivo. Design adaptável + ações diferentes por contexto.

- **ExerciseCardDisplayMode.swift**  
  Enum para diferentes modos de exibição: firebaseList, creation, editableList, details, activeWorkout.

### 3.5 Mocks para Previews

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