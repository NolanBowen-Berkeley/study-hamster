import Foundation

// Self-checks for HamsterCore. Run with `swift run HamsterChecks`; exits 1 on any failure.

runDurationParserChecks()
runTimeFormatChecks()
runSettingsChecks()
runPlannerChecks()
runEngineChecks()
runWindowSelectorChecks()
runScreenGeometryChecks()
runPerchChecks()

print("HamsterChecks: \(Harness.passed) passed, \(Harness.failed) failed")
if Harness.failed > 0 { exit(1) }
