package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.ast.OcamlDebugPos;

/**
	Maps Haxe byte offsets to stable generated-OCaml debug positions.

	File contents and line starts are cached per compiler process because the
	expression builder may request positions for many nodes in the same source.
**/
class OcamlSourcePositionMapper {
	#if macro
	static var sourceContentByFile:Map<String, String> = [];
	static var lineStartsByFile:Map<String, Array<Int>> = [];
	static var normalizedFileByFile:Map<String, String> = [];

	static function normalizeHaxeFilePath(file:String):String {
		if (file == null)
			return "";
		var normalized = StringTools.replace(file, "\\", "/");
		final cwd = StringTools.replace(Sys.getCwd(), "\\", "/");
		if (StringTools.startsWith(normalized, cwd)) {
			normalized = normalized.substr(cwd.length);
			if (StringTools.startsWith(normalized, "/"))
				normalized = normalized.substr(1);
		}
		return normalized;
	}

	static function ensureLineStarts(file:String):Array<Int> {
		final cached = lineStartsByFile.get(file);
		if (cached != null)
			return cached;

		final content = try {
			final cachedContent = sourceContentByFile.get(file);
			if (cachedContent != null)
				cachedContent
			else {
				final loaded = sys.io.File.getContent(file);
				sourceContentByFile.set(file, loaded);
				loaded;
			}
		} catch (_:Dynamic) {
			"";
		}

		final starts:Array<Int> = [0];
		for (index in 0...content.length) {
			if (content.charCodeAt(index) == "\n".code)
				starts.push(index + 1);
		}
		lineStartsByFile.set(file, starts);
		return starts;
	}

	/** Returns the one-based file, line, and column for a Haxe position. */
	public static function debugPosition(position:Position):Null<OcamlDebugPos> {
		final info = haxe.macro.Context.getPosInfos(position);
		if (info == null || info.file == null || info.file.length == 0)
			return null;

		final starts = ensureLineStarts(info.file);
		final min = info.min;
		if (min == null || min < 0)
			return null;

		var low = 0;
		var high = starts.length - 1;
		while (low < high) {
			final middle = Std.int((low + high + 1) / 2);
			if (starts[middle] <= min)
				low = middle;
			else
				high = middle - 1;
		}

		var normalizedFile = normalizedFileByFile.get(info.file);
		if (normalizedFile == null) {
			normalizedFile = normalizeHaxeFilePath(info.file);
			normalizedFileByFile.set(info.file, normalizedFile);
		}
		return {
			file: normalizedFile,
			line: low + 1,
			col: min - starts[low] + 1
		};
	}

	/** Whether wrapping this expression adds useful source information. */
	public static inline function shouldWrap(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TConst(_), TLocal(_), TTypeExpr(_): false;
			case _: true;
		}
	}
	#end
}
#end
