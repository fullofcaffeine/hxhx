package backend.source;

/**
	Identify one source-native target without depending on its shared renderer.

	The enum lives outside `SourceTargetCommon` so request-owned render frames
	can carry a target without creating a generated OCaml module cycle back to
	the shared syntax kernel.
**/
enum SourceNativeTarget {
	Python;
	Java;
	Cs;
	Php;
	Lua;
}
