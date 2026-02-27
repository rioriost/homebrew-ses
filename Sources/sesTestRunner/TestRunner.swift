import Foundation
import sesCore

func runAllTestsAndExit() async -> Never {
    var passed = 0
    var failed = 0

    for (name, test) in TestRegistry.tests() {
        let ok = await run(name, test)
        if ok { passed += 1 } else { failed += 1 }
    }

    print("Tests: \(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
}
