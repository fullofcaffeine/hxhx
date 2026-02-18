package backend.js;

import backend.BackendCapabilities;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.IBackend;
import backend.ITargetBackendProvider;
import backend.ITargetCore;
import backend.TargetDescriptor;
import backend.TargetCoreBackend;

/**
	Stage3 JS backend MVP (`js-native`).

	Why
	- `hxhx` needs a first non-delegating JS emission rung so `--target js-native`
	  can run without stage0 delegation.
	- We intentionally keep this as a constrained subset and fail fast on unsupported
	  expression shapes.

	What
	- Emits one JavaScript file with:
	  - static classes/functions/fields from the typed module graph
	  - basic statement/expression lowering via `JsStmtEmitter` / `JsExprEmitter`
	  - optional IIFE wrapper (`js-classic` disables it)
	- Returns a non-executable artifact (`entry_js`), executed by Stage3 runner via `node`.

	How
	- Keep output deterministic and readable.
	- Keep unsupported behavior explicit (throws with actionable error).
**/
class JsBackend implements IBackend implements ITargetBackendProvider {
	public static inline var TARGET_ID = "js-native";
	public static inline var IMPL_ID = "builtin/js-native";
	public static inline var ABI_VERSION = 1;
	public static inline var PRIORITY = 100;
	public static inline var PROVIDER_IMPL_ID = "provider/js-native-wrapper";
	public static inline var PROVIDER_PRIORITY = 200;

	final delegate:TargetCoreBackend;

	public function id():String {
		return delegate.id();
	}

	public function describe():String {
		return delegate.describe();
	}

	public static function descriptor():TargetDescriptor {
		return {
			id: TARGET_ID,
			implId: IMPL_ID,
			abiVersion: ABI_VERSION,
			priority: PRIORITY,
			description: "Native JS backend (MVP)",
			capabilities: capabilitiesStatic(),
			requires: {
				genIrVersion: 1,
				macroApiVersion: 1,
				hostCaps: ["filesystem", "process", "node"]
			}
		};
	}

	public static function providerDescriptor():TargetDescriptor {
		return {
			id: TARGET_ID,
			implId: PROVIDER_IMPL_ID,
			abiVersion: ABI_VERSION,
			priority: PROVIDER_PRIORITY,
			description: "JS backend provider wrapper (dynamic)",
			capabilities: capabilitiesStatic(),
			requires: {
				genIrVersion: 1,
				macroApiVersion: 1,
				hostCaps: ["filesystem", "process", "node"]
			}
		};
	}

	static function capabilitiesStatic():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	public function capabilities():BackendCapabilities {
		return delegate.capabilities();
	}

	public static function targetCore():ITargetCore {
		return new JsTargetCore();
	}

	public function new() {
		delegate = new TargetCoreBackend(descriptor(), targetCore());
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return delegate.emit(program, context);
	}

	public function registrations():Array<BackendRegistrationSpec> {
		final provided = providerDescriptor();
		return [
			{
				descriptor: provided,
				create: function() return new TargetCoreBackend(provided, targetCore())
			}
		];
	}
}
