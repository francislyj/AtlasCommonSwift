import Testing
@testable import AtlasCommonSwift

@Test func logLevelEnumExists() {
    let levels: [Log.Level] = [.debug, .info, .warning, .error]
    #expect(levels.count == 4)
}

@Test func logDoesNotCrashWhenHookIsNil() {
    Log._otelEmit = nil
    Log.debug("no crash")
    Log.info("no crash")
    Log.warning("no crash")
    Log.error("no crash")
}
