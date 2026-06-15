package backend.vm;

import backend.BackendAbi;
import backend.BackendCapabilities;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;

/**
	Registration facade for VM-style native targets.

	Neko is promoted from placeholder to a source-emission MVP here. HashLink remains
	owned by `UnsupportedNativeTargetBackend` until its backend has a real target core.
**/
class VmNativeBackend {
	public static inline var NEKO_TARGET_ID = "neko-native";

	static function nekoCapabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	public static function nekoDescriptor():TargetDescriptor {
		return {
			id: NEKO_TARGET_ID,
			implId: "builtin/neko-native-source-mvp",
			abiVersion: BackendAbi.VERSION,
			priority: 120,
			description: "Native Neko source backend (MVP)",
			capabilities: nekoCapabilities(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", "process", "neko"]
			}
		};
	}

	public static function nekoRegistration():BackendRegistrationSpec {
		final d = nekoDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program:GenIrProgram, context:BackendContext):EmitResult {
				return NekoTargetCore.emit(program, context);
			})
		};
	}
}
