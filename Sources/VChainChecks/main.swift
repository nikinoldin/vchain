// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

runBPMTagChecks()
runPendulumChecks()
runKeyringChecks()
runKeychainStateChecks()
runBeadCharmsChecks()
runSpectrumChecks()
runDescriptorMaskChecks()
runBandLCDChecks()
runStripPowerOnChecks()
runEnergyPowerOnChecks()
runTagPowerOnChecks()
runStripEditChecks()
runPlugChecks()

print("\(Checks.total) checks, \(Checks.failed) failed")
exit(Checks.failed == 0 ? 0 : 1)
