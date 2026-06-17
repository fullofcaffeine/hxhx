package backend.cpp;

import backend.BackendAbi;
import backend.BackendCapabilities;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;

/**
	Registration facade for the Stage3 C++ target boundary.

	Why
	- `--cpp` is part of the Full1 extended target matrix, so leaving it behind a
	  generic unsupported-target placeholder hides whether the compiler reached a
	  real target-core seam.
	- C++/hxcpp parity is a large target, but the first honest step is still a
	  repo-owned target core with focused coverage and precise unsupported-shape
	  diagnostics.

	What
	- Registers `cpp-native` as a native C++ source MVP target.
	- Keeps descriptor metadata separate from emission logic.

	How
	- `CppTargetCore` owns code generation and optional local compiler smoke
	  building. This wrapper only exposes the backend descriptor and factory.
**/
class CppNativeBackend {
	public static inline var CPP_TARGET_ID = "cpp-native";

	static function capabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: true,
			supportsCustomOutputFile: true
		};
	}

	public static function descriptor():TargetDescriptor {
		return {
			id: CPP_TARGET_ID,
			implId: "builtin/cpp-native-source-mvp",
			abiVersion: BackendAbi.VERSION,
			priority: 120,
			description: "Native C++ source backend (MVP)",
			capabilities: capabilities(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", "process", "cpp"]
			}
		};
	}

	public static function registration():BackendRegistrationSpec {
		final d = descriptor();
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program:GenIrProgram, context:BackendContext):EmitResult {
				return CppTargetCore.emit(program, context);
			})
		};
	}
}
