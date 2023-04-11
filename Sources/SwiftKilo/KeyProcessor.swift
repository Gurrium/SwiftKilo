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

    func process(_ scalar: UnicodeScalar) -> EditorAction? {
        var action: EditorAction?

        state.append(scalar)

        switch state {
        case [("q" as UnicodeScalar).modified(with: .control)]:
            action = .quit
        case [("b" as UnicodeScalar).modified(with: .control)]:
            action = .moveCursorToTopOfScreen
        case [("f" as UnicodeScalar).modified(with: .control)]:
            action = .moveCursorToBottomOfScreen
        case ["h"]:
            action = .moveCursorLeft
        case ["j"]:
            action = .moveCursorDown
        case ["k"]:
            action = .moveCursorUp
        case ["l"]:
            action = .moveCursorRight
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
}
