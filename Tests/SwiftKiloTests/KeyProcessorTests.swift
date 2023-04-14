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

    // MARK: cursor

    func test_moveCursorUp() {
        XCTAssertEqual(keyProcessor.process(.init("k")), .moveCursorUp)
    }

    func test_moveCursorLeft() {
        XCTAssertEqual(keyProcessor.process(.init("h")), .moveCursorLeft)
    }

    func test_moveCursorRight() {
        XCTAssertEqual(keyProcessor.process(.init("l")), .moveCursorRight)
    }

    func test_moveCursorDown() {
        XCTAssertEqual(keyProcessor.process(.init("j")), .moveCursorDown)
    }

    func test_moveCursorToBeginningOfLine() {
        XCTAssertEqual(keyProcessor.process(.init("H")), .moveCursorToBeginningOfLine)
    }

    func test_moveCursorToEndOfLine() {
        XCTAssertEqual(keyProcessor.process(.init("L")), .moveCursorToEndOfLine)
    }

    // MARK: page

    func test_movePageUp() {
        XCTAssertEqual(keyProcessor.process(.init("b").modified(with: .control)), .movePageUp)
    }

    func test_movePageDown() {
        XCTAssertEqual(keyProcessor.process(.init("f").modified(with: .control)), .movePageDown)
    }

    // MARK: text

    func test_delete() {
        "\u{1b}[3".unicodeScalars.forEach { XCTAssertNil(keyProcessor.process($0)) }
        XCTAssertEqual(keyProcessor.process(.init("~")), .delete)
    }

    // MARK: editor

    func test_quit() {
        XCTAssertEqual(keyProcessor.process(.init("q").modified(with: .control)), .quit)
    }
}
