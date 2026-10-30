import haxe.macro.Expr.Position;

/**
	Source positions shared by the export and import of one expression-macro call.

	A macro receives `haxe.macro.Expr` values whose `pos` says where each piece of syntax was
	written. hxhx's parser records a start offset, line, and column (`HxPos`) on some expression
	nodes only, and it keeps no end offset on any expression node. This class therefore makes two
	honest promises and no others:

	- Export: a node that owns a known `HxPos` gets `{file: <call file>, min: start, max: start}`.
	  The span is zero-width because the end is not known; it is never widened by guessing.
	  Callers decide what a node without its own position receives (see `MacroSyntaxExport`).
	- Import: when the macro returns a position this call exported, the original `HxPos` (with its
	  line and column) is restored. Any other position, for example one the macro created or one
	  in another file, cannot be mapped to a line and column without the source text, so the
	  importer receives `null` and applies its own documented fallback.

	Exact per-node source ranges are owned by `haxe_ocaml-9sj5p.2`.
**/
class MacroSyntaxPositions {
	final file:String;
	final exported:Map<Int, HxPos>;
	var first:Null<HxPos>;

	public function new(file:String) {
		if (file == null || file.length == 0)
			throw "macro syntax positions require the call's source file";
		this.file = file;
		exported = new Map();
		first = null;
	}

	public function getFile():String
		return file;

	/** True when the parser recorded where this node starts; `HxPos.unknown()` has line 0. */
	public static function isKnown(position:Null<HxPos>):Bool
		return position != null && position.getLine() > 0;

	/** Public position for a node start that hxhx owns. Rejects positions it cannot prove. */
	public function export(position:HxPos):Position {
		if (!isKnown(position))
			throw "macro syntax export: a source position was requested for syntax whose start is unknown";
		final index = position.getIndex();
		if (!exported.exists(index))
			exported.set(index, position);
		if (first == null)
			first = position;
		return {file: file, min: index, max: index};
	}

	/** The original `HxPos` for a position this call exported, or null for any other position. */
	public function resolve(position:Null<Position>):Null<HxPos> {
		if (position == null || position.file != file || position.min != position.max)
			return null;
		return exported.get(position.min);
	}

	/** The first exported position (the first argument's start), used as the import fallback. */
	public function getAnchor():Null<HxPos>
		return first;
}
