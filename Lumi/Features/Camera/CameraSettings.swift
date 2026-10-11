import CoreGraphics
import Foundation

struct CameraSettings: Codable, Equatable {
    enum Flash: String, Codable, CaseIterable { case off, auto, on }
    enum Aspect: String, Codable, CaseIterable {
        case fourThree = "4:3", sixteenNine = "16:9", square = "1:1"
        var ratio: Double { switch self { case .fourThree: 3.0 / 4; case .sixteenNine: 9.0 / 16; case .square: 1 } }       // portrait w/h
    }
    enum Lens: String, Codable, CaseIterable { case front, back, ultraWide }

    var flash = Flash.off
    var timer = 0                       // seconds: 0, 3 or 10
    var aspect = Aspect.fourThree
    var lens = Lens.back
    var showGrid = false
    var mirrorFront = true
    var lookID: String?                 // live filter from the filter pack
    var beauty = 0.0                    // 0...1 scales the "Natural" auto-beauty look (T62)

    static let timers = [0, 3, 10]

    mutating func cycleTimer() { timer = Self.timers[((Self.timers.firstIndex(of: timer) ?? 0) + 1) % Self.timers.count] }
    mutating func cycleFlash() {
        let all = Flash.allCases
        flash = all[((all.firstIndex(of: flash) ?? 0) + 1) % all.count]
    }
    mutating func flip() { lens = lens == .front ? .back : .front }

    /// Flash is a back-camera feature; front uses screen flash, which the UI handles, so the hardware setting is off.
    var hardwareFlash: Flash { lens == .front ? .off : flash }

    /// Crop (in pixels, y-down) that turns a portrait sensor frame into the chosen aspect, centered.
    func cropRect(for frame: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        let target = aspect.ratio, have = Double(frame.width / frame.height)
        if have > target { let w = Double(frame.height) * target; return CGRect(x: (Double(frame.width) - w) / 2, y: 0, width: w, height: Double(frame.height)) }
        let h = Double(frame.width) / target
        return CGRect(x: 0, y: (Double(frame.height) - h) / 2, width: Double(frame.width), height: h)
    }
}

/// Countdown before a timed shot. Pure state so it is testable without a clock.
struct Countdown: Equatable {
    private(set) var remaining: Int
    private(set) var isRunning = false
    init(seconds: Int) { remaining = max(seconds, 0) }

    mutating func start() { isRunning = remaining > 0 }
    mutating func cancel() { isRunning = false }
    /// Advances one second. Returns true when it reaches zero (take the photo now).
    mutating func tick() -> Bool {
        guard isRunning else { return false }
        remaining -= 1
        if remaining <= 0 { isRunning = false; remaining = 0; return true }
        return false
    }
}
