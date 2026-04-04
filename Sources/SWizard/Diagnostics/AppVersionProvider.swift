import Foundation

protocol AppVersionProviding {
    var displayVersion: String { get }
}

struct BundleAppVersionProvider: AppVersionProviding {
    private let infoDictionaryProvider: () -> [String: Any]?

    init(infoDictionaryProvider: @escaping () -> [String: Any]? = { Bundle.main.infoDictionary }) {
        self.infoDictionaryProvider = infoDictionaryProvider
    }

    var displayVersion: String {
        let info = infoDictionaryProvider()
        let shortVersion = sanitized(info?["CFBundleShortVersionString"] as? String)
        let buildVersion = sanitized(info?["CFBundleVersion"] as? String)

        switch (shortVersion, buildVersion) {
        case let (.some(short), .some(build)) where short == build:
            return short
        case let (.some(short), .some(build)):
            return "\(short) (\(build))"
        case let (.some(short), _ ):
            return short
        case let (_, .some(build)):
            return build
        default:
            return "dev"
        }
    }

    private func sanitized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct GitDescribeAppVersionProvider: AppVersionProviding {
    private let repoRootProvider: () -> URL?
    private let gitDescribeRunner: (URL) -> String?

    init(
        repoRootProvider: @escaping () -> URL? = GitDescribeAppVersionProvider.defaultRepoRoot,
        gitDescribeRunner: @escaping (URL) -> String? = GitDescribeAppVersionProvider.defaultGitDescribe
    ) {
        self.repoRootProvider = repoRootProvider
        self.gitDescribeRunner = gitDescribeRunner
    }

    var displayVersion: String {
        guard let repoRoot = repoRootProvider() else { return "dev" }
        guard let rawTag = gitDescribeRunner(repoRoot) else { return "dev" }
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? "dev" : tag
    }

    static func defaultRepoRoot() -> URL? {
        let candidates = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]

        for candidate in candidates {
            if let root = findRepoRoot(startingAt: candidate) {
                return root
            }
        }

        return nil
    }

    static func defaultGitDescribe(repoRoot: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot.path, "describe", "--tags", "--always", "--dirty"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func findRepoRoot(startingAt url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fm = FileManager.default

        while true {
            let gitPath = current.appendingPathComponent(".git").path
            if fm.fileExists(atPath: gitPath) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}

struct DefaultAppVersionProvider: AppVersionProviding {
    private let bundleProvider: any AppVersionProviding
    private let gitProvider: any AppVersionProviding

    init(
        bundleProvider: any AppVersionProviding = BundleAppVersionProvider(),
        gitProvider: any AppVersionProviding = GitDescribeAppVersionProvider()
    ) {
        self.bundleProvider = bundleProvider
        self.gitProvider = gitProvider
    }

    var displayVersion: String {
        let bundleVersion = bundleProvider.displayVersion
        if bundleVersion != "dev" {
            return bundleVersion
        }

        let gitVersion = gitProvider.displayVersion
        return gitVersion == "dev" ? "dev" : gitVersion
    }
}
