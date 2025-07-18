# README_ASSINATURAS.md

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Motivação da Refatoração para RevenueCat](#motivação-da-refatoração-para-revenuecat)
3. [Arquivos e Responsabilidades](#arquivos-e-responsabilidades)
4. [Fluxo Geral de Assinatura e Entitlements](#fluxo-geral-de-assinatura-e-entitlements)
5. [Integração com RevenueCat](#integração-com-revenuecat)
6. [Tracking de Eventos de Assinatura](#tracking-de-eventos-de-assinatura)
7. [Onboarding com Trial/Promoção](#onboarding-com-trialpromoção)
8. [Fluxos Práticos na UI & Exemplos](#fluxos-práticos-na-ui--exemplos)
9. [Diagramas - Fluxos e Integração](#diagramas---fluxos-e-integração)
10. [Testes, Edge Cases & Observações](#testes-edge-cases--observações)
11. [Referências & Links Úteis](#referências--links-úteis)

---

## 1. Visão Geral

O Fitter utiliza **assinaturas in-app** para liberar recursos premium, controlar upgrades, liberar trials e maximizar retenção, integrando 100% das operações ao **RevenueCat**.

### **Princípios**
- RevenueCat como **fonte de verdade** do status premium
- Clean Architecture: camada de serviço dedicada
- Toda UI consome status reativo (publishers) de assinatura
- Tracking e onboarding (trial/promo) centralizados via painel RevenueCat

---

## 2. Motivação da Refatoração para RevenueCat

- **Reduzir complexidade**: Adeus código customizado para StoreKit, recibos, validação e edge cases.
- **Centralizar e automatizar**: RevenueCat controla trials, upgrades/downgrades, restore, e tracking.
- **Analytics e promoções prontos**: Dashboard e integrações out-of-the-box.
- **UX instantânea**: Mudança de status premium reflete imediatamente na UI com menos risco de bug.
- **Melhor manutenção e evolução**: Atualizar ofertas/trials/pacotes sem mexer no código.

---

## 3. Arquivos e Responsabilidades

### **A. Criar**

- **RevenueCatService.swift**  
  _Camada responsável por toda integração com o SDK RevenueCat._  
  - Inicializa Purchases
  - Exibe publishers de status premium (ex: `isPremium`, `customerInfo`)
  - Métodos: `fetchOfferings()`, `purchase()`, `restorePurchases()`
  - Gerencia listeners para entitlement changes

### **B. Adaptar**

- **SubscriptionManager.swift**  
  _Camada orquestradora que consome RevenueCatService e distribui status para toda a UI/app._  
  - Publisher `isPremium`  
  - Mantém estado local se necessário (ex: para acesso offline)

- **PaywallView.swift**  
  _Interface de venda e upgrade. Mostra ofertas/packages vindas do RevenueCat._  
  - Exibe trial, promo, valores e ações de compra

- **ProfileView.swift**  
  _Mostra status premium, botão de restore, e detalhes da assinatura usando dados do RevenueCatService/SubscriptionManager._

- **WorkoutSessionViewModel.swift / WorkoutSessionView.swift**  
  _Toda lógica de bloqueio/upgrade de recursos premium consulta o SubscriptionManager (e, indiretamente, RevenueCatService)._

- **CDAppUser (Core Data Model)**  
  _Opcional para espelhar status premium para acesso offline/cache ou analytics próprios._

- **SubscriptionType.swift**  
  _Enum local para exibir status/tipo, populado pelo status do RevenueCat._

---

## 4. Fluxo Geral de Assinatura e Entitlements

- RevenueCat controla todos os produtos, planos, trials, promoções e entitlements (ex: “premium”).
- No app, você consome offerings/packages diretamente do RevenueCat para exibir o que quiser (inclusive trials especiais para onboarding).
- O status de premium/free é **100% reativo**: qualquer mudança (compra, cancelamento, restore) reflete na app sem delay.

---

## 5. Integração com RevenueCat

### **A. Inicialização**

```swift
import RevenueCat

Purchases.configure(withAPIKey: "REVENUECAT_PUBLIC_API_KEY")
```

### **B. RevenueCatService.swift (Exemplo)**

```swift
final class RevenueCatService: ObservableObject {
    @Published var isPremium: Bool = false
    @Published var offerings: Offerings?

    init() {
        Purchases.shared.getOfferings { [weak self] offerings, error in
            self?.offerings = offerings
        }
        Purchases.shared.getCustomerInfo { [weak self] info, error in
            self?.isPremium = info?.entitlements.active["premium"] != nil
        }
        NotificationCenter.default.addObserver(
            forName: .PurchasesCustomerInfoUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo?["customerInfo"] as? CustomerInfo else { return }
            self?.isPremium = info.entitlements.active["premium"] != nil
        }
    }

    func purchase(_ package: Package, completion: @escaping (Bool) -> Void) {
        Purchases.shared.purchase(package: package) { transaction, info, error, userCancelled in
            completion(info?.entitlements.active["premium"] != nil)
        }
    }

    func restorePurchases(completion: @escaping (Bool) -> Void) {
        Purchases.shared.restorePurchases { info, error in
            completion(info?.entitlements.active["premium"] != nil)
        }
    }
}
```

---

## 6. Tracking de Eventos de Assinatura

- **RevenueCat já faz o tracking automático de:**
    - Ativações, upgrades/downgrades, cancelamentos, trials, restores, churn, revenue, LTV, etc
    - Dashboard: [RevenueCat Dashboard > Analytics](https://app.revenuecat.com/)
- **Integração nativa:**  
    - Pode conectar RevenueCat com Firebase, Amplitude, Mixpanel, DataDog e outros, sem código adicional no app
    - Todos os eventos (purchase, renew, trial_start, trial_convert, cancel, etc.) já aparecem no dashboard e exportam automaticamente
- **Para tracking custom:**  
    - Ouça mudanças no publisher do RevenueCatService/SubscriptionManager
    - Exemplo:
      ```swift
      revenueCatService.$isPremium
          .sink { isPremium in
              if isPremium {
                  // enviar evento custom para analytics próprio, se quiser
              }
          }
      ```

---

## 7. Onboarding com Trial/Promoção

- **No painel RevenueCat:**  
    - Crie offerings/packages especiais para onboarding (ex: trial de 7 dias, preço promocional, lifetime, etc)
    - Configure eligibility para trials
- **No app:**  
    - Busque a oferta onboarding por ID:
      ```swift
      if let onboardingOffer = revenueCatService.offerings?.offering(identifier: "onboarding") {
          // Mostre essa oferta/paywall específico no onboarding
      }
      ```
    - Exiba o trial, promo, preço, detalhes da oferta diretamente da API do RevenueCat

- **Não precisa lógica custom para controlar trial/promo**:  
    - RevenueCat já sabe se usuário tem direito ao trial, tempo restante, etc.

---

## 8. Fluxos Práticos na UI & Exemplos

### **A. Verificar Status Premium na UI**

```swift
if subscriptionManager.isPremium {
    // liberar recurso premium
} else {
    // bloquear e mostrar paywall
}
```

### **B. Exibir Ofertas do RevenueCat**

```swift
let packages = revenueCatService.offerings?.current?.availablePackages ?? []
ForEach(packages) { package in
    // Exibir nome, valor, tipo, trial se houver
    Text(package.product.localizedTitle)
    Text(package.localizedPriceString)
    if package.storeProduct.introductoryDiscount != nil {
        Text("Trial disponível!")
    }
    Button("Assinar") {
        revenueCatService.purchase(package) { sucesso in ... }
    }
}
```

### **C. Restaurar Compras**

```swift
Button("Restaurar Compras") {
    revenueCatService.restorePurchases { sucesso in
        // feedback ao usuário
    }
}
```

### **D. Onboarding com Oferta de Trial**

```swift
if let onboardingOffer = revenueCatService.offerings?.offering(identifier: "onboarding") {
    // Mostre paywall especial com pacote de trial/promo do onboarding
    PaywallView(offer: onboardingOffer)
}
```

---

## 9. Diagramas - Fluxos e Integração

### **1. Fluxo de Assinatura e Liberação Premium**

```markdown
+-------------------+
|  RevenueCat Panel |
+-------------------+
        |
        v
+----------------------+
|  RevenueCatService   |
|  (SDK + wrapper)     |
+----------+-----------+
           |
           v
+----------------------+
| SubscriptionManager  |
| - Publisher isPremium|
+----------+-----------+
           |
           v
+-------------------------------+
|  Toda UI (ViewModels/Views)   |
|  Paywall/Profile/Treino Ativo |
+-------------------------------+
```

---

### **2. Fluxo de Upgrade/Restore**

```markdown
Usuário clica em "Assinar" ou "Restaurar"
         |
         v
+---------------------+
| RevenueCatService   |
| - purchase()        |
| - restorePurchases()|
+---------------------+
         |
         v
+---------------------------+
|  Atualiza isPremium      |
|  em SubscriptionManager  |
+---------------------------+
         |
         v
+--------------------+
|  UI reflete status |
+--------------------+
```

---

### **3. Jornada Usuário: Onboarding, Trial e Premium**

```markdown
+----------------------------+
|    Cadastro/Login          |
+----------------------------+
         |
         v
+----------------------------+
| Exibe Onboarding Paywall   |---> Se oferta onboarding disponível
| (com trial/promo)          |
+----------------------------+
         |
         v
+---------------------------+
|  Aceita trial/assina      |
|  (purchase onboarding)    |
+---------------------------+
         |
         v
+---------------------------+
|  Treino ativo liberado    |
|  (premium status = true)  |
+---------------------------+
```

---

### **4. Comunicação Entre Camadas - Clean Architecture**

```markdown
[UI - Views/ViewModels]
        |
        v
[SubscriptionManager.swift]
        |
        v
[RevenueCatService.swift]
        |
        v
[RevenueCat SDK]
        |
        v
[Dashboard RevenueCat / Webhooks / Analytics externos]
```

---

## 10. Testes, Edge Cases & Observações

- [ ] Assinatura, restore, upgrade/downgrade refletem instantaneamente na UI
- [ ] Trial/promo só aparece para usuários elegíveis
- [ ] Upgrade/desativação/switch de device funciona normalmente
- [ ] UI nunca mostra recurso premium se isPremium = false
- [ ] Paywall exibe preço/trial/promo correto de acordo com a oferta do RevenueCat
- [ ] Analytics/reflexo no dashboard RevenueCat conferem com ações do usuário
- [ ] Fallback offline: (opcional) status local no Core Data pode ser espelhado para limitar recursos

---

## 11. Referências & Links Úteis

- [RevenueCat Docs (iOS)](https://www.revenuecat.com/docs/ios)
- [Offerings & Packages](https://www.revenuecat.com/docs/entitlements)
- [Tracking de Eventos & Analytics](https://www.revenuecat.com/docs/events)
- [Dashboard de Trials, Conversions, LTV](https://app.revenuecat.com/)
- [SwiftUI + RevenueCat Example](https://github.com/RevenueCat/purchases-ios)
- [Entitlements & Eligibility](https://www.revenuecat.com/docs/entitlements)

---

## 12. Pagamento e Integração com Apple Wallet/Apple ID

### **Como o pagamento é processado no Fitter usando RevenueCat?**

- O **RevenueCat NÃO é processador de pagamentos** — ele apenas controla, valida e observa as assinaturas feitas pelo StoreKit (Apple).
- O **pagamento real é SEMPRE feito pela Apple**, usando o StoreKit (sistema oficial de assinaturas da App Store).
- **O app nunca manipula nem solicita dados de cartão do usuário diretamente.**

### **Fluxo detalhado do pagamento:**

1. **Usuário seleciona uma assinatura pelo app**
    - As ofertas são carregadas e exibidas via RevenueCat (offerings/packages).
2. **Ao clicar para assinar:**
    - O RevenueCat chama o StoreKit, que exibe a tela de pagamento nativa da Apple.
3. **Na tela nativa de pagamento:**
    - O usuário pode escolher qualquer **cartão cadastrado na Apple Wallet/Apple ID**.
    - Pode usar saldo Apple ID, cartão de crédito, métodos cadastrados — tudo igual a qualquer compra de App Store.
    - Confirma a compra via Face ID, Touch ID ou senha.

4. **Após pagamento aprovado:**
    - A Apple processa o pagamento.
    - O RevenueCat valida o recibo automaticamente, libera o acesso premium no app, dispara eventos e atualiza o dashboard.

### **Diagrama do fluxo de pagamento:**

```markdown
[Seu App (Fitter)]
      |
      v
[RevenueCat SDK]
      |
      v
[StoreKit - Apple]
      |
      v
[Tela Nativa de Pagamento]
      |
      v
[Usuário escolhe cartão já salvo na Apple Wallet/Apple ID]
      |
      v
[Apple processa o pagamento]
      |
      v
[RevenueCat valida e libera acesso premium]
```

### **Principais pontos:**

1. **User Experience máxima:**
    - O usuário não precisa digitar cartão; usa o método preferido já salvo na conta Apple.

2. **Segurança máxima:**
    - O app nunca acessa cartão nem dados sensíveis.

3. **Zero fricção:**
    - Experiência igual à compra de apps, música, iCloud etc — fluxo familiar para todo usuário iOS.

4. **Recebimento/controle:**
    - O pagamento vai para a Apple, e você recebe via App Store Connect normalmente.

---

**FIM**
