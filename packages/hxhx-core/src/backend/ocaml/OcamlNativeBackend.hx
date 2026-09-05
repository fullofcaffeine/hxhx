package backend.ocaml;

import backend.BackendAbi;
import backend.BackendCapabilities;
import backend.BackendRegistrationSpec;
import backend.TargetDescriptor;
import backend.reflaxe.ReflaxeTargetAdapter;

/** Builtin activation metadata for the authentic standalone OCaml target core. **/
class OcamlNativeBackend {
	public static inline final TARGET_ID = "ocaml-native";
	public static inline final IMPL_ID = "builtin/reflaxe-ocaml";
	public static inline final PRIORITY = 100;

	public static function descriptor():TargetDescriptor {
		return {
			id: TARGET_ID,
			implId: IMPL_ID,
			abiVersion: BackendAbi.VERSION,
			priority: PRIORITY,
			description: "Standalone reflaxe.ocaml target core",
			capabilities: capabilities(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", "process", "ocaml", "dune"]
			}
		};
	}

	public static function capabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: true,
			supportsCustomOutputFile: false
		};
	}

	public static function targetCore():OcamlNativeTargetCore
		return new OcamlNativeTargetCore();

	public static function registration():BackendRegistrationSpec {
		return ReflaxeTargetAdapter.registration(descriptor(), function() {
			final core = targetCore();
			return function(program, context) return OcamlNativeTargetCore.emitBridge(core, program, context);
		});
	}
}
