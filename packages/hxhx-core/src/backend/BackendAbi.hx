package backend;

/**
	Canonical backend ABI contract versions for Stage3 backend loading.

	Why
	- Backend descriptors are registered from both linked builtins and dynamic providers.
	- Version checks must stay centralized so compatibility behavior is deterministic.

	What
	- `VERSION`: backend descriptor ABI version.
	- `GEN_IR_VERSION`: required `GenIrProgram` contract version.
	- `MACRO_API_VERSION`: required macro host/client contract version.

	How
	- `validateDescriptor` returns a deterministic error string or `null` when valid.
	- Registry callers should run this check before accepting a registration.
**/
class BackendAbi {
	public static inline var VERSION:Int = 1;
	public static inline var GEN_IR_VERSION:Int = 1;
	public static inline var MACRO_API_VERSION:Int = 1;

	static function normalizePluginLabel(pluginId:String):String {
		final normalized = pluginId == null ? "" : StringTools.trim(pluginId);
		return normalized.length == 0 ? "<unknown-plugin>" : normalized;
	}

	/**
		Validate manifest-level plugin compatibility requirements.

		Why
		- Native plugin manifests declare ABI/IR/macro API requirements independently from
		  backend descriptor registration.
		- Loader paths should fail fast *before* attempting runtime loading when versions
		  are incompatible.
	**/
	public static function validateManifestRequires(pluginId:String, abiVersion:Int, genIrVersion:Int, macroApiVersion:Int):Null<String> {
		final label = normalizePluginLabel(pluginId);
		if (abiVersion != VERSION) {
			return "backend ABI mismatch for plugin " + label + ": expected abiVersion=" + VERSION + ", got " + abiVersion;
		}
		if (genIrVersion != GEN_IR_VERSION) {
			return "backend GenIR mismatch for plugin " + label + ": expected genIrVersion=" + GEN_IR_VERSION + ", got " + genIrVersion;
		}
		if (macroApiVersion != MACRO_API_VERSION) {
			return "backend macro API mismatch for plugin "
				+ label
				+ ": expected macroApiVersion="
				+ MACRO_API_VERSION
				+ ", got "
				+ macroApiVersion;
		}
		return null;
	}

	static function descriptorLabel(descriptor:TargetDescriptor):String {
		if (descriptor.implId != null && descriptor.implId.length > 0) {
			return descriptor.implId;
		}
		if (descriptor.id != null && descriptor.id.length > 0) {
			return descriptor.id;
		}
		return "<unknown-backend>";
	}

	public static function validateDescriptor(descriptor:TargetDescriptor):Null<String> {
		if (descriptor == null) {
			return "invalid backend registration: descriptor is required";
		}
		if (descriptor.requires == null) {
			return "invalid backend registration: descriptor.requires is required";
		}

		final label = descriptorLabel(descriptor);

		if (descriptor.abiVersion != VERSION) {
			return "backend ABI mismatch for " + label + ": expected abiVersion=" + VERSION + ", got " + descriptor.abiVersion;
		}

		if (descriptor.requires.genIrVersion != GEN_IR_VERSION) {
			return "backend GenIR mismatch for "
				+ label
				+ ": expected genIrVersion="
				+ GEN_IR_VERSION
				+ ", got "
				+ descriptor.requires.genIrVersion;
		}

		if (descriptor.requires.macroApiVersion != MACRO_API_VERSION) {
			return "backend macro API mismatch for " + label + ": expected macroApiVersion=" + MACRO_API_VERSION + ", got "
				+ descriptor.requires.macroApiVersion;
		}

		if (descriptor.requires.hostCaps == null) {
			return "invalid backend registration: requires.hostCaps is required for " + label;
		}

		var index = 0;
		for (hostCap in descriptor.requires.hostCaps) {
			final normalized = hostCap == null ? "" : StringTools.trim(hostCap);
			if (normalized.length == 0) {
				return "invalid backend host capability for " + label + " at index " + index + ": value must be non-empty";
			}
			index++;
		}

		return null;
	}
}
