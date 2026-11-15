import SwiftUI
import SpriteKit

@main
struct TaikoPersonalApp: App {
    init() {
        SoundFX.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct PlayRequest: Identifiable {
    let id = UUID()
    let song: Song
    let course: Course
}

// MARK: - Song list

struct RootView: View {
    @StateObject private var lib = Library()
    @State private var picked: Song?
    @State private var play: PlayRequest?
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var search = ""

    private var filtered: [Song] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return lib.songs }
        return lib.songs.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if lib.songs.isEmpty {
                    VStack(spacing: 14) {
                        if lib.loading {
                            ProgressView()
                            Text("곡 찾는 중…")
                        } else {
                            Text("곡이 없어요")
                                .font(.title2.bold())
                            Text("파일 앱 → 이 기기 → '태고' 폴더에\n곡 폴더(.tja + 음원)를 넣거나\n오른쪽 위 + 버튼으로 폴더를 가져오세요.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { song in
                        Button { picked = song } label: { SongRow(song: song) }
                    }
                }
            }
            .navigationTitle("태고")
            .searchable(text: $search)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { lib.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        }
        .onAppear { lib.reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: true) { res in
            if case .success(let urls) = res { lib.importFolders(urls) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog(
            picked?.title ?? "",
            isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(Array((picked?.courses ?? []).enumerated()), id: \.offset) { _, c in
                Button("\(c.name)  ★\(c.level)") {
                    if let s = picked { play = PlayRequest(song: s, course: c) }
                }
            }
        }
        .fullScreenCover(item: $play) { req in
            GameView(req: req) { play = nil }
        }
    }
}

struct SongRow: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(song.title).font(.headline)
            if !song.subtitle.isEmpty {
                Text(song.subtitle).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(Array(song.courses.enumerated()), id: \.offset) { _, c in
                    Text("\(c.name) ★\(c.level)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let note = song.audioNote {
                    Text(note).font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("speed") private var speed = 1.0
    @AppStorage("offsetMs") private var offsetMs = 0.0
    @AppStorage("seVol") private var seVol = 0.8
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("노트 속도") {
                    Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "x%.2f", speed))
                }
                Section("화면/판정 보정 (ms)") {
                    Slider(value: $offsetMs, in: -200...200, step: 5)
                    Text("\(Int(offsetMs)) ms")
                    Text("소리가 화면보다 늦게 들리면 +, 빠르면 − 로 맞추세요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("효과음 볼륨") {
                    Slider(value: $seVol, in: 0...1)
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Game container

struct GameView: View {
    let req: PlayRequest
    let onClose: () -> Void
    @State private var result: ResultStats?

    var body: some View {
        ZStack {
            GameSceneView(req: req, onFinish: { result = $0 }, onQuit: onClose)
                .ignoresSafeArea()
            if let r = result {
                ResultOverlay(stats: r, title: req.song.title, onClose: onClose)
            }
        }
        .background(Color.black)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

struct GameSceneView: UIViewRepresentable {
    let req: PlayRequest
    var onFinish: (ResultStats) -> Void
    var onQuit: () -> Void

    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.isMultipleTouchEnabled = true
        v.ignoresSiblingOrder = true
        v.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        scene.song = req.song
        scene.course = req.course
        scene.onFinish = onFinish
        scene.onQuit = onQuit
        v.presentScene(scene)
        return v
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}

struct ResultOverlay: View {
    let stats: ResultStats
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(title).font(.title3.bold())
                Text(stats.cleared ? "클리어!" : "실패…")
                    .font(.largeTitle.bold())
                    .foregroundColor(stats.cleared ? .yellow : .gray)
                Text("점수 \(stats.score)").font(.title2)
                HStack(spacing: 24) {
                    Text("良 \(stats.good)")
                    Text("可 \(stats.ok)")
                    Text("不可 \(stats.miss)")
                }
                Text("최대 콤보 \(stats.maxCombo)  /  연타 \(stats.rollHits)")
                    .foregroundColor(.secondary)
                Button("확인", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
            .foregroundColor(.white)
        }
    }
}
