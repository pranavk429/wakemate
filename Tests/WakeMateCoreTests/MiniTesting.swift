import Foundation

public struct TestFailure: Sendable {
    public let message: String
    public let file: StaticString
    public let line: UInt
}

public final class TestContext: @unchecked Sendable {
    public static let shared = TestContext()
    private let lock = NSLock()
    private var failures: [TestFailure] = []
    private var totalTests: Int = 0
    private var passedTests: Int = 0

    public func recordTest(passed: Bool) {
        lock.withLock {
            totalTests += 1
            if passed { passedTests += 1 }
        }
    }

    public func recordFailure(_ message: String, file: StaticString, line: UInt) {
        lock.withLock {
            failures.append(TestFailure(message: message, file: file, line: line))
            print("  ❌ [FAIL] \(file):\(line) - \(message)")
        }
    }

    public func reset() {
        lock.withLock {
            failures.removeAll()
            totalTests = 0
            passedTests = 0
        }
    }

    public var hasFailures: Bool {
        lock.withLock { !failures.isEmpty }
    }

    public var summary: (total: Int, passed: Int, failed: Int) {
        lock.withLock { (totalTests, passedTests, failures.count) }
    }
}

public func expect(_ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    do {
        let result = try condition()
        if !result {
            let msg = message().isEmpty ? "Expectation failed" : message()
            TestContext.shared.recordFailure(msg, file: file, line: line)
        }
    } catch {
        TestContext.shared.recordFailure("Condition threw unexpected error: \(error)", file: file, line: line)
    }
}

public func require<T>(_ value: T?, _ message: @autoclosure () -> String = "Value was nil", file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else {
        TestContext.shared.recordFailure(message(), file: file, line: line)
        throw TestFatalError(message: message())
    }
    return value
}

public struct TestFatalError: Error {
    public let message: String
}

public func expectThrows<T, E: Error & Equatable>(_ expected: E, file: StaticString = #file, line: UInt = #line, _ operation: () throws -> T) {
    do {
        _ = try operation()
        TestContext.shared.recordFailure("Expected error \(expected) but nothing was thrown", file: file, line: line)
    } catch let error as E {
        if error != expected {
            TestContext.shared.recordFailure("Expected error \(expected) but caught \(error)", file: file, line: line)
        }
    } catch {
        TestContext.shared.recordFailure("Expected error \(expected) but caught different error \(error)", file: file, line: line)
    }
}

public func expectThrowsType<T, E: Error>(_ errorType: E.Type, file: StaticString = #file, line: UInt = #line, _ operation: () throws -> T) {
    do {
        _ = try operation()
        TestContext.shared.recordFailure("Expected error of type \(errorType) but nothing was thrown", file: file, line: line)
    } catch is E {
        // Expected
    } catch {
        TestContext.shared.recordFailure("Expected error of type \(errorType) but caught \(error)", file: file, line: line)
    }
}

public func runTest(_ name: String, _ block: () throws -> Void) {
    print("▶ Running: \(name)...")
    let startFailures = TestContext.shared.summary.failed
    do {
        try block()
        let endFailures = TestContext.shared.summary.failed
        if endFailures == startFailures {
            TestContext.shared.recordTest(passed: true)
            print("  ✅ \(name)")
        } else {
            TestContext.shared.recordTest(passed: false)
        }
    } catch {
        TestContext.shared.recordTest(passed: false)
        TestContext.shared.recordFailure("Test threw unexpected error: \(error)", file: #file, line: #line)
    }
}

public func runAsyncTest(_ name: String, _ block: @MainActor () throws -> Void) {
    print("▶ Running: \(name)...")
    let startFailures = TestContext.shared.summary.failed
    MainActor.assumeIsolated {
        do {
            try block()
            let endFailures = TestContext.shared.summary.failed
            if endFailures == startFailures {
                TestContext.shared.recordTest(passed: true)
                print("  ✅ \(name)")
            } else {
                TestContext.shared.recordTest(passed: false)
            }
        } catch {
            TestContext.shared.recordTest(passed: false)
            TestContext.shared.recordFailure("Test threw unexpected error: \(error)", file: #file, line: #line)
        }
    }
}
