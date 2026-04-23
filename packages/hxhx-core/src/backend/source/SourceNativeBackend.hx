package backend.source;

import backend.BackendAbi;
import backend.BackendCapabilities;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;
import backend.source.SourceTargetCommon.SourceNativeTarget;

/**
	Thin registration facade for native source-target backends.

	Why
	- The source-target implementation grew into a large mixed-ownership file
	  spanning shared MVP rendering, Java packaging, and PHP-specific runtime
	  lowering.
	- Keeping registration and implementation in one class made every target
	  change harder to review and pushed the architecture further away from the
	  upstream-style target ownership boundaries we want to converge on.

	What
	- Keeps the public target descriptors and registration wiring stable.
	- Delegates actual emission to dedicated target-core modules:
	  shared MVP targets, Java, and PHP.

	How
	- This is an ownership extraction seam, not a behavior change. The emitted
	  artifacts, target IDs, and CLI routing remain unchanged while the
	  implementation moves behind smaller modules that can be refined further.
**/
class SourceNativeBackend {
	public static inline var PYTHON_TARGET_ID = "python-native";
	public static inline var JAVA_TARGET_ID = "java-native";
	public static inline var CS_TARGET_ID = "cs-native";
	public static inline var PHP_TARGET_ID = "php-native";
	public static inline var LUA_TARGET_ID = "lua-native";

	static function capabilitiesStatic():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	static function javaCapabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: true,
			supportsCustomOutputFile: true
		};
	}

	static function descriptor(targetId:String, implId:String, description:String, hostCap:String):TargetDescriptor {
		return {
			id: targetId,
			implId: implId,
			abiVersion: BackendAbi.VERSION,
			priority: 120,
			description: description,
			capabilities: capabilitiesStatic(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", hostCap]
			}
		};
	}

	static function descriptorWithCapabilities(targetId:String, implId:String, description:String, hostCap:String,
			capabilities:BackendCapabilities):TargetDescriptor {
		final d = descriptor(targetId, implId, description, hostCap);
		return {
			id: d.id,
			implId: d.implId,
			abiVersion: d.abiVersion,
			priority: d.priority,
			description: d.description,
			capabilities: capabilities,
			requires: d.requires
		};
	}

	public static function pythonDescriptor():TargetDescriptor {
		return descriptor(PYTHON_TARGET_ID, "builtin/python-native-source-mvp", "Native Python source backend (MVP)", "python");
	}

	public static function javaDescriptor():TargetDescriptor {
		return descriptorWithCapabilities(JAVA_TARGET_ID, "builtin/java-native-source-mvp", "Native Java source backend (MVP)", "java", javaCapabilities());
	}

	public static function csDescriptor():TargetDescriptor {
		return descriptor(CS_TARGET_ID, "builtin/cs-native-source-mvp", "Native C# source backend (MVP)", "dotnet");
	}

	public static function phpDescriptor():TargetDescriptor {
		return descriptor(PHP_TARGET_ID, "builtin/php-native-source-mvp", "Native PHP source backend (MVP)", "php");
	}

	public static function luaDescriptor():TargetDescriptor {
		return descriptor(LUA_TARGET_ID, "builtin/lua-native-source-mvp", "Native Lua source backend (MVP)", "lua");
	}

	static function registration(d:TargetDescriptor, target:SourceNativeTarget):BackendRegistrationSpec {
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitTarget(target, program, context))
		};
	}

	public static function pythonRegistration():BackendRegistrationSpec {
		return registration(pythonDescriptor(), Python);
	}

	public static function javaRegistration():BackendRegistrationSpec {
		return registration(javaDescriptor(), Java);
	}

	public static function csRegistration():BackendRegistrationSpec {
		return registration(csDescriptor(), Cs);
	}

	public static function phpRegistration():BackendRegistrationSpec {
		return registration(phpDescriptor(), Php);
	}

	public static function luaRegistration():BackendRegistrationSpec {
		return registration(luaDescriptor(), Lua);
	}

	static function emitTarget(target:SourceNativeTarget, program:GenIrProgram, context:BackendContext):EmitResult {
		return switch (target) {
			case Java:
				JavaSourceTargetCore.emit(program, context);
			case Php:
				PhpSourceTargetCore.emit(program, context);
			case Python | Cs | Lua:
				SourceMvpTargetCore.emit(target, program, context);
		};
	}
}
