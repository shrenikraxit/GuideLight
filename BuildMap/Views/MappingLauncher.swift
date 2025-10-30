import SwiftUI
import Combine

// MARK: - Mapping Launcher View Modifier
struct MappingLauncher: ViewModifier {
    @State private var showingBuildMap = false
    @State private var showingMapList = false
    @State private var cancellables = Set<AnyCancellable>()
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .triggerPathfinderMapping)) { _ in
                showingBuildMap = true
            }
            .sheet(isPresented: $showingBuildMap) {
                BuildMapView()
            }
            .onAppear {
                setupNotificationListeners()
            }
    }
    
    private func setupNotificationListeners() {
        // Listen for mapping trigger
        NotificationCenter.default.publisher(for: .triggerPathfinderMapping)
            .sink { _ in
                showingBuildMap = true
            }
            .store(in: &cancellables)
    }
}

// MARK: - View Extension
extension View {
    func mappingLauncher() -> some View {
        modifier(MappingLauncher())
    }
}

// MARK: - Additional Notifications
extension Notification.Name {
    static let showMapList = Notification.Name("ShowMapList")
    static let mapSelectionChanged = Notification.Name("MapSelectionChanged")
}

// MARK: - Map Selection Manager
@MainActor
class MapSelectionManager: ObservableObject {
    @Published var selectedMapId: UUID?
    @Published var selectedMapName: String?
    
    private let mapManager = MapManagerViewModel()
    
    init() {
        loadSelectedMap()
    }
    
    func loadSelectedMap() {
        selectedMapId = mapManager.selectedMapId
        
        if let selectedMapId = selectedMapId {
            Task {
                if let map = await mapManager.loadMap(with: selectedMapId) {
                    await MainActor.run {
                        self.selectedMapName = map.name
                    }
                }
            }
        } else {
            selectedMapName = nil
        }
    }
    
    func selectMap(with id: UUID) {
        mapManager.selectMap(with: id)
        loadSelectedMap()
        
        // Notify about selection change
        NotificationCenter.default.post(name: .mapSelectionChanged, object: nil)
    }
    
    func clearSelection() {
        mapManager.clearSelectedMap()
        selectedMapId = nil
        selectedMapName = nil
        
        // Notify about selection change
        NotificationCenter.default.post(name: .mapSelectionChanged, object: nil)
    }
}
