//
//  DirectionPickerSearchTests.swift
//  LoopTests
//
//  Created by Nicolas Corini on 2026-10-27.
//

@testable import Loop
import Testing

struct DirectionPickerSearchTests {
    @Test func searchRanksPrefixSubstringSubsequenceAndRejectsOutOfOrder() {
        #expect(DirectionPickerView.fuzzyScore("Left Half", "left") == 0)
        #expect(DirectionPickerView.fuzzyScore("Left Half", "half") == 1)
        #expect(DirectionPickerView.fuzzyScore("Left Half", "lfhf") == 2)
        #expect(DirectionPickerView.fuzzyScore("Left Half", "fl l") == nil)
    }

    /// Regression test for #1187, where a multi-byte character in the name crashed the search.
    /// "meta" doesn't match "Metà" because the search isn't diacritic-insensitive.
    @Test func nonASCIINamesAndPatternsDoNotCrashTheSubsequenceMatch() {
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "meta") == nil)
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "eeoe") == 2)
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "mà ie") == 2)
    }
}
