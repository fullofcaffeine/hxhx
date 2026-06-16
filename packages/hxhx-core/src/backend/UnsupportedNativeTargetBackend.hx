package backend;

/**
	Placeholder backend registration for declared native target tracks without a
	specific target-core boundary yet.

	Why
	- Full1 strict target evidence must distinguish "CLI never routed this target" from
	  "the target reached Stage3 backend dispatch and now needs implementation".
	- Registering an explicit backend descriptor gives CI and bead evidence a stable,
	  target-specific failure seam without weakening no-stage0/no-skip policy.

	What
	- Provides backend descriptors for target families that are declared but not
	  implemented yet and do not yet have a more specific target-core boundary.
	- Supports `--hxhx-no-emit` so front-end/macro/type smoke checks can select the
	  target without emitting artifacts.
	- Fails on real emission with an explicit target-specific implementation error.

	How
	- Keep this backend intentionally small and fail-fast.
	- Replace each placeholder with a real target-core backend as the corresponding
	  Full1 target track lands.
**/
class UnsupportedNativeTargetBackend {
	public static inline var CPP_TARGET_ID = "cpp-native";

	public static function cppDescriptor():TargetDescriptor {
		return descriptor(CPP_TARGET_ID, "builtin/cpp-native-placeholder", "Native C++/hxcpp backend placeholder", "process");
	}

	static function descriptor(targetId:String, implId:String, description:String, hostCap:String):TargetDescriptor {
		return {
			id: targetId,
			implId: implId,
			abiVersion: BackendAbi.VERSION,
			priority: 100,
			description: description,
			capabilities: {
				supportsNoEmit: true,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: true
			},
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", hostCap]
			}
		};
	}

	static function emitUnsupported(targetLabel:String, _program:GenIrProgram, _context:BackendContext):EmitResult {
		throw targetLabel + " native backend reached Stage3 dispatch but is not implemented yet.";
	}

	public static function cppRegistration():BackendRegistrationSpec {
		final d = cppDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("C++", program, context))
		};
	}
}
