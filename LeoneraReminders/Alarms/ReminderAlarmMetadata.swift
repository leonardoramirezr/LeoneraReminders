import AlarmKit
import Foundation

/// Datos que viajan con cada alarma de AlarmKit.
struct ReminderAlarmMetadata: AlarmMetadata {
    var reminderID: UUID
}
