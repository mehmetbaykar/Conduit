import Foundation
import XCTest
@testable import Conduit

#if canImport(MLX)

final class MLXProviderIntegrationTests: XCTestCase {

    func testGenerateUsingCachedQwenMLXModel() async throws {
        try requireCachedModel("mlx-community/Qwen3-0.6B-8bit")

        let provider = MLXProvider(configuration: .memoryEfficient)
        let available = await provider.isAvailable
        XCTAssertTrue(available, "MLXProvider should be available on Apple Silicon")

        let config = GenerateConfig.default
            .maxTokens(8)
            .temperature(0)
            .topP(1)

        let result = try await provider.generate(
            "Reply with exactly one short word: OK",
            model: .mlx("mlx-community/Qwen3-0.6B-8bit"),
            config: config
        )

        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func requireCachedModel(_ repoID: String) throws {
        let sanitized = repoID.replacingOccurrences(of: "/", with: "--")
        let possibleRoots = [
            NSString(string: "~/.cache/huggingface/hub/models--\(sanitized)/snapshots").expandingTildeInPath,
            NSString(string: "~/Library/Caches/Conduit/Models/mlx/\(sanitized)").expandingTildeInPath
        ]

        let fileManager = FileManager.default
        let hasCache = possibleRoots.contains { root in
            guard fileManager.fileExists(atPath: root) else { return false }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: root) else { return false }
            return !contents.isEmpty
        }

        if !hasCache {
            throw XCTSkip("Skipping MLX smoke test because cached model \(repoID) was not found locally.")
        }
    }
}

#endif
