import Foundation

final class Library: ObservableObject {
    @Published var songs: [Song] = []
    @Published var loading = false

    static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func reload() {
        loading = true
        let root = Library.docs
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Library.scan(root: root)
            DispatchQueue.main.async {
                self.songs = found
                self.loading = false
            }
        }
    }

    static func scan(root: URL) -> [Song] {
        var found: [Song] = []
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        while let url = en.nextObject() as? URL {
            if url.pathExtension.lowercased() == "tja", let s = TJAParser.parse(url: url) {
                found.append(s)
            }
        }
        found.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        return found
    }

    /// Copies chosen folders (each holding a .tja + audio) into Documents/Songs.
    func importFolders(_ urls: [URL]) {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let dest = Library.docs.appendingPathComponent("Songs", isDirectory: true)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for url in urls {
                let ok = url.startAccessingSecurityScopedResource()
                let target = dest.appendingPathComponent(url.lastPathComponent, isDirectory: true)
                try? fm.removeItem(at: target)
                try? fm.copyItem(at: url, to: target)
                if ok { url.stopAccessingSecurityScopedResource() }
            }
            let found = Library.scan(root: Library.docs)
            DispatchQueue.main.async {
                self.songs = found
                self.loading = false
            }
        }
    }
}
