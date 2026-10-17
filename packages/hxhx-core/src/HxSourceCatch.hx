/**
	Immutable written catch facts, separate from the recursively stored body.
	An empty type hint records omitted syntax; typing selects its meaning later.
	Keeping bodies on HxExpr avoids a recursive module dependency through HxStmt.
**/
class HxSourceCatch {
	final name:String;
	final typeHint:String;
	final position:HxPos;

	public function new(name:String, typeHint:String, position:HxPos) {
		if (name == null || name.length == 0 || position == null)
			throw "source catch requires a name and source position";
		this.name = name;
		this.typeHint = typeHint == null ? "" : typeHint;
		this.position = position;
	}

	public function getName():String
		return name;

	public function getTypeHint():String
		return typeHint;

	public function getPosition():HxPos
		return position;

	/** Retain written annotation absence and the exact recorded start position in revisions. */
	public function getCanonicalIdentity():String
		return CompilerCacheIdentity.encode([
			name,
			typeHint,
			Std.string(position.getIndex()),
			Std.string(position.getLine()),
			Std.string(position.getColumn())
		]);
}
