# REFATORAR_LOGIN.md

---

## **Checklist de Refatoração - Contexto de Login e Criação de Conta**
*Resolução de 4 Duplicações + 6 Incoerências Críticas*

**📊 PROGRESSO:** 0/10 itens concluídos (0% ✅)

---

## 🔴 **PRIORIDADE CRÍTICA (Quebram compilação)**

### 1. [ ] 🆕 **Criar MockAuthUseCase.swift**
**PROBLEMA:** ViewModels não compilam previews - MockAuthUseCase não existe  
**LOCALIZAÇÃO:** Referenciado em LoginViewModel.swift:150, CreateAccountViewModel.swift:165  
**AÇÃO:**
- Criar arquivo `Shared/UseCases/Mocks/MockAuthUseCase.swift`
- Implementar `MockAuthUseCase: AuthUseCaseProtocol`
- Adicionar métodos mock para todos os casos do protocolo
- Testar previews funcionando nos ViewModels

**ARQUIVOS AFETADOS:**
- `Shared/UseCases/Mocks/MockAuthUseCase.swift` (novo)
- `Fitter V2/ViewsModel/LoginViewModel.swift` (validar preview)
- `Fitter V2/ViewsModel/CreateAccountViewModel.swift` (validar preview)

---

### 2. [ ] 🔧 **Implementar métodos ausentes AuthUseCase**
**PROBLEMA:** LoginViewModel chama métodos que não existem no AuthUseCase  
**LOCALIZAÇÃO:** LoginViewModel.swift:127, 133, 139  
**AÇÃO:**
- Adicionar `signInWithApple()` ao AuthUseCase.swift
- Adicionar `signInWithGoogle()` ao AuthUseCase.swift  
- Adicionar `signInWithFacebook()` ao AuthUseCase.swift
- Integrar com services correspondentes (AppleSignInService, etc.)
- Testar fluxos de login social funcionando

**ARQUIVOS AFETADOS:**
- `Shared/UseCases/AuthUseCase.swift` (implementar métodos)
- `Fitter V2/ViewsModel/LoginViewModel.swift` (validar funcionamento)

---

### 3. [ ] 🔧 **Corrigir interface checkInactivityTimeout**
**PROBLEMA:** iOSApp.swift usa await/try mas método é síncrono  
**LOCALIZAÇÃO:** AuthUseCase.swift:37, iOSApp.swift:395  
**AÇÃO:**
- Corrigir `checkInactivityTimeout() -> Bool` para `checkInactivityTimeout() async throws -> Bool`
- Atualizar implementação para async/await
- Corrigir chamada em iOSApp.swift se necessário
- Atualizar AuthServiceProtocol se necessário

**ARQUIVOS AFETADOS:**
- `Shared/UseCases/AuthUseCase.swift` (corrigir interface)
- `Fitter V2/Services/AuthService.swift` (atualizar implementação)
- `Fitter V2/iOSApp.swift` (validar chamada)

---

## 🟡 **PRIORIDADE IMPORTANTE (Violam arquitetura)**

### 4. [ ] 🔄 **Migrar LoginViewModel para BaseViewModel**
**PROBLEMA:** Duplicação de estados UI (isLoading, showError, etc.)  
**LOCALIZAÇÃO:** LoginViewModel.swift:14-23 vs BaseViewModel.swift  
**AÇÃO:**
- Alterar `class LoginViewModel: ObservableObject` para `class LoginViewModel: BaseViewModel`
- Remover estados duplicados: `@Published var isLoading`, `showError`, `errorMessage`, `isProcessing`
- Remover métodos duplicados: `withLoading()`, `withProcessing()`, `showError()`, `clearError()`
- Usar `BaseViewModel.executeUseCase()` nos métodos de login
- Atualizar preview para usar `AuthUseCase` via super.init()

**ARQUIVOS AFETADOS:**
- `Fitter V2/ViewsModel/LoginViewModel.swift` (refatorar herança)
- `Fitter V2/iOSApp.swift` (atualizar inicialização se necessário)

---

### 5. [ ] 🔄 **Migrar CreateAccountViewModel para BaseViewModel**
**PROBLEMA:** Duplicação de estados UI e helper methods  
**LOCALIZAÇÃO:** CreateAccountViewModel.swift:14-23 vs BaseViewModel.swift  
**AÇÃO:**
- Alterar `class CreateAccountViewModel: ObservableObject` para `class CreateAccountViewModel: BaseViewModel`
- Remover estados duplicados: `@Published var isLoading`, `showError`, `errorMessage`, `isProcessing`
- Remover métodos duplicados: `withLoading()`, `withProcessing()`, `showError()`, `clearError()`
- Usar `BaseViewModel.executeUseCase()` no método `createAccount()`
- Atualizar preview para usar `AuthUseCase` via super.init()

**ARQUIVOS AFETADOS:**
- `Fitter V2/ViewsModel/CreateAccountViewModel.swift` (refatorar herança)
- `Fitter V2/iOSApp.swift` (atualizar inicialização se necessário)

---

### 6. [ ] 🗑️ **Remover Singleton AuthService**
**PROBLEMA:** Viola dependency injection conforme item 74  
**LOCALIZAÇÃO:** AuthService.swift:134  
**AÇÃO:**
- Remover linha `static let shared = AuthService()`
- Verificar se há alguma referência a `AuthService.shared` no projeto
- Substituir por dependency injection via inicializador
- Atualizar comentários sobre remoção do singleton

**ARQUIVOS AFETADOS:**
- `Fitter V2/Services/AuthService.swift` (remover singleton)
- Buscar e corrigir referências `AuthService.shared` no projeto

---

### 7. [ ] 🔧 **Corrigir casting forçado SubscriptionManager**
**PROBLEMA:** Force casting perigoso em iOSApp.swift  
**LOCALIZAÇÃO:** iOSApp.swift:311  
**AÇÃO:**
- Corrigir `.environmentObject(subscriptionManager as! SubscriptionManager)`
- Usar casting seguro ou ajustar tipo da propriedade
- Verificar se SubscriptionManager está devidamente inicializado
- Testar se environmentObject funciona corretamente

**ARQUIVOS AFETADOS:**
- `Fitter V2/iOSApp.swift` (corrigir casting)

---

## 🔵 **PRIORIDADE BAIXA (Otimizações)**

### 8. [ ] 🔄 **Consolidar Keychain Services**
**PROBLEMA:** Múltiplos Keychain services fragmentados  
**LOCALIZAÇÃO:** AuthService.swift, AppleSignInService.swift, BiometricAuthService.swift  
**AÇÃO:**
- Criar `Shared/Services/KeychainService.swift` centralizado
- Implementar `KeychainServiceProtocol` com métodos genéricos
- Migrar AuthService para usar KeychainService
- Migrar AppleSignInService para usar KeychainService
- Migrar BiometricAuthService para usar KeychainService
- Atualizar inicializadores com dependency injection

**ARQUIVOS AFETADOS:**
- `Shared/Services/KeychainService.swift` (novo)
- `Fitter V2/Services/AuthService.swift` (migrar)
- `Fitter V2/Services/Auth/AppleSignInService.swift` (migrar)
- `Fitter V2/Services/Auth/BiometricAuthService.swift` (migrar)

---

### 9. [ ] 🔧 **Padronizar tratamento de erros AuthServices**
**PROBLEMA:** Inconsistência nos enums de erro entre services  
**LOCALIZAÇÃO:** Múltiplos arquivos de services Auth/  
**AÇÃO:**
- Revisar `AuthServiceError`, `AppleSignInError`, `BiometricAuthError`
- Padronizar estrutura de erros (description, recoverySuggestion)
- Consolidar erros comuns em enum base se possível
- Atualizar mensagens para português consistente
- Testar exibição de erros na UI

**ARQUIVOS AFETADOS:**
- `Fitter V2/Services/AuthService.swift` (padronizar erros)
- `Fitter V2/Services/Auth/AppleSignInService.swift` (padronizar erros)
- `Fitter V2/Services/Auth/BiometricAuthService.swift` (padronizar erros)
- `Fitter V2/Services/Auth/GoogleSignInService.swift` (padronizar erros)
- `Fitter V2/Services/Auth/FacebookSignInService.swift` (padronizar erros)

---

### 10. [ ] 📝 **Atualizar documentação FLUXO_LOGIN.md**
**PROBLEMA:** Documentação pode estar desatualizada após refatorações  
**LOCALIZAÇÃO:** FLUXO_LOGIN.md  
**AÇÃO:**
- Revisar fluxos documentados vs implementação atual
- Atualizar arquitetura de AuthUseCase + BaseViewModel
- Corrigir referências a métodos alterados
- Adicionar seção sobre MockAuthUseCase para desenvolvimento
- Validar que todos os cenários estão cobertos

**ARQUIVOS AFETADOS:**
- `FLUXO_LOGIN.md` (atualizar documentação)

---

## 🎯 **CRITÉRIOS DE CONCLUSÃO:**

### **✅ Item Concluído Quando:**
1. **Compilação:** Projeto compila sem erros
2. **Testes:** Previews funcionam corretamente
3. **Funcionalidade:** Fluxo de login/cadastro funciona end-to-end
4. **Arquitetura:** Sem duplicações ou violações Clean Architecture
5. **Documentação:** Código documentado e consistente

### **🏁 Refatoração Concluída Quando:**
- ✅ Todos os 10 itens marcados como concluídos
- ✅ Zero duplicações de código identificadas
- ✅ Zero incoerências arquiteturais
- ✅ Projeto compila e executa perfeitamente
- ✅ Previews de todos ViewModels funcionais
- ✅ Fluxos de login/cadastro 100% operacionais

---

## 📊 **ESTIMATIVAS:**

**⏱️ TEMPO TOTAL:** 3-4 horas  
**👤 COMPLEXIDADE:** Média  
**🎯 IMPACTO:** Alto (base sólida para toda aplicação)  
**📈 BENEFÍCIO:** ~200 linhas duplicadas removidas + arquitetura consistente

---

**REFATORAR_LOGIN.md - Checklist Detalhado 2025** 