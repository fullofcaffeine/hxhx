import backend.BackendAbi;
import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;

class M14LoaderDuplicateBundledProvider implements ITargetBackendProvider {
	public function new() {}

	public function registrations():Array<BackendRegistrationSpec> {
		final descriptor:backend.TargetDescriptor = {
			id: "js-native",
			implId: "plugin/js-native@loader-shared",
			abiVersion: BackendAbi.VERSION,
			priority: 5,
			description: "Bundled duplicate loader fixture",
			capabilities: {
				supportsNoEmit: true,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: true
			},
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: []
			}
		};
		return [
			{
				descriptor: descriptor,
				create: function() return new TargetCoreBackend(descriptor, function(_program, _context) throw "duplicate fixture should not emit")
			}
		];
	}
}
