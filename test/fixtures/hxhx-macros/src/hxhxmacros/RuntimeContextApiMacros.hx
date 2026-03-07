package hxhxmacros;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.DisplayMode;
import haxe.macro.PositionTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
	Runtime macro probe for the external-host `haxe.macro.*` override slice.

	Why
	- `bxlg.9.5` is not about builtin entrypoints anymore; it is about whether macro modules that
	  import `haxe.macro.Compiler` / `haxe.macro.Context` can observe a sane runtime API surface.
	- This probe focuses on the current bring-up slice only:
	  - `Compiler.getConfiguration()`
	  - `Context.currentPos()`
	  - `Context.getDisplayMode()`
	  - `Context.getPosInfos()` / `Context.makePosition()`
	  - `PositionTools.getInfos()` / `PositionTools.make()`

	What
	- Validates the slice and returns a stable summary string for external-host integration tests.

	Gotchas
	- This intentionally does **not** touch typed APIs like `Context.getModule()` or `Context.typeExpr()`.
	  Those remain separate parity work.
**/
class RuntimeContextApiMacros {
	public static function probeConfigAndPosition():String {
		final config = Compiler.getConfiguration();
		if (config == null)
			Context.fatalError("runtime macro API probe: missing compiler configuration", Context.currentPos());
		if (config.args == null || config.args.length == 0)
			Context.fatalError("runtime macro API probe: missing compiler args", Context.currentPos());
		if (config.stdPath == null || config.stdPath.length == 0)
			Context.fatalError("runtime macro API probe: missing std path", Context.currentPos());

		final supportsUnicode = config.platformConfig.supportsUnicode;
		final pos = Context.currentPos();
		final info = Context.getPosInfos(pos);
		if (info.file == null || info.file.length == 0)
			Context.fatalError("runtime macro API probe: empty currentPos file", pos);

		final rebuilt = Context.makePosition(info);
		final roundTripped = PositionTools.getInfos(rebuilt);
		if (roundTripped.file != info.file)
			Context.fatalError("runtime macro API probe: position roundtrip mismatch", pos);
		final rebuiltAgain = PositionTools.make(roundTripped);
		if (rebuiltAgain == null)
			Context.fatalError("runtime macro API probe: PositionTools.make returned null", pos);

		final displayMode = Context.getDisplayMode();
		switch (displayMode) {
			case None:
			case _:
				Context.fatalError("runtime macro API probe: expected DisplayMode.None in external-host bring-up", pos);
		}

		Compiler.define("HXHX_RUNTIME_CONTEXT_ARGS", Std.string(config.args.length));
		Compiler.define("HXHX_RUNTIME_CONTEXT_FILE", info.file);
		Compiler.define("HXHX_RUNTIME_CONTEXT_MODE", "None");

		return "cfg.version=" + config.version + ";args=" + config.args.length + ";std=" + config.stdPath.length + ";unicode="
			+ (supportsUnicode ? "1" : "0") + ";file=" + info.file + ";display=None";
	}

	public static function probeBuiltinTypePlumbing():String {
		final pos = Context.currentPos();

		final stringType = Context.getType("String");
		if (TypeTools.toString(stringType) != "String")
			Context.fatalError("runtime macro type probe: expected getType(String) -> String", pos);

		final boolType = Context.resolveType(macro :Bool, pos);
		final boolTypeString = TypeTools.toString(boolType);
		if (boolTypeString != "Bool")
			Context.fatalError("runtime macro type probe: expected Bool resolveType result", pos);

		final nullStringType = Context.resolveType(macro :Null<String>, pos);
		final nullStringComplex = TypeTools.toComplexType(nullStringType);
		if (nullStringComplex == null)
			Context.fatalError("runtime macro type probe: expected Null<String> complex type to exist", pos);
		final nullStringText = TypeTools.toString(nullStringType);
		if (nullStringText != "Null<String>")
			Context.fatalError("runtime macro type probe: expected Null<String> complex type", pos);

		final literalIntType:Type = Context.typeof(macro 1 + 2);
		final literalIntText = TypeTools.toString(literalIntType);
		if (literalIntText != "Int")
			Context.fatalError("runtime macro type probe: expected typeof integer add -> Int but got " + literalIntText, pos);

		Compiler.define("HXHX_RUNTIME_TYPE_BOOL", boolTypeString);
		Compiler.define("HXHX_RUNTIME_TYPE_NULL", nullStringText);
		Compiler.define("HXHX_RUNTIME_TYPE_LITERAL", literalIntText);

		return "getType=String;resolveType=" + boolTypeString + ";nullType=" + nullStringText + ";typeof=Int";
	}
}
