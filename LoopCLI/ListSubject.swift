//
//  ListSubject.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser

enum ListSubject: String, CaseIterable, ExpressibleByArgument {
    case windows
    case screens
    case actions
}
