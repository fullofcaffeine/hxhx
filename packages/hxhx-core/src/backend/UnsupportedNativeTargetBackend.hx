package backend;

/**
	Placeholder backend registration for declared native target tracks.

	Why
	- Full1 strict target evidence must distinguish "CLI never routed this target" from
	  "the target reached Stage3 backend dispatch and now needs implementation".
	- Registering an explicit backend descriptor gives CI and bead evidence a stable,
	  target-specific failure seam without weakening no-stage0/no-skip policy.

	What
	- Provides backend descriptors for target families that are declared but not
	  implemented yet.
	- Supports `--hxhx-no-emit` so front-end/macro/type smoke checks can select the
	  target without emitting artifacts.
	- Fails on real emission with an explicit target-specific implementation error.

	How
	- Keep this backend intentionally small and fail-fast.
	- Replace each placeholder with a real target-core backend as the corresponding
	  Full1 target track lands.
**/
class UnsupportedNativeTargetBackend {
	public static inline var NEKO_TARGET_ID = "neko-native";
	public static inline var HL_TARGET_ID = "hl-native";
	public static inline var PYTHON_TARGET_ID = "python-native";
	public static inline var JAVA_TARGET_ID = "java-native";
	public static inline var CS_TARGET_ID = "cs-native";
	public static inline var PHP_TARGET_ID = "php-native";
	public static inline var LUA_TARGET_ID = "lua-native";

	public static function nekoDescriptor():TargetDescriptor {
		return descriptor(NEKO_TARGET_ID, "builtin/neko-native-placeholder", "Native Neko backend placeholder", "process");
	}

	public static function hlDescriptor():TargetDescriptor {
		return descriptor(HL_TARGET_ID, "builtin/hl-native-placeholder", "Native HashLink backend placeholder", "process");
	}

	public static function pythonDescriptor():TargetDescriptor {
		return descriptor(PYTHON_TARGET_ID, "builtin/python-native-placeholder", "Native Python backend placeholder", "process");
	}

	public static function javaDescriptor():TargetDescriptor {
		return descriptor(JAVA_TARGET_ID, "builtin/java-native-placeholder", "Native Java backend placeholder", "process");
	}

	public static function csDescriptor():TargetDescriptor {
		return descriptor(CS_TARGET_ID, "builtin/cs-native-placeholder", "Native C# backend placeholder", "process");
	}

	public static function phpDescriptor():TargetDescriptor {
		return descriptor(PHP_TARGET_ID, "builtin/php-native-placeholder", "Native PHP backend placeholder", "process");
	}

	public static function luaDescriptor():TargetDescriptor {
		return descriptor(LUA_TARGET_ID, "builtin/lua-native-placeholder", "Native Lua backend placeholder", "process");
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

	public static function nekoRegistration():BackendRegistrationSpec {
		final d = nekoDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("Neko", program, context))
		};
	}

	public static function hlRegistration():BackendRegistrationSpec {
		final d = hlDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("HashLink", program, context))
		};
	}

	public static function pythonRegistration():BackendRegistrationSpec {
		final d = pythonDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("Python", program, context))
		};
	}

	public static function javaRegistration():BackendRegistrationSpec {
		final d = javaDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("Java", program, context))
		};
	}

	public static function csRegistration():BackendRegistrationSpec {
		final d = csDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("C#", program, context))
		};
	}

	public static function phpRegistration():BackendRegistrationSpec {
		final d = phpDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("PHP", program, context))
		};
	}

	public static function luaRegistration():BackendRegistrationSpec {
		final d = luaDescriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitUnsupported("Lua", program, context))
		};
	}
}
