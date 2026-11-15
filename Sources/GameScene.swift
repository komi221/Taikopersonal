import SpriteKit
import AVFoundation
import UIKit

final class GameScene: SKScene {
    // inputs (set before presenting)
    var song: Song!
    var course: Course!
    var onFinish: ((ResultStats) -> Void)?
    var onQuit: (() -> Void)?

    // state
    private var built = false
    private var started = false
    private var finished = false
    private var chart = Chart()
    private var player: AVAudioPlayer?
    private var startSys = 0.0       // systemUptime at which audio time == 0
    private var latency = 0.0

    // layout
    private var s: CGFloat = 1
    private var judgeX: CGFloat = 0
    private var laneY: CGFloat = 0
    private var laneH: CGFloat = 0
    private var ppb: CGFloat = 0     // pixels per beat at scroll 1

    // scoring
    private var stats = ResultStats()
    private var combo = 0
    private var gauge = 0.0
    private var scoreF = 0.0
    private var baseScore = 0.0
    private var gainGood = 0.0

    // pointers / nodes
    private var visStart = 0
    private var missPtr = 0
    private var barStart = 0
    private var noteNodes: [Int: SKNode] = [:]
    private var barNodes: [Int: SKSpriteNode] = [:]
    private var textures: [String: SKTexture] = [:]
    private var zoneNodes: [SKSpriteNode] = []
    private var gogoGlow = SKSpriteNode()
    private var flash = SKShapeNode()
    private var comboLabel = SKLabelNode()
    private var judgeLabel = SKLabelNode()
    private var scoreLabel = SKLabelNode()
    private var gaugeFill = SKSpriteNode()

    // judgement windows (seconds)
    private let goodWin = 0.042
    private let okWin = 0.108
    private let badWin = 0.125

    deinit { player?.stop() }

    // MARK: lifecycle

    override func didMove(to view: SKView) { buildIfNeeded() }
    override func didChangeSize(_ oldSize: CGSize) { buildIfNeeded() }

    private func buildIfNeeded() {
        guard !built, song != nil, size.width > 200, size.height > 100 else { return }
        built = true
        setup()
        start()
    }

    // MARK: setup

    private func setup() {
        s = size.height / 390
        judgeX = size.width * 0.2
        laneH = 120 * s
        laneY = size.height * 0.68
        let speed = CGFloat(UserDefaults.standard.object(forKey: "speed") as? Double ?? 1.0)
        ppb = (size.width - judgeX) / 3.4 * speed
        backgroundColor = SKColor(red: 0.13, green: 0.12, blue: 0.15, alpha: 1)

        chart = ChartBuilder.build(song: song, course: course)
        let total = max(chart.total, 1)
        baseScore = 1_000_000.0 / Double(total)
        gainGood = 100.0 / Double(total)

        makeTextures()

        // lane
        let lane = SKSpriteNode(color: SKColor(white: 0.07, alpha: 1), size: CGSize(width: size.width, height: laneH))
        lane.anchorPoint = CGPoint(x: 0, y: 0.5)
        lane.position = CGPoint(x: 0, y: laneY)
        lane.zPosition = 0
        addChild(lane)

        gogoGlow = SKSpriteNode(color: SKColor(red: 1, green: 0.3, blue: 0.1, alpha: 0.28), size: lane.size)
        gogoGlow.anchorPoint = CGPoint(x: 0, y: 0.5)
        gogoGlow.position = lane.position
        gogoGlow.zPosition = 0.5
        gogoGlow.isHidden = true
        addChild(gogoGlow)

        // left panel (notes slide under it)
        let panelW = judgeX - 52 * s
        let panel = SKSpriteNode(color: SKColor(red: 0.55, green: 0.12, blue: 0.1, alpha: 1), size: CGSize(width: panelW, height: laneH))
        panel.anchorPoint = CGPoint(x: 0, y: 0.5)
        panel.position = CGPoint(x: 0, y: laneY)
        panel.zPosition = 3
        addChild(panel)

        comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        comboLabel.fontSize = 38 * s
        comboLabel.fontColor = .white
        comboLabel.position = CGPoint(x: panelW / 2, y: laneY - 14 * s)
        comboLabel.zPosition = 4
        addChild(comboLabel)

        // judge ring + hit flash
        let ring = SKShapeNode(circleOfRadius: 31 * s)
        ring.strokeColor = SKColor(white: 1, alpha: 0.85)
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.position = CGPoint(x: judgeX, y: laneY)
        ring.zPosition = 1
        addChild(ring)

        flash = SKShapeNode(circleOfRadius: 36 * s)
        flash.fillColor = SKColor(red: 1, green: 0.9, blue: 0.4, alpha: 0.7)
        flash.strokeColor = .clear
        flash.position = ring.position
        flash.zPosition = 1.5
        flash.alpha = 0
        addChild(flash)

        judgeLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        judgeLabel.fontSize = 24 * s
        judgeLabel.position = CGPoint(x: judgeX, y: laneY + laneH / 2 + 12 * s)
        judgeLabel.zPosition = 4
        judgeLabel.alpha = 0
        addChild(judgeLabel)

        // drum zones: ka | don | don | ka
        let zoneH = laneY - laneH / 2 - 10 * s
        let zw = size.width / 4
        for i in 0..<4 {
            let isDon = (i == 1 || i == 2)
            let color = isDon
                ? SKColor(red: 0.9, green: 0.25, blue: 0.2, alpha: 1)
                : SKColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 1)
            let z = SKSpriteNode(color: color, size: CGSize(width: zw - 6, height: zoneH))
            z.anchorPoint = CGPoint(x: 0, y: 0)
            z.position = CGPoint(x: CGFloat(i) * zw + 3, y: 0)
            z.alpha = 0.25
            z.zPosition = 0
            addChild(z)
            zoneNodes.append(z)

            let l = SKLabelNode(fontNamed: "AvenirNext-Bold")
            l.text = isDon ? "ドン" : "カッ"
            l.fontSize = 28 * s
            l.fontColor = SKColor(white: 1, alpha: 0.35)
            l.position = CGPoint(x: CGFloat(i) * zw + zw / 2, y: zoneH / 2 - 10 * s)
            l.zPosition = 0.2
            addChild(l)
        }

        // HUD
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        scoreLabel.fontSize = 26 * s
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: size.width - 24, y: size.height - 44 * s)
        scoreLabel.text = "0"
        addChild(scoreLabel)

        let quit = SKLabelNode(fontNamed: "AvenirNext-Bold")
        quit.text = "✕ 나가기"
        quit.fontSize = 16 * s
        quit.horizontalAlignmentMode = .left
        quit.position = CGPoint(x: 60, y: size.height - 40 * s)
        quit.fontColor = SKColor(white: 1, alpha: 0.7)
        addChild(quit)

        let gw = size.width * 0.3
        let gx = size.width * 0.38
        let gy = size.height - 38 * s
        let gbg = SKSpriteNode(color: SKColor(white: 0.25, alpha: 1), size: CGSize(width: gw, height: 14 * s))
        gbg.anchorPoint = CGPoint(x: 0, y: 0.5)
        gbg.position = CGPoint(x: gx, y: gy)
        addChild(gbg)
        gaugeFill = SKSpriteNode(color: SKColor(red: 1, green: 0.75, blue: 0.1, alpha: 1), size: CGSize(width: gw, height: 14 * s))
        gaugeFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        gaugeFill.position = CGPoint(x: gx, y: gy)
        gaugeFill.xScale = 0.001
        gaugeFill.zPosition = 1
        addChild(gaugeFill)
        let mark = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 22 * s))
        mark.position = CGPoint(x: gx + gw * 0.7, y: gy)
        mark.zPosition = 2
        addChild(mark)
    }

    private func circleTexture(r: CGFloat, fill: UIColor) -> SKTexture {
        let dim = r * 2 + 4
        let img = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim)).image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: dim, height: dim).insetBy(dx: 2, dy: 2)
            c.setFillColor(UIColor.black.cgColor)
            c.fillEllipse(in: rect)
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
            c.setFillColor(fill.cgColor)
            c.fillEllipse(in: rect.insetBy(dx: r * 0.22, dy: r * 0.22))
        }
        return SKTexture(image: img)
    }

    private func makeTextures() {
        let red = UIColor(red: 0.95, green: 0.25, blue: 0.15, alpha: 1)
        let blue = UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1)
        let yellow = UIColor(red: 1, green: 0.78, blue: 0.1, alpha: 1)
        let orange = UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
        textures["don"] = circleTexture(r: 26 * s, fill: red)
        textures["ka"] = circleTexture(r: 26 * s, fill: blue)
        textures["bigDon"] = circleTexture(r: 38 * s, fill: red)
        textures["bigKa"] = circleTexture(r: 38 * s, fill: blue)
        textures["roll"] = circleTexture(r: 26 * s, fill: yellow)
        textures["bigRoll"] = circleTexture(r: 38 * s, fill: yellow)
        textures["balloon"] = circleTexture(r: 30 * s, fill: orange)
    }

    // MARK: start / finish

    private func start() {
        let lead = max(2.0, 1.5 - chart.startTime)
        latency = AVAudioSession.sharedInstance().outputLatency
            + UserDefaults.standard.double(forKey: "offsetMs") / 1000
        startSys = ProcessInfo.processInfo.systemUptime + lead
        if let url = song.audio, let p = try? AVAudioPlayer(contentsOf: url) {
            p.prepareToPlay()
            player = p
            startSys = ProcessInfo.processInfo.systemUptime + lead
            p.play(atTime: p.deviceCurrentTime + lead)
        }
        started = true
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        player?.stop()
        stats.score = Int(scoreF.rounded())
        stats.gauge = gauge
        onFinish?(stats)
    }

    private func quit() {
        guard !finished else { return }
        finished = true
        player?.stop()
        onQuit?()
    }

    private func songTime(_ sys: Double) -> Double {
        sys - startSys - latency
    }

    // MARK: input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard built else { return }
        for touch in touches {
            let p = touch.location(in: self)
            if p.x < 160 && p.y > size.height - 70 * s {
                quit()
                return
            }
            guard started, !finished else { continue }
            if p.y > laneY - laneH / 2 { continue }
            let z = min(3, max(0, Int(p.x / (size.width / 4))))
            flashZone(z)
            let isDon = (z == 1 || z == 2)
            handle(isDon: isDon, at: songTime(touch.timestamp))
        }
    }

    private func flashZone(_ z: Int) {
        guard z < zoneNodes.count else { return }
        let n = zoneNodes[z]
        n.removeAllActions()
        n.alpha = 0.75
        n.run(SKAction.fadeAlpha(to: 0.25, duration: 0.12))
    }

    private func handle(isDon: Bool, at t: Double) {
        SoundFX.shared.play(don: isDon)

        var i = missPtr
        while i < chart.notes.count {
            let n = chart.notes[i]
            if n.time - t > badWin { break }
            if n.done { i += 1; continue }

            if n.isHold {
                if t >= n.time && t <= n.endTime {
                    holdHit(n)
                    return
                }
                if t < n.time { break }
                i += 1
                continue
            }

            let match = (isDon && n.isDon) || (!isDon && n.isKa)
            if match { judgeHit(n, dt: abs(t - n.time)) }
            return
        }
    }

    // MARK: judgement

    private func judgeHit(_ n: Note, dt: Double) {
        n.done = true
        removeNode(for: n)
        let j: Judge = dt <= goodWin ? .good : (dt <= okWin ? .ok : .miss)
        apply(j)
        if j != .miss { flashHit(big: n.isBig) }
    }

    private func holdHit(_ n: Note) {
        n.hits += 1
        if n.isBalloon {
            scoreF += 300
            if n.hits >= max(n.needHits, 1) {
                n.done = true
                scoreF += 5000
                removeNode(for: n)
                flashHit(big: true)
            } else if let node = noteNodes[n.index] {
                if let lbl = node.childNode(withName: "cnt") as? SKLabelNode {
                    lbl.text = "\(n.needHits - n.hits)"
                }
                node.removeAllActions()
                node.run(SKAction.sequence([
                    SKAction.scale(to: 1.15, duration: 0.03),
                    SKAction.scale(to: 1.0, duration: 0.06)
                ]))
            }
        } else {
            stats.rollHits += 1
            scoreF += (n.kind == .bigRoll ? 200 : 100)
            flashHit(big: false)
        }
        scoreLabel.text = "\(Int(scoreF))"
    }

    private func apply(_ j: Judge) {
        switch j {
        case .good:
            stats.good += 1
            combo += 1
            scoreF += baseScore
            gauge = min(100, gauge + gainGood)
            judgeLabel.text = "良"
            judgeLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        case .ok:
            stats.ok += 1
            combo += 1
            scoreF += baseScore * 0.5
            gauge = min(100, gauge + gainGood * 0.5)
            judgeLabel.text = "可"
            judgeLabel.fontColor = .white
        case .miss:
            stats.miss += 1
            combo = 0
            gauge = max(0, gauge - gainGood * 1.2)
            judgeLabel.text = "不可"
            judgeLabel.fontColor = SKColor(red: 0.45, green: 0.65, blue: 1, alpha: 1)
        }
        stats.maxCombo = max(stats.maxCombo, combo)
        judgeLabel.removeAllActions()
        judgeLabel.alpha = 1
        judgeLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.25),
            SKAction.fadeOut(withDuration: 0.2)
        ]))
        comboLabel.text = combo >= 2 ? "\(combo)" : ""
        gaugeFill.xScale = max(0.001, CGFloat(gauge / 100))
        scoreLabel.text = "\(Int(scoreF))"
    }

    private func flashHit(big: Bool) {
        flash.removeAllActions()
        flash.setScale(big ? 1.3 : 1.0)
        flash.alpha = 1
        flash.run(SKAction.fadeOut(withDuration: 0.15))
    }

    private func advanceMisses(_ t: Double) {
        while missPtr < chart.notes.count {
            let n = chart.notes[missPtr]
            if n.done { missPtr += 1; continue }
            if n.isHold {
                if t > n.endTime {
                    n.done = true
                    missPtr += 1
                    continue
                }
                break
            }
            if t - n.time > badWin {
                n.done = true
                apply(.miss)
                missPtr += 1
                continue
            }
            break
        }
    }

    // MARK: rendering

    override func update(_ currentTime: TimeInterval) {
        guard built, started, !finished else { return }
        let t = songTime(ProcessInfo.processInfo.systemUptime)
        advanceMisses(t)
        updateNodes(t)

        var inGogo = false
        for g in chart.gogo where t >= g.0 && t <= g.1 { inGogo = true; break }
        gogoGlow.isHidden = !inGogo

        if t > chart.endTime + 2.5 { finish() }
    }

    private func updateNodes(_ t: Double) {
        let dNow = chart.dist(at: t)
        func xFor(_ d: Double) -> CGFloat { judgeX + CGFloat(d - dNow) * ppb }

        // bar lines
        var b = barStart
        while b < chart.bars.count {
            let x = xFor(chart.bars[b].dist)
            if x < -20 {
                barNodes[b]?.removeFromParent()
                barNodes[b] = nil
                if b == barStart { barStart += 1 }
                b += 1
                continue
            }
            if x > size.width + 20 { break }
            let node: SKSpriteNode
            if let existing = barNodes[b] {
                node = existing
            } else {
                node = SKSpriteNode(color: SKColor(white: 0.85, alpha: 0.7), size: CGSize(width: 2, height: laneH))
                node.zPosition = 1
                addChild(node)
                barNodes[b] = node
            }
            node.position = CGPoint(x: x, y: laneY)
            b += 1
        }

        // notes
        var i = visStart
        while i < chart.notes.count {
            let n = chart.notes[i]
            let headX = xFor(n.dist)
            let tailX = (n.isHold && !n.isBalloon) ? xFor(n.endDist) : headX

            if n.done {
                removeNode(for: n)
                if i == visStart { visStart += 1 }
                i += 1
                continue
            }
            if tailX < -80 * s {
                removeNode(for: n)
                if i == visStart { visStart += 1 }
                i += 1
                continue
            }
            if headX > size.width + 80 * s { break }

            let node = noteNodes[i] ?? makeNode(for: n, index: i)
            node.position = CGPoint(x: headX, y: laneY)
            if n.isHold && !n.isBalloon,
               let body = node.childNode(withName: "body") as? SKSpriteNode,
               let tail = node.childNode(withName: "tail") {
                let len = max(tailX - headX, 1)
                body.size = CGSize(width: len, height: body.size.height)
                tail.position = CGPoint(x: len, y: 0)
            }
            i += 1
        }
    }

    private func sprite(_ key: String, _ r: CGFloat) -> SKSpriteNode {
        SKSpriteNode(texture: textures[key], size: CGSize(width: r * 2 + 4, height: r * 2 + 4))
    }

    private func makeNode(for n: Note, index: Int) -> SKNode {
        let c = SKNode()
        c.zPosition = 2
        switch n.kind {
        case .don: c.addChild(sprite("don", 26 * s))
        case .ka: c.addChild(sprite("ka", 26 * s))
        case .bigDon: c.addChild(sprite("bigDon", 38 * s))
        case .bigKa: c.addChild(sprite("bigKa", 38 * s))
        case .roll, .bigRoll:
            let big = n.kind == .bigRoll
            let r: CGFloat = (big ? 38 : 26) * s
            let key = big ? "bigRoll" : "roll"
            let body = SKSpriteNode(color: SKColor(red: 1, green: 0.78, blue: 0.1, alpha: 1),
                                    size: CGSize(width: 1, height: r * 2))
            body.anchorPoint = CGPoint(x: 0, y: 0.5)
            body.name = "body"
            body.zPosition = 0
            c.addChild(body)
            let tail = sprite(key, r)
            tail.name = "tail"
            tail.zPosition = 0.5
            c.addChild(tail)
            let head = sprite(key, r)
            head.zPosition = 1
            c.addChild(head)
        case .balloon, .kusudama:
            c.addChild(sprite("balloon", 30 * s))
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.name = "cnt"
            l.text = "\(n.needHits)"
            l.fontSize = 20 * s
            l.fontColor = .white
            l.verticalAlignmentMode = .center
            l.zPosition = 1
            c.addChild(l)
        }
        addChild(c)
        noteNodes[index] = c
        return c
    }

    private func removeNode(for n: Note) {
        if let node = noteNodes[n.index] {
            node.removeFromParent()
            noteNodes[n.index] = nil
        }
    }
}
