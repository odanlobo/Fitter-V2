import SwiftUI
import SwiftData

struct ListExerciseView: View {
    @EnvironmentObject var authViewModel: LoginViewModel
    
    @Binding var selectedExercises: Set<String>
    let workoutTitle: String
    var onExerciseSelect: ((ExerciseTemplate) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [ExerciseTemplate]

    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var selectedEquipment: String? = nil

    /// Opções de equipamentos, filtradas pelo grupo muscular (se houver)
    private var equipmentOptions: [String] {
        let source = (selectedMuscleGroup == nil)
            ? exercises
            : exercises.filter { $0.muscleGroup == selectedMuscleGroup }
        let set = Set(source.map { $0.equipment })
        let ordem = ["Barra", "Halteres", "Polia", "Máquina", "Peso do Corpo"]
        let primeiros = ordem.filter { set.contains($0) }
        let outros = set.subtracting(ordem).sorted()
        return primeiros + outros
    }

    /// Exercícios após aplicar filtros de grupo e equipamento
    private var filteredExercises: [ExerciseTemplate] {
        exercises.filter {
            (selectedMuscleGroup == nil || $0.muscleGroup == selectedMuscleGroup) &&
            (selectedEquipment == nil || $0.equipment == selectedEquipment)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Cabeçalho com botão de voltar e título
                HStack {
                    BackButton()
                    Spacer()
                    Text(workoutTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                // Filtros
                HStack(spacing: 16) {
                    // Grupo muscular
                    Menu {
                        Button("Todos") {
                            selectedMuscleGroup = nil
                            selectedEquipment = nil
                        }
                        ForEach(MuscleGroup.allCases) { group in
                            Button(group.displayName) {
                                selectedMuscleGroup = group
                                selectedEquipment = nil
                            }
                        }
                    } label: {
                        Label(
                            selectedMuscleGroup?.displayName ?? "Todos Grupos",
                            systemImage: "figure.walk"
                        )
                        .foregroundColor(.white)
                    }

                    // Equipamento
                    Menu {
                        Button("Todos") { selectedEquipment = nil }
                        ForEach(equipmentOptions, id: \.self) { equip in
                            Button(equip) { selectedEquipment = equip }
                        }
                    } label: {
                        Label(
                            selectedEquipment ?? "Todos Equipamentos",
                            systemImage: "wrench.and.screwdriver"
                        )
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Lista de exercícios
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredExercises) { template in
                            ListExerciseCard(
                                template: template,
                                isSelected: selectedExercises.contains(template.templateId)
                            ) {
                                if let action = onExerciseSelect {
                                    action(template)
                                    dismiss()
                                } else {
                                    if selectedExercises.contains(template.templateId) {
                                        selectedExercises.remove(template.templateId)
                                    } else {
                                        selectedExercises.insert(template.templateId)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Preview
#Preview("Seleção de exercícios") {
    ListExerciseView(
        selectedExercises: .constant(Set()),
        workoutTitle: "Selecione exercícios"
    )
    .modelContainer(for: [ExerciseTemplate.self])
}
