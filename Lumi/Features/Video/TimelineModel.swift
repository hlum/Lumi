import Foundation

struct TimelineClip: Codable, Equatable, Identifiable {
    enum Source: Codable, Equatable { case video(String), photo(String) }

    var id = UUID()
    var source: Source
    /// For video: the trimmed range inside the source, in seconds. For photos: `sourceDuration` is the display time.
    var sourceStart = 0.0
    var sourceDuration: Double
    var speed = 1.0                    // 0.1...8
    var volume = 1.0                   // 0...1
    var isReversed = false
    /// Transition INTO this clip from the previous one (ignored for the first clip).
    var transition = TransitionKind.none
    var transitionDuration = Transitions.defaultDuration
    /// Per-clip look: color, filter, effects, drawn on every frame.
    var look = EditDocument()
    var layout = ClipOps.FrameLayout()

    static let minDuration = 0.1
    static let photoDefault = 3.0

    var isPhoto: Bool { if case .photo = source { true } else { false } }
    /// Length on the timeline.
    var duration: Double { sourceDuration / min(max(speed, 0.1), 8) }
}

/// A flat, ordered edit list. All edits are pure value changes, so undo is just snapshots of this struct.
struct Timeline: Codable, Equatable {
    private(set) var clips: [TimelineClip] = []

    /// Overlap with the previous clip caused by this clip's transition (0 for the first clip or no transition).
    func overlap(at i: Int) -> Double {
        guard i > 0, i < clips.count, clips[i].transition != .none else { return 0 }
        return Transitions.overlap(clipA: clips[i - 1].duration, clipB: clips[i].duration, requested: clips[i].transitionDuration)
    }

    /// Start of each clip on the timeline; transitions pull the next clip earlier by the overlap.
    var starts: [Double] {
        var out: [Double] = []; var cursor = 0.0
        for i in clips.indices { let s = max(cursor - overlap(at: i), 0); out.append(s); cursor = s + clips[i].duration }
        return out
    }

    var duration: Double { zip(starts, clips).map { $0 + $1.duration }.max() ?? 0 }
    var isEmpty: Bool { clips.isEmpty }

    enum EditError: Error, Equatable { case noSuchClip, outOfRange, tooShort }

    func index(of id: UUID) -> Int? { clips.firstIndex { $0.id == id } }
    func start(of id: UUID) -> Double? { index(of: id).map { starts[$0] } }

    /// Which clip is under timeline time `t`, and where inside that clip's own (timeline-length) span.
    func locate(_ t: Double) -> (index: Int, offset: Double)? {
        guard t >= 0, t < duration else { return nil }
        // during an overlap the incoming clip is the "current" one
        let st = starts
        for i in clips.indices.reversed() where t >= st[i] { return (i, t - st[i]) }
        return nil
    }

    mutating func append(_ clip: TimelineClip) { clips.append(clip) }

    mutating func insert(_ clip: TimelineClip, at index: Int) { clips.insert(clip, at: min(max(index, 0), clips.count)) }

    mutating func remove(_ id: UUID) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips.remove(at: i)
    }

    mutating func move(_ id: UUID, to newIndex: Int) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        let c = clips.remove(at: i)
        clips.insert(c, at: min(max(newIndex, 0), clips.count))
    }

    mutating func duplicate(_ id: UUID) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        var c = clips[i]; c.id = UUID()
        clips.insert(c, at: i + 1)
    }

    mutating func replace(_ id: UUID, with source: TimelineClip.Source, duration: Double) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        guard duration >= TimelineClip.minDuration else { throw EditError.tooShort }
        clips[i].source = source; clips[i].sourceStart = 0; clips[i].sourceDuration = duration; clips[i].isReversed = false
    }

    /// Trims the clip's source range. `start` and `duration` are in source seconds.
    mutating func trim(_ id: UUID, start: Double, duration: Double) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        guard start >= 0, duration > 0 else { throw EditError.outOfRange }
        guard duration >= TimelineClip.minDuration else { throw EditError.tooShort }
        clips[i].sourceStart = start; clips[i].sourceDuration = duration
    }

    /// Splits whichever clip is under timeline time `t` into two. Photos split their display time.
    @discardableResult
    mutating func split(at t: Double) throws -> (UUID, UUID) {
        guard let (i, offset) = locate(t) else { throw EditError.outOfRange }
        let c = clips[i]
        let srcCut = offset * min(max(c.speed, 0.1), 8)            // timeline offset -> source seconds
        guard srcCut >= TimelineClip.minDuration, c.sourceDuration - srcCut >= TimelineClip.minDuration else { throw EditError.tooShort }
        var first = c, second = c; second.id = UUID(); second.transition = .none     // the transition belongs to the first half
        if c.isReversed {          // a reversed clip plays its source tail first
            first.sourceStart = c.sourceStart + (c.sourceDuration - srcCut); first.sourceDuration = srcCut
            second.sourceDuration = c.sourceDuration - srcCut
        } else {
            first.sourceDuration = srcCut
            second.sourceStart = c.sourceStart + srcCut; second.sourceDuration = c.sourceDuration - srcCut
        }
        clips[i] = first; clips.insert(second, at: i + 1)
        return (first.id, second.id)
    }

    mutating func setSpeed(_ id: UUID, _ speed: Double) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips[i].speed = min(max(speed, 0.1), 8)
    }
    mutating func setVolume(_ id: UUID, _ volume: Double) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips[i].volume = min(max(volume, 0), 1)
    }
    mutating func setTransition(_ id: UUID, _ kind: TransitionKind, duration: Double = Transitions.defaultDuration) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips[i].transition = kind; clips[i].transitionDuration = min(max(duration, 0.1), 3)
    }
    mutating func setLook(_ id: UUID, _ look: EditDocument) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips[i].look = look
    }
    mutating func setReversed(_ id: UUID, _ r: Bool) throws {
        guard let i = index(of: id) else { throw EditError.noSuchClip }
        clips[i].isReversed = r
    }
}

/// A draft: the timeline plus export choices, saved like a photo project.
struct VideoDraft: Codable, Equatable {
    var timeline = Timeline()
    var export = VideoExportOptions()
}

struct VideoExportOptions: Codable, Equatable {
    enum Resolution: Int, Codable, CaseIterable { case p720 = 720, p1080 = 1080, p2160 = 2160 }
    var resolution = Resolution.p1080
    var fps = 30
    static let allowedFPS = [24, 25, 30, 60]

    var normalizedFPS: Int { Self.allowedFPS.contains(fps) ? fps : 30 }
    /// Output size for a source of `size`, long side matching the chosen resolution class, even dimensions, never upscaled.
    func outputSize(for size: CGSize) -> CGSize {
        let target = CGFloat(resolution.rawValue) * 16 / 9           // long side: 720p => 1280
        let long = max(size.width, size.height)
        guard long > 0 else { return .zero }
        let s = min(1, target / long)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v * s / 2).rounded() * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }
}
