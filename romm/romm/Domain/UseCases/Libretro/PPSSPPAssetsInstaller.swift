import Foundation

/// Legt die Laufzeit-Assets des PPSSPP-Cores unterhalb des libretro-System-
/// Verzeichnisses ab.
///
/// Anders als BIOS-Dateien sind diese Assets Open Source und Teil des Cores,
/// deshalb liegen sie im App-Bundle statt auf dem RomM-Server. Der Core sucht
/// sie ausschließlich unter `<systemDir>/PPSSPP/` — der Ordnername steht so
/// (Großschreibung inklusive) in `libretro/libretro.cpp`:
///
/// ```
/// retro_base_dir /= "PPSSPP";
/// ...
/// g_VFS.Register("", new DirectoryReader(retro_base_dir));
/// ```
///
/// Fehlen die Dateien, stürzt nichts ab: der Core zeigt „Core system files
/// missing, expect bugs.“ und arbeitet degradiert weiter (keine PPGe-Dialoge,
/// keine Systemschriften, keine Compat-Hacks). Genau das soll dieser Installer
/// verhindern.
enum PPSSPPAssetsInstaller {

    /// Ordner im App-Bundle, in dem die Assets als Folder Reference liegen.
    static let bundleFolderName = "PPSSPPAssets"

    /// Vom Core erwarteter Unterordner unterhalb des System-Verzeichnisses.
    /// Case-sensitive, siehe Doc-Kommentar oben.
    static let systemSubdirectoryName = "PPSSPP"

    /// Kopiert die gebündelten Assets nach `<systemDir>/PPSSPP/`, sofern dort
    /// noch etwas fehlt. Ein vollständiges Zielverzeichnis wird nicht angefasst,
    /// damit nicht bei jedem Spielstart 12 MB neu geschrieben werden.
    ///
    /// Best effort: schlägt das Kopieren fehl, startet der Core trotzdem — nur
    /// eben mit den oben beschriebenen Einbußen.
    @discardableResult
    static func installIfNeeded(
        into systemDir: URL,
        fileSystem: PFileSystemService = DefaultFileSystemService()
    ) -> Bool {
        guard let sourceDir = bundledAssetsDirectory(fileSystem: fileSystem) else {
            print("[PPSSPP] assets missing from app bundle (\(bundleFolderName))")
            return false
        }

        let targetDir = systemDir.appendingPathComponent(
            systemSubdirectoryName,
            isDirectory: true
        )

        let relativePaths = self.relativePaths(in: sourceDir)
        guard !relativePaths.isEmpty else {
            print("[PPSSPP] assets folder in app bundle is empty")
            return false
        }

        let missing = relativePaths.filter {
            !fileSystem.fileExists(at: targetDir.appendingPathComponent($0))
        }
        if missing.isEmpty { return true }

        do {
            for relativePath in missing {
                let target = targetDir.appendingPathComponent(relativePath)
                try fileSystem.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try Data(contentsOf: sourceDir.appendingPathComponent(relativePath))
                try fileSystem.write(data, to: target)
            }
            print("[PPSSPP] installed \(missing.count) asset file(s) into \(targetDir.path)")
            return true
        } catch {
            print("[PPSSPP] asset install failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Die Assets liegen als Folder Reference direkt im Bundle-Root. Der
    /// `Bundle`-Lookup ist der übliche Weg, der Pfad-Fallback deckt den Fall ab,
    /// dass die Ressource nicht im Resource-Index landet.
    private static func bundledAssetsDirectory(fileSystem: PFileSystemService) -> URL? {
        if let url = Bundle.main.url(forResource: bundleFolderName, withExtension: nil) {
            return url
        }
        let fallback = Bundle.main.bundleURL.appendingPathComponent(
            bundleFolderName,
            isDirectory: true
        )
        return fileSystem.fileExists(at: fallback) ? fallback : nil
    }

    /// Alle Dateien unterhalb von `directory`, als Pfade relativ dazu.
    private static func relativePaths(in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = directory.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            result.append(String(path.dropFirst(prefix.count)))
        }
        return result
    }
}
