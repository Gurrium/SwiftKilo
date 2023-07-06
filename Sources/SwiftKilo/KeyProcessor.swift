//
//  File.swift
//  
//
//  Created by gurrium on 2023/04/11.
//

import Foundation

final class KeyProcessor {
    private var state = [UnicodeScalar]()
    private var stateRefreshingTask: Task<Void, Never>?

    func process(_ scalar: UnicodeScalar, mode: SwiftKilo.Mode) -> EditorAction? {
        switch mode {
        case .normal:
            return processNormalMode(scalar: scalar)
        case .insert:
            return processInsertMode(scalar: scalar)
        }
    }

    private func processNormalMode(scalar: UnicodeScalar) -> EditorAction? {
        var action: EditorAction?

        state.append(scalar)

        switch state {
        case [.init("q").modified(with: .control)]:
            action = .quit
        case [.init("b").modified(with: .control)]:
            action = .movePageUp
        case [.init("f").modified(with: .control)]:
            action = .movePageDown
        case ["h"]:
            action = .moveCursorLeft
        case ["j"]:
            action = .moveCursorDown
        case ["k"]:
            action = .moveCursorUp
        case ["l"]:
            action = .moveCursorRight
        case ["H"]:
            action = .moveCursorToBeginningOfLine
        case ["L"]:
            action = .moveCursorToEndOfLine
        case Array("\u{1b}[3~".unicodeScalars):
            action = .delete
        case ["i"]:
            action = .changeModeToInput
        case [.init("s").modified(with: .control)]:
            action = .save
        case [.init("f").modified(with: .control)]:
            action = .find
        default:
            action = nil
        }

        stateRefreshingTask?.cancel()
        // TODO: 候補がなくなった時点でstateを空にする
        if action != nil {
            state = []
        } else {
            stateRefreshingTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard !Task.isCancelled else { return }

                state = []
            }
        }

        return action
    }

    private func processInsertMode(scalar: UnicodeScalar) -> EditorAction? {
        var action: EditorAction?

        state.append(scalar)

        switch state {
        case ["\u{1b}"]:
            action = .changeModeToNormal
        case [.init("m").modified(with: .control)]:
            action = .newLine
        case [.init("h").modified(with: .control)]:
            action = .delete
        case [.init("l").modified(with: .control)]:
            break
        default:
            action = .insert(scalar)
        }

        if action != nil {
            state = []
        }

        return action
    }
}
