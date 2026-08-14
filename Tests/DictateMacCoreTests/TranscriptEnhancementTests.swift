import XCTest
@testable import DictateMacCore

final class TranscriptEnhancementTests: XCTestCase {
    private let evidence = [
        BrainEvidenceItem(
            id: "project:nuri",
            type: "project",
            label: "nuri-expo",
            path: "/Brain/Repositories/nuri-expo",
            excerpt: "Nuri Expo mobile application repository",
            url: "https://github.com/eminogrande/nuri-expo"
        )
    ]

    func testAcceptsSpellingCorrectionAndGroundedRepositoryContext() throws {
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Please open the Nuri repository.",
            corrections: [
                TranscriptCorrection(original: "nuwi", replacement: "Nuri", confidence: 0.99),
                TranscriptCorrection(original: "repo", replacement: "repository", confidence: 0.97),
            ],
            usefulContext: [
                TranscriptContextItem(
                    title: "Nuri Expo repository",
                    detail: "Relevant repository from Brain",
                    url: "https://github.com/eminogrande/nuri-expo",
                    sourcePath: "/Brain/Repositories/nuri-expo"
                )
            ]
        )

        let result = try XCTUnwrap(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "please open the nuwi repo",
                evidence: evidence
            )
        )

        XCTAssertEqual(result.correctedTranscript, "Please open the Nuri repository.")
        XCTAssertEqual(result.usefulContext.count, 1)
    }

    func testRejectsCandidateThatRewritesTheSpokenMeaning() {
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Deploy the production banking service and notify every customer immediately.",
            usefulContext: []
        )

        XCTAssertNil(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "please open the nuwi repo",
                evidence: evidence
            )
        )
    }

    func testDropsContextWithoutExactBrainSource() throws {
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Please open the Nuri repository.",
            corrections: [
                TranscriptCorrection(original: "nuwi", replacement: "Nuri", confidence: 0.99),
                TranscriptCorrection(original: "repo", replacement: "repository", confidence: 0.97),
            ],
            usefulContext: [
                TranscriptContextItem(
                    title: "Invented",
                    detail: "Not grounded",
                    url: "https://example.com/invented",
                    sourcePath: "/not/in/brain"
                )
            ]
        )

        let result = try XCTUnwrap(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "please open the nuwi repo",
                evidence: evidence
            )
        )
        XCTAssertTrue(result.usefulContext.isEmpty)
    }

    func testRejectsUncertainWordCorrection() {
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Please open the Nuri repo.",
            corrections: [
                TranscriptCorrection(original: "nuwi", replacement: "Nuri", confidence: 0.72),
            ],
            usefulContext: []
        )

        XCTAssertNil(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "please open the nuwi repo",
                evidence: evidence
            )
        )
    }

    func testAcceptsPasskeyCorrectionOnlyWhenBrainContainsReplacement() throws {
        let passkeyEvidence = [
            BrainEvidenceItem(
                id: "file:passkey",
                type: "file",
                label: "PasskeyManager.swift",
                path: "/repo/PasskeyManager.swift",
                excerpt: "Verify passkey WebAuthn assertions.",
                url: nil
            )
        ]
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Please test the passkey flow.",
            corrections: [
                TranscriptCorrection(original: "PASCII", replacement: "passkey", confidence: 0.99),
            ],
            usefulContext: []
        )

        XCTAssertNotNil(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "Please test the PASCII flow.",
                evidence: passkeyEvidence
            )
        )
        XCTAssertNil(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "Please test the PASCII flow.",
                evidence: []
            )
        )
    }

    func testRejectsHighConfidenceCorrectionMissingFromBrainEvidence() {
        let candidate = TranscriptEnhancement(
            correctedTranscript: "Please open the Bitcoin repo.",
            corrections: [
                TranscriptCorrection(original: "nuwi", replacement: "Bitcoin", confidence: 0.99),
            ],
            usefulContext: []
        )

        XCTAssertNil(
            TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: "Please open the nuwi repo.",
                evidence: evidence
            )
        )
    }

    func testRecentFocusUsesDistinctBoundedHeadlines() {
        XCTAssertEqual(
            RecentWorkSummary.make(headlines: ["Brain browser", "Brain browser", "Menu fix", "Archive migration"]),
            "Recent focus: Brain browser · Menu fix · Archive migration"
        )
    }
}
