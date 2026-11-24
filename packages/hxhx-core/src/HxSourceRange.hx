/**
	One written source range, as upstream Haxe 4.3.7 records a position.

	Why
	- A macro reads the exact place each argument was written (`Context.getPosInfos`), and
	  diagnostics print it as `File.hx:3: characters 23-27`. `HxPos` records a start only, with
	  no end and no file (`docs/00-project/MACRO_SOURCE_POSITIONS_PLAN.md`).

	What
	- `file` is the file name as upstream spells it: the class-path entry joined with the module
	  path, for example `A.hx` or `src/pack/Mod.hx`. It is not normalized.
	- `min` and `max` count Unicode code points from the start of the original file text; `max`
	  is exclusive. Upstream's lexer measures with `Sedlexing.Utf8`, so a non-BMP character is one
	  unit (`src/syntax/lexer.ml`, lines 20-21 and 297-301; `src/core/globals.ml`, lines 1-3).
	- Any values are kept as given. Upstream accepts `min > max`, a negative `min`, and an empty
	  file (`Context.makePosition`, `src/macro/macroApi.ml`, lines 1981-1986). Only `min == -1`
	  has a meaning: the position is unknown (`null_pos`, `src/core/globals.ml`, line 36).

	The value is immutable. Line and column text comes from `HxLineTable`.
**/
class HxSourceRange {
	public final file:String;
	public final min:Int;
	public final max:Int;

	public function new(file:String, min:Int, max:Int) {
		if (file == null)
			throw "HxSourceRange requires a file name (an empty name is allowed)";
		this.file = file;
		this.min = min;
		this.max = max;
	}

	/** Upstream's unknown position: file `?`, `min` and `max` are -1. */
	public static function unknown():HxSourceRange
		return new HxSourceRange("?", -1, -1);

	public function getFile():String
		return file;

	public function getMin():Int
		return min;

	public function getMax():Int
		return max;

	/** Whether this is the unknown position (`min == -1`), as upstream decides it. */
	public function isUnknown():Bool
		return min == -1;

	public function equals(other:Null<HxSourceRange>):Bool
		return other != null && other.file == file && other.min == min && other.max == max;

	public function toString():String
		return file + ":" + min + "-" + max;
}
