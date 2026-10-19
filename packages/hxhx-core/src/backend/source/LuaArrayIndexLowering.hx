package backend.source;

/**
	Translate typed Haxe Array indices to the existing one-based Lua storage.
	The exact read or write catalog owns this choice. Native table accesses keep
	their original indices. Both operands remain once in their original order.
**/
class LuaArrayIndexLowering {
	final accesses:Array<TypedBackendArrayAccess> = [];

	public function new() {}

	/** Collect parent writes as well as reads before the structural rewrite rebuilds their operands. */
	public function add(access:Null<TypedBackendArrayAccess>):Void {
		if (access == null)
			return;
		final type = TyAliasExpansion.revealNonNullable(access.receiverType);
		final identity = type.getNominalIdentity();
		// Shared typing also represents the core Array<T> application before its
		// std declaration is loaded. Match that structured application, not display text.
		final owner = identity == null ? type.getUnresolvedPath() : identity.getCanonicalName();
		if (type.getTypeArguments().length == 1 && (owner == "Array" || owner == "haxe.Array"))
			accesses.push(access);
	}

	public function expression(original:HxExpr, rebuilt:HxExpr):HxExpr {
		return switch [original, rebuilt] {
			case [EArrayAccess(receiver, index), EArrayAccess(nextReceiver, nextIndex)]:
				var selected = false;
				for (access in accesses)
					if (access.receiver == receiver && access.index == index) {
						selected = true;
						break;
					}
				selected ? EArrayAccess(nextReceiver, EBinop("+", nextIndex, EInt(1))) : rebuilt;
			case _: rebuilt;
		};
	}
}
