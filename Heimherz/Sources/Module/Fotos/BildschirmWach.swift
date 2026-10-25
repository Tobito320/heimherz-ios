import UIKit

/// Hält den Bildschirm an, solange ein Abgleich im Vordergrund läuft und das Handy am Strom hängt (sonst bremst iOS die App, wenn der Bildschirm ausgeht).
/// Ohne Strom, beim Anhalten und am Ende des Laufs ist der Zeitgeber wieder normal.
@MainActor
enum BildschirmWach {
    /// Rein (Test): wach nur mit laufendem Abgleich und Strom.
    nonisolated static func soll(laeuft: Bool, amStrom: Bool) -> Bool { laeuft && amStrom }

    static var amStrom: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    static func setze(laeuft: Bool) {
        UIApplication.shared.isIdleTimerDisabled = soll(laeuft: laeuft, amStrom: laeuft && amStrom)
    }
}
