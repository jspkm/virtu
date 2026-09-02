import Foundation

/// The preference set PRD §14 has specified since the beginning and the app
/// has never had a home for.
///
/// Deliberately narrower than §14's list: `tuningPreset` belongs to `Tuner`,
/// `stageMode` to `AppState`, and the one-time hint flag already persists
/// beside the tool settings. Duplicating any of them here would give each two
/// sources of truth. What is left is what genuinely had nowhere to live.
///
/// Clamped in explicit setters over private stores, NOT in `didSet`:
/// `@Observable` rewrites a stored property into a computed one, so writing to
/// a property inside its own `didSet` re-enters the setter and recurses. The
/// metronome learned this the hard way.
@Observable
final class Preferences {

    /// How long the carried-over system stays up, if the seam is ever built
    /// (PRD §9 — the seam is undecided; see PLAN Part II, Decision 1). Stored
    /// now so the preference exists whichever way that decision goes.
    static let minSeamHoldSeconds = 2
    static let maxSeamHoldSeconds = 10

    private let defaults: UserDefaults
    private var storedSeamHoldSeconds = 4
    private var storedHalfPageTurns = false
    private var storedBluetoothPedal = true
    private var storedFingerDrawing = false
    private var storedPencilEverPaired = false

    var seamHoldSeconds: Int {
        get { storedSeamHoldSeconds }
        set {
            let clamped = min(max(newValue, Self.minSeamHoldSeconds), Self.maxSeamHoldSeconds)
            guard clamped != storedSeamHoldSeconds else { return }
            storedSeamHoldSeconds = clamped
            defaults.set(clamped, forKey: "seamHoldSeconds")
        }
    }

    var halfPageTurns: Bool {
        get { storedHalfPageTurns }
        set {
            guard newValue != storedHalfPageTurns else { return }
            storedHalfPageTurns = newValue
            defaults.set(newValue, forKey: "halfPageTurns")
        }
    }

    var bluetoothPedal: Bool {
        get { storedBluetoothPedal }
        set {
            guard newValue != storedBluetoothPedal else { return }
            storedBluetoothPedal = newValue
            defaults.set(newValue, forKey: "bluetoothPedal")
        }
    }

    /// §0.2: fingers never draw when a Pencil is present, and this is never
    /// auto-enabled. It is offered only when `pencilEverPaired` is false.
    var fingerDrawing: Bool {
        get { storedFingerDrawing }
        set {
            guard newValue != storedFingerDrawing else { return }
            storedFingerDrawing = newValue
            defaults.set(newValue, forKey: "fingerDrawing")
        }
    }

    /// Latched true the first time a Pencil touch reaches the ink surface.
    /// There is no public API for "has a Pencil ever been paired", and the
    /// honest proxy is having seen one write.
    private(set) var pencilEverPaired: Bool {
        get { storedPencilEverPaired }
        set {
            guard newValue != storedPencilEverPaired else { return }
            storedPencilEverPaired = newValue
            defaults.set(newValue, forKey: "pencilEverPaired")
        }
    }

    func notePencilSeen() {
        guard !storedPencilEverPaired else { return }
        pencilEverPaired = true
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Through the setters, which do the clamping.
        if defaults.object(forKey: "seamHoldSeconds") != nil {
            seamHoldSeconds = defaults.integer(forKey: "seamHoldSeconds")
        }
        if defaults.object(forKey: "halfPageTurns") != nil {
            halfPageTurns = defaults.bool(forKey: "halfPageTurns")
        }
        if defaults.object(forKey: "bluetoothPedal") != nil {
            bluetoothPedal = defaults.bool(forKey: "bluetoothPedal")
        }
        if defaults.object(forKey: "fingerDrawing") != nil {
            fingerDrawing = defaults.bool(forKey: "fingerDrawing")
        }
        if defaults.object(forKey: "pencilEverPaired") != nil {
            pencilEverPaired = defaults.bool(forKey: "pencilEverPaired")
        }
    }
}
