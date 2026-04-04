import XCTest
@testable import SWizard

final class BundleAppVersionProviderTests: XCTestCase {

    func testDisplayVersionUsesShortAndBuildWhenBothAvailable() {
        let provider = BundleAppVersionProvider {
            [
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45"
            ]
        }

        XCTAssertEqual(provider.displayVersion, "1.2.3 (45)")
    }

    func testDisplayVersionUsesShortWhenBuildMissing() {
        let provider = BundleAppVersionProvider {
            ["CFBundleShortVersionString": "1.2.3"]
        }

        XCTAssertEqual(provider.displayVersion, "1.2.3")
    }

    func testDisplayVersionUsesBuildWhenShortMissing() {
        let provider = BundleAppVersionProvider {
            ["CFBundleVersion": "9001"]
        }

        XCTAssertEqual(provider.displayVersion, "9001")
    }

    func testDisplayVersionFallsBackToDevWhenMissing() {
        let provider = BundleAppVersionProvider { nil }

        XCTAssertEqual(provider.displayVersion, "dev")
    }

    func testDisplayVersionAvoidsDuplicateShortAndBuildValues() {
        let provider = BundleAppVersionProvider {
            [
                "CFBundleShortVersionString": "dev",
                "CFBundleVersion": "dev"
            ]
        }

        XCTAssertEqual(provider.displayVersion, "dev")
    }

    func testGitDescribeProviderUsesRunnerOutput() {
        let provider = GitDescribeAppVersionProvider(
            repoRootProvider: { URL(fileURLWithPath: "/tmp/repo") },
            gitDescribeRunner: { _ in "v0.1.0-alpha\n" }
        )

        XCTAssertEqual(provider.displayVersion, "v0.1.0-alpha")
    }

    func testGitDescribeProviderFallsBackToDevWhenNoRepo() {
        let provider = GitDescribeAppVersionProvider(
            repoRootProvider: { nil },
            gitDescribeRunner: { _ in "v0.1.0-alpha" }
        )

        XCTAssertEqual(provider.displayVersion, "dev")
    }

    func testDefaultProviderFallsBackToGitVersionWhenBundleIsDev() {
        let provider = DefaultAppVersionProvider(
            bundleProvider: StaticVersionProvider(displayVersion: "dev"),
            gitProvider: StaticVersionProvider(displayVersion: "v0.1.0-alpha")
        )

        XCTAssertEqual(provider.displayVersion, "v0.1.0-alpha")
    }

    func testDefaultProviderPrefersBundleVersionWhenAvailable() {
        let provider = DefaultAppVersionProvider(
            bundleProvider: StaticVersionProvider(displayVersion: "1.2.3 (4)"),
            gitProvider: StaticVersionProvider(displayVersion: "v0.1.0-alpha")
        )

        XCTAssertEqual(provider.displayVersion, "1.2.3 (4)")
    }
}

private struct StaticVersionProvider: AppVersionProviding {
    let displayVersion: String
}
