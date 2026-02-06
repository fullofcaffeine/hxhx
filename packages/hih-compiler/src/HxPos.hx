/**
	Lightweight source position information for the Haxe-in-Haxe parser.

	Why:
	- Even a “subset” parser should produce actionable errors.
	- Downstream stages (typer, macros, codegen) will need stable positions to
	  report diagnostics that resemble the real Haxe compiler.

	What:
	- A 0-based index into the original source string.
	- 1-based line and column for human-friendly messages.

	How:
	- The lexer increments the cursor for every consumed character and updates
	  line/column on newlines.
**/
class HxPos {
	public final index:Int;
	public final line:Int;
	public final column:Int;

	public function new(index:Int, line:Int, column:Int) {
		this.index = index;
		this.line = line;
		this.column = column;
	}

	public function toString():String {
		return 'line ${line}, col ${column}';
	}

	/**
		Accessors for cross-module use.

		Why
		- The OCaml build uses dune `-opaque`, which can make direct field access
		  across compilation units fragile during bootstrap.
	**/
	public function getIndex():Int return index;
	public function getLine():Int return line;
	public function getColumn():Int return column;

	/**
		Sentinel “unknown” position.

		Why
		- Some bootstrap seams (notably the native frontend protocol) currently
		  return partial ASTs without statement-level positions.
		- We still want to construct a well-typed AST and report diagnostics in a
		  uniform shape, even when the location is not available.
	**/
	public static function unknown():HxPos {
		return new HxPos(0, 0, 0);
	}
}
