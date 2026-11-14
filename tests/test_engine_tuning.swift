import Foundation

enum HengeLog {
    static func log(_ category: String, _ message: String) {}
}

@main
struct EngineTuningTests {
    static func main() {
        let first = "HENGE_TUNING_TEST_FIRST", second = "HENGE_TUNING_TEST_SECOND"
        let original = [first, second].reduce(into: [String: String]()) { values, key in
            if let value = getenv(key) { values[key] = String(cString: value) }
        }
        defer {
            EngineTuning.applyEnvironment([:])
            for (key, value) in original { setenv(key, value, 1) }
        }

        EngineTuning.applyEnvironment([first: "1", second: "2"])
        precondition(String(cString: getenv(first)!) == "1")
        precondition(String(cString: getenv(second)!) == "2")

        EngineTuning.applyEnvironment([second: "3"])
        precondition(getenv(first) == nil)
        precondition(String(cString: getenv(second)!) == "3")

        EngineTuning.applyEnvironment([:])
        precondition(getenv(second) == nil)
        print("Engine tuning: 5 checks")
    }
}
