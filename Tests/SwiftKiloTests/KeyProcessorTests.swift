//
//  KeyProcessorTests.swift
//  
//
//  Created by gurrium on 2023/04/11.
//

import XCTest
@testable import SwiftKilo

final class KeyProcessorTests: XCTestCase {
    var keyProcessor: KeyProcessor!

    override func setUp() {
        keyProcessor = KeyProcessor()
    }

    func test_moveCursorUp() {
        XCTAssertEqual(keyProcessor.process("k" as UnicodeScalar), .moveCursorUp)
    }

    func test_moveCursorLeft() {
        XCTAssertEqual(keyProcessor.process("h" as UnicodeScalar), .moveCursorLeft)
    }

    func test_moveCursorRight() {
        XCTAssertEqual(keyProcessor.process("l" as UnicodeScalar), .moveCursorRight)
    }

    func test_moveCursorDown() {
        XCTAssertEqual(keyProcessor.process("j" as UnicodeScalar), .moveCursorDown)
    }

    func test_moveCursorToTopOfScreen() {
        XCTAssertEqual(keyProcessor.process(("b" as UnicodeScalar).modified(with: .control)!), .moveCursorToTopOfScreen)
    }

    func test_moveCursorToBottomOfScreen() {
        XCTAssertEqual(keyProcessor.process(("f" as UnicodeScalar).modified(with: .control)!), .moveCursorToBottomOfScreen)
    }

    func test_quit() {
        XCTAssertEqual(keyProcessor.process(("q" as UnicodeScalar).modified(with: .control)!), .quit)
    }
}
