import Foundation

enum NoteKind { case don, ka, bigDon, bigKa, roll, bigRoll, balloon, kusudama }

enum Judge { case good, ok, miss }

final class Note {
    let kind: NoteKind
    let time: Double          // seconds, audio-relative
    let dist: Double          // scroll distance (beats * scroll)
    var endTime: Double
    var endDist: Double
    var needHits: Int
    var hits = 0
    var done = false
    var index = 0

    init(kind: NoteKind, time: Double, dist: Double, needHits: Int = 0) {
        self.kind = kind
        self.time = time
        self.dist = dist
        self.endTime = time
        self.endDist = dist
        self.needHits = needHits
    }

    var isDon: Bool { kind == .don || kind == .bigDon }
    var isKa: Bool { kind == .ka || kind == .bigKa }
    var isBig: Bool { kind == .bigDon || kind == .bigKa }
    var isBalloon: Bool { kind == .balloon || kind == .kusudama }
    var isHold: Bool {
        switch kind {
        case .roll, .bigRoll, .balloon, .kusudama: return true
        default: return false
        }
    }
}

struct BarLine {
    let time: Double
    let dist: Double
}

struct Segment {
    let t: Double
    let d: Double
    let rate: Double   // dist per second
}

final class Chart {
    var notes: [Note] = []
    var bars: [BarLine] = []
    var segs: [Segment] = []
    var gogo: [(Double, Double)] = []
    var total = 0
    var startTime = 0.0
    var endTime = 0.0

    /// Scroll distance at audio time t (piecewise linear, handles BPM/SCROLL/DELAY).
    func dist(at t: Double) -> Double {
        guard !segs.isEmpty else { return 0 }
        if t < segs[0].t { return segs[0].d + (t - segs[0].t) * segs[0].rate }
        var lo = 0
        var hi = segs.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segs[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        let s = segs[lo]
        return s.d + (t - s.t) * s.rate
    }
}

struct Course {
    let name: String
    let order: Int
    let level: Int
    let balloons: [Int]
    let body: [String]
}

struct Song: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let dir: URL
    let audio: URL?
    let audioNote: String?
    let bpm: Double
    let offset: Double
    let courses: [Course]
}

struct ResultStats {
    var good = 0
    var ok = 0
    var miss = 0
    var maxCombo = 0
    var rollHits = 0
    var score = 0
    var gauge = 0.0
    var cleared: Bool { gauge >= 70 }
}
