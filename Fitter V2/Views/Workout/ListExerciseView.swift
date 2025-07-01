//
//  ListExerciseView.swift
//  Fitter V2
//
//  Atualizado em 15/06/25
//

import SwiftUI
import UIKit

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct ListExerciseView: View {
    @ObservedObject var viewModel: ListExerciseViewModel
    @Binding var selectedExercises: Set<String>
    let workoutTitle: String
    var onExerciseSelect: ((FirebaseExercise) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    // — Novos estados
    @State private var initialScrollOffset: CGFloat? = nil
    @State private var showSearchBar: Bool = false
    @State private var searchBarOpacity: Double = 1
    @State private var searchBarOffset: CGFloat = 0
    @State private var filtrosOpacity: Double = 1
    @State private var filtrosOffset: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                }
                .frame(height: 0)

                // SearchBar + filtros (animados conforme o offset)
                VStack(spacing: 0) {
                    SearchBar(text: $viewModel.searchText)
                        .padding(.horizontal)
                        .opacity(searchBarOpacity)
                        .offset(y: searchBarOffset)
                        .animation(.easeInOut, value: searchBarOpacity)
                    FiltrosView()
                        .opacity(filtrosOpacity)
                        .offset(y: filtrosOffset)
                        .animation(.easeInOut, value: filtrosOpacity)
                }

                ExerciseList()
            }
        }
        .coordinateSpace(name: "scroll")
        .highPriorityGesture(
            DragGesture().onChanged { _ in hideKeyboard() }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            HeaderContent()
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .task {
            await viewModel.loadExercises()
        }
        .onAppear {
            FirebaseExerciseService.shared.startRealtimeListener()
            viewModel.updateSelectedExercises(selectedExercises)
        }
        .onDisappear {
            FirebaseExerciseService.shared.stopRealtimeListener()
        }
        .onChange(of: selectedExercises) { _, newValue in
            viewModel.updateSelectedExercises(newValue)
        }
        .onPreferenceChange(ScrollOffsetKey.self) { offsetY in
            let progress = min(max(-offsetY / 70, 0), 1)
            searchBarOpacity = 1 - progress
            searchBarOffset = -progress * 40
            filtrosOpacity = 1 - progress * 0.5
            filtrosOffset = -progress * 20
        }
    }

    // MARK: - ExerciseList
    @ViewBuilder
    private func ExerciseList() -> some View {
        VStack(spacing: 12) {
            ForEach(viewModel.filteredFirebaseExercises) { exercise in
                ListExerciseCard(
                    exercise: exercise,
                    isSelected: selectedExercises.contains(exercise.safeTemplateId),
                    onTap: {
                        if let onSelect = onExerciseSelect {
                            onSelect(exercise)
                            dismiss()
                        } else {
                            if selectedExercises.contains(exercise.safeTemplateId) {
                                selectedExercises.remove(exercise.safeTemplateId)
                            } else {
                                selectedExercises.insert(exercise.safeTemplateId)
                            }
                        }
                    }
                )
            }
            if viewModel.filteredFirebaseExercises.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Nenhum exercício encontrado")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Tente ajustar os filtros ou verifique sua conexão")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .padding(.top, 40)
            }
        }
    }

    // MARK: - HeaderContent
    @ViewBuilder
    private func HeaderContent() -> some View {
        HStack {
            BackButton()
            Spacer()
            Text("Exercícios")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button("Concluir") {
                dismiss()
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.black)
    }

    // MARK: - FiltrosView
    @ViewBuilder
    private func FiltrosView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filtros principais
            HStack {
                Spacer()
                if viewModel.selectedMuscleGroup != nil {
                    Button(action: {
                        viewModel.resetFilters()
                    }) {
                        Text("Remover filtros")
                            .font(.system(size: 16, weight: .medium))
                            .italic()
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.availableMuscleGroups, id: \ .self) { group in
                        Button(action: {
                            if viewModel.selectedMuscleGroup == group {
                                viewModel.resetFilters()
                            } else {
                                viewModel.selectedMuscleGroup = group
                                viewModel.selectedEquipment = nil
                                viewModel.selectedGrip = nil
                                viewModel.showGripFilter = true
                                viewModel.showEquipmentFilter = true
                            }
                        }) {
                            Text(group.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(viewModel.selectedMuscleGroup == group ? .black : .white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 82)
                                        .fill(viewModel.selectedMuscleGroup == group ? Color.white : Color.clear)
                                        .stroke(Color.white.opacity(1), lineWidth: 2)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 22)

            // Filtros Secundários
            if viewModel.selectedMuscleGroup != nil && 
               (!viewModel.gripOptions.isEmpty || !viewModel.equipmentOptions.isEmpty) {
                VStack(spacing: 16) {
                    // Pegada - só mostra se houver opções
                    if !viewModel.gripOptions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.gripOptions, id: \ .self) { grip in
                                    Button(action: {
                                        if viewModel.selectedGrip == grip {
                                            viewModel.selectedGrip = nil
                                        } else {
                                            viewModel.selectedGrip = grip
                                        }
                                    }) {
                                        Text(grip)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(viewModel.selectedGrip == grip ? .black : .white)
                                            .padding(.horizontal, 22)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 22)
                                                    .fill(viewModel.selectedGrip == grip ? Color.white : Color.clear)
                                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    // Equipamentos - só mostra se houver opções
                    if !viewModel.equipmentOptions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.equipmentOptions, id: \ .self) { equipment in
                                    Button(action: {
                                        if viewModel.selectedEquipment == equipment {
                                            viewModel.selectedEquipment = nil
                                        } else {
                                            viewModel.selectedEquipment = equipment
                                        }
                                    }) {
                                        Text(equipment)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(viewModel.selectedEquipment == equipment ? .black : .white)
                                            .padding(.horizontal, 22)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 22)
                                                    .fill(viewModel.selectedEquipment == equipment ? Color.white : Color.clear)
                                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 16)
                .background(Color.black)
            }
        }
        .background(Color.black)
    }
}

// MARK: – SearchBar UIViewRepresentable
struct SearchBar: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UISearchBar {
        let sb = UISearchBar(frame: .zero)
        sb.placeholder = "Buscar exercício"
        sb.delegate = context.coordinator
        sb.searchBarStyle = .minimal
        sb.returnKeyType = .done
        sb.showsCancelButton = false
        return sb
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
        uiView.showsCancelButton = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        let parent: SearchBar
        init(_ parent: SearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
    }
}

// MARK: – PreferenceKey para ler offset
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if DEBUG
struct ListExerciseView_Previews: PreviewProvider {
    @State static var selectedExercises: Set<String> = []
    static var previews: some View {
        // Inicializa o ViewModel de preview explicitamente com o serviço mock
        let viewModel = ListExerciseViewModel(exerciseService: .preview)
        ListExerciseView(
            viewModel: viewModel,
            selectedExercises: $selectedExercises,
            workoutTitle: "Treino de Exemplo"
        )
        .environment(\.managedObjectContext, PreviewCoreDataStack.shared.viewContext)
        .background(Color.black)
    }
}
#endif
