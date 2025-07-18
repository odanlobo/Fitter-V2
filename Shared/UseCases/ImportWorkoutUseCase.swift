/*
 * ImportWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para importação de treinos a partir de arquivos (imagem, PDF, CSV).
 *                   Implementa Clean Architecture com orquestração de parsing, validação e criação.
 *
 * ARQUITETURA:
 * - Orquestra ImportWorkoutService (parsing de arquivos)
 * - Orquestra WorkoutDataService (persistência local)
 * - Orquestra SyncWorkoutUseCase (sincronização remota)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI
 *
 * DEPENDÊNCIAS:
 * - ImportWorkoutServiceProtocol: Parsing e extração de dados de arquivos (item 40)
 * - WorkoutDataServiceProtocol: CRUD de planos de treino
 * - SyncWorkoutUseCaseProtocol: Sincronização remota (item 23) ✅ INTEGRADO
 * - FetchFBExercisesUseCaseProtocol: Validação de exercícios no Firebase (item 30) ✅ INTEGRADO
 *
 * FLUXO DE EXECUÇÃO:
 * 1. Validação de entrada (fonte de dados válida)
 * 2. Parsing via ImportWorkoutService (extrair dados estruturados)
 * 3. Validação dos dados parseados (estrutura de treino válida)
 * 4. Criação via WorkoutDataService (autoTitle + customTitle do arquivo)
 * 5. Sincronização via SyncWorkoutUseCase
 * 6. Retorno do resultado com detalhes da importação
 *
 * TIPOS DE ARQUIVO SUPORTADOS:
 * - Imagem: OCR para extrair texto de fotos de treinos
 * - PDF: Parsing de documentos estruturados de treinos
 * - CSV: Import de planilhas com exercícios e séries
 *
 * SISTEMA DUAL DE TÍTULOS:
 * - autoTitle: Sempre "Treino A", "Treino B"... (sistemático, não editável)
 * - customTitle: Título extraído do arquivo ou nome do arquivo (editável)
 * - Exemplo: "Treino Monday.pdf" → autoTitle: "Treino A" → customTitle: "Monday"
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 * - LOGIN OBRIGATÓRIO: user: CDAppUser (nunca opcional)
 *
 * REFATORAÇÃO ITEM 39/105:
 * ✅ Use Case de importação com orquestração completa
 * ✅ Injeção de ImportWorkoutService (item 40)
 * ✅ Injeção de WorkoutDataService (item 16)
 * ✅ Preparado para SyncWorkoutUseCase (item 23)
 * ✅ Clean Architecture - sem acesso direto ao Core Data
 * ✅ Tratamento de erros específicos do domínio de importação
 * ✅ ITEM 66: Bloqueio de funcionalidades premium - limite de 4 treinos para usuários free
 */

import Foundation
import UniformTypeIdentifiers

// MARK: - ImportWorkoutError

enum ImportWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case fileNotSupported(String)
    case parsingFailed(Error)
    case dataValidationFailed(String)
    case workoutLimitExceeded(limit: Int, current: Int)
    case subscriptionRequired(feature: String)
    case creationFailed(Error)
    case syncFailed(Error)
    case serviceUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Dados inválidos para importação: \(message)"
        case .fileNotSupported(let type):
            return "Tipo de arquivo não suportado: \(type)"
        case .parsingFailed(let error):
            return "Falha no parsing do arquivo: \(error.localizedDescription)"
        case .dataValidationFailed(let message):
            return "Dados do arquivo inválidos: \(message)"
        case .workoutLimitExceeded(let limit, let current):
            return "Limite de treinos excedido: \(current)/\(limit). Faça upgrade para Premium para treinos ilimitados."
        case .subscriptionRequired(let feature):
            return "Recurso premium necessário: \(feature). Faça upgrade para continuar."
        case .creationFailed(let error):
            return "Falha na criação do treino importado: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização do treino importado: \(error.localizedDescription)"
        case .serviceUnavailable(let service):
            return "Serviço indisponível: \(service)"
        }
    }
}

// MARK: - ImportWorkoutInput

struct ImportWorkoutInput {
    let source: ImportSource
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let customTitle: String?  // Título personalizado opcional (sobrescreve título extraído)
    let autoDetectExercises: Bool  // Se deve tentar detectar exercícios automaticamente
    let validateExercises: Bool  // Se deve validar exercícios contra banco Firebase
    
    /// Validação dos dados de entrada
    func validate() throws {
        // Validar fonte de dados
        try source.validate()
        
        // Validar título personalizado se fornecido
        if let title = customTitle {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportWorkoutError.invalidInput("Título personalizado não pode estar vazio")
            }
            
            guard title.count <= 50 else {
                throw ImportWorkoutError.invalidInput("Título personalizado não pode ter mais de 50 caracteres")
            }
        }
    }
}

// MARK: - ImportSource

enum ImportSource {
    case camera(Data)  // Dados da imagem capturada
    case photo(Data)   // Dados da imagem da galeria
    case file(Data, UTType)  // Dados do arquivo + tipo
    
    func validate() throws {
        switch self {
        case .camera(let data), .photo(let data):
            guard !data.isEmpty else {
                throw ImportWorkoutError.invalidInput("Imagem vazia")
            }
            
            guard data.count <= 10 * 1024 * 1024 else { // 10MB max
                throw ImportWorkoutError.invalidInput("Imagem muito grande (máximo 10MB)")
            }
            
        case .file(let data, let type):
            guard !data.isEmpty else {
                throw ImportWorkoutError.invalidInput("Arquivo vazio")
            }
            
            guard data.count <= 50 * 1024 * 1024 else { // 50MB max
                throw ImportWorkoutError.invalidInput("Arquivo muito grande (máximo 50MB)")
            }
            
            // Validar tipos suportados
            let supportedTypes: [UTType] = [.pdf, .commaSeparatedText, .image]
            guard supportedTypes.contains(where: { $0.conforms(to: type) }) else {
                throw ImportWorkoutError.fileNotSupported(type.description)
            }
        }
    }
    
    var displayName: String {
        switch self {
        case .camera: return "Câmera"
        case .photo: return "Galeria"
        case .file(_, let type): return type.localizedDescription ?? "Arquivo"
        }
    }
}

// MARK: - ImportWorkoutOutput

struct ImportWorkoutOutput {
    let workoutPlan: CDWorkoutPlan
    let planExercises: [CDPlanExercise]
    let parseDetails: ParseDetails
    let syncStatus: ImportWorkoutSyncStatus
}

struct ParseDetails {
    let source: ImportSource
    let extractedTitle: String?
    let detectedExercises: Int
    let validatedExercises: Int
    let skippedExercises: Int
    let parsingTime: TimeInterval
}

enum ImportWorkoutSyncStatus {
    case synced
    case pending
    case failed(Error)
    case disabled // Quando SyncWorkoutUseCase não está disponível
}

// MARK: - ImportWorkoutUseCaseProtocol

protocol ImportWorkoutUseCaseProtocol {
    func execute(_ input: ImportWorkoutInput) async throws -> ImportWorkoutOutput
}

// MARK: - ParsedWorkoutData Structures
// ✅ Structures are shared with ImportWorkoutService.swift for consistency

// MARK: - ImportWorkoutUseCase

final class ImportWorkoutUseCase: ImportWorkoutUseCaseProtocol {
    
    // MARK: - Properties
    
    private let importService: ImportWorkoutServiceProtocol
    private let workoutDataService: WorkoutDataServiceProtocol
    private let subscriptionManager: SubscriptionManagerProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    private let fetchFBExercisesUseCase: FetchFBExercisesUseCaseProtocol?
    
    // MARK: - Initialization
    
    init(
        importService: ImportWorkoutServiceProtocol,
        workoutDataService: WorkoutDataServiceProtocol,
        subscriptionManager: SubscriptionManagerProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil,
        fetchFBExercisesUseCase: FetchFBExercisesUseCaseProtocol? = nil
    ) {
        self.importService = importService
        self.workoutDataService = workoutDataService
        self.subscriptionManager = subscriptionManager
        self.syncUseCase = syncUseCase
        self.fetchFBExercisesUseCase = fetchFBExercisesUseCase
        
        print("📥 ImportWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: ImportWorkoutInput) async throws -> ImportWorkoutOutput {
        let sourceDisplay = input.source.displayName
        print("📥 Iniciando importação de treino via: \(sourceDisplay)")
        
        let parseStart = Date()
        
        do {
            // 1. Validar entrada
            try input.validate()
            print("✅ Validação de entrada concluída")
            
            // 2. Validar limite de treinos
            try await validateWorkoutLimit(for: input.user)
            print("✅ Validação de limite de treinos concluída")
            
            // 3. Parsing via ImportWorkoutService
            let parsedData = try await parseWorkoutData(input.source)
            print("✅ Parsing concluído: \(parsedData.exercises.count) exercícios detectados")
            
            // 4. Validar dados parseados
            try validateParsedData(parsedData)
            print("✅ Dados parseados validados")
            
            // 5. Converter para exercícios Core Data
            let (exerciseTemplates, validatedCount, skippedCount) = try await convertToExerciseTemplates(
                parsedData.exercises,
                autoDetect: input.autoDetectExercises,
                validate: input.validateExercises
            )
            print("✅ \(validatedCount) exercícios convertidos, \(skippedCount) ignorados")
            
            // 6. Criar plano de treino
            let (workoutPlan, planExercises) = try await createWorkoutPlan(
                from: parsedData,
                exercises: exerciseTemplates,
                input: input
            )
            print("✅ Plano de treino criado: \(workoutPlan.displayTitle)")
            
            // 7. Tentar sincronização
            let syncStatus = await attemptSync(workoutPlan)
            
            let parseTime = Date().timeIntervalSince(parseStart)
            let parseDetails = ParseDetails(
                source: input.source,
                extractedTitle: parsedData.title,
                detectedExercises: parsedData.exercises.count,
                validatedExercises: validatedCount,
                skippedExercises: skippedCount,
                parsingTime: parseTime
            )
            
            let output = ImportWorkoutOutput(
                workoutPlan: workoutPlan,
                planExercises: planExercises,
                parseDetails: parseDetails,
                syncStatus: syncStatus
            )
            
            print("🎉 Treino importado com sucesso: \(workoutPlan.displayTitle)")
            return output
            
        } catch let error as ImportWorkoutError {
            print("❌ Erro na importação: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na importação: \(error)")
            throw ImportWorkoutError.creationFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func parseWorkoutData(_ source: ImportSource) async throws -> ParsedWorkoutData {
        do {
            return try await importService.parseWorkout(from: source)
        } catch {
            throw ImportWorkoutError.parsingFailed(error)
        }
    }
    
    private func validateParsedData(_ data: ParsedWorkoutData) throws {
        guard !data.exercises.isEmpty else {
            throw ImportWorkoutError.dataValidationFailed("Nenhum exercício foi detectado no arquivo")
        }
        
        guard data.exercises.count <= 20 else {
            throw ImportWorkoutError.dataValidationFailed("Muito exercícios detectados (máximo 20)")
        }
        
        // Validar se pelo menos alguns exercícios têm nome válido
        let validExercises = data.exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard validExercises.count >= 1 else {
            throw ImportWorkoutError.dataValidationFailed("Nenhum exercício válido detectado")
        }
    }
    
    private func convertToExerciseTemplates(
        _ parsedExercises: [ParsedExercise],
        autoDetect: Bool,
        validate: Bool
    ) async throws -> (templates: [CDExerciseTemplate], validated: Int, skipped: Int) {
        
        var templates: [CDExerciseTemplate] = []
        var validatedCount = 0
        var skippedCount = 0
        
        for exercise in parsedExercises {
            let cleanName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !cleanName.isEmpty else {
                skippedCount += 1
                continue
            }
            
            // ✅ Integração real com FetchFBExercisesUseCase (item 30)
            if validate, let fetchFBExercisesUseCase = fetchFBExercisesUseCase {
                do {
                    // Buscar exercício no Firebase por nome
                    let searchInput = FetchFBExercisesInput(
                        searchText: cleanName,
                        muscleGroups: [],
                        equipments: [],
                        gripVariations: []
                    )
                    
                    let searchResult = try await fetchFBExercisesUseCase.searchExercises(searchInput)
                    
                    if let firebaseExercise = searchResult.exercises.first {
                        // ✅ Exercício encontrado no Firebase - usar dados reais
                        let template = firebaseExercise.toCDExerciseTemplate()
                        templates.append(template)
                        validatedCount += 1
                        print("✅ Exercício validado no Firebase: \(cleanName)")
                        continue
                    } else if autoDetect {
                        // Exercício não encontrado e autoDetect está ativo
                        print("⚠️ Exercício não encontrado no Firebase e ignorado: \(cleanName)")
                        skippedCount += 1
                        continue
                    }
                    // Se não encontrado mas autoDetect é false, continua para criar mock
                } catch {
                    print("⚠️ Erro ao validar exercício '\(cleanName)' no Firebase: \(error)")
                    // Em caso de erro, continua para fallback se autoDetect for false
                    if autoDetect {
                        skippedCount += 1
                        continue
                    }
                }
            }
            
            // Fallback: criar template mock quando Firebase não está disponível ou exercício não encontrado
            let template = createMockTemplate(from: exercise)
            templates.append(template)
            validatedCount += 1
            
            if validate && fetchFBExercisesUseCase != nil {
                print("⚠️ Exercício criado como mock (não encontrado no Firebase): \(cleanName)")
            }
        }
        
        guard !templates.isEmpty else {
            throw ImportWorkoutError.dataValidationFailed("Nenhum exercício válido após validação")
        }
        
        return (templates, validatedCount, skippedCount)
    }
    
    private func createMockTemplate(from exercise: ParsedExercise) -> CDExerciseTemplate {
        // ✅ Fallback: criar template local quando exercício não encontrado no Firebase
        let template = CDExerciseTemplate()
        template.id = UUID()
        template.templateId = "import_\(UUID().uuidString.prefix(8))"
        template.name = exercise.name
        template.muscleGroup = detectMuscleGroup(from: exercise.name)
        template.equipment = detectEquipment(from: exercise.name)
        template.description = exercise.notes
        template.createdAt = Date()
        template.cloudSyncStatus = CloudSyncStatus.pending.rawValue
        
        return template
    }
    
    private func detectMuscleGroup(from name: String) -> String {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("supino") || lowercaseName.contains("peito") {
            return "Peito"
        } else if lowercaseName.contains("agachamento") || lowercaseName.contains("leg") {
            return "Pernas"
        } else if lowercaseName.contains("rosca") || lowercaseName.contains("bíceps") {
            return "Bíceps"
        } else if lowercaseName.contains("terra") || lowercaseName.contains("costas") {
            return "Costas"
        } else {
            return "Outros"
        }
    }
    
    private func detectEquipment(from name: String) -> String {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("barra") {
            return "Barra"
        } else if lowercaseName.contains("halteres") || lowercaseName.contains("halter") {
            return "Halteres"
        } else if lowercaseName.contains("máquina") {
            return "Máquina"
        } else if lowercaseName.contains("polia") {
            return "Polia"
        } else {
            return "Peso do Corpo"
        }
    }
    
    private func createWorkoutPlan(
        from parsedData: ParsedWorkoutData,
        exercises: [CDExerciseTemplate],
        input: ImportWorkoutInput
    ) async throws -> (CDWorkoutPlan, [CDPlanExercise]) {
        
        do {
            // Determinar título final
            let finalTitle = input.customTitle ?? parsedData.title
            
            // Gerar título automático
            let autoTitle = try await generateAutoTitleForUser(input.user)
            
            // Detectar grupos musculares
            let muscleGroups = generateMuscleGroups(from: exercises)
            
            // Criar plano via WorkoutDataService
            let workoutPlan = try await workoutDataService.createWorkoutPlan(
                autoTitle: autoTitle,
                customTitle: finalTitle,
                muscleGroups: muscleGroups,
                user: input.user
            )
            
            // Adicionar exercícios ao plano
            var planExercises: [CDPlanExercise] = []
            for (index, template) in exercises.enumerated() {
                let planExercise = try await workoutDataService.addPlanExercise(
                    template: template,
                    to: workoutPlan,
                    order: Int32(index)
                )
                planExercises.append(planExercise)
            }
            
            return (workoutPlan, planExercises)
            
        } catch {
            throw ImportWorkoutError.creationFailed(error)
        }
    }
    
    private func generateAutoTitleForUser(_ user: CDAppUser) async throws -> String {
        do {
            let existingPlans = try await workoutDataService.fetchWorkoutPlans(for: user)
            return generateAutomaticTitle(basedOnCount: existingPlans.count)
        } catch {
            print("⚠️ Erro ao buscar planos para título automático: \(error)")
            // Fallback: usar timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM HH:mm"
            return "Treino \(formatter.string(from: Date()))"
        }
    }
    
    private func generateAutomaticTitle(basedOnCount count: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let letterIndex = count % letters.count
        let cycle = count / letters.count
        
        let letter = String(letters[letterIndex])
        return cycle == 0 ? "Treino \(letter)" : "Treino \(letter)\(cycle)"
    }
    
    private func generateMuscleGroups(from exercises: [CDExerciseTemplate]) -> String {
        let muscleGroups = Set(exercises.compactMap { $0.muscleGroup })
        return muscleGroups.sorted().joined(separator: ", ")
    }
    
    /// Valida limite de treinos para usuários free
    /// ✅ Implementação do item 66 - bloqueio de funcionalidades premium
    private func validateWorkoutLimit(for user: CDAppUser) async throws {
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin para desenvolvimento
        // Verificar se é usuário admin primeiro
        if await subscriptionManager.isAdminUser(user) {
            print("👑 [IMPORT] Usuário admin detectado: treinos ilimitados")
            return
        }
        
        // ✅ Verificar status premium via SubscriptionManager
        let status = await subscriptionManager.getSubscriptionStatus(for: user)
        
        switch status {
        case .active(let type, _):
            if type != .none {
                print("💎 [IMPORT] Usuário premium: treinos ilimitados")
                return  // Premium: ilimitado
            }
        case .gracePeriod(let type, _):
            if type != .none {
                print("⏰ [IMPORT] Usuário em grace period: treinos ilimitados")
                return  // Grace period: manter benefícios
            }
        case .expired, .none:
            // Continuar para verificar limite
            break
        }
        
        // ✅ Usuário free: verificar limite de 4 treinos
        do {
            let existingPlans = try await workoutDataService.fetchWorkoutPlans(for: user)
            let currentCount = existingPlans.count
            let maxWorkouts = 4
            
            if currentCount >= maxWorkouts {
                print("🚫 [IMPORT] Limite de treinos atingido: \(currentCount)/\(maxWorkouts)")
                throw ImportWorkoutError.workoutLimitExceeded(limit: maxWorkouts, current: currentCount)
            }
            
            print("✅ [IMPORT] Limite de treinos OK: \(currentCount)/\(maxWorkouts)")
        } catch let error as ImportWorkoutError {
            throw error
        } catch {
            print("⚠️ [IMPORT] Erro ao verificar limite de treinos: \(error)")
            throw ImportWorkoutError.creationFailed(error)
        }
    }
    
    /// Sistema de admin movido para SubscriptionManager.isAdminUser() para evitar duplicação
    /// ✅ Para desenvolvimento e testes sem limitações
    /// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
    
    private func attemptSync(_ workoutPlan: CDWorkoutPlan) async -> ImportWorkoutSyncStatus {
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase indisponível - sincronização desabilitada")
            return .disabled
        }
        
        do {
            // ✅ Integração real com SyncWorkoutUseCase (item 23)
            let syncInput = SyncWorkoutInput(
                entity: workoutPlan,
                strategy: .upload,
                priority: .normal
            )
            let result = try await syncUseCase.execute(syncInput)
            
            switch result.status {
            case .success:
                print("✅ Treino importado sincronizado com sucesso")
                return .synced
            case .pending:
                print("⏳ Sincronização agendada para treino importado")
                return .pending
            case .failed(let error):
                print("⚠️ Falha na sincronização do treino importado: \(error)")
                return .failed(error)
            }
        } catch {
            print("⚠️ Erro na sincronização do treino importado: \(error)")
            return .failed(error)
        }
    }
}

// MARK: - Extension for Convenience

extension ImportWorkoutUseCase {
    
    /// Método de conveniência para importação rápida via câmera
    /// ✅ Inclui validação automática de limite de treinos (item 66)
    func importFromCamera(
        imageData: Data,
        user: CDAppUser,
        customTitle: String? = nil
    ) async throws -> ImportWorkoutOutput {
        let input = ImportWorkoutInput(
            source: .camera(imageData),
            user: user,
            customTitle: customTitle,
            autoDetectExercises: true,
            validateExercises: true
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para importação via arquivo
    /// ✅ Inclui validação automática de limite de treinos (item 66)
    func importFromFile(
        fileData: Data,
        fileType: UTType,
        user: CDAppUser,
        customTitle: String? = nil
    ) async throws -> ImportWorkoutOutput {
        let input = ImportWorkoutInput(
            source: .file(fileData, fileType),
            user: user,
            customTitle: customTitle,
            autoDetectExercises: true,
            validateExercises: false  // Arquivos geralmente já estão estruturados
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para importação via galeria de fotos
    /// ✅ Inclui validação automática de limite de treinos (item 66)
    func importFromPhoto(
        imageData: Data,
        user: CDAppUser,
        customTitle: String? = nil
    ) async throws -> ImportWorkoutOutput {
        let input = ImportWorkoutInput(
            source: .photo(imageData),
            user: user,
            customTitle: customTitle,
            autoDetectExercises: true,
            validateExercises: true
        )
        
        return try await execute(input)
    }
}

// MARK: - Exemplos de Uso

/*
 // EXEMPLO 1: Importação via câmera com todas as dependências
 let importUseCase = ImportWorkoutUseCase(
     importService: ImportWorkoutService(),
     workoutDataService: WorkoutDataService(),
     subscriptionManager: SubscriptionManager(),
     syncUseCase: SyncWorkoutUseCase(),
     fetchFBExercisesUseCase: FetchFBExercisesUseCase()
 )
 
 let cameraResult = try await importUseCase.importFromCamera(
     imageData: cameraImageData,
     user: currentUser,
     customTitle: "Treino Segunda"
 )
 
 // EXEMPLO 2: Importação via arquivo PDF
 let fileResult = try await importUseCase.importFromFile(
     fileData: pdfData,
     fileType: .pdf,
     user: currentUser,
     customTitle: nil  // Usar título extraído do PDF
 )
 
 // EXEMPLO 3: Importação completa com configurações
 let input = ImportWorkoutInput(
     source: .file(csvData, .commaSeparatedText),
     user: currentUser,
     customTitle: "Planilha Hipertrofia",
     autoDetectExercises: false,  // Confiar nos dados do CSV
     validateExercises: true      // Validar contra Firebase
 )
 
 let result = try await importUseCase.execute(input)
 print("Treino importado: \(result.workoutPlan.displayTitle)")
 print("Exercícios: \(result.parseDetails.validatedExercises) válidos")
 */ 