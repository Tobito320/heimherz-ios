import Synchronization

/// Ein Wert, den Schließungen aus mehreren Threads lesen und ändern dürfen (`Mutex` selbst lässt sich nicht in Schließungen fangen).
final class Kasten<T: Sendable>: Sendable {
    private let m: Mutex<T>
    init(_ wert: T) { m = Mutex(wert) }
    func mit<R: Sendable>(_ f: (inout T) -> R) -> R { m.withLock { f(&$0) } }
}
