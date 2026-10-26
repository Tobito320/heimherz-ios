import Foundation
import UserNotifications

/// Der Weg zu den Mitteilungen des Systems; im Test eine Attrappe (der Test-Host fasst `UNUserNotificationCenter` nie an).
protocol MitteilungsDienst: Sendable {
    /// Fragt nach der Erlaubnis, aber nur beim allerersten Mal (danach entscheidet allein der Nutzer in den iOS-Einstellungen).
    func erlaubnisFragen() async
    /// nil: noch nicht gefragt.
    func erlaubt() async -> Bool?
    func zeige(text: String) async
}

struct SystemMitteilungen: MitteilungsDienst {
    func erlaubnisFragen() async {
        let zentrale = UNUserNotificationCenter.current()
        guard await zentrale.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await zentrale.requestAuthorization(options: [.alert, .sound])
    }

    func erlaubt() async -> Bool? {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return nil
        case .denied: return false
        default: return true
        }
    }

    func zeige(text: String) async {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Haven"
        inhalt.body = text
        inhalt.sound = .default
        // Ohne Auslöser: sofort. Eine feste Kennung, damit ein zweiter Lauf die alte Mitteilung ersetzt statt sie zu stapeln.
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "heimherz.fotos.gesichert", content: inhalt, trigger: nil))
    }
}

/// Die Mitteilung nach einem Foto-Abgleich: "N Fotos gesichert". Nur wenn etwas ankam, nur wenn der Schalter an ist, nie nach "Anhalten".
/// Steht die App im Vordergrund, zeigt iOS sie nicht (der Lauf ist dort ohnehin zu sehen).
enum FotoMitteilung {
    static func text(gesichert: Int) -> String {
        gesichert == 1 ? "1 Foto gesichert" : "\(gesichert.formatted()) Fotos gesichert"
    }

    static func sollMelden(gesichert: Int, vomNutzerAngehalten: Bool, schalterAn: Bool) -> Bool {
        schalterAn && !vomNutzerAngehalten && gesichert > 0
    }

    /// Ruft der Lauf am Ende auf. true, wenn eine Mitteilung ging.
    @discardableResult
    static func meldeNachLauf(gesichert: Int, vomNutzerAngehalten: Bool, schalterAn: Bool, dienst: any MitteilungsDienst) async -> Bool {
        guard sollMelden(gesichert: gesichert, vomNutzerAngehalten: vomNutzerAngehalten, schalterAn: schalterAn) else { return false }
        await dienst.zeige(text: text(gesichert: gesichert))
        return true
    }
}
