# GUIA_APP_STORE_CONNECT.md

---

## **📱 Guia Completo: Configuração App Store Connect + RevenueCat**

Este documento guia você através da configuração completa dos produtos In-App Purchase no App Store Connect e integração com RevenueCat.

---

## **🎯 PRODUTOS A CONFIGURAR**

### **1. Assinatura Mensal**
- **ID:** `fitter.monthly`
- **Preço:** R$ 9,99/mês
- **Tipo:** Auto-Renewable Subscription
- **Período:** 1 mês

### **2. Assinatura Anual**
- **ID:** `fitter.yearly`
- **Preço:** R$ 99,99/ano
- **Tipo:** Auto-Renewable Subscription
- **Período:** 1 ano

### **3. Assinatura Vitalícia**
- **ID:** `fitter.lifetime`
- **Preço:** R$ 199,99
- **Tipo:** Non-Consumable
- **Período:** Vitalício

---

## **📋 PASSO A PASSO: APP STORE CONNECT**

### **1. Acessar App Store Connect**
1. Vá para [App Store Connect](https://appstoreconnect.apple.com/)
2. Faça login com sua Apple Developer Account
3. Selecione seu app "Fitter"

### **2. Criar Produtos In-App Purchase**

#### **A. Assinatura Mensal**
1. **App Store Connect** → **Features** → **In-App Purchases**
2. Clique em **"+"** → **"Create In-App Purchase"**
3. **Product Type:** Auto-Renewable Subscription
4. **Product ID:** `fitter.monthly`
5. **Reference Name:** "Fitter Premium Mensal"
6. **Subscription Group:** Criar novo grupo "Fitter Premium"
7. **Subscription Duration:** 1 Month
8. **Price:** R$ 9,99

#### **B. Assinatura Anual**
1. **Product ID:** `fitter.yearly`
2. **Reference Name:** "Fitter Premium Anual"
3. **Subscription Group:** Mesmo grupo "Fitter Premium"
4. **Subscription Duration:** 1 Year
5. **Price:** R$ 99,99

#### **C. Assinatura Vitalícia**
1. **Product Type:** Non-Consumable
2. **Product ID:** `fitter.lifetime`
3. **Reference Name:** "Fitter Premium Vitalício"
4. **Price:** R$ 199,99

### **3. Configurar Localização (Português Brasil)**
Para cada produto:
1. **Localization** → **Portuguese (Brazil)**
2. **Display Name:** "Fitter Premium"
3. **Description:** "Acesso completo a todos os recursos premium do Fitter"

### **4. Configurar Review Information**
1. **Review Information** → **Add Review Information**
2. **Review Notes:** "Produtos de assinatura premium para app de fitness"
3. **Screenshot:** Captura de tela do PaywallView

---

## **🎯 PASSO A PASSO: REVENUECAT DASHBOARD**

### **1. Criar Conta RevenueCat**
1. Acesse [RevenueCat Dashboard](https://app.revenuecat.com/)
2. Crie uma conta ou faça login
3. Crie um novo projeto "Fitter"

### **2. Configurar Entitlement**
1. **Entitlements** → **"+"** → **"Create Entitlement"**
2. **Entitlement ID:** `premium`
3. **Display Name:** "Premium Access"
4. **Description:** "Acesso completo aos recursos premium"

### **3. Configurar Products**
Para cada produto do App Store Connect:

#### **A. fitter.monthly**
1. **Products** → **"+"** → **"Add Product"**
2. **Product ID:** `fitter.monthly`
3. **Store:** App Store
4. **Entitlement:** `premium`
5. **Type:** Auto-Renewable Subscription

#### **B. fitter.yearly**
1. **Product ID:** `fitter.yearly`
2. **Store:** App Store
3. **Entitlement:** `premium`
4. **Type:** Auto-Renewable Subscription

#### **C. fitter.lifetime**
1. **Product ID:** `fitter.lifetime`
2. **Store:** App Store
3. **Entitlement:** `premium`
4. **Type:** Non-Consumable

### **4. Configurar Offerings**
1. **Offerings** → **"+"** → **"Create Offering"**
2. **Offering ID:** `default`
3. **Display Name:** "Fitter Premium"
4. **Add Packages:**
   - **Monthly Package:** `fitter.monthly`
   - **Yearly Package:** `fitter.yearly`
   - **Lifetime Package:** `fitter.lifetime`

### **5. Obter API Key**
1. **Project Settings** → **API Keys**
2. **Copie a "Public API Key"** (não a Secret Key!)
3. **Substitua em iOSApp.swift:**
   ```swift
   let revenueCatAPIKey = "SUA_PUBLIC_API_KEY_AQUI"
   ```

---

## **🧪 TESTE SANDBOX**

### **1. Criar Conta Sandbox**
1. **App Store Connect** → **Users and Access** → **Sandbox Testers**
2. **"+"** → **"Add Sandbox Tester"**
3. Crie uma conta de teste com email único

### **2. Testar no Simulador/Device**
1. **Settings** → **App Store** → **Sign Out** (se logado)
2. **Abra o app Fitter**
3. **Tente fazer uma compra**
4. **Use a conta sandbox** para completar a compra

### **3. Verificar RevenueCat Dashboard**
1. **Events** → Verificar se a compra aparece
2. **Customers** → Verificar se o usuário foi criado
3. **Entitlements** → Verificar se `premium` está ativo

---

## **🔧 INTEGRAÇÃO NO CÓDIGO**

### **1. Atualizar iOSApp.swift**
```swift
private func configureRevenueCat() {
    // ⚠️ SUBSTITUIR pela sua chave real
    let revenueCatAPIKey = "SUA_PUBLIC_API_KEY_AQUI"
    
    Purchases.configure(withAPIKey: revenueCatAPIKey)
    print("✅ [FitterApp] RevenueCat configurado com sucesso")
}
```

### **2. Atualizar PaywallView.swift**
```swift
private var availablePackages: [Package] {
    // ✅ Buscar packages do RevenueCatService
    return subscriptionManager.revenueCatService.offerings?.current?.availablePackages ?? []
}
```

### **3. Testar Fluxo Completo**
1. **Login** com usuário admin (para desenvolvimento)
2. **Abrir PaywallView** em qualquer contexto
3. **Verificar** se produtos carregam
4. **Testar** compra com conta sandbox

---

## **📊 MONITORAMENTO**

### **1. RevenueCat Dashboard**
- **Analytics** → Conversão, churn, LTV
- **Events** → Compras, restores, cancelamentos
- **Customers** → Status de assinatura por usuário

### **2. App Store Connect**
- **Sales and Trends** → Receita e downloads
- **App Analytics** → Métricas de engajamento
- **In-App Purchases** → Performance dos produtos

---

## **🚨 PROBLEMAS COMUNS**

### **1. Produtos não carregam**
- ✅ Verificar se API Key está correta
- ✅ Verificar se produtos estão aprovados no App Store Connect
- ✅ Verificar se entitlement está configurado no RevenueCat

### **2. Compra falha**
- ✅ Verificar se está usando conta sandbox
- ✅ Verificar se produtos estão mapeados corretamente
- ✅ Verificar logs do RevenueCat

### **3. Status premium não atualiza**
- ✅ Verificar se SubscriptionManager está observando mudanças
- ✅ Verificar se AuthUseCase está integrado
- ✅ Verificar se usuário está logado

---

## **✅ CHECKLIST DE VERIFICAÇÃO**

- [ ] Produtos criados no App Store Connect
- [ ] Entitlement configurado no RevenueCat
- [ ] API Key inserida no código
- [ ] PaywallView carrega produtos
- [ ] Compra funciona com conta sandbox
- [ ] Status premium atualiza após compra
- [ ] Restore funciona corretamente
- [ ] Analytics aparecem no dashboard

---

## **🎯 PRÓXIMOS PASSOS**

1. **Configurar produtos** seguindo este guia
2. **Testar fluxo completo** com conta sandbox
3. **Remover sistema admin** antes do lançamento
4. **Submeter para review** na App Store

---

**GUIA_APP_STORE_CONNECT.md - Configuração Completa 2025** 