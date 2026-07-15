import Foundation
import SwiftUI

/// Live-tunable parameters for the recording orb visualizer.
/// Adjust in the Visualizer Lab; values persist across launches.
@MainActor
final class OrbSettings: ObservableObject {
    static let shared = OrbSettings()

    struct Param {
        let key: String
        let def: Double
        let range: ClosedRange<Double>
        let label: String
    }

    static let params: [String: Param] = [
        "count": Param(key: "orb.count", def: 3, range: 1...6, label: "Orb Copies"),
        "ripple": Param(key: "orb.ripple", def: 0.303, range: 0...0.9, label: "Ripple Depth"),
        "scale": Param(key: "orb.scale", def: 3.321, range: 0.5...8, label: "Ripple Tightness"),
        "speed": Param(key: "orb.speed", def: 3.709, range: 0.1...6, label: "Ripple Speed"),
        "gain": Param(key: "orb.gain", def: 1.0, range: 0.2...3, label: "Input Gain"),
        "floor": Param(key: "orb.floor", def: 0.256, range: 0...0.4, label: "Silence Floor"),
        "stiffness": Param(key: "orb.stiffness", def: 0.42, range: 0.05...0.9, label: "Spring Stiffness"),
        "damping": Param(key: "orb.damping", def: 0.669, range: 0.3...0.95, label: "Spring Damping"),
        "size": Param(key: "orb.size", def: 0.46, range: 0.2...0.6, label: "Orb Size"),
        "variation": Param(key: "orb.variation", def: 0.184, range: 0...0.6, label: "Copy Variation"),
        "blur": Param(key: "orb.blur", def: 38.2, range: 0...40, label: "Glow Blur"),
        "fill": Param(key: "orb.fill", def: 1.0, range: 0.1...1, label: "Fill Opacity"),
        "glow": Param(key: "orb.glow", def: 0.457, range: 0...1, label: "Glow Opacity"),
    ]

    @Published var count: Double { didSet { save("count", count) } }
    @Published var ripple: Double { didSet { save("ripple", ripple) } }
    @Published var scale: Double { didSet { save("scale", scale) } }
    @Published var speed: Double { didSet { save("speed", speed) } }
    @Published var gain: Double { didSet { save("gain", gain) } }
    @Published var floor: Double { didSet { save("floor", floor) } }
    @Published var stiffness: Double { didSet { save("stiffness", stiffness) } }
    @Published var damping: Double { didSet { save("damping", damping) } }
    @Published var size: Double { didSet { save("size", size) } }
    @Published var variation: Double { didSet { save("variation", variation) } }
    @Published var blur: Double { didSet { save("blur", blur) } }
    @Published var fill: Double { didSet { save("fill", fill) } }
    @Published var glow: Double { didSet { save("glow", glow) } }

    /// Drives the orb with synthetic audio so the look can be dialed in
    /// without holding down the record button. Not persisted.
    @Published var simulate = false

    private init() {
        func load(_ name: String) -> Double {
            let param = Self.params[name]!
            let stored = UserDefaults.standard.object(forKey: param.key) as? Double
            return stored ?? param.def
        }
        count = load("count")
        ripple = load("ripple")
        scale = load("scale")
        speed = load("speed")
        gain = load("gain")
        floor = load("floor")
        stiffness = load("stiffness")
        damping = load("damping")
        size = load("size")
        variation = load("variation")
        blur = load("blur")
        fill = load("fill")
        glow = load("glow")
    }

    private func save(_ name: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: Self.params[name]!.key)
    }

    func reset() {
        count = Self.params["count"]!.def
        ripple = Self.params["ripple"]!.def
        scale = Self.params["scale"]!.def
        speed = Self.params["speed"]!.def
        gain = Self.params["gain"]!.def
        floor = Self.params["floor"]!.def
        stiffness = Self.params["stiffness"]!.def
        damping = Self.params["damping"]!.def
        size = Self.params["size"]!.def
        variation = Self.params["variation"]!.def
        blur = Self.params["blur"]!.def
        fill = Self.params["fill"]!.def
        glow = Self.params["glow"]!.def
    }

    /// Snapshot of the current values, ready to paste back to be committed
    /// as the new defaults.
    var snapshot: String {
        """
        OrbSettings values:
        count: \(fmt(count))
        ripple: \(fmt(ripple))
        scale: \(fmt(scale))
        speed: \(fmt(speed))
        gain: \(fmt(gain))
        floor: \(fmt(floor))
        stiffness: \(fmt(stiffness))
        damping: \(fmt(damping))
        size: \(fmt(size))
        variation: \(fmt(variation))
        blur: \(fmt(blur))
        fill: \(fmt(fill))
        glow: \(fmt(glow))
        """
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
}
