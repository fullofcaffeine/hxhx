package backend;

/**
	Backend identity and selection metadata.

	Why
	- `hxhx` needs a stable target contract that can describe both linked builtin backends
	  and plugin-provided backends without special-casing loader paths.
	- Descriptor metadata is the basis for deterministic backend precedence and ABI checks.

	What
	- `id`: user-facing target ID (for example `js-native`).
	- `implId`: concrete implementation ID (for example `builtin/js-native`).
	- `abiVersion`: backend ABI version declared by the implementation.
	- `priority`: precedence value when multiple implementations provide the same `id`.
	- `description`: short diagnostic text.
	- `capabilities`: emission/build capability flags consumed by Stage3 driver logic.
	- `requires`: compatibility requirements for IR/macro/host contracts.

	How
	- Keep this as a plain immutable typedef so descriptors are easy to emit, compare,
	  and serialize later when plugin discovery moves out-of-process.
**/
typedef TargetDescriptor = {
	final id:String;
	final implId:String;
	final abiVersion:Int;
	final priority:Int;
	final description:String;
	final capabilities:BackendCapabilities;
	final requires:TargetRequirements;
}
