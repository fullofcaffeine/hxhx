package backend.source;

/** Emit the native keyword around the caller's statements without introducing a delegate. */
function render(kind:HxTargetScopeKind, target:SourceNativeTarget, indent:String, body:() -> Array<String>):Array<String> {
	if (target != Cs)
		throw "C# syntax scope reached another target";
	final keyword = switch kind {
		case CsUnsafe: "unsafe";
	};
	return [indent + keyword].concat(body());
}
