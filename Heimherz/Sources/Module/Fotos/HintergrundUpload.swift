import Foundation
import Network
import Synchronization

/// Schickt Dateien über eine Hintergrund-`URLSession`: iOS führt den Transfer weiter, auch wenn die App schläft oder das Handy gesperrt ist.
/// Nur Delegate, keine Completion-Handler (Hintergrund-Sitzungen erlauben nichts anderes). Die Sitzung hat eine feste Kennung; nach einem
/// Neustart der App liefert iOS die Ergebnisse alter Transfers an diesen Delegate, dann gibt es keinen Wartenden mehr und nur die Temp-Datei wird gelöscht.
final class HintergrundUpload: NSObject, FotoSender, URLSessionTaskDelegate, Sendable {
    static let sitzungsKennung = "com.onlyus.heimherz.fotos-upload"
    static let geteilt = HintergrundUpload()

    private let wartende = Mutex<[Int: CheckedContinuation<Void, any Error>]>([:])
    private let sitzungBox = Mutex<URLSession?>(nil)

    private var sitzung: URLSession {
        sitzungBox.withLock { box in
            if let s = box { return s }
            let konfig = URLSessionConfiguration.background(withIdentifier: Self.sitzungsKennung)
            konfig.sessionSendsLaunchEvents = true
            konfig.isDiscretionary = false
            konfig.waitsForConnectivity = true
            let s = URLSession(configuration: konfig, delegate: self, delegateQueue: nil)
            box = s
            return s
        }
    }

    func sende(datei: URL, anfrage: URLRequest) async throws {
        let pfad = datei.path
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let task = sitzung.uploadTask(with: anfrage, fromFile: datei)
                task.taskDescription = pfad
                wartende.withLock { $0[task.taskIdentifier] = c }
                task.resume()
            }
        } onCancel: {
            sitzung.getAllTasks { tasks in tasks.filter { $0.taskDescription == pfad }.forEach { $0.cancel() } }
        }
    }

    /// Pfade der Dateien, die laufende oder wartende Transfers noch brauchen (der Rest in `FotoTemp` ist Müll).
    func laufendeDateien() async -> Set<String> {
        await withCheckedContinuation { (c: CheckedContinuation<Set<String>, Never>) in
            sitzung.getAllTasks { c.resume(returning: Set($0.compactMap(\.taskDescription))) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let pfad = task.taskDescription { try? FileManager.default.removeItem(atPath: pfad) }
        guard let c = wartende.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let fehler = error as? URLError {
            c.resume(throwing: HeimFehler(urlFehler: fehler))
        } else if error != nil {
            c.resume(throwing: HeimFehler.nichtErreichbar)
        } else if let status = (task.response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) {
            c.resume()
        } else {
            c.resume(throwing: HeimFehler.aus(status: (task.response as? HTTPURLResponse)?.statusCode ?? 0))
        }
    }
}

/// Ob das Handy gerade im WLAN (oder am Kabel) ist.
final class NetzartLive: Netzart, @unchecked Sendable {
    // shortcut: NWPathMonitor ist nicht als Sendable markiert; er wird nur hier gestartet, gelesen wird allein über das Mutex.
    static let geteilt = NetzartLive()

    private let monitor = NWPathMonitor()
    private let pfad = Mutex<NWPath?>(nil)

    private init() {
        monitor.pathUpdateHandler = { [self] p in self.pfad.withLock { $0 = p } }
        monitor.start(queue: DispatchQueue(label: "heimherz.netzart"))
    }

    func istWLAN() async -> Bool {
        for _ in 0..<10 {
            if let p = pfad.withLock({ $0 }) { return p.status == .satisfied && (p.usesInterfaceType(.wifi) || p.usesInterfaceType(.wiredEthernet)) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
