package hxhxmacros;

import String;
import haxe.Template as T;
import haxe.macro.*;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.DisplayMode;
import haxe.macro.Expr.ImportExpr;
import haxe.macro.Expr.ImportMode;
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
	  - `Context.getClassPath()` / `Context.resolvePath()`
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
		final classPath = Context.getClassPath();
		if (classPath == null || classPath.length == 0)
			Context.fatalError("runtime macro API probe: missing classpath snapshot", Context.currentPos());
		final resolvedThisModule = Context.resolvePath("hxhxmacros/RuntimeContextApiMacros.hx");
		if (resolvedThisModule == null || resolvedThisModule.length == 0)
			Context.fatalError("runtime macro API probe: failed to resolve runtime fixture path", Context.currentPos());

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
		Compiler.define("HXHX_RUNTIME_CONTEXT_CP", Std.string(classPath.length));
		Compiler.define("HXHX_RUNTIME_CONTEXT_RESOLVED", resolvedThisModule);

		return "cfg.version=" + config.version + ";args=" + config.args.length + ";std=" + config.stdPath.length + ";unicode="
			+ (supportsUnicode ? "1" : "0") + ";cp=" + classPath.length + ";file=" + info.file + ";display=None";
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

		final followedNullString = Context.follow(nullStringType);
		final followedNullStringText = TypeTools.toString(followedNullString);
		if (followedNullStringText != "Null<String>")
			Context.fatalError("runtime macro type probe: expected follow(Null<String>) to stay Null<String>", pos);

		final followedBool = TypeTools.follow(boolType);
		if (TypeTools.toString(followedBool) != "Bool")
			Context.fatalError("runtime macro type probe: expected TypeTools.follow(Bool) -> Bool", pos);

		if (!Context.unify(boolType, Context.resolveType(macro :Bool, pos)))
			Context.fatalError("runtime macro type probe: expected Bool to unify with Bool", pos);
		if (!Context.unify(nullStringType, stringType))
			Context.fatalError("runtime macro type probe: expected Null<String> to unify with String in builtin runtime model", pos);
		if (Context.unify(boolType, stringType))
			Context.fatalError("runtime macro type probe: unexpected Bool/String unification", pos);

		Compiler.define("HXHX_RUNTIME_TYPE_BOOL", boolTypeString);
		Compiler.define("HXHX_RUNTIME_TYPE_NULL", nullStringText);
		Compiler.define("HXHX_RUNTIME_TYPE_LITERAL", literalIntText);
		Compiler.define("HXHX_RUNTIME_TYPE_FOLLOW", followedNullStringText);
		Compiler.define("HXHX_RUNTIME_TYPE_UNIFY", "1");

		return "getType=String;resolveType="
			+ boolTypeString
			+ ";nullType="
			+ nullStringText
			+ ";typeof=Int;follow="
			+ followedNullStringText
			+ ";unify=1";
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

	static function renderImportMode(mode:ImportMode):String {
		return switch (mode) {
			case INormal: "INormal";
			case IAll: "IAll";
			case IAsName(alias): "IAsName(" + alias + ")";
		};
	}

	static function renderImport(expr:ImportExpr):String {
		final path = expr.path == null ? "" : [for (segment in expr.path) segment.name].join(".");
		return renderImportMode(expr.mode) + ":" + path;
	}

	public static function probeLocalImports():String {
		final pos = Context.currentPos();
		final imports = Context.getLocalImports();
		if (imports == null || imports.length == 0)
			Context.fatalError("runtime macro local-import probe: expected local imports snapshot", pos);

		final rendered = [for (expr in imports) renderImport(expr)];
		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");

		if (rendered.indexOf("INormal:String") < 0)
			Context.fatalError("runtime macro local-import probe: missing String import in " + summary, pos);
		if (rendered.indexOf("IAsName(T):haxe.Template") < 0)
			Context.fatalError("runtime macro local-import probe: missing aliased Template import in " + summary, pos);
		if (rendered.indexOf("IAll:haxe.macro") < 0)
			Context.fatalError("runtime macro local-import probe: missing wildcard haxe.macro import in " + summary, pos);

		Compiler.define("HXHX_RUNTIME_LOCAL_IMPORTS", summary);
		return summary;
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

	public static function probeCompilerInclude():String {
		final modulePath = "hxhxmacros.RuntimeContextApiMacros";
		Compiler.include(modulePath);
		Compiler.define("HXHX_RUNTIME_INCLUDE", modulePath);
		return "include=" + modulePath;
	}
}
