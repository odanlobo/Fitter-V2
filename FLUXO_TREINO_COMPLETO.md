# FLUXO_TREINO_COMPLETO.md

---

## **Documentação Completa do Fluxo de Treino Ativo - Fitter 2025**
*Clean Architecture, Premium-aware, Captura de Sensores e Sincronização em Tempo Real*

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Arquitetura Geral e Princípios](#2-arquitetura-geral-e-princípios)
3. [Captação e Processamento de Sensores](#3-captação-e-processamento-de-sensores)
4. [Fluxo Técnico de Dados: Watch ↔ iPhone](#4-fluxo-técnico-de-dados-watch--iphone)
5. [Ciclo de Vida Completo do Treino Ativo](#5-ciclo-de-vida-completo-do-treino-ativo)
6. [Arquivos e Responsabilidades](#6-arquivos-e-responsabilidades)
7. [Interface do Usuário: WorkoutSessionView](#7-interface-do-usuário-workoutsessionview)
8. [Política Premium/Free Integrada ao RevenueCat](#8-política-premiumfree-integrada-ao-revenuecat)
9. [Localização do Treino](#9-localização-do-treino)
10. [Estrutura CoreData e Persistência](#10-estrutura-coredata-e-persistência)
11. [Sincronização, Estados e Controle de Fases](#11-sincronização-estados-e-controle-de-fases)
12. [Testes, Edge Cases e Boas Práticas](#12-testes-edge-cases-e-boas-práticas)

---

## 1. Visão Geral

O **treino ativo** é o núcleo do Fitter — onde acontece a captura, processamento, sincronização e exibição dos dados de treino em tempo real, tanto no iPhone quanto no Apple Watch, sempre respeitando o status de assinatura do usuário via RevenueCat.

**Princípios-chave:**
- Dados de sensores captados e sincronizados em tempo real (50Hz execução, 20Hz descanso)
- UI reativa sempre refletindo dados reais e permissões premium
- RevenueCat determina via publishers o que está liberado/bloqueado
- Clean Architecture: Use Cases, Services e Managers bem separados
- Chunking eficiente de 100 amostras para transferência Watch→iPhone
- Localização opcional do treino para todos os usuários
- Upgrade instantâneo para dados históricos detalhados

---

## 2. **Arquivos e Responsabilidades**

**Principais arquivos já existentes:**
- **MotionManager.swift** — Captura dados brutos dos sensores no Watch.
- **WorkoutPhaseManager.swift** — Gerencia fases do treino, timers automáticos, transições.
- **WatchSessionManager.swift / PhoneSessionManager.swift** — Sincronização Watch ↔ iPhone, envio de chunks.
- **SessionManager.swift** — Estado global do treino ativo, buffer de dados.
- **HealthKitManager.swift** — Captura heart rate e calorias.
- **TimerService.swift** — Timers globais e locais de treino.
- **StartWorkoutUseCase.swift** — Inicia sessão, ativa cronômetro global, dispara todos os serviços.
- **StartExerciseUseCase.swift / EndExerciseUseCase.swift** — Controle granular de exercícios.
- **StartSetUseCase.swift / EndSetUseCase.swift** — Controle granular de séries, salva dados.
- **EndWorkoutUseCase.swift** — Finaliza tudo, migra para histórico.
- **WorkoutDataService.swift / CoreDataService.swift / CoreDataAdapter.swift / SensorData.swift**  — Persistência e serialização dos dados.
- **iOSApp.swift** — Configuração, DI e startup do app.
- **AuthUseCase.swift / AuthService.swift** — Autenticação, permissão, status premium.
- **FetchWorkoutUseCase.swift / UpdateWorkoutUseCase.swift** — Busca e atualização de planos.

---

## 3. Captação e Processamento de Sensores

### 3.1 Fases de Captação

- **Execução (`WorkoutPhase.execution`)**
  - **Intervalo:** 0,02s (50 Hz)
  - **Sensores:** Acelerômetro, Giroscópio, Gravidade, Orientação, Campo Magnético
  - **Objetivo:** Alta resolução para detecção precisa de repetições

- **Descanso (`WorkoutPhase.rest`)**
  - **Intervalo:** 0,05s (20 Hz)
  - **Sensores:** Mesmos sensores, menor frequência
  - **Objetivo:** Economia de bateria mantendo contexto

### 3.2 Detecção Automática de Fases

- **MotionManager (Watch)** realiza detecção automática de mudança de fase
- **Timer de 10 segundos:** usuário é notificado para confirmar descanso
- **Override manual:** usuário pode iniciar/cancelar descanso em qualquer device
- **Sincronização bidirecional:** mudanças propagadas via WCSession instantaneamente

### 3.3 Chunking e Transferência

```swift
// MotionManager captura → buffer 100 amostras
let chunk = SensorDataChunk(
    samples: buffer,
    metadata: ChunkMetadata(
        sessionId: sessionId,
        exerciseId: exerciseId,
        setId: setId,
        phase: currentPhase,
        timestamp: Date()
    )
)

// WatchSessionManager → transferFile com metadata
watchSession.transferFile(chunkURL, metadata: chunk.metadata)
```

---

## 4. Fluxo Técnico de Dados: Watch ↔ iPhone

### 4.1 Contexto da Sessão

```markdown
SessionManager (iPhone) → updateApplicationContext() → WatchSessionManager (Watch)

Contexto inclui:
- sessionId, planId, exerciseId, setId
- setOrder, exerciseIndex
- currentPhase, isPremium
```

### 4.2 Pipeline de Dados

```markdown
[Apple Watch: MotionManager]
      |
      v (captura 50Hz/20Hz)
[Buffer 100 amostras]
      |
      v (chunk completo)
[WatchSessionManager] ---- transferFile + metadata ---->
      |
      v (iPhone recebe)
[PhoneSessionManager] ---- processa JSON + contexto ---->
      |
      v (ML/algoritmos)
[Processamento Real-time] ---- reps, padrões, métricas ---->
      |
      v (publishers)
[WorkoutSessionViewModel] ---- estado UI reativo ---->
      |
      v
[WorkoutSessionView] <-- UI atualizada em tempo real
```

### 4.3 Heart Rate e Calories

- **HealthKitManager** captura continuamente durante treino pelo Watch
- **Envio a cada 2 segundos** para sincronização UI
- **Exibição em tempo real** em ambos devices
- **Sempre salvo** se autorização HealthKit disponível

---

## 5. **Fluxo de Treino Ativo**

**O fluxo inicia com o StartWorkoutUseCase:**  
Todos os serviços e timers globais são ativados imediatamente, **assim que o cronômetro global do treino começa a contar**:

### **Passo a Passo**

1. **Usuário loga e seleciona treino (FetchWorkoutUseCase).**

2. **Início do treino (`StartWorkoutUseCase`):**
   - Cronômetro global do treino **começa a contar** (TimerService).
   - Dispara:
     - **MotionManager.swift** (se hardware disponível e permissão): começa a capturar sensores.
     - **HealthKitManager.swift**: começa a capturar heart rate/calorias (se autorizado, sempre).
     - **WorkoutPhaseManager.swift**: inicia controle de fases/timers.
     - **WatchSessionManager.swift / PhoneSessionManager.swift**: sincronização de dados/chunks.
     - **SessionManager.swift**: sincroniza estados com UI.
   - *Tudo acima ocorre sempre que possível, **independente do status premium***.

3. **Durante o treino:**
   - **Envio de chunks (MotionManager → WatchSessionManager):**
     - A cada 100 amostras, envia chunk para iPhone.
     - Chunks processados por ML via `UpdateDataToMLUseCase.swift`.
     - Resultados (timeline de reps, picos/vales) **sempre salvos em memória/CoreData**.
   - **Atualização de timers, heart rate, calorias:**
     - TimerService e HealthKitManager atualizam dados em tempo real.
   - **Execução de exercícios/séries:**
     - Contagem automática de reps, timeline, gráfico etc **sempre processados e salvos** (se hardware/perm/ML disponíveis).
     - Para usuários não premium: **UI não exibe nada disso** — só dados básicos, timers e entrada manual.
     - Para premium: **UI exibe feedback em tempo real, gráficos, histórico detalhado**.

4. **Finalização de série/exercício/treino:**
   - **EndSetUseCase/EndExerciseUseCase/EndWorkoutUseCase**: persistem todos os dados, migram para histórico.
   - Dados de heart rate/calorias **sempre salvos** se disponíveis.
   - Dados de sensores, reps detalhados/timeline **sempre salvos**, mas acesso é premium.

5. **Histórico e pós-treino:**
   - Para premium: acesso total a gráficos, reps automáticos, timeline, etc.
   - Para não-premium: acesso apenas ao básico (duração, manual, heart rate/calorias).
   - Upgrade premium: **acesso imediato ao histórico detalhado já processado**.

---

## 6. **Premium vs Não-Premium: O que muda?**

| Fluxo/Serviço                         | Premium               | Não-Premium           |
|---------------------------------------|-----------------------|-----------------------|
| **Captação de sensores**              | ✔ Ativa               | ✔ Ativa               |
| **Processamento ML**                  | ✔ Ativa               | ✔ Ativa               |
| **Salvamento dados detalhados**       | ✔ Ativa               | ✔ Ativa               |
| **Séries por exercício**              | Ilimitado             | Máx. 3                |
| **Visualização reps em tempo real**   | ✔ Ativa               | ✗                     |
| **Gráficos histórico detalhado**      | ✔ Ativa               | ✗                     |
| **Timers automáticos**                | ✔ Ativa               | ✔ Ativa               |
| **Heart Rate/Calorias**               | ✔ Ativo (se permitir) | ✔ Ativo (se permitir) |
| **Localização do treino**             | ✔ Ativo (se permitir) | ✔ Ativo (se permitir) |
| **Upgrade premium**                   |          -            | ✔ Imediato            |

---

#### **FLUXO CORRETO DE NAVEGAÇÃO (GRANULAR - SÉRIES DINÂMICAS):**

> **IMPORTANTE:** Este fluxo foi atualizado para refletir a lógica detalhada em @README_FLUXO_DADOS.md

StartWorkoutUseCase → CDCurrentSession + inicia MotionManager + inicia HealthKitManager
      ↓
StartExerciseUseCase → Próximo exercício + finaliza anterior
      ↓
╔═══ LOOP SÉRIES (DINÂMICO - CONTROLADO PELO USUÁRIO) ═════════════════════════════╗
║ 🎯 **LÓGICA UI:** WorkoutSessionView mostra APENAS 1 série no incio do xercício   ║
║ 🎯 **CONTROLE:** Usuário decide quantas séries fazer via botão "+"                ║
║ 🎯 **FLEXÍVEL:** 1 série mínima, sem máximo definido                              ║
║                                                                                  ║
║ StartSetUseCase → Inicia série atual                                             ║
║       ↓                                                                          ║
║ • Captura contínua de sensores (50 Hz)                                           ║
║ • Chunks enviados a cada 100 amostras                                            ║
║ • ML processa dados em tempo real                                                ║
║ • UI sincronizada Watch ↔ iPhone                                                 ║
║ • Detecção automática de descanso                                                ║
║       ↓                                                                          ║
║ EndSetUseCase → Finaliza série atual + persiste                                  ║
║       ↓                                                                          ║
║ 🔄 **DECISÃO DO USUÁRIO:**                                                       ║
║ ├─ Botão "+" → StartSetUseCase (nova série do mesmo exercício)                   ║
║ └─ Botão "Próximo" → EndExerciseUseCase (finalizar exercício)                    ║
╚══════════════════════════════════════════════════════════════════════════════════╝
      ↓
EndExerciseUseCase → Finaliza exercício + decide próximo passo + salva dados
      ↓
┌─ StartExerciseUseCase → Próximo exercício (se houver exercícios restantes)
│        ↓
│   (volta ao LOOP SÉRIES DINÂMICO)
│
└─ EndWorkoutUseCase → Finaliza treino + finaliza MotionManager + persiste histórico completo

---

## 7. Arquivos e Responsabilidades

### 7.1 Interface e Estado (iOS)

- **WorkoutSessionView.swift**
  - **RESPONSABILIDADE:**
    - Interface central para treino ativo, com controle dinâmico de Exercícios, Séries e visualização dos dados ao vivo.

  - **🎯 UX PRINCIPAL:**
    - Estruturada em 3 Seções:

    **WorkoutSummaryCard:**
      - Card de relatório geral do treino ativo (nome, progresso, tempo, calorias, heart rate ao vivo, destaque premium).

    **ExerciseSessionCard:**
      - Card dinâmico do exercício atual, exibindo lista de séries planejadas e em andamento:

      - **SetCard:**
        - Campo "Série N"
        - Peso (editável)
        - Reps alvo (editável)
        - Reps atuais (real time, readonly, sensor/ML)
        - Checkmark para marcar como concluída

      - Botão "Adicionar Série +": sempre visível, respeita limite (máx. 3 não-premium, ilimitado premium). Ao exceder, exibir modal/call-to-action.

      - Timer de descanso: Exibido ao concluir série, integra lógica automática/manual do Watch.

    **ExerciseListSection:**
      - Lista todos os exercícios do treino:
      - Exercícios concluídos, ativos, pendentes, com destaque visual
      - Drag-and-drop para reordenar exercícios não feitos
      - Exercício ativo destacado; troca rápida exige confirmação se houver série em andamento

  - **🎯 CONTROLE USUÁRIO:**
    - Adicionar novas séries (até limite premium)
    - Editar peso e reps alvo de séries ainda não concluídas
    - Marcar série como feita (checkmark manual)
    - Iniciar timer de descanso (manual/automático)
    - Avançar exercício via botão "Próximo" (apenas se houver pelo menos uma série concluída)

  - **🎯 NAVEGAÇÃO:**
    - Botão "Próximo" para finalizar exercício atual e avançar para o próximo

  - **INTEGRAÇÃO:**
    - Consome WorkoutSessionViewModel
    - Aciona todos os Use Cases de Lifecycle (24-29)
    - StartWorkout, StartExercise, StartSet, EndSet, EndExercise, EndWorkout
    - Atualização real-time dos sensores/ML, heart rate, timers, progresso
    - WATCH SYNC: Sincronização automática com Apple Watch (dados, timers, status)

  - **REAL-TIME:**
    - Dados em tempo real: reps atuais (ML/sensor), heart rate, timers, progresso
    - Feedback visual para premium e não-premium conforme regra do fluxo refatorado

  - **PREMIUM:**
  - Limite de 3 séries/exercício para não-premium
  - Call-to-action visual ao tentar exceder funções premium
  - Destaque especial para recursos premium (gráficos, relatórios, histórico completo)

- **WorkoutSessionViewModel.swift**
  - **RESPONSABILIDADE:**
    - ViewModel dedicado para gerenciar todo o estado dinâmico do treino ativo, séries e exercícios

  - **🎯 ESTADO DINÂMICO:**
    - Controle completo de séries por exercício (1-N séries)
    - Editar campos de peso/reps alvo antes de marcar como concluída
    - Permitir adicionar séries (até 3 não-premium, ilimitado premium)
    - Recebe e propaga reps atuais via sensor/ML em tempo real
    - Exposição dos publishers para campos editáveis, timers, progresso e status

  - **USE CASES:**
    - Orquestra StartWorkout, StartExercise, StartSet, EndSet, EndExercise, EndWorkout
    - Integra todos os fluxos descritos no FLUXO_TREINO_COMPLETO.md

  - **TIMER INTEGRATION**
    - Usa TimerService para cronometro global, descanso entre séries e duração das séries/exercício/treino
    - Gerencia timers automáticos/manuais conforme lógica

  - **REAL-TIME:**
    - Publishers para dados dos sensores (reps, heart rate, calorias) e timers
    - Atualizações instantâneas para UI e sincronização com Apple Watch

  - **NAVIGATION STATE:**
    - Controle de qual exercício e qual série está ativa
    - Validação ao trocar exercício/série (confirmação em caso de andamento)

  - **ERROR HANDLING:**
    - Publishers específicos para estados de erro:
      - Tentativa de exceder limite de séries (não-premium)
      - Falha sensores
      - Watch desconectado
      - Erros de sincronização, timers, dados

  - **PREMIUM:**
    - Detecta status premium em tempo real
    - Libera/desbloqueia funções premium ao upgrade imediato

## 8. **Pontos Críticos e Checks de Permissão**

- **Checagem de hardware/permissão**:
  - Sempre feita **antes de iniciar qualquer serviço**.
  - Sem hardware/permissão: serviços ML/sensores não são ativados, app segue só com timers básicos e heart rate/calorias se possível.

- **Checagem de status premium**:
  - Controla **exclusivamente a visualização/acesso** aos dados avançados, nunca o processamento/captura.

- **Persistência resiliente**:
  - Todos os campos aceitam ausência de dados avançados (ex: reps detalhadas = nil/null se não processado).

---

## 9. **O que criar/atualizar (alinhado ao contexto atual)**

### **Criar** UpdateDataToMLUseCase.swift
- Responsável por receber os chunks de sensores do Watch, processar via modelo ML, manter a timeline das reps em memória, atualizar (se premium) a UI em tempo real e delegar persistência ao EndSetUseCase.

### **Criar** MLModelManager.swift
- Gerencia inicialização, execução, atualização e testes do modelo ML.
- Usado por UpdateDataToMLUseCase.

### **Atualizar** EndSetUseCase.swift
- Ao finalizar uma série, salva em CDCurrentSet o valor final de reps (`actualReps`).
- Ao migrar para histórico (CDHistorySet), além de `actualReps`, salva também a timeline detalhada em `repsCounterData` (Binary Data).

### **Atualizar** SessionManager.swift
- Buffer temporário para timeline/array/JSON das reps de cada série em andamento.
- Fornece snapshot dos dados para o EndSetUseCase.

### **Atualizar** CoreData (FitterModel.xcdatamodeld):

**CDCurrentSet**
```xml
<entity name="CDCurrentSet" representedClassName="CDCurrentSet" syncable="YES" codeGenerationType="class">
    <attribute name="actualReps" optional="YES" attributeType="Integer 32" usesScalarValueType="YES"/>
    ...
</entity>
```
- **Mantém apenas actualReps (valor final) durante treino ativo** para leveza e performance.

**CDHistorySet**
```xml
<entity name="CDHistorySet" representedClassName="CDHistorySet" syncable="YES" codeGenerationType="class">
    ...
    <attribute name="actualReps" optional="YES" attributeType="Integer 32" usesScalarValueType="YES"/>
    <attribute name="repsCounterData" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
    ...
</entity>
```
- **Salva o vetor/array/JSON de reps detalhadas do ML em repsCounterData**, permitindo upgrade premium instantâneo.

**No CoreDataAdapter.swift**  
- Adicionar métodos utilitários para serialização/deserialização do vetor/JSON para Binary Data.

**Em todos os casos, persistência é resiliente**: campos opcionais, sem impacto para quem não utiliza sensores/ML.

### **Atualizar** PhoneSessionManager.swift / WatchSessionManager.swift
- Garantir trigger correto para UpdateDataToMLUseCase sempre que um chunk chegar do Watch.

### **Atualizar** Permissão e Coleta

```swift
// iOSApp.swift - após HealthKit
CLLocationButton(.shareCurrentLocation) {
    locationManager.requestWhenInUseAuthorization()
}
.onLocationReceived { location in
    // Salvar em CDCurrentSession depois migrado para Histórico ao fim do treino
}

```
**Info.plist:**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Guardar localização do treino para histórico e estatísticas.</string>
```

- **Localização sempre exibida para todos os usuários** (se coletada)
- Mapa do treino, estatísticas por local
- Privacidade respeitada: usuário controla permissão

---

## 10. **Estrutura do CoreData para Reps e ML**

- **Durante o treino ativo (série em andamento):**
    - Mantém em memória (SessionManager/Use Case) a timeline da contagem de repetições.
    - Se premium: exibe valor crescendo das reps em tempo real na UI.
    - Se não premium: fluxo igual, mas sem exibição na UI.
    - Ao final da série, salva apenas o valor final (`actualReps`) em CDCurrentSet.

- **Ao finalizar/migrar para histórico:**
    - Salva o valor final em `actualReps` (CDHistorySet).
    - Salva o vetor detalhado do ML em `repsCounterData` (CDHistorySet).
    - Dados persistidos para todos, acesso via premium.
    - Upgrade premium: acesso imediato ao histórico completo.

**Vantagens:**  
Performance máxima, simplicidade de uso, e upgrade instantâneo.

---

## 11. **Resumo do fluxo de reps automáticas, timeline e persistência**

**Durante o treino ativo (série em andamento):**
- O app mantém em memória (SessionManager/Use Case) a timeline da contagem de repetições, na forma de vetor/array/JSON que cresce conforme o processamento dos chunks de sensores via ML.
- Se o usuário for premium:
    - Exibe em “tempo real” o valor atual de repetições na UI, mostrando o contador crescendo conforme o ML detecta novas reps.
    - Pode também exibir o gráfico/timeline animado se desejar.
- Se o usuário não for premium:
    - O fluxo de processamento e timeline é o mesmo, mas nada é exibido na UI durante a execução.

- Ao final da série:
    - O valor final de reps detectado (`actualReps`) é salvo em **CDCurrentSet**.
    - A timeline detalhada (vetor/JSON) permanece em memória até migração.

**Ao finalizar o exercício ou migrar para histórico:**
- No momento de migração (EndSetUseCase/EndExerciseUseCase):
    - Salva o valor final em `actualReps` (CDHistorySet).
    - Salva o vetor detalhado do ML em `repsCounterData` (CDHistorySet), serializado como Binary Data (array ou JSON).
    - Esse dado é persistido para todos os usuários, mas só é exibido/desbloqueado na UI/histórico se o usuário for premium.
    - Se o usuário se tornar premium depois, o app libera imediatamente o acesso aos históricos já salvos.

**Vantagens:**
- Performance máxima: só um campo simples na entidade “current” durante o treino, sem overhead desnecessário.
- Upgrade instantâneo: ao virar premium, o usuário tem acesso imediato a todos os seus históricos detalhados.
- Flexibilidade para analytics, gráficos e personalização futura.

---

## 12. **Observações finais**

- **Toda a lógica de sensores, ML, timers, heart rate, calorias e localização é inicializada automaticamente assim que o cronômetro global começa, para todos os usuários com hardware e permissão.**
- O acesso a dados de sensores/ML é premium, mas a coleta/processamento é feita para todos — garantindo upgrade “instantâneo” e sem retrabalho.
- Heart rate e calorias são considerados *core features* — sempre disponíveis se possível, sem relação com premium. O mesmo vale para localização. 
- O fluxo do app é **resiliente, seguro e preparado para upgrades futuros**.
- O CoreData está ajustado para máxima performance, simplicidade de manutenção e evolução futura.

---

# Fluxo de Treino Completo - Fitter V2

## 🆕 NOVO FLUXO: Detecção Automática de Fim de Série

### 📋 Resumo da Implementação

A nova funcionalidade detecta automaticamente quando o usuário para de fazer exercício e oferece um modal para iniciar o timer de descanso, seguindo exatamente o fluxo solicitado:

### 🔄 Fluxo Completo de Detecção Automática

1. **Detecção no Apple Watch** (`MotionManager.swift`)
   - Monitora dados dos sensores continuamente
   - Detecta mudança de padrão (execution → rest) baseado em threshold
   - Aguarda 1 segundo para confirmar mudança
   - Envia notificação para iPhone via `WatchSessionManager`

2. **Comunicação Watch → iPhone** (`WatchSessionManager.swift` → `PhoneSessionManager.swift`)
   - `WatchSessionManager.sendPhaseChangeDetection()` envia dados estruturados
   - `PhoneSessionManager.processPhaseChangeDetected()` recebe e processa
   - Publisher notifica o `WorkoutSessionViewModel` via Combine

3. **Processamento no iPhone** (`WorkoutSessionViewModel.swift`)
   - `handlePhaseChangeDetection()` valida se é fim de série válido
   - Inicia timer de 10 segundos (`startAutoDetectionTimer()`)
   - Após 10 segundos, exibe modal "Finalizou a série?" (`showAutoDetectionModal()`)

4. **Interação do Usuário**
   - **Botão "Iniciar timer (1:30)"**: Finaliza série + inicia timer padrão descontando tempo decorrido
   - **Botão "Escolher outro timer"**: Abre sheet com opções de timer pré-definidas
   - **Cancelar**: Ignora detecção e continua série
   - **Timer manual**: Cancela detecção automática automaticamente

### 🎯 Responsabilidades por Arquivo

#### `MotionManager.swift` (Apple Watch)
- **Função**: `detectPhaseAutomatically()` - Detecta mudança de padrão
- **Função**: `notifyPhoneOfPhaseChange()` - Notifica iPhone
- **Threshold**: 0.015 para descanso, 1 segundo de confirmação

#### `WatchSessionManager.swift` (Apple Watch)
- **Função**: `sendPhaseChangeDetection()` - Envia dados estruturados
- **Contexto**: Inclui sessionId, exerciseId, setId, setOrder, exerciseName

#### `PhoneSessionManager.swift` (iPhone)
- **Função**: `processPhaseChangeDetected()` - Processa dados recebidos
- **Publisher**: `phaseChangeDetectionPublisher` - Notifica ViewModel
- **Estrutura**: `PhaseChangeDetectionData` - DTO com dados da detecção

#### `WorkoutSessionViewModel.swift` (iPhone)
- **Estados**: `AutoDetectionModalState`, `TimerSelectionSheetState`
- **Timer**: 10 segundos após detecção para exibir modal
- **Validações**: Série ativa, mesmo setOrder, não cancelado manualmente
- **Desconto**: Tempo decorrido é descontado do timer selecionado

#### `WorkoutPhaseManager.swift` (Shared/Manager)
- **Responsabilidade**: Gerenciador simples de estado de fases (execution/rest)
- **Estado**: `currentPhase`, `isWorkoutActive` 
- **Publisher**: `phaseChangePublisher` - Notifica mudanças de fase via Combine
- **Funções**: `updatePhase()`, `startSession()`, `endSession()`, `reset()`
- **❌ NÃO gerencia**: Timers, ações automáticas, comunicação (delegado para outros componentes)

#### `TimerService.swift` (Shared)
- **Opções**: 7 opções pré-definidas (1:00 a 5:00)
- **Integração**: Usado para iniciar timer com duração personalizada
- **Responsabilidade**: Gerencia todos os timers do app (descanso, workout, inatividade)

### 🔧 Funcionalidades Implementadas

✅ **Detecção Automática**: Baseada em sensores do Apple Watch
✅ **Timer de 10 segundos**: Aguarda antes de exibir modal
✅ **Modal "Finalizou a série?"**: Título e mensagem conforme solicitado
✅ **Botão "Iniciar timer (1:30)"**: Timer padrão com desconto de tempo
✅ **Botão "Escolher outro timer"**: Sheet com 7 opções pré-definidas
✅ **Desconto de tempo**: Tempo decorrido é descontado do timer
✅ **Cancelamento automático**: Se usuário iniciar timer manualmente
✅ **Validações**: Série ativa, mesmo exercício, contexto correto
✅ **Logs detalhados**: Para debug e acompanhamento

### 🎯 Estados da UI

```swift
// Modal de detecção automática
@Published private(set) var autoDetectionModal: AutoDetectionModalState = .hidden

// Sheet de seleção de timer
@Published private(set) var timerSelectionSheet: TimerSelectionSheetState = .hidden

// Dados da última detecção (controle de 10 segundos)
@Published private(set) var lastPhaseDetection: PhaseChangeDetectionData?
```

### 🔄 Fluxo de Dados Atualizado

```
Apple Watch (MotionManager)
    ↓ (mudança de padrão detectada)
WatchSessionManager.sendPhaseChangeDetection()
    ↓ (WCSession)
PhoneSessionManager.processPhaseChangeDetected()
    ↓ (Publisher)
WorkoutSessionViewModel.handlePhaseChangeDetection()
    ↓ (10 segundos)
AutoDetectionModalState.show()
    ↓ (usuário escolhe)
TimerService.startRestTimer() + WorkoutPhaseManager.updatePhase(.rest)
```

### 🏗️ Arquitetura de Estado

```
WorkoutPhaseManager (Shared/Manager)
├── Estado Global: currentPhase (execution/rest)
├── Publisher: phaseChangePublisher (notifica mudanças)
└── Observadores:
    ├── MotionManager (ajusta frequência 50Hz/20Hz)
    ├── WorkoutSessionViewModel (reage a mudanças)
    ├── PhoneSessionManager (sincroniza com Watch)
    └── TimerService (coordena timers com fases)

Detecção Automática (Fluxo Paralelo)
├── MotionManager → PhoneSessionManager → WorkoutSessionViewModel
├── Timer 10s + Modal → Usuário decide
└── TimerService inicia timer + WorkoutPhaseManager atualiza fase
```

### 🚀 Benefícios da Nova Arquitetura

- **UX Intuitiva**: Detecta automaticamente quando usuário para
- **Flexibilidade**: Múltiplas opções de timer com desconto inteligente
- **Precisão**: Desconta tempo já decorrido do timer selecionado
- **Robustez**: Validações e cancelamentos automáticos
- **Performance**: Processamento eficiente via Combine Publishers
- **Arquitetura Limpa**: Separação clara de responsabilidades
- **Estado Centralizado**: WorkoutPhaseManager como fonte única de verdade
- **Reatividade**: Componentes observam mudanças via phaseChangePublisher
- **Escalabilidade**: Novos observadores podem ser adicionados facilmente

### 🔧 Integração WorkoutPhaseManager

```swift
// Exemplo de uso no WorkoutSessionViewModel
workoutPhaseManager.phaseChangePublisher
    .sink { [weak self] event in
        if event.trigger == .automatic && event.toPhase == .rest {
            await self?.handleAutomaticPhaseDetection(event)
        }
    }
    .store(in: &cancellables)

// Exemplo de uso no MotionManager
await workoutPhaseManager.updatePhase(.rest, trigger: .automatic)

// Exemplo de uso no TimerService
if workoutPhaseManager.currentPhase == .rest {
    await startRestTimer(duration: 90)
}
```

A implementação segue exatamente o fluxo solicitado e mantém a arquitetura Clean Architecture com estado centralizado e responsabilidades bem definidas.
