import BackgroundTasks
import Foundation

/// Systemaufgaben für den Foto-Abgleich (Quelle: developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
/// und BGProcessingTaskRequest). Beide Kennungen stehen in `BGTaskSchedulerPermittedIdentifiers` (project.yml).
/// Es läuft nie mehr als ein Abgleich, darum reicht je Art eine feste Kennung (die Wildcard-Schreibweise steht nicht in Apples Doku).
enum FotoHintergrund {
    /// Vom Nutzer gestartete Arbeit (iOS 26): läuft mit Fortschrittsanzeige im System weiter, wenn die App in den Hintergrund geht. Kennung mit Bundle-ID-Präfix.
    static let abgleichKennung = "com.onlyus.heimherz.fotos-abgleich"
    /// Nachts mit Strom und Netz: macht den Rest, wenn der Nutzer den Abgleich nicht angehalten hat.
    static let nachtKennung = "com.onlyus.heimherz.fotos-nacht"

    /// BGTask ist nicht Sendable. Die Box wird nur auf dem MainActor benutzt, der Launch-Handler läuft auf einer Hintergrund-Queue.
    struct AufgabenBox: @unchecked Sendable { let task: BGTask }   // shortcut: nur Weitergabe an den MainActor, danach greift allein dort jemand zu

    /// Einmal beim App-Start (vor dem Ende von `didFinishLaunching`); doppeltes Registrieren wirft.
    static func registriere() {
        let planer = BGTaskScheduler.shared
        _ = planer.register(forTaskWithIdentifier: abgleichKennung, using: nil) { task in
            let box = AufgabenBox(task: task)
            Task { @MainActor in FotosModell.geteilt.haengeAn(box) }
        }
        _ = planer.register(forTaskWithIdentifier: nachtKennung, using: nil) { task in
            let box = AufgabenBox(task: task)
            Task { @MainActor in await FotosModell.geteilt.nachtlauf(box) }
        }
    }

    /// Nur aus dem Knopf "Abgleich starten" (Apple: Auslöser muss eine Handlung des Nutzers sein). Scheitert es, läuft der Abgleich im Vordergrund weiter.
    static func reicheFortsetzungEin() {
        guard !AppUmgebung.istTestHost else { return }
        let anfrage = BGContinuedProcessingTaskRequest(identifier: abgleichKennung, title: "Fotos zum PC", subtitle: "Starte …")
        try? BGTaskScheduler.shared.submit(anfrage)
    }

    static func planeNacht() {
        guard !AppUmgebung.istTestHost else { return }
        let anfrage = BGProcessingTaskRequest(identifier: nachtKennung)
        anfrage.requiresExternalPower = true
        anfrage.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(anfrage)
    }

    static func sageNachtAb() {
        guard !AppUmgebung.istTestHost else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: nachtKennung)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: abgleichKennung)
    }
}
