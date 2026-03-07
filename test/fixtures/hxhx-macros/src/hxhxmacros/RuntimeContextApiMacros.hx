package hxhxmacros;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.DisplayMode;
import haxe.macro.PositionTools;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
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
	  - compiler-seeded local-context queries (`getLocalModule`, `getLocalMethod`,
		`getLocalType`, `getExpectedType`, `getLocalClass`)

	What
	- Validates the slice and returns a stable summary string for external-host integration tests.

	Gotchas
	- Typed-expression support is still deliberately narrow:
	  `Context.typeExpr()` only covers the synthetic literal/parenthesized/simple-binop rung exercised
	  here, and `Context.getModule()` is still only an existence-only lookup.
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

	public static function probeLocalContextSnapshot():String {
		final pos = Context.currentPos();

		final localModule = Context.getLocalModule();
		if (localModule != "hxhxmacros.RuntimeContextApiMacros")
			Context.fatalError("runtime macro local context probe: expected local module snapshot", pos);

		final localMethod = Context.getLocalMethod();
		if (localMethod != "probeLocalContextSnapshot")
			Context.fatalError("runtime macro local context probe: expected local method snapshot", pos);

		final localType = Context.getLocalType();
		if (localType == null)
			Context.fatalError("runtime macro local context probe: expected local type snapshot", pos);
		final localTypeText = TypeTools.toString(localType);
		if (localTypeText != "String")
			Context.fatalError("runtime macro local context probe: expected local type String", pos);

		final expectedType = Context.getExpectedType();
		if (expectedType == null)
			Context.fatalError("runtime macro local context probe: expected expected-type snapshot", pos);
		final expectedTypeText = TypeTools.toString(expectedType);
		if (expectedTypeText != "Bool")
			Context.fatalError("runtime macro local context probe: expected expected type Bool", pos);

		final localClass = Context.getLocalClass();
		if (localClass == null || localClass.get().name != "String")
			Context.fatalError("runtime macro local context probe: expected local class String", pos);

		Compiler.define("HXHX_RUNTIME_LOCAL_MODULE", localModule);
		Compiler.define("HXHX_RUNTIME_LOCAL_METHOD", localMethod);
		Compiler.define("HXHX_RUNTIME_LOCAL_TYPE", localTypeText);
		Compiler.define("HXHX_RUNTIME_EXPECTED_TYPE", expectedTypeText);

		return "module=" + localModule + ";method=" + localMethod + ";localType=" + localTypeText + ";expectedType=" + expectedTypeText;
	}

	public static function probeModuleLookup():String {
		final pos = Context.currentPos();
		final modulePath = "hxhxmacros.RuntimeContextApiMacros";
		final moduleTypes = Context.getModule(modulePath);
		if (moduleTypes == null || moduleTypes.length == 0)
			Context.fatalError("runtime macro module probe: expected module lookup to resolve " + modulePath, pos);
		final typeText = TypeTools.toString(moduleTypes[0]);
		if (typeText != modulePath)
			Context.fatalError("runtime macro module probe: expected synthetic module type " + modulePath + " but got " + typeText, pos);

		Compiler.define("HXHX_RUNTIME_MODULE_LOOKUP", modulePath);
		return "moduleLookup=" + modulePath;
	}

	public static function probeTypedExprPlumbing():String {
		final pos = Context.currentPos();
		final typedExpr = Context.typeExpr(macro 1 + 2);
		final typedExprType = TypeTools.toString(typedExpr.t);
		if (typedExprType != "Int")
			Context.fatalError("runtime macro typed-expr probe: expected Int typed expr type", pos);

		var visitedNodes = 0;
		TypedExprTools.iter(typedExpr, function(_:haxe.macro.Type.TypedExpr):Void {
			visitedNodes++;
		});
		if (visitedNodes <= 0)
			Context.fatalError("runtime macro typed-expr probe: TypedExprTools.iter did not visit child nodes", pos);

		final typedExprString = TypedExprTools.toString(typedExpr, false);
		if (typedExprString.indexOf("+") < 0)
			Context.fatalError("runtime macro typed-expr probe: expected stringified binop expression", pos);

		final typedExprMapped = TypedExprTools.map(typedExpr, function(node:haxe.macro.Type.TypedExpr):haxe.macro.Type.TypedExpr {
			return node;
		});
		if (TypeTools.toString(typedExprMapped.t) != "Int")
			Context.fatalError("runtime macro typed-expr probe: identity map changed expression type", pos);

		Compiler.define("HXHX_RUNTIME_TYPED_EXPR", typedExprString);
		Compiler.define("HXHX_RUNTIME_TYPED_EXPR_VISITS", Std.string(visitedNodes));

		return "typedExpr=" + typedExprString + ";typedType=" + typedExprType + ";visits=" + visitedNodes;
	}
}
