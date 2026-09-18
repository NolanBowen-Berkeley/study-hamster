import Foundation

/// Minimal assertion harness: counts passes and failures and prints every failure with its location.
enum Harness {
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failed = 0
    nonisolated(unsafe) static var currentSection = ""

    static func pass() { passed += 1 }

    static func fail(_ message: String, file: StaticString, line: UInt) {
        failed += 1
        print("FAIL [\(currentSection)] \(file):\(line): \(message)")
    }
}

/// Runs one named group of checks and prints how many of them failed, if any.
func section(_ name: String, _ body: () -> Void) {
    Harness.currentSection = name
    let failuresBefore = Harness.failed
    let passesBefore = Harness.passed
    body()
    let failures = Harness.failed - failuresBefore
    let passes = Harness.passed - passesBefore
    print(failures == 0 ? "ok   \(name) (\(passes) checks)" : "FAIL \(name): \(failures) of \(passes + failures) checks failed")
}

func check(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        Harness.pass()
    } else {
        Harness.fail(message(), file: file, line: line)
    }
}

func checkEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID, line: UInt = #line
) {
    if actual == expected {
        Harness.pass()
    } else {
        let context = message()
        Harness.fail("\(context.isEmpty ? "" : context + ": ")got \(actual), expected \(expected)", file: file, line: line)
    }
}

func checkClose(
    _ actual: Double, _ expected: Double, tolerance: Double = 1e-9, _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID, line: UInt = #line
) {
    if abs(actual - expected) <= tolerance {
        Harness.pass()
    } else {
        let context = message()
        Harness.fail(
            "\(context.isEmpty ? "" : context + ": ")got \(actual), expected \(expected) ± \(tolerance)",
            file: file, line: line
        )
    }
}
