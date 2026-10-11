import SwiftUI

@main
struct LeoneraRemindersApp: App {
    @State private var store = ReminderStore.shared
    @State private var settings = SettingsStore.shared
    @State private var alarms = AlarmSyncService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ReminderListView()
                .environment(store)
                .environment(settings)
                .environment(alarms)
                .tint(.brand)
                .task { await alarms.start() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    // Ningún vencido se queda callado: vuelve a sonar en el siguiente minuto.
                    store.retryOverdue(ringing: alarms.alertingAlarmIDs)
                    alarms.requestSync()
                }
        }
    }
}
