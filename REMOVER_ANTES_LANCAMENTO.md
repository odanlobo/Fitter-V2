# REMOVER_ANTES_LANCAMENTO.md

---

## **⚠️ CHECKLIST DE REMOÇÃO ANTES DO LANÇAMENTO**

Este documento lista todos os itens que devem ser removidos ou alterados antes do lançamento do app na App Store.

---

## **🔑 CHAVE API DO REVENUECAT**

### **Arquivo:** `Fitter V2/iOSApp.swift`
**Linha:** ~320

**O QUE REMOVER:**
```swift
// ⚠️ REMOVER ANTES DO LANÇAMENTO: Substitua pela sua chave API real
let revenueCatAPIKey = "YOUR_REVENUECAT_PUBLIC_API_KEY"
```

**O QUE FAZER:**
1. Obter Public API Key do [RevenueCat Dashboard](https://app.revenuecat.com/)
2. Substituir `"YOUR_REVENUECAT_PUBLIC_API_KEY"` pela chave real
3. Configurar produtos In-App Purchase no App Store Connect (item 61 da checklist)

---

## **👑 SISTEMA DE ADMIN - SubscriptionManager.swift**

### **Arquivo:** `Shared/Services/SubscriptionManager.swift`

**SEÇÃO COMPLETA A REMOVER:**
```swift
// MARK: - ⚠️ SISTEMA ADMIN - REMOVER ANTES DO LANÇAMENTO

/// Obtém usuário atual (para verificação admin)
/// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
private func getCurrentUser() -> CDAppUser? {
    return nil
}

/// Verifica se o usuário é admin/teste para bypass do RevenueCat
/// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
private func isAdminUser(_ user: CDAppUser) async -> Bool {
    // ⚠️ REMOVER ANTES DO LANÇAMENTO: Lista de emails admin apenas para desenvolvimento
    let adminEmails = [
        "daniel@example.com",
        "admin@fitter.com",
        "test@fitter.com"
    ]
    
    // ⚠️ REMOVER ANTES DO LANÇAMENTO: Lista de IDs admin apenas para desenvolvimento
    let adminUserIds = [
        "V4pKs83V1Dc2yElHZB0ns2PbrIN2",
        "ADMIN_USER_ID_2"
    ]
    
    // ... resto do código
}
```

**VERIFICAÇÕES A REMOVER:**
```swift
// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
// ✅ VERIFICAÇÃO ADMIN: Se não há usuário atual, tentar RevenueCat
if let currentUser = getCurrentUser() {
    if await isAdminUser(currentUser) {
        print("👑 [SUBSCRIPTION] Usuário admin detectado, definindo premium")
        isPremium = true
        subscriptionStatus = .active(type: .lifetime, expiresAt: Date.distantFuture)
        isLoading = false
        return
    }
}
```

**MÉTODOS A LIMPAR:**
1. `refreshSubscriptionStatus()` - remover verificação admin
2. `getSubscriptionStatus(for:)` - remover verificação admin  
3. `updateUserSubscription(_:)` - remover verificação admin

---

## **📱 CONFIGURAÇÕES DE DESENVOLVIMENTO**

### **Arquivo:** `Fitter V2/iOSApp.swift`

**REMOVER COMENTÁRIOS:**
```swift
// ⚠️ IMPORTANTE: Substitua pela sua chave API real do RevenueCat Dashboard
```

**SUBSTITUIR POR:**
```swift
// RevenueCat Public API Key - Configurada no dashboard
```

---

## **🔧 REFATORAÇÃO.md - ATUALIZAR CHECKLIST**

### **Arquivo:** `REFATORAÇÃO.md`

**REMOVER PENDÊNCIAS:**
- [ ] 🔑 **CHAVE API:** Inserir chave API real do RevenueCat após configurar App Store Connect
- [ ] 🔑 **CHAVE API:** Após configurar produtos, inserir Public API Key em iOSApp.swift (item 57)

**ADICIONAR:**
- [x] ✅ **CHAVE API:** RevenueCat configurado com chave de produção
- [x] ✅ **SISTEMA ADMIN:** Removido código de desenvolvimento

---

## **🎯 ORDEM DE REMOÇÃO SUGERIDA**

### **1. CONFIGURAR REVENUECAT (PRIMEIRO)**
1. Criar conta no [RevenueCat Dashboard](https://app.revenuecat.com/)
2. Configurar projeto e obter Public API Key
3. Configurar entitlement "premium"
4. Configurar produtos no App Store Connect

### **2. REMOVER SISTEMA ADMIN**
1. Abrir `SubscriptionManager.swift`
2. Remover seção "⚠️ SISTEMA ADMIN - REMOVER ANTES DO LANÇAMENTO"
3. Limpar verificações admin dos métodos públicos
4. Testar se RevenueCat funciona corretamente

### **3. ATUALIZAR CHAVE API**
1. Substituir chave em `iOSApp.swift`
2. Testar configuração do RevenueCat
3. Verificar se produtos carregam corretamente

### **4. LIMPEZA FINAL**
1. Remover comentários de desenvolvimento
2. Atualizar `REFATORAÇÃO.md`
3. Teste completo do fluxo de assinaturas

---

## **✅ CHECKLIST DE VERIFICAÇÃO**

- [ ] RevenueCat configurado com chave de produção
- [ ] Sistema admin completamente removido
- [ ] Produtos configurados no App Store Connect
- [ ] Entitlement "premium" configurado no RevenueCat
- [ ] Fluxo de compra testado com usuário real
- [ ] Fluxo de restore testado
- [ ] PaywallView exibe produtos corretamente
- [ ] ProfileView mostra status premium
- [ ] Limites free/premium funcionando
- [ ] Comentários de desenvolvimento removidos

---

## **🚨 IMPORTANTE**

**NUNCA FAÇA COMMIT DESTAS MUDANÇAS SEM TESTAR:**
1. Fluxo completo de assinatura
2. Restore de compras
3. Limites free/premium
4. Integração com AuthUseCase

**SEMPRE TESTE EM DISPOSITIVO REAL** antes de submeter para a App Store.

---

**REMOVER_ANTES_LANCAMENTO.md - Checklist de Segurança** 