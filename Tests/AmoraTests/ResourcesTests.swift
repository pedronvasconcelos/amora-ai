import Foundation
import Testing
@testable import Amora

@Test func bundledHookScriptsArePresent() {
    for name in ["codex-hook", "cursor-hook", "claude-hook"] {
        #expect(BundledHook.url(named: name) != nil)
    }
}
