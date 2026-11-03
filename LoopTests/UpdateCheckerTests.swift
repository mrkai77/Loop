//
//  UpdateCheckerTests.swift
//  LoopTests
//
//  Created by Joshua Van Deren on 2026-11-02.
//

import Foundation
@testable import Loop
import Testing

struct UpdateCheckerTests {
    /// Builds a release the way the GitHub API reports it: prereleases carry their version and build in the name,
    /// stable releases in the tag.
    private func release(_ version: String, build: Int? = nil) -> GitHubRelease {
        GitHubRelease(
            id: version.hashValue,
            tagName: build == nil ? version : "prerelease",
            name: build.map { "🧪 \(version) (\($0))" } ?? version,
            body: "",
            assets: [],
            prerelease: build != nil,
            createdAt: .now,
            updatedAt: .now,
            publishedAt: .now
        )
    }

    @Test func aNewerPrereleaseIsOffered() async {
        let releases = [release("1.4.3", build: 1783), release("1.4.2")]
        let candidate = await UpdateChecker().developmentCandidate(in: releases)
        #expect(candidate?.name == "🧪 1.4.3 (1783)")
    }

    @Test func aStableReleaseNewerThanTheLastPrereleaseIsOffered() async {
        let releases = [release("1.5.0"), release("1.4.3", build: 1783), release("1.4.2")]
        let candidate = await UpdateChecker().developmentCandidate(in: releases)
        #expect(candidate?.tagName == "1.5.0")
    }

    /// The stable release of a version has no build number, so it must not replace that version's prerelease.
    @Test func aStableReleaseOfTheSameVersionKeepsThePrerelease() async {
        let releases = [release("1.4.3"), release("1.4.3", build: 1783)]
        let candidate = await UpdateChecker().developmentCandidate(in: releases)
        #expect(candidate?.prerelease == true)
    }

    @Test func aStableReleaseIsOfferedWhenThereIsNoPrerelease() async {
        let releases = [release("1.4.2"), release("1.4.1")]
        let candidate = await UpdateChecker().developmentCandidate(in: releases)
        #expect(candidate?.tagName == "1.4.2")
    }
}
