//
//  WorkoutsPlansList.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI

struct WorkoutsPlansList: View {
    let plans: [WorkoutPlan]
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (WorkoutPlan) -> Void
    let onCreate: () -> Void
    let onDelete: (WorkoutPlan) -> Void
    let onRefresh: () -> Void
    
    @Binding var editMode: EditMode
    
    var body: some View {
        List {
            ForEach(plans) { plan in
                // --- CARD CUSTOMIZADO: personalize tudo abaixo! ---
                ZStack {
                    // Fundo do card (pode trocar cor, gradiente, imagem...)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.black))
                        .shadow(color: .white.opacity(0.12), radius: 8, x: 0, y: 3)
                    
                    HStack(spacing: 16) {
                        // Informações do treino
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.title)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(plan.muscleGroups)
                                .font(.system(size: 14, weight: .semibold, design: .rounded).italic())
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Botão de editar (exemplo, remova se não quiser)
                        Button(action: {
                            onSelect(plan)
                        }) {
                            Image(systemName: "pencil")
                                .foregroundColor(.white)
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        
                        // Botão de deletar manual (além do swipe para deletar)
                        Button(action: {
                            onDelete(plan)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        
                        // Handle de drag (só aparece no EditMode)
                        if editMode == .active {
                            Image(systemName: "line.horizontal.3")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.leading, 6)
                                .opacity(0.9)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear) // Mantém fundo escuro atrás do card
                .onTapGesture {
                    onSelect(plan)
                }
            }
            .onMove(perform: onMove)
            .onDelete { indices in
                indices.forEach { idx in
                    onDelete(plans[idx])
                }
            }
            
            // --- Seção de criar novo treino ---
            Section {
                CreateButton {
                    onCreate()
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable {
            onRefresh()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview("Mock isolado") {
    @State var editMode: EditMode = .active // Para handles de drag aparecerem

    let template = ExerciseTemplate(
        templateId: "test_1",
        name: "Supino Reto",
        muscleGroup: .chest,
        equipment: "Barra",
        imageName: nil
    )
    
    let plan1 = WorkoutPlan(title: "Treino A")
    let plan2 = WorkoutPlan(title: "Treino B")
    let planExercise1 = PlanExercise(order: 0, plan: plan1, template: template)
    let planExercise2 = PlanExercise(order: 0, plan: plan2, template: template)
    plan1.exercises.append(planExercise1)
    plan2.exercises.append(planExercise2)
    
    return WorkoutsPlansList(
        plans: [plan1, plan2],
        onMove: { from, to in
            print("Move from \(from) to \(to)")
        },
        onSelect: { plan in
            print("Selected: \(plan.title)")
        },
        onCreate: {
            print("Create workout")
        },
        onDelete: { plan in
            print("Delete: \(plan.title)")
        },
        onRefresh: {
            print("Refresh")
        },
        editMode: $editMode
    )
    .background(Color.black)
}
