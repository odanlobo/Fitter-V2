/*
 * ImportWorkoutService.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Service para seleção, leitura e extração de dados de arquivos (imagem, PDF, CSV).
 *                   Implementa parsing e extração de dados brutos sem lógica de negócio.
 *
 * ARQUITETURA:
 * - Service puro, sem lógica de negócio
 * - Apenas manipulação de arquivos e extração de dados brutos
 * - Preparado para ser chamado pela UI e retornar dados para o Use Case
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de validação de exercícios
 *
 * TECNOLOGIAS UTILIZADAS:
 * - VisionKit: OCR para extração de texto de imagens
 * - PDFKit: Parsing de documentos PDF estruturados
 * - Foundation: Parsing de arquivos CSV e manipulação de dados
 * - SwiftUI: Pickers para seleção de arquivos (futura integração UI)
 *
 * TIPOS DE ARQUIVO SUPORTADOS:
 * - Imagem (.jpg, .png, .heic): OCR via VisionKit para extrair texto de fotos de treinos
 * - PDF (.pdf): Parsing de documentos estruturados de treinos e planilhas
 * - CSV (.csv): Import de planilhas com exercícios, séries, repetições e cargas
 *
 * FLUXO DE PARSING:
 * 1. Identificação do tipo de fonte (camera/photo/file)
 * 2. Seleção da estratégia de parsing apropriada
 * 3. Extração de dados brutos (OCR, PDF parsing, CSV parsing)
 * 4. Conversão para estrutura ParsedWorkoutData padronizada
 * 5. Retorno de dados estruturados para o Use Case
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Error handling específico do domínio de parsing
 * - Async/await para operações de I/O
 * - Compatibilidade multiplataforma (iOS/iPadOS)
 *
 * REFATORAÇÃO ITEM 40/105:
 * ✅ Service puro sem lógica de negócio
 * ✅ Manipulação de arquivos e extração de dados brutos
 * ✅ Preparado para integração com ImportWorkoutUseCase
 * ✅ Suporte a múltiplos tipos de arquivo
 * ✅ Clean Architecture - separação clara de responsabilidades
 */

import Foundation
import SwiftUI
import VisionKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - ImportWorkoutServiceError

enum ImportWorkoutServiceError: Error, LocalizedError {
    case unsupportedSourceType
    case ocrNotAvailable
    case ocrProcessingFailed(Error)
    case pdfParsingFailed(Error)
    case csvParsingFailed(Error)
    case fileReadingFailed(Error)
    case noDataExtracted
    case invalidFileFormat(String)
    case processingTimeout
    
    var errorDescription: String? {
        switch self {
        case .unsupportedSourceType:
            return "Tipo de fonte não suportado"
        case .ocrNotAvailable:
            return "OCR não disponível neste dispositivo"
        case .ocrProcessingFailed(let error):
            return "Falha no processamento OCR: \(error.localizedDescription)"
        case .pdfParsingFailed(let error):
            return "Falha no parsing do PDF: \(error.localizedDescription)"
        case .csvParsingFailed(let error):
            return "Falha no parsing do CSV: \(error.localizedDescription)"
        case .fileReadingFailed(let error):
            return "Falha na leitura do arquivo: \(error.localizedDescription)"
        case .noDataExtracted:
            return "Nenhum dado foi extraído do arquivo"
        case .invalidFileFormat(let format):
            return "Formato de arquivo inválido: \(format)"
        case .processingTimeout:
            return "Timeout no processamento do arquivo"
        }
    }
}

// MARK: - ImportWorkoutServiceProtocol

protocol ImportWorkoutServiceProtocol {
    func parseWorkout(from source: ImportSource) async throws -> ParsedWorkoutData
    func canProcessSource(_ source: ImportSource) -> Bool
}

// MARK: - ImportWorkoutService

final class ImportWorkoutService: ImportWorkoutServiceProtocol {
    
    // MARK: - Properties
    
    private let ocrParser: OCRParserProtocol
    private let pdfParser: PDFParserProtocol
    private let csvParser: CSVParserProtocol
    
    // MARK: - Initialization
    
    init(
        ocrParser: OCRParserProtocol = OCRParser(),
        pdfParser: PDFParserProtocol = PDFParser(),
        csvParser: CSVParserProtocol = CSVParser()
    ) {
        self.ocrParser = ocrParser
        self.pdfParser = pdfParser
        self.csvParser = csvParser
        
        print("📥 ImportWorkoutService inicializado")
    }
    
    // MARK: - Public Methods
    
    func parseWorkout(from source: ImportSource) async throws -> ParsedWorkoutData {
        print("📥 Iniciando parsing de: \(source.displayName)")
        
        guard canProcessSource(source) else {
            throw ImportWorkoutServiceError.unsupportedSourceType
        }
        
        let parseStart = Date()
        
        do {
            let parsedData: ParsedWorkoutData
            
            switch source {
            case .camera(let data), .photo(let data):
                parsedData = try await parseImageData(data, source: source)
                
            case .file(let data, let type):
                if type.conforms(to: .pdf) {
                    parsedData = try await parsePDFData(data)
                } else if type.conforms(to: .commaSeparatedText) {
                    parsedData = try await parseCSVData(data)
                } else if type.conforms(to: .image) {
                    parsedData = try await parseImageData(data, source: source)
                } else {
                    throw ImportWorkoutServiceError.invalidFileFormat(type.description)
                }
            }
            
            let processingTime = Date().timeIntervalSince(parseStart)
            
            // Validar se dados foram extraídos
            guard !parsedData.exercises.isEmpty else {
                throw ImportWorkoutServiceError.noDataExtracted
            }
            
            // Atualizar metadata com tempo real de processamento
            let updatedMetadata = ParseMetadata(
                confidence: parsedData.metadata.confidence,
                processingTime: processingTime,
                detectedFormat: parsedData.metadata.detectedFormat
            )
            
            let result = ParsedWorkoutData(
                title: parsedData.title,
                exercises: parsedData.exercises,
                metadata: updatedMetadata
            )
            
            print("✅ Parsing concluído: \(result.exercises.count) exercícios em \(String(format: "%.2f", processingTime))s")
            return result
            
        } catch let error as ImportWorkoutServiceError {
            print("❌ Erro de parsing: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado no parsing: \(error)")
            throw ImportWorkoutServiceError.fileReadingFailed(error)
        }
    }
    
    func canProcessSource(_ source: ImportSource) -> Bool {
        switch source {
        case .camera, .photo:
            return VNRecognizeTextRequest.supportedRecognitionLanguages().contains("en-US")
            
        case .file(_, let type):
            let supportedTypes: [UTType] = [.pdf, .commaSeparatedText, .image]
            return supportedTypes.contains { type.conforms(to: $0) }
        }
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseImageData(_ data: Data, source: ImportSource) async throws -> ParsedWorkoutData {
        do {
            return try await ocrParser.parseWorkoutFromImage(data, source: source)
        } catch {
            throw ImportWorkoutServiceError.ocrProcessingFailed(error)
        }
    }
    
    private func parsePDFData(_ data: Data) async throws -> ParsedWorkoutData {
        do {
            return try await pdfParser.parseWorkoutFromPDF(data)
        } catch {
            throw ImportWorkoutServiceError.pdfParsingFailed(error)
        }
    }
    
    private func parseCSVData(_ data: Data) async throws -> ParsedWorkoutData {
        do {
            return try await csvParser.parseWorkoutFromCSV(data)
        } catch {
            throw ImportWorkoutServiceError.csvParsingFailed(error)
        }
    }
}

// MARK: - OCR Parser Protocol & Implementation

protocol OCRParserProtocol {
    func parseWorkoutFromImage(_ data: Data, source: ImportSource) async throws -> ParsedWorkoutData
}

final class OCRParser: OCRParserProtocol {
    
    func parseWorkoutFromImage(_ data: Data, source: ImportSource) async throws -> ParsedWorkoutData {
        guard VNRecognizeTextRequest.supportedRecognitionLanguages().contains("en-US") else {
            throw ImportWorkoutServiceError.ocrNotAvailable
        }
        
        guard let image = UIImage(data: data) else {
            throw ImportWorkoutServiceError.fileReadingFailed(NSError(domain: "OCRParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível criar UIImage"]))
        }
        
        print("🔍 Iniciando OCR para imagem...")
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ImportWorkoutServiceError.noDataExtracted)
                    return
                }
                
                do {
                    let extractedText = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }.joined(separator: "\n")
                    
                    let parsedData = try self.parseTextToWorkout(extractedText, source: source)
                    continuation.resume(returning: parsedData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = true
            
            guard let cgImage = image.cgImage else {
                continuation.resume(throwing: ImportWorkoutServiceError.fileReadingFailed(NSError(domain: "OCRParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "Não foi possível obter CGImage"])))
                return
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseTextToWorkout(_ text: String, source: ImportSource) throws -> ParsedWorkoutData {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var exercises: [ParsedExercise] = []
        var extractedTitle: String?
        
        // Heurística simples para detectar exercícios
        for line in lines {
            // Detectar título (primeira linha ou linha com "treino")
            if extractedTitle == nil && (line.lowercased().contains("treino") || exercises.isEmpty) {
                extractedTitle = line
                continue
            }
            
            // Detectar exercícios (linhas com números ou padrões de exercício)
            if isExerciseLine(line) {
                let exercise = parseExerciseFromLine(line)
                exercises.append(exercise)
            }
        }
        
        let confidence = calculateOCRConfidence(exercises: exercises, totalLines: lines.count)
        
        let metadata = ParseMetadata(
            confidence: confidence,
            processingTime: 0, // Será atualizado no service principal
            detectedFormat: "OCR-\(source.displayName)"
        )
        
        return ParsedWorkoutData(
            title: extractedTitle,
            exercises: exercises,
            metadata: metadata
        )
    }
    
    private func isExerciseLine(_ line: String) -> Bool {
        let lowercaseLine = line.lowercased()
        
        // Verifica se contém palavras-chave de exercícios
        let exerciseKeywords = ["supino", "agachamento", "levantamento", "rosca", "remada", "puxada", "leg", "press", "fly", "triceps", "bíceps"]
        let hasExerciseKeyword = exerciseKeywords.contains { lowercaseLine.contains($0) }
        
        // Verifica se contém números (séries/reps)
        let hasNumbers = line.rangeOfCharacter(from: .decimalDigits) != nil
        
        // Verifica se contém padrões típicos (x, séries, reps)
        let hasPatterns = lowercaseLine.contains("x") || lowercaseLine.contains("série") || lowercaseLine.contains("rep")
        
        return hasExerciseKeyword || (hasNumbers && hasPatterns)
    }
    
    private func parseExerciseFromLine(_ line: String) -> ParsedExercise {
        // Parsing simples - pode ser melhorado com regex mais complexas
        let components = line.components(separatedBy: CharacterSet(charactersIn: " -x×"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var name = ""
        var sets: Int?
        var reps: String?
        var weight: String?
        
        // Estratégia: primeira parte não numérica é o nome
        var foundName = false
        for component in components {
            if !foundName && !component.allSatisfy({ $0.isNumber }) {
                if !name.isEmpty { name += " " }
                name += component
            } else {
                foundName = true
                
                // Tentar extrair números
                if component.allSatisfy({ $0.isNumber }), let number = Int(component) {
                    if sets == nil && number <= 10 { // Provavelmente séries
                        sets = number
                    } else if reps == nil { // Provavelmente reps
                        reps = String(number)
                    } else if weight == nil { // Provavelmente peso
                        weight = String(number) + "kg"
                    }
                } else if component.contains("kg") || component.contains("lb") {
                    weight = component
                } else if reps == nil {
                    reps = component
                }
            }
        }
        
        // Fallback se nome não foi encontrado
        if name.isEmpty {
            name = components.first ?? "Exercício"
        }
        
        return ParsedExercise(
            name: name,
            sets: sets,
            reps: reps,
            weight: weight,
            notes: nil
        )
    }
    
    private func calculateOCRConfidence(exercises: [ParsedExercise], totalLines: Int) -> Double {
        guard totalLines > 0 else { return 0.0 }
        
        let extractionRatio = Double(exercises.count) / Double(totalLines)
        let baseConfidence = min(extractionRatio * 2.0, 1.0) // Max 1.0
        
        // Bonus para exercícios com dados completos
        let completeExercises = exercises.filter { $0.sets != nil && $0.reps != nil }
        let completenessBonus = Double(completeExercises.count) / Double(max(exercises.count, 1)) * 0.2
        
        return min(baseConfidence + completenessBonus, 1.0)
    }
}

// MARK: - PDF Parser Protocol & Implementation

protocol PDFParserProtocol {
    func parseWorkoutFromPDF(_ data: Data) async throws -> ParsedWorkoutData
}

final class PDFParser: PDFParserProtocol {
    
    func parseWorkoutFromPDF(_ data: Data) async throws -> ParsedWorkoutData {
        guard let document = PDFDocument(data: data) else {
            throw ImportWorkoutServiceError.fileReadingFailed(NSError(domain: "PDFParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir PDF"]))
        }
        
        print("📄 Iniciando parsing de PDF com \(document.pageCount) página(s)...")
        
        var allText = ""
        
        // Extrair texto de todas as páginas
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            if let pageText = page.string {
                allText += pageText + "\n"
            }
        }
        
        return try parseTextToWorkout(allText, format: "PDF")
    }
    
    private func parseTextToWorkout(_ text: String, format: String) throws -> ParsedWorkoutData {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var exercises: [ParsedExercise] = []
        var extractedTitle: String?
        
        // PDF pode ter estrutura mais organizada
        for line in lines {
            if extractedTitle == nil && isLikelyTitle(line) {
                extractedTitle = line
                continue
            }
            
            if isExerciseLinePDF(line) {
                let exercise = parseExerciseFromPDFLine(line)
                exercises.append(exercise)
            }
        }
        
        let confidence = exercises.isEmpty ? 0.0 : 0.8 // PDFs tendem a ser mais estruturados
        
        let metadata = ParseMetadata(
            confidence: confidence,
            processingTime: 0,
            detectedFormat: format
        )
        
        return ParsedWorkoutData(
            title: extractedTitle,
            exercises: exercises,
            metadata: metadata
        )
    }
    
    private func isLikelyTitle(_ line: String) -> Bool {
        let lowercaseLine = line.lowercased()
        return lowercaseLine.contains("treino") || lowercaseLine.contains("workout") || lowercaseLine.contains("plano")
    }
    
    private func isExerciseLinePDF(_ line: String) -> Bool {
        // PDFs podem ter estrutura mais específica
        let patterns = ["\\d+\\s*x\\s*\\d+", "\\d+\\s*séries", "\\d+\\s*reps", "kg", "lb"]
        
        for pattern in patterns {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func parseExerciseFromPDFLine(_ line: String) -> ParsedExercise {
        // Implementação similar ao OCR mas considerando estrutura mais organizada
        let components = line.components(separatedBy: CharacterSet(charactersIn: "\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var name = ""
        var sets: Int?
        var reps: String?
        var weight: String?
        
        // Em PDFs, exercício geralmente vem primeiro
        var nameComponents: [String] = []
        var foundNumbers = false
        
        for component in components {
            if !foundNumbers && !component.allSatisfy({ $0.isNumber || $0 == "x" || $0 == "×" }) {
                nameComponents.append(component)
            } else {
                foundNumbers = true
                name = nameComponents.joined(separator: " ")
                
                // Parse números e padrões
                if let number = Int(component), sets == nil {
                    sets = number
                } else if component.contains("x") || component.contains("×") {
                    let parts = component.components(separatedBy: CharacterSet(charactersIn: "x×"))
                    if parts.count == 2 {
                        sets = Int(parts[0])
                        reps = parts[1]
                    }
                } else if component.contains("kg") || component.contains("lb") {
                    weight = component
                }
            }
        }
        
        if name.isEmpty {
            name = nameComponents.joined(separator: " ")
        }
        
        return ParsedExercise(
            name: name.isEmpty ? "Exercício" : name,
            sets: sets,
            reps: reps,
            weight: weight,
            notes: nil
        )
    }
}

// MARK: - CSV Parser Protocol & Implementation

protocol CSVParserProtocol {
    func parseWorkoutFromCSV(_ data: Data) async throws -> ParsedWorkoutData
}

final class CSVParser: CSVParserProtocol {
    
    func parseWorkoutFromCSV(_ data: Data) async throws -> ParsedWorkoutData {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw ImportWorkoutServiceError.fileReadingFailed(NSError(domain: "CSVParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível decodificar CSV como UTF-8"]))
        }
        
        print("📊 Iniciando parsing de CSV...")
        
        let lines = csvString.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            throw ImportWorkoutServiceError.noDataExtracted
        }
        
        // Primeira linha pode ser cabeçalho ou título
        let firstLine = lines[0]
        var dataLines = Array(lines[1...])
        
        var extractedTitle: String?
        var headers: [String] = []
        
        // Detectar se primeira linha é cabeçalho
        if isHeaderLine(firstLine) {
            headers = parseCSVLine(firstLine)
            extractedTitle = detectTitleFromHeaders(headers)
        } else {
            // Primeira linha é dados
            dataLines = lines
            extractedTitle = "Treino Importado"
        }
        
        var exercises: [ParsedExercise] = []
        
        for line in dataLines {
            guard !line.isEmpty else { continue }
            
            let values = parseCSVLine(line)
            if let exercise = parseExerciseFromCSVValues(values, headers: headers) {
                exercises.append(exercise)
            }
        }
        
        let confidence = exercises.isEmpty ? 0.0 : 0.9 // CSVs são muito estruturados
        
        let metadata = ParseMetadata(
            confidence: confidence,
            processingTime: 0,
            detectedFormat: "CSV"
        )
        
        return ParsedWorkoutData(
            title: extractedTitle,
            exercises: exercises,
            metadata: metadata
        )
    }
    
    private func isHeaderLine(_ line: String) -> Bool {
        let lowercaseLine = line.lowercased()
        let headerKeywords = ["exercicio", "exercise", "nome", "name", "series", "sets", "reps", "peso", "weight"]
        
        return headerKeywords.contains { lowercaseLine.contains($0) }
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        // Parser CSV simples - pode ser melhorado para lidar com aspas e vírgulas dentro de campos
        return line.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }
    }
    
    private func detectTitleFromHeaders(_ headers: [String]) -> String? {
        // Se há um cabeçalho específico para título ou nome do treino
        for header in headers {
            let lowercaseHeader = header.lowercased()
            if lowercaseHeader.contains("treino") || lowercaseHeader.contains("workout") || lowercaseHeader.contains("plano") {
                return header
            }
        }
        return nil
    }
    
    private func parseExerciseFromCSVValues(_ values: [String], headers: [String]) -> ParsedExercise? {
        guard !values.isEmpty else { return nil }
        
        var name = ""
        var sets: Int?
        var reps: String?
        var weight: String?
        var notes: String?
        
        // Se temos cabeçalhos, usar mapeamento
        if !headers.isEmpty && headers.count == values.count {
            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                
                let value = values[index]
                let lowercaseHeader = header.lowercased()
                
                if lowercaseHeader.contains("exercicio") || lowercaseHeader.contains("exercise") || lowercaseHeader.contains("nome") || lowercaseHeader.contains("name") {
                    name = value
                } else if lowercaseHeader.contains("series") || lowercaseHeader.contains("sets") {
                    sets = Int(value)
                } else if lowercaseHeader.contains("reps") || lowercaseHeader.contains("rep") {
                    reps = value
                } else if lowercaseHeader.contains("peso") || lowercaseHeader.contains("weight") || lowercaseHeader.contains("kg") || lowercaseHeader.contains("lb") {
                    weight = value
                } else if lowercaseHeader.contains("nota") || lowercaseHeader.contains("note") || lowercaseHeader.contains("obs") {
                    notes = value
                }
            }
        } else {
            // Sem cabeçalhos, assumir ordem padrão: nome, séries, reps, peso
            name = values[0]
            
            if values.count > 1, let setsValue = Int(values[1]) {
                sets = setsValue
            }
            
            if values.count > 2 {
                reps = values[2]
            }
            
            if values.count > 3 {
                weight = values[3]
            }
            
            if values.count > 4 {
                notes = values[4]
            }
        }
        
        // Validar se pelo menos o nome foi extraído
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        return ParsedExercise(
            name: name,
            sets: sets,
            reps: reps,
            weight: weight,
            notes: notes
        )
    }
}

// MARK: - ParsedWorkoutData Structures

struct ParsedWorkoutData {
    let title: String?
    let exercises: [ParsedExercise]
    let metadata: ParseMetadata
}

struct ParsedExercise {
    let name: String
    let sets: Int?
    let reps: String?  // Pode ser "10-12" ou "15"
    let weight: String?
    let notes: String?
}

struct ParseMetadata {
    let confidence: Double  // 0.0 - 1.0
    let processingTime: TimeInterval
    let detectedFormat: String
}

// MARK: - Extension for Convenience

extension ImportWorkoutService {
    
    /// Método de conveniência para verificar se OCR está disponível
    static var isOCRAvailable: Bool {
        return VNRecognizeTextRequest.supportedRecognitionLanguages().contains("en-US")
    }
    
    /// Método de conveniência para obter tipos de arquivo suportados
    static var supportedFileTypes: [UTType] {
        return [.pdf, .commaSeparatedText, .image]
    }
    
    /// Método de conveniência para verificar se um tipo de arquivo é suportado
    static func isFileTypeSupported(_ type: UTType) -> Bool {
        return supportedFileTypes.contains { type.conforms(to: $0) }
    }
}
 