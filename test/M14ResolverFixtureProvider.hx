import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;

class M14ResolverFixtureProvider implements ITargetBackendProvider {
	public function new() {}

	public function registrations():Array<BackendRegistrationSpec> {
		final descriptor:backend.TargetDescriptor = {
			id: "js-native",
			implId: "plugin/js-native@fixture",
			abiVersion: 1,
			priority: 150,
			description: "Fixture provider registration",
			capabilities: {
				supportsNoEmit: true,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: true
			},
			requires: {
				genIrVersion: 1,
				macroApiVersion: 1,
				hostCaps: []
			}
		};
		return [
			{
				descriptor: descriptor,
				create: function() return new TargetCoreBackend(
					descriptor,
					function(_program, _context) throw "fixture target core should not emit in this test"
				)
			}
		];
	}
}
