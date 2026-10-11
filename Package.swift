// swift-tools-version: 6.0
// Paquete sólo para compilar y probar la lógica sin interfaz (LeoneraReminders/Core) con `swift test`,
// incluso en Linux. La app se abre con LeoneraReminders.xcodeproj.
import PackageDescription

let package = Package(
    name: "ReminderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReminderCore", targets: ["ReminderCore"]),
    ],
    targets: [
        .target(name: "ReminderCore", path: "LeoneraReminders/Core"),
        .testTarget(
            name: "ReminderCoreTests",
            dependencies: ["ReminderCore"],
            path: "Tests/ReminderCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
