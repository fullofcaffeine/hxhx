#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

/**
	Project macros that use the first `haxe.macro.Context` services: positions (`currentPos`,
	`makePosition`, `getPosInfos`), defines (`defined`, `definedValue`), parsing (`parse`,
	`parseInlineString`), and `error`.

	The `Context` import and the macro bodies are inside `#if macro`, a usual Haxe idiom. Upstream
	never types a macro body outside the macro context, so its output is the same either way. hxhx
	still types and emits macro classes into the target program (haxe_ocaml-q3mio), and an emitted
	`haxe.macro.Context` pulls in `haxe.macro.Type`, whose `TLazy` the Stage3 emitter cannot
	represent (haxe_ocaml-fmiag). The guard keeps both out of the target program; the plugin
	compiles in the macro context and runs the real bodies.
**/
class ContextProbe {
	/** `callerFile` is the end of the caller's file name; the file name stays out of this source. */
	public static macro function describe(callerFile:String):Expr {
		#if macro
		final here = Context.getPosInfos(Context.currentPos());
		final made = Context.getPosInfos(Context.makePosition({min: 3, max: 9, file: "made/file.hx"}));
		final odd = Context.getPosInfos(Context.makePosition({min: 7, max: 2, file: ""}));
		final parts = [
			"current " + StringTools.endsWith(here.file, callerFile),
			"made " + made.file + " " + made.min + "-" + made.max,
			"odd '" + odd.file + "' " + odd.min + "-" + odd.max,
			"flag " + Context.defined("probe_flag"),
			"dashed " + Context.defined("probe-dashed"),
			"missing " + Context.defined("probe_missing"),
			"value " + Context.definedValue("probe_value"),
			"flagValue " + Context.definedValue("probe_flag"),
			// The value of an undefined name is null. Concatenating a null String prints garbage in
			// Stage3-emitted plugin code, so the line prints the comparison instead.
			"missingValue null " + (Context.definedValue("probe_missing") == null)
		];
		return macro $v{parts.join("\n")};
		#else
		return null;
		#end
	}

	public static macro function inlined():Expr {
		#if macro
		return Context.parseInlineString("[1, 2, 3].length + 40", Context.currentPos());
		#else
		return null;
		#end
	}

	public static macro function parsed():Expr {
		#if macro
		return Context.parse("'pa' + 'rse'", Context.currentPos());
		#else
		return null;
		#end
	}

	/** Report `message` at the code points `min`..`max` of `file`. */
	public static macro function fail(message:String, file:String, min:Int, max:Int):Expr {
		#if macro
		Context.error(message, Context.makePosition({min: min, max: max, file: file}));
		#end
		return null;
	}
}
