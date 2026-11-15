import Foundation

// MARK: - TJA file parsing

enum TJAParser {
    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        return String(data: data, encoding: .shiftJIS)
    }

    static func courseInfo(_ raw: String) -> (String, Int) {
        switch raw.lowercased() {
        case "0", "easy": return ("Easy", 0)
        case "1", "normal": return ("Normal", 1)
        case "2", "hard": return ("Hard", 2)
        case "3", "oni": return ("Oni", 3)
        case "4", "edit", "ura": return ("Ura", 4)
        default: return (raw, 3)
        }
    }

    static func parse(url: URL) -> Song? {
        guard let text = readText(url) else { return nil }

        var global: [String: String] = [:]
        var cur: [String: String] = [:]
        var seenCourse = false
        var courses: [Course] = []
        var body: [String] = []
        var inChart = false
        var skipChart = false

        func val(_ k: String) -> String? { cur[k] ?? global[k] }

        for raw in text.components(separatedBy: .newlines) {
            var line = raw
            if let r = line.range(of: "//") { line = String(line[..<r.lowerBound]) }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let up = line.uppercased()

            if up.hasPrefix("#START") {
                inChart = true
                body = []
                skipChart = up.contains("P2")
                continue
            }
            if up == "#END" || up.hasPrefix("#END ") {
                if inChart && !skipChart {
                    let (name, order) = courseInfo(val("COURSE") ?? "Oni")
                    let level = Int((val("LEVEL") ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
                    let balloons = (val("BALLOON") ?? "")
                        .split(whereSeparator: { $0 == "," || $0 == " " })
                        .compactMap { Int($0) }
                    courses.append(Course(name: name, order: order, level: level, balloons: balloons, body: body))
                }
                inChart = false
                continue
            }
            if inChart {
                if !skipChart { body.append(line) }
                continue
            }

            if let c = line.firstIndex(of: ":") {
                let key = line[..<c].trimmingCharacters(in: .whitespaces).uppercased()
                let value = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if key == "COURSE" {
                    cur = ["COURSE": value]
                    seenCourse = true
                } else if seenCourse {
                    cur[key] = value
                } else {
                    global[key] = value
                }
            }
        }

        guard !courses.isEmpty else { return nil }
        courses.sort { $0.order < $1.order }

        let dir = url.deletingLastPathComponent()
        var sub = global["SUBTITLE"] ?? ""
        if sub.hasPrefix("--") || sub.hasPrefix("++") { sub = String(sub.dropFirst(2)) }
        let (audio, note) = resolveAudio(dir: dir, wave: global["WAVE"])

        return Song(
            id: url.path,
            title: global["TITLE"] ?? url.deletingPathExtension().lastPathComponent,
            subtitle: sub,
            dir: dir,
            audio: audio,
            audioNote: note,
            bpm: Double(global["BPM"] ?? "") ?? 120,
            offset: Double(global["OFFSET"] ?? "") ?? 0,
            courses: courses
        )
    }

    /// AVAudioPlayer cannot decode OGG, so look for a playable sibling file.
    static func resolveAudio(dir: URL, wave: String?) -> (URL?, String?) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let supported = ["mp3", "m4a", "wav", "aac", "caf", "aif", "aiff", "flac"]

        func find(_ n: String) -> URL? {
            names.first { $0.lowercased() == n.lowercased() }.map { dir.appendingPathComponent($0) }
        }

        if let w = wave, !w.isEmpty {
            let ext = (w as NSString).pathExtension.lowercased()
            if supported.contains(ext), let u = find(w) { return (u, nil) }
            let base = (w as NSString).deletingPathExtension
            for e in supported {
                if let u = find(base + "." + e) { return (u, nil) }
            }
        }
        if let n = names.first(where: { supported.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return (dir.appendingPathComponent(n), nil)
        }
        if names.contains(where: { ($0 as NSString).pathExtension.lowercased() == "ogg" }) {
            return (nil, "OGG → MP3/M4A 변환 필요")
        }
        return (nil, "음원 파일 없음")
    }
}

// MARK: - Chart building (timing, scroll, gogo, balloons, rolls)

enum ChartBuilder {
    private enum Tok {
        case note(Character)
        case bpm(Double)
        case scroll(Double)
        case measure(Double, Double)
        case gogo(Bool)
        case delay(Double)
        case bar(Bool)
    }

    private static func kindFor(_ c: Character) -> NoteKind? {
        switch c {
        case "1": return .don
        case "2": return .ka
        case "3": return .bigDon
        case "4": return .bigKa
        case "5": return .roll
        case "6": return .bigRoll
        case "7": return .balloon
        case "9": return .kusudama
        default: return nil
        }
    }

    static func build(song: Song, course: Course) -> Chart {
        let chart = Chart()
        var bpm = max(song.bpm, 1)
        var scroll = 1.0
        var mN = 4.0
        var mM = 4.0
        var t = -song.offset
        var d = 0.0
        var barOn = true
        var gogoStart: Double? = nil
        var balloonIdx = 0
        var openHold: Note? = nil
        var toks: [Tok] = []
        var skipBranch = false
        var firstNoteTime: Double? = nil

        chart.startTime = t
        chart.segs.append(Segment(t: t, d: d, rate: bpm * scroll / 60))

        func rate() -> Double { bpm * scroll / 60 }

        func advance(_ dur: Double) {
            t += dur
            d += dur * rate()
        }

        func addNote(_ c: Character) {
            if c == "8" {
                if let r = openHold {
                    r.endTime = t
                    r.endDist = d
                    openHold = nil
                }
                return
            }
            guard let k = kindFor(c) else { return }
            var need = 0
            if k == .balloon || k == .kusudama {
                need = balloonIdx < course.balloons.count ? course.balloons[balloonIdx] : 5
                balloonIdx += 1
            }
            let n = Note(kind: k, time: t, dist: d, needHits: need)
            n.index = chart.notes.count
            chart.notes.append(n)
            if n.isHold {
                openHold = n
            } else {
                chart.total += 1
            }
            if firstNoteTime == nil { firstNoteTime = t }
        }

        func flush() {
            var count = 0
            for tk in toks { if case .note = tk { count += 1 } }
            for tk in toks {
                if case .measure(let a, let b) = tk { mN = a; mM = b }
                if case .bar(let v) = tk { barOn = v }
            }
            let beats = 4.0 * mN / max(mM, 1)
            if barOn { chart.bars.append(BarLine(time: t, dist: d)) }
            let slots = Double(max(count, 1))

            for tk in toks {
                switch tk {
                case .note(let c):
                    let dur = beats / slots * 60 / bpm
                    addNote(c)
                    advance(dur)
                case .bpm(let b):
                    bpm = max(b, 1)
                    chart.segs.append(Segment(t: t, d: d, rate: rate()))
                case .scroll(let sc):
                    scroll = sc
                    chart.segs.append(Segment(t: t, d: d, rate: rate()))
                case .gogo(let on):
                    if on {
                        if gogoStart == nil { gogoStart = t }
                    } else if let g = gogoStart {
                        chart.gogo.append((g, t))
                        gogoStart = nil
                    }
                case .delay(let sec):
                    if sec > 0 {
                        chart.segs.append(Segment(t: t, d: d, rate: 0))
                        t += sec
                        chart.segs.append(Segment(t: t, d: d, rate: rate()))
                    }
                case .measure, .bar:
                    break
                }
            }
            if count == 0 { advance(beats * 60 / bpm) }
            toks.removeAll()
        }

        let branchCmds: Set<String> = ["M", "N", "E", "BRANCHSTART", "BRANCHEND"]

        for line in course.body {
            if line.hasPrefix("#") {
                let parts = line.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let cmd = parts.first.map { String($0).uppercased() } ?? ""
                let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                switch cmd {
                case "N", "E": skipBranch = true; continue   // use the master (#M) branch only
                case "M", "BRANCHEND": skipBranch = false; continue
                default: break
                }
                if skipBranch && !branchCmds.contains(cmd) { continue }

                switch cmd {
                case "BPMCHANGE":
                    if let v = Double(arg) { toks.append(.bpm(v)) }
                case "SCROLL":
                    toks.append(.scroll(Double(arg) ?? 1))
                case "MEASURE":
                    let p = arg.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if p.count == 2 { toks.append(.measure(p[0], p[1])) }
                case "GOGOSTART":
                    toks.append(.gogo(true))
                case "GOGOEND":
                    toks.append(.gogo(false))
                case "DELAY":
                    if let v = Double(arg) { toks.append(.delay(v)) }
                case "BARLINEOFF":
                    toks.append(.bar(false))
                case "BARLINEON":
                    toks.append(.bar(true))
                default:
                    break
                }
                continue
            }
            if skipBranch { continue }
            for ch in line {
                if ch == "," {
                    flush()
                } else if ("0"..."9").contains(ch) {
                    toks.append(.note(ch))
                }
            }
        }
        if !toks.isEmpty { flush() }
        if let g = gogoStart { chart.gogo.append((g, t)); gogoStart = nil }

        var end = t
        for n in chart.notes { end = max(end, n.endTime) }
        chart.endTime = end
        if let f = firstNoteTime { chart.startTime = min(chart.startTime, f) }
        return chart
    }
}
