//
//  DirectionPickerSearchTests.swift
//  LoopTests
//
//  Created by Nicolas Corini on 2026-10-27.
//

@testable import Loop
import Testing

struct DirectionPickerSearchTests {
    @Test func prefixMatchScoresZero() {
        #expect(DirectionPickerView.fuzzyScore("Left Half", "left") == 0)
    }

    @Test func substringMatchScoresOne() {
        #expect(DirectionPickerView.fuzzyScore("Left Half", "half") == 1)
    }

    @Test func subsequenceMatchScoresTwo() {
        #expect(DirectionPickerView.fuzzyScore("Left Half", "lfhf") == 2)
    }

    @Test func outOfOrderCharactersDoNotMatch() {
        #expect(DirectionPickerView.fuzzyScore("Left Half", "fl l") == nil)
    }

    /// Regression test for #1187, where a multi-byte character in the name crashed the search.
    /// "meta" doesn't match "Metà" because the search isn't diacritic-insensitive.
    @Test func subsequenceMatchAgainstNonASCIINameDoesNotCrash() {
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "meta") == nil)
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "eeoe") == 2)
    }

    @Test func subsequenceMatchWithNonASCIIPattern() {
        #expect(DirectionPickerView.fuzzyScore("Metà inferiore", "mà ie") == 2)
    }
}
