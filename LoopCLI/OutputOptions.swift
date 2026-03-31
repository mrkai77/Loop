//
//  OutputOptions.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-30.
//

import ArgumentParser

struct OutputOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Print raw JSON instead of human-readable text")
    var json = false

    var outputMode: CLIOutputMode {
        json ? .json : .human
    }
}
