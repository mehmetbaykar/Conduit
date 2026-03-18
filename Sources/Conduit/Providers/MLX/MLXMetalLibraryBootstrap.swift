// MLXMetalLibraryBootstrap.swift
// Conduit

#if CONDUIT_TRAIT_MLX
#if canImport(MLX)

import Foundation

/// Bootstraps MLX Metal shaders when running from SwiftPM/test contexts.
///
/// `mlx-swift` documents that SwiftPM builds the Swift/C++ targets but does not
/// package the metal shader bundle that the runtime expects. In Xcode app builds
/// that bundle is normally available as a resource. When running tests or command
/// line tools directly from SwiftPM, we generate `mlx.metallib` next to the
/// running binary so MLX can discover it via its colocated-library lookup.
internal enum MLXMetalLibraryBootstrap {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hasEnsuredAvailability = false

    static func ensureAvailable() throws {
        #if os(macOS) && arch(arm64)
        lock.lock()
        defer { lock.unlock() }

        guard !hasEnsuredAvailability else { return }
        defer { hasEnsuredAvailability = true }

        let fileManager = FileManager.default
        guard let runtimeDirectory else { return }

        let runtimeMLX = runtimeDirectory.appendingPathComponent("mlx.metallib")
        let runtimeDefault = runtimeDirectory.appendingPathComponent("default.metallib")
        if fileManager.fileExists(atPath: runtimeMLX.path) || fileManager.fileExists(atPath: runtimeDefault.path) {
            return
        }

        guard let metalSourceDirectory else { return }

        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try buildMetallib(from: metalSourceDirectory, outputURL: runtimeDefault)

        if !fileManager.fileExists(atPath: runtimeMLX.path) {
            try? fileManager.copyItem(at: runtimeDefault, to: runtimeMLX)
        }
        #endif
    }

    #if os(macOS) && arch(arm64)
    private static var runtimeDirectory: URL? {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private static var metalSourceDirectory: URL? {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoots = [
            sourceFileURL
                .deletingLastPathComponent() // MLX
                .deletingLastPathComponent() // Providers
                .deletingLastPathComponent() // Conduit
                .deletingLastPathComponent() // Sources
        ] + ancestorDirectories(of: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        for root in candidateRoots {
            let candidate = root
                .appendingPathComponent(".build")
                .appendingPathComponent("checkouts")
                .appendingPathComponent("mlx-swift")
                .appendingPathComponent("Source")
                .appendingPathComponent("Cmlx")
                .appendingPathComponent("mlx-generated")
                .appendingPathComponent("metal")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func ancestorDirectories(of start: URL) -> [URL] {
        var directories: [URL] = []
        var current = start

        while true {
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        return directories
    }

    private static func buildMetallib(from sourceDirectory: URL, outputURL: URL) throws {
        let fileManager = FileManager.default
        let buildDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("conduit-mlx-metallib", isDirectory: true)
        try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let metalFiles = fileManager
            .enumerator(at: sourceDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "metal" }
            .sorted(by: { $0.path < $1.path }) ?? []

        guard !metalFiles.isEmpty else {
            throw NSError(
                domain: "Conduit.MLXMetalLibraryBootstrap",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No MLX metal shader sources were found at \(sourceDirectory.path)."]
            )
        }

        var airFiles: [URL] = []
        for metalFile in metalFiles {
            let relativePath = metalFile.path.replacingOccurrences(of: sourceDirectory.path + "/", with: "")
            let airFile = buildDirectory.appendingPathComponent(relativePath.replacingOccurrences(of: "/", with: "__"))
                .deletingPathExtension()
                .appendingPathExtension("air")
            try runTool(
                "/usr/bin/xcrun",
                arguments: [
                    "-sdk", "macosx",
                    "metal",
                    "-Wall",
                    "-Wextra",
                    "-fno-fast-math",
                    "-Wno-c++17-extensions",
                    "-c", metalFile.path,
                    "-I\(sourceDirectory.path)",
                    "-I\(sourceDirectory.appendingPathComponent("metal_3_1").path)",
                    "-I\(sourceDirectory.appendingPathComponent("metal_3_0").path)",
                    "-o", airFile.path
                ]
            )
            airFiles.append(airFile)
        }

        try runTool(
            "/usr/bin/xcrun",
            arguments: ["-sdk", "macosx", "metallib"] + airFiles.map(\.path) + ["-o", outputURL.path]
        )
    }

    private static func runTool(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let description = output?.isEmpty == false ? output! : "\(launchPath) failed with exit code \(process.terminationStatus)"
            throw NSError(
                domain: "Conduit.MLXMetalLibraryBootstrap",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }
    #endif
}

#endif // canImport(MLX)
#endif // CONDUIT_TRAIT_MLX
