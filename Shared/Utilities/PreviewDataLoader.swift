//
//  PreviewDataLoader.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/06/25.
//

import CoreData

struct PreviewDataLoader {
    static func populatePreviewData(in context: NSManagedObjectContext) {
        print("🔄 PreviewDataLoader - Iniciando população de dados de preview...")
        
        // Busca exercícios do banco já seeded
        let fetch: NSFetchRequest<CDExerciseTemplate> = CDExerciseTemplate.fetchRequest()
        let allExercises = (try? context.fetch(fetch)) ?? []
        
        // Garante que todos têm cloudSyncStatus válido
        for template in allExercises {
            template.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        }

        // Usuário fictício com dados completos
        let user = CDAppUser(context: context)
        user.id = UUID()
        user.name = "Dan Lobo"
        user.email = "dan@fitter.com"
        user.height = 1.78
        user.weight = 78
        user.gender = "M"
        user.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())
        user.createdAt = Date().addingTimeInterval(-86400 * 30)
        
        // Campos obrigatórios que estavam faltando
        user.providerId = "preview_user_123" // Campo obrigatório
        user.updatedAt = Date() // Campo obrigatório
        user.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório
        
        print("🎯 PreviewDataLoader - Usuário criado: \(user.safeName)")
        
        // Salva o usuário primeiro
        do {
            try context.save()
            print("✅ PreviewDataLoader - Usuário salvo com sucesso")
        } catch {
            print("❌ PreviewDataLoader - Erro ao salvar usuário: \(error)")
            return
        }

        // 3 Planos de treino
        for i in 0..<3 {
            let plan = CDWorkoutPlan(context: context)
            plan.id = UUID()
            plan.title = "Treino \(["A", "B", "C"][i])"
            plan.createdAt = Date().addingTimeInterval(TimeInterval(-i * 86400 * 2))
            plan.order = Int32(i)
            plan.user = user
            plan.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório

            // 3 exercícios por plano, grupos diferentes
            let startIdx = i * 3
            let templates = Array(allExercises.dropFirst(startIdx).prefix(3))
            var muscleGroupsSet: Set<String> = []
            
            for (idx, template) in templates.enumerated() {
                let planEx = CDPlanExercise(context: context)
                planEx.id = UUID()
                planEx.order = Int32(idx)
                planEx.plan = plan
                planEx.template = template
                planEx.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório
                
                // Coleta grupos musculares para o plano
                if let muscleGroup = template.muscleGroup {
                    muscleGroupsSet.insert(muscleGroup)
                }
            }
            
            // Define muscleGroups obrigatório no plano
            plan.muscleGroups = muscleGroupsSet.joined(separator: ",")
        }
        
        print("🎯 PreviewDataLoader - Criados 3 planos de treino para usuário \(user.safeName)")

        // 7 dias de histórico com dados de sensores completos (para testes futuros com Apple Watch)
        for day in 0..<7 {
            let history = CDWorkoutHistory(context: context)
            history.id = UUID()
            history.date = Calendar.current.date(byAdding: .day, value: -day, to: Date())
            history.user = user
            history.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório

            // 2 exercícios por histórico
            let exercises = allExercises.shuffled().prefix(2)
            for (idx, template) in exercises.enumerated() {
                let hex = CDHistoryExercise(context: context)
                hex.id = UUID()
                hex.name = template.safeName
                hex.order = Int32(idx)
                hex.history = history
                hex.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório

                // 2 séries mock com dados completos (incluindo sensores para testes futuros)
                for setOrder in 0..<2 {
                    let set = CDHistorySet(context: context)
                    set.id = UUID()
                    set.order = Int32(setOrder)
                    set.reps = 10 + Int32(setOrder)
                    set.weight = 20.0 + Double(setOrder * 2)
                    let baseTimestamp = history.date ?? Date()
                    set.timestamp = baseTimestamp.addingTimeInterval(Double(setOrder) * 180)
                    set.heartRate = 90 + Int32(setOrder) * 5
                    set.caloriesBurned = 15.0 + Double(setOrder)
                    set.exercise = hex
                    set.cloudSyncStatus = CloudSyncStatus.synced.rawValue // Campo obrigatório
                    
                    // Campos de tempo opcionais mas úteis
                    set.startTime = set.timestamp!.addingTimeInterval(-60)
                    set.endTime = set.timestamp
                    set.restTime = 90.0 // 90 segundos de descanso
                    
                    // DADOS DE SENSORES OPCIONAIS - Valores simulados realistas para testes futuros com Apple Watch
                    // Dados de rotação (giroscópio) em rad/s
                    set.rotationX = Double.random(in: -0.5...0.5)
                    set.rotationY = Double.random(in: -0.3...0.3)
                    set.rotationZ = Double.random(in: -0.2...0.2)
                    
                    // Dados de aceleração (acelerômetro) em m/s²
                    set.accelerationX = Double.random(in: -2.0...2.0)
                    set.accelerationY = Double.random(in: -1.5...1.5)
                    set.accelerationZ = Double.random(in: 8.0...12.0) // Inclui gravidade
                    
                    // Dados de gravidade em m/s²
                    set.gravityX = Double.random(in: -1.0...1.0)
                    set.gravityY = Double.random(in: -1.0...1.0)
                    set.gravityZ = Double.random(in: 9.0...10.0) // Gravidade terrestre
                    
                    // Dados de atitude (orientação) em radianos
                    set.attitudeRoll = Double.random(in: -Double.pi/4...Double.pi/4)
                    set.attitudePitch = Double.random(in: -Double.pi/6...Double.pi/6)
                    set.attitudeYaw = Double.random(in: -Double.pi...Double.pi)
                }
            }
        }

        // (Opcional) Sessão ativa mockada com dados de sensores para testes
        let session = CDCurrentSession(context: context)
        session.id = UUID()
        session.startTime = Date().addingTimeInterval(-1800)
        session.plan = user.workoutPlansArray.first
        session.user = user
        session.currentExerciseIndex = 1
        session.isActive = true // Campo obrigatório
        user.currentSession = session

        let currExercise = CDCurrentExercise(context: context)
        currExercise.id = UUID()
        currExercise.session = session
        currExercise.template = session.plan?.exercisesArray.first?.template
        currExercise.startTime = session.startTime
        currExercise.currentSetIndex = 0 // Campo obrigatório
        currExercise.isActive = true // Campo obrigatório
        session.currentExercise = currExercise

        let currSet = CDCurrentSet(context: context)
        currSet.id = UUID()
        currSet.exercise = currExercise
        currSet.order = 0
        currSet.targetReps = 12
        currSet.weight = 25.0
        currSet.timestamp = Date()
        currSet.startTime = Date().addingTimeInterval(-60)
        currSet.isActive = true
        
        // Dados de sensores para a série atual (opcionais, úteis para testes futuros)
        currSet.rotationX = 0.1
        currSet.rotationY = -0.05
        currSet.rotationZ = 0.02
        currSet.accelerationX = 0.5
        currSet.accelerationY = -0.3
        currSet.accelerationZ = 9.8
        currSet.gravityX = 0.0
        currSet.gravityY = 0.0
        currSet.gravityZ = 9.8
        currSet.attitudeRoll = 0.1
        currSet.attitudePitch = -0.05
        currSet.attitudeYaw = 1.2
        
        currExercise.currentSet = currSet

        // Salva tudo
        do {
            try context.save()
            print("✅ PreviewDataLoader - Todos os dados foram salvos com sucesso")
            
            // Verifica se o usuário foi salvo corretamente
            let userFetch: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
            let users = try context.fetch(userFetch)
            print("📊 PreviewDataLoader - Usuários no contexto: \(users.count)")
            
            // Verifica se os planos foram salvos
            let plansFetch: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
            let plans = try context.fetch(plansFetch)
            print("📊 PreviewDataLoader - Planos no contexto: \(plans.count)")
            
            // Verifica se o histórico foi salvo
            let historyFetch: NSFetchRequest<CDWorkoutHistory> = CDWorkoutHistory.fetchRequest()
            let histories = try context.fetch(historyFetch)
            print("📊 PreviewDataLoader - Históricos no contexto: \(histories.count)")
            
            // Verifica se as séries foram salvas
            let setsFetch: NSFetchRequest<CDHistorySet> = CDHistorySet.fetchRequest()
            let sets = try context.fetch(setsFetch)
            print("📊 PreviewDataLoader - Séries no contexto: \(sets.count)")
            
        } catch {
            print("❌ PreviewDataLoader - Erro ao salvar dados finais: \(error)")
        }
    }
}
