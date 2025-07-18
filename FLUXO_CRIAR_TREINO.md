# FLUXO_CRIAR_TREINO.md

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Arquitetura e Princípios](#arquitetura-e-princípios)
3. [Duas formas de criar treino](#duas-formas-de-criar-treino)
4. [Ciclo de Vida da Criação de Treino (Manual)](#ciclo-de-vida-da-criação-de-treino-manual)
5. [Ciclo de Vida da Importação de Treino (Upload)](#ciclo-de-vida-da-importação-de-treino-upload)
6. [Regras Premium/Free e RevenueCat](#regras-premiumfree-e-revenuecat)
7. [Arquivos e Responsabilidades](#arquivos-e-responsabilidades)
8. [Diagramas - Fluxos e Integração](#diagramas---fluxos-e-integração)
9. [Jornada do Usuário](#jornada-do-usuário)
10. [Sincronização, Estados e Edge Cases](#sincronização-estados-e-edge-cases)

---

## 1. Visão Geral

A criação de treino no Fitter pode ser feita de duas formas:
- **Manual:** Selecionando exercícios da base e montando um treino do zero
- **Upload/Importação:** Enviando arquivos (imagem, PDF, CSV) de outros treinos, reconhecidos e processados automaticamente

Ambas respeitam as regras de assinatura (máximo de 6 exercícios por treino e 4 treinos ativos para não-assinantes).

---

## 2. Arquitetura e Princípios

```markdown
+----------------------------------------------------------+
|                        Usuário                           |
+----------------------------------------------------------+
            | (Manual ou Upload)           
            v
+---------------------------+        +---------------------------+
| WorkoutEditorView.swift   |        | UploadButton.swift        |
| (Criação manual)          |        | (Inicia importação)       |
+---------------------------+        +---------------------------+
            |                             |
            v                             v
+---------------------------+        +---------------------------+
| WorkoutViewModel.swift    |        | ImportWorkoutCard.swift   |
| (Coordena manual e recebe |        | (Mostra progresso)        |
| resultado de importação)  |        +---------------------------+
            |                             |
            v                             v
+---------------------------+        +---------------------------+
| CreateWorkoutUseCase.swift|        | ImportWorkoutUseCase.swift|
| UpdateWorkoutUseCase.swift|        | (Orquestra parsing,       |
| DeleteWorkoutUseCase.swift|        | valida, cria e sincroniza)|
+---------------------------+        +---------------------------+
            |                             |
            v                             v
+---------------------------+        +---------------------------+
| WorkoutDataService.swift  |        | ImportWorkoutService.swift|
| CoreDataService.swift     |        | (Parsing OCR/PDF/CSV)     |
+---------------------------+        +---------------------------+
            |                             |
            +-------------+---------------+
                          |
                          v
+---------------------------+
| SubscriptionManager.swift |<----> RevenueCatService.swift
+---------------------------+
            |
            v
+---------------------------+
| CloudSyncManager.swift    |
| Firestore                |
+---------------------------+
```

---

## 3. Duas formas de criar treino

### **A. Criação Manual**
- Tela: `WorkoutEditorView.swift`
- Usuário seleciona/exclui exercícios (máximo 6 se não assinante), define nome, grupos musculares, ordem
- Limites premium/free validados ao adicionar exercício e ao salvar
- Ao salvar, chama `CreateWorkoutUseCase` para persistir
- Após salvar, navega para edição (caso deseje)

### **B. Upload/Importação de Treino**
- Tela inicial: `WorkoutView.swift` com botão `UploadButton.swift`
- Usuário pode enviar **imagem (OCR)**, **PDF**, ou **CSV** (câmera, fotos ou arquivos)
- `ImportWorkoutCard.swift` exibe progresso animado na UI
- Parsing/validação feita por `ImportWorkoutService.swift`
- Lógica de negócio (validação, limites, persistência, sync) feita por `ImportWorkoutUseCase.swift`
- Exercícios identificados são mapeados para o banco do Firebase, lidando com nomes similares/erros
- Limites premium/free aplicados (máximo 6 exercícios por treino e 4 treinos para não assinantes; se vier mais, só cria até o máximo)
- Após criado, navega automaticamente para edição (`WorkoutEditorView.swift` no modo edição do treino recém-criado)

---

## 4. Ciclo de Vida da Criação de Treino (Manual)

```markdown
1. Usuário abre WorkoutView.swift e clica em "Criar Treino"
       |
       v
2. WorkoutEditorView.swift aberto em modo criação
       |
       v
3. Usuário escolhe nome, grupo muscular e seleciona exercícios (até 6 free, ilimitado premium)
       |
       v
4. Limite premium validado via SubscriptionManager
       |
       v
5. Salva treino: chama CreateWorkoutUseCase.swift
       |
       v
6. WorkoutDataService.swift salva no Core Data e dispara sync Firestore
       |
       v
7. Treino aparece em WorkoutView.swift. Ao clicar no card, navega para edição/visualização
```

---

## 5. Ciclo de Vida da Importação de Treino (Upload)

```markdown
1. Usuário clica em "Importar Treino" (UploadButton.swift)
       |
       v
2. Seleciona fonte: Câmera, Fotos ou Arquivo (.jpg, .png, .pdf, .csv)
       |
       v
3. ImportWorkoutService.swift processa arquivo:
      - OCR para imagens
      - Parsing para PDF/CSV
      - Identifica um ou mais treinos no arquivo
       |
       v
4. ImportWorkoutUseCase.swift:
      - Valida dados extraídos
      - Identifica nomes de exercícios e grupos musculares usando Firebase (lida com similaridade/erros)
      - Cria até 4 treinos para free, ilimitado premium
      - Em cada treino, só adiciona até 6 exercícios para free, ilimitado premium
      - Chama WorkoutDataService.swift para persistir cada treino
      - Sincroniza com Firestore
       |
       v
5. ImportWorkoutCard.swift mostra progresso em tempo real (estados: lendo arquivo, extraindo, criando treino, sucesso/erro)
       |
       v
6. Ao concluir, exibe o(s) novo(s) treino(s) em WorkoutView.swift
       |
       v
7. Ao clicar em um treino recém-criado, usuário é levado a WorkoutEditorView.swift no modo edição
```

---

## 6. Regras Premium/Free e RevenueCat

| Limite/Função                        | Premium   | Não-Premium |
|---------------------------------------|-----------|-------------|
| Máx. exercícios por treino            | Ilimitado | **6**       |
| Máx. treinos ativos criados           | Ilimitado | **4**       |
| Importação de múltiplos treinos       | ✔         | Até 4 por vez|
| Exercícios importados por treino      | Ilimitado | Até 6 por treino|
| Navegação para edição após importação | ✔         | ✔           |
| Call-to-action de upgrade             | —         | ✔ (se exceder limite) |

- **Todas as validações e bloqueios são feitas via SubscriptionManager.isPremium (integrado ao RevenueCat).**
- **Se um arquivo importar vários treinos e exceder o limite de 4 (free), só os 4 primeiros são criados.**
- **Se um treino importado tem mais de 6 exercícios (free), só os 6 primeiros são criados.**

---

## 7. Arquivos e Responsabilidades

- **WorkoutView.swift:**  
  Tela principal de listagem, inicia criação manual ou upload/importação, exibe ImportWorkoutCard e WorkoutPlanCard

- **WorkoutEditorView.swift:**  
  Tela para criar/editar treino, chamada tanto manualmente quanto após upload/importação

- **WorkoutViewModel.swift:**  
  Estado reativo de treinos, integração com SubscriptionManager, recebe updates do ImportWorkoutUseCase

- **UploadButton.swift:**  
  UI para escolher fonte (câmera, galeria, arquivo), dispara upload

- **ImportWorkoutService.swift:**  
  Service puro para parsing de imagem/PDF/CSV, converte para ParsedWorkoutData, identifica estrutura e dados brutos

- **ImportWorkoutUseCase.swift:**  
  Orquestra parsing, validação contra base Firebase (nome/exercício/grupo muscular), aplica limites de premium/free, cria treinos e chama sync, retorna progresso para a UI

- **ImportWorkoutCard.swift:**  
  UI de progresso visual/animado durante importação, estados claros de cada etapa

- **WorkoutDataService.swift/CoreDataService.swift:**  
  CRUD dos treinos/exercícios, cria e persiste cada treino importado

- **ListExerciseViewModel.swift:**  
  Carrega base de exercícios Firebase, usada para validação de similaridade na importação

- **SubscriptionManager.swift:**  
  Exposição do status premium (publisher), consulta constante ao RevenueCatService

- **RevenueCatService.swift:**  
  SDK RevenueCat, controla entitlement, offerings, upgrades

- **WorkoutPlanCard.swift:**  
  Card visual para cada treino já salvo, acessa navegação/edição

---

## 8. Diagramas - Fluxos e Integração

### **A. Diagrama Geral do Fluxo de Criação de Treino**

```markdown
             +-------------------+   
             |  WorkoutView.swift|   
             +---------+---------+   
                       |                     
    +-----------+------+------------------+ 
    |           |                         |
    v           v                         v
[WorkoutEditor] [UploadButton]      [ImportWorkoutCard]
   (manual)        (upload)             (feedback)
    |                                   /
    v                                 /
[WorkoutViewModel] <----------------+
    |                                      +---[CreateWorkoutUseCase]              |         |                              |         v                               |   [WorkoutDataService]                   |         |                                 |         v                                  |   [Core Data/Firestore]                     |                                             +--------<--ImportWorkoutUseCase<--ImportWorkoutService
              |     | (parse/process)  |     |
              |     +------------------+     |
              +------------------------------+
```

---

### **B. Fluxo de Importação e Bloqueio Premium**

```markdown
Usuário faz upload (imagem/pdf/csv)
        |
        v
ImportWorkoutService.swift parseia e identifica treinos
        |
        v
ImportWorkoutUseCase.swift valida/extrai/exercícios
        |
        v
[Se free] Só cria até 4 treinos, e 6 exercícios por treino
        |
        v
WorkoutDataService/CoreData salva local e dispara sync
        |
        v
ImportWorkoutCard mostra progresso visual e resultado
        |
        v
WorkoutViewModel é atualizado, treinos aparecem em WorkoutView
        |
        v
Usuário pode clicar no card para abrir WorkoutEditorView e editar
```

---

### **C. Jornada UI na Importação**

```markdown
+-------------------------+
| 1. WorkoutView.swift    |
|   [ UploadButton ]      |
+-------------------------+
          |
          v
+-------------------------+
| 2. UploadButton         |
|   (Sheet: Câmera/Fotos/Arquivo)|
+-------------------------+
          |
          v
+-------------------------+
| 3. ImportWorkoutCard    |
|   (progresso: lendo -> extraindo -> criando) |
+-------------------------+
          |
          v
+-------------------------+
| 4. Após sucesso         |
|   - Card some           |
|   - WorkoutPlanCard(s)  |
|   - Clique abre edição  |
+-------------------------+
```

---

## 9. Jornada do Usuário

**Cenário 1: Criação Manual**
1. Usuário clica em "Criar Treino"
2. Monta treino do zero (limite 6 exercícios free)
3. Salva e aparece na lista. Clica para editar/visualizar

**Cenário 2: Upload/Importação**
1. Usuário clica em "Importar Treino"
2. Escolhe foto/câmera/arquivo (imagem, PDF, CSV)
3. Progresso aparece (ImportWorkoutCard)
4. App identifica 1 ou mais treinos e os cria automaticamente
5. Limite premium é aplicado (máx 4 treinos e 6 exercícios free)
6. Novos treinos aparecem na lista; usuário pode editar

---

## 10. Sincronização, Estados e Edge Cases

- **Sync:** Tudo salvo local e no Firestore, visível em todos devices
- **Premium/free:** Limites nunca podem ser burlados (checados sempre)
- **Progress bar:** Feedback visual sempre exibido durante parsing/upload (ImportWorkoutCard)
- **Similaridade:** Exercícios extraídos são validados por nome/similaridade via FetchFBExercisesUseCase/Firebase; se não encontrado, cria exercício genérico
- **Falhas:** Erros de parsing/validação aparecem na UI, usuário pode tentar novamente
- **Edição pós-importação:** Sempre disponível, seja manual ou upload

---

**FIM**
