package hxhxmacros;

import String;
import haxe.Template as T;
import haxe.io.Bytes;
import sys.io.File;

using StringTools;
using haxe.io.Path;

import haxe.macro.*;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.DisplayMode;
import haxe.macro.Expr.ImportExpr;
import haxe.macro.Expr.ImportMode;
import haxe.macro.Expr.ExprDef;
import haxe.macro.Expr.Constant;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.TypeDefinition;
import haxe.macro.Expr.TypePath;
import haxe.macro.PositionTools;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import haxe.macro.TypeTools;
import hxhxmacrohost.api.RuntimeMacroTypes;

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
		`getLocalType`, `getExpectedType`, `getLocalClass`, `getLocalTVars`)
	  - compiler-owned warning/info message snapshots

	What
	- Validates the slice and returns a stable summary string for external-host integration tests.

	Gotchas
	- Typed-expression support is still deliberately narrow:
	  `Context.typeExpr()` only covers the synthetic literal/parenthesized/simple-binop rung exercised
	  here, `Context.getModule()` remains a narrow synthetic module lookup, and `Context.getType()`
	  only resolves builtins plus exact qualified type paths.
**/
class RuntimeContextApiMacros {
	static function exprIsIntLiteral(e:Null<Expr>, expected:String):Bool {
		if (e == null)
			return false;
		return switch (e.expr) {
			case EConst(CInt(value, _)): value == expected;
			case _: false;
		}
	}

	static function exprIsStringLiteral(e:Null<Expr>, expected:String):Bool {
		if (e == null)
			return false;
		return switch (e.expr) {
			case EConst(CString(value, _)): value == expected;
			case _: false;
		}
	}

	static function exprIsIdent(e:Null<Expr>, expected:String):Bool {
		if (e == null)
			return false;
		return switch (e.expr) {
			case EConst(CIdent(value)): value == expected;
			case _: false;
		}
	}

	static function exprHasRenderBodyShape(e:Null<Expr>):Bool {
		if (e == null)
			return false;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts.length == 2):
				switch (stmts[0].expr) {
					case EVars(vars) if (vars.length == 1 && vars[0].name == "prefix"):
						if (!exprIsIdent(vars[0].expr, "label")) false; else switch (stmts[1].expr) {
							case EReturn(ret):
								if (ret == null) false; else switch (ret.expr) {
									case EBinop(OpAdd, left, right):
										if (!exprIsIdent(right, "count")) false; else switch (left.expr) {
											case EBinop(OpAdd, prefixExpr, colonExpr): exprIsIdent(prefixExpr, "prefix") && exprIsStringLiteral(colonExpr, ":");
											case _:
												false;
										}
									case _:
										false;
								}
							case _:
								false;
						}
					case _:
						false;
				}
			case _:
				false;
		}
	}

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
		if (Context.containsDisplayPosition(pos))
			Context.fatalError("runtime macro API probe: expected containsDisplayPosition(currentPos) to be false without display state", pos);

		Compiler.define("HXHX_RUNTIME_CONTEXT_ARGS", Std.string(config.args.length));
		Compiler.define("HXHX_RUNTIME_CONTEXT_FILE", info.file);
		Compiler.define("HXHX_RUNTIME_CONTEXT_MODE", "None");
		Compiler.define("HXHX_RUNTIME_CONTEXT_CP", Std.string(classPath.length));
		Compiler.define("HXHX_RUNTIME_CONTEXT_RESOLVED", resolvedThisModule);

		return "cfg.version=" + config.version + ";args=" + config.args.length + ";std=" + config.stdPath.length + ";unicode="
			+ (supportsUnicode ? "1" : "0") + ";cp=" + classPath.length + ";file=" + info.file + ";display=None";
	}

	public static function probeAfterInitMacros():String {
		final pos = Context.currentPos();
		final order = new Array<String>();
		Context.onAfterInitMacros(function():Void {
			order.push("callback");
			Compiler.define("HXHX_RUNTIME_AFTER_INIT", "ok");
		});
		order.push("after");
		final summary = order.join(";");
		if (summary != "callback;after")
			Context.fatalError("runtime macro after-init probe: expected immediate callback but got " + summary, pos);
		return "afterInit=" + summary;
	}

	public static function probeBuiltinTypePlumbing():String {
		final pos = Context.currentPos();
		function assertTypePos(label:String, t:Type, expectedSuffix:String):Void {
			final info = Context.getPosInfos(RuntimeMacroTypes.typePos(t));
			if (info.file == null || info.file.indexOf(expectedSuffix) < 0)
				Context.fatalError("runtime macro type probe: expected " + label + " source file " + expectedSuffix + " but got " + info.file, pos);
			if (info.min >= info.max)
				Context.fatalError("runtime macro type probe: expected non-empty source range for " + label, pos);
		}

		final stringType = Context.getType("String");
		if (TypeTools.toString(stringType) != "String")
			Context.fatalError("runtime macro type probe: expected getType(String) -> String", pos);
		final moduleType = Context.getType("hxhxmacros.RuntimeContextApiMacros");
		final moduleTypeText = TypeTools.toString(moduleType);
		if (moduleTypeText != "hxhxmacros.RuntimeContextApiMacros")
			Context.fatalError("runtime macro type probe: expected qualified getType result but got " + moduleTypeText, pos);
		final moduleEnumType = Context.getType("hxhxmacros.RuntimeModuleMembers.RuntimeModuleState");
		final moduleEnumTypeText = TypeTools.toString(moduleEnumType);
		if (moduleEnumTypeText != "hxhxmacros.RuntimeModuleMembers.RuntimeModuleState")
			Context.fatalError("runtime macro type probe: expected module enum lookup result but got " + moduleEnumTypeText, pos);
		final moduleTypedefType = Context.getType("hxhxmacros.RuntimeModuleMembers.RuntimeModuleData");
		final moduleTypedefTypeText = TypeTools.toString(moduleTypedefType);
		if (moduleTypedefTypeText != "hxhxmacros.RuntimeModuleMembers.RuntimeModuleData")
			Context.fatalError("runtime macro type probe: expected module typedef lookup result but got " + moduleTypedefTypeText, pos);
		final moduleAbstractType = Context.getType("hxhxmacros.RuntimeModuleMembers.RuntimeModuleId");
		final moduleAbstractTypeText = TypeTools.toString(moduleAbstractType);
		if (moduleAbstractTypeText != "hxhxmacros.RuntimeModuleMembers.RuntimeModuleId")
			Context.fatalError("runtime macro type probe: expected module abstract lookup result but got " + moduleAbstractTypeText, pos);
		assertTypePos("module type", moduleType, "RuntimeContextApiMacros.hx");
		assertTypePos("module enum type", moduleEnumType, "RuntimeModuleMembers.hx");
		assertTypePos("module typedef type", moduleTypedefType, "RuntimeModuleMembers.hx");
		assertTypePos("module abstract type", moduleAbstractType, "RuntimeModuleMembers.hx");

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
		Compiler.define("HXHX_RUNTIME_TYPE_MODULE", moduleTypeText);
		Compiler.define("HXHX_RUNTIME_TYPE_MODULE_ENUM", moduleEnumTypeText);
		Compiler.define("HXHX_RUNTIME_TYPE_MODULE_TYPEDEF", moduleTypedefTypeText);
		Compiler.define("HXHX_RUNTIME_TYPE_MODULE_ABSTRACT", moduleAbstractTypeText);

		return "getType=String;resolveType=" + boolTypeString + ";moduleType=" + moduleTypeText + ";nullType=" + nullStringText + ";typeof=Int;follow="
			+ followedNullStringText + ";unify=1;moduleEnumType=" + moduleEnumTypeText + ";moduleTypedefType=" + moduleTypedefTypeText
			+ ";moduleAbstractType=" + moduleAbstractTypeText;
	}

	public static function probeTypeParameterSubstitution():String {
		final pos = Context.currentPos();
		final tParam = RuntimeMacroTypes.typeParameter("T", [Context.getType("String")]);
		final funcType:Type = TFun([
			{
				name: "value",
				opt: false,
				t: tParam.t
			}
		], RuntimeMacroTypes.nullWrapped(tParam.t));
		final appliedFunc = TypeTools.applyTypeParameters(funcType, [tParam], [Context.getType("String")]);
		final appliedSummary = TypeTools.toString(appliedFunc);
		if (appliedSummary != "(String) -> Null<String>")
			Context.fatalError("runtime macro type-parameter probe: unexpected substituted summary " + appliedSummary, pos);

		final iterVisited = new Array<String>();
		TypeTools.iter(appliedFunc, function(inner:Type):Void {
			iterVisited.push(TypeTools.toString(inner));
		});
		final iterSummary = iterVisited.join("|");
		if (iterSummary != "String|Null<String>")
			Context.fatalError("runtime macro type-parameter probe: unexpected iter summary " + iterSummary, pos);

		final aliasRef = RuntimeMacroTypes.syntheticDefTypeRef(["synthetic"], "AliasBox", "AliasBox", [tParam], tParam.t);
		final followedAlias = TypeTools.follow(TType(aliasRef, [Context.getType("Bool")]));
		if (TypeTools.toString(followedAlias) != "Bool")
			Context.fatalError("runtime macro type-parameter probe: typedef follow mismatch", pos);

		final abstractRef = RuntimeMacroTypes.syntheticAbstractRef(["synthetic"], "AbstractBox", "AbstractBox", [tParam], tParam.t);
		final abstractTemplate = RuntimeMacroTypes.abstractType(abstractRef, [tParam.t]);
		final appliedAbstract = TypeTools.applyTypeParameters(abstractTemplate, [tParam], [Context.getType("String")]);
		final abstractSummary = TypeTools.toString(appliedAbstract);
		if (abstractSummary != "synthetic.AbstractBox<String>")
			Context.fatalError("runtime macro type-parameter probe: abstract substitution mismatch " + abstractSummary, pos);

		Compiler.define("HXHX_RUNTIME_TYPE_PARAMS", appliedSummary + ";" + iterSummary + ";Bool;" + abstractSummary);
		return "typeParams=" + appliedSummary + ";iter=" + iterSummary + ";typedef=Bool;abstract=" + abstractSummary;
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

	public static function probeCallArguments():String {
		final pos = Context.currentPos();
		final args = Context.getCallArguments();
		if (args == null || args.length != 3)
			Context.fatalError("runtime macro call-arguments probe: expected three call arguments", pos);

		switch (args[0].expr) {
			case EConst(CInt("1", _)):
			case _:
				Context.fatalError("runtime macro call-arguments probe: expected integer first arg", pos);
		}

		switch (args[1].expr) {
			case EBinop(OpAdd, left, right):
				switch ([left.expr, right.expr]) {
					case [EConst(CInt("2", _)), EConst(CInt("3", _))]:
					case _:
						Context.fatalError("runtime macro call-arguments probe: expected 2 + 3 second arg", pos);
				}
			case _:
				Context.fatalError("runtime macro call-arguments probe: expected binop second arg", pos);
		}

		switch (args[2].expr) {
			case EObjectDecl(fields):
				if (fields.length != 1 || fields[0].field != "ok")
					Context.fatalError("runtime macro call-arguments probe: expected object third arg", pos);
			case _:
				Context.fatalError("runtime macro call-arguments probe: expected object third arg", pos);
		}

		final summary = "1;(2+3);{ok:true}";
		Compiler.define("HXHX_RUNTIME_CALL_ARGUMENTS", summary);
		return "callArgs=" + summary;
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

	public static function probeLocalUsing():String {
		final pos = Context.currentPos();
		final usings = Context.getLocalUsing();
		if (usings == null || usings.length == 0)
			Context.fatalError("runtime macro local-using probe: expected local using snapshot", pos);

		final rendered = [for (cls in usings) TypeTools.toString(TInst(cls, []))];
		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");

		if (rendered.indexOf("StringTools") < 0)
			Context.fatalError("runtime macro local-using probe: missing StringTools using in " + summary, pos);
		if (rendered.indexOf("haxe.io.Path") < 0)
			Context.fatalError("runtime macro local-using probe: missing haxe.io.Path using in " + summary, pos);

		Compiler.define("HXHX_RUNTIME_LOCAL_USING", summary);
		return summary;
	}

	public static function probeLocalTVars():String {
		final pos = Context.currentPos();
		final tvars = Context.getLocalTVars();
		if (tvars == null || !tvars.exists("count") || !tvars.exists("label"))
			Context.fatalError("runtime macro local-tvars probe: expected local tvar snapshot", pos);

		final countVar = tvars.get("count");
		final labelVar = tvars.get("label");
		if (countVar == null || labelVar == null)
			Context.fatalError("runtime macro local-tvars probe: null tvar entries", pos);

		final countType = TypeTools.toString(countVar.t);
		final labelType = TypeTools.toString(labelVar.t);
		if (countType != "Int")
			Context.fatalError("runtime macro local-tvars probe: expected count:Int but got " + countType, pos);
		if (labelType != "String")
			Context.fatalError("runtime macro local-tvars probe: expected label:String but got " + labelType, pos);
		if (countVar.capture)
			Context.fatalError("runtime macro local-tvars probe: expected count capture=false", pos);
		if (!labelVar.capture)
			Context.fatalError("runtime macro local-tvars probe: expected label capture=true", pos);

		final rendered = [countVar.name + ":" + countType + ":" + countVar.id + ":" + (countVar.capture ? "capture" : "plain"),
			labelVar.name
			+ ":"
			+ labelType
			+ ":"
			+ labelVar.id
			+ ":"
			+ (labelVar.capture ? "capture" : "plain")];
		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");
		Compiler.define("HXHX_RUNTIME_LOCAL_TVARS", summary);
		return summary;
	}

	public static function probeModuleLookup():String {
		final pos = Context.currentPos();
		final modulePath = "hxhxmacros.RuntimeModuleMembers";
		final moduleTypes = Context.getModule(modulePath);
		if (moduleTypes == null || moduleTypes.length < 5)
			Context.fatalError("runtime macro module probe: expected module lookup to resolve " + modulePath, pos);
		final rendered = new Array<String>();
		for (t in moduleTypes) {
			final path = TypeTools.toString(t);
			rendered.push(path);
			switch (path) {
				case "hxhxmacros.RuntimeModuleMembers":
				case "hxhxmacros.RuntimeModuleHelper":
				case "hxhxmacros.RuntimeModuleState":
				case "hxhxmacros.RuntimeModuleData":
				case "hxhxmacros.RuntimeModuleId":
				case _:
					Context.fatalError("runtime macro module probe: unexpected member " + path, pos);
			}
		}
		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");
		for (expected in [
			"hxhxmacros.RuntimeModuleMembers",
			"hxhxmacros.RuntimeModuleHelper",
			"hxhxmacros.RuntimeModuleState",
			"hxhxmacros.RuntimeModuleData",
			"hxhxmacros.RuntimeModuleId"
		]) {
			if (rendered.indexOf(expected) < 0)
				Context.fatalError("runtime macro module probe: missing module member " + expected + " in " + summary, pos);
		}

		Compiler.define("HXHX_RUNTIME_MODULE_LOOKUP", summary);
		return "moduleLookup=" + summary;
	}

	public static function probeModuleFieldCarrier():String {
		final pos = Context.currentPos();
		final modulePath = "hxhxmacros.RuntimeModuleFieldCarrier";
		final moduleTypes = Context.getModule(modulePath);
		if (moduleTypes == null || moduleTypes.length == 0)
			Context.fatalError("runtime macro module-field probe: expected module lookup to resolve " + modulePath, pos);

		var sawCarrier = false;
		final rendered = new Array<String>();
		for (t in moduleTypes) {
			final classRef = RuntimeMacroTypes.moduleFieldsCarrierOf(t);
			if (classRef == null)
				continue;
			final classType = classRef.get();
			switch (classType.kind) {
				case KModuleFields(moduleName):
					if (moduleName != modulePath)
						Context.fatalError("runtime macro module-field probe: unexpected carrier module " + moduleName, pos);
				case _:
					Context.fatalError("runtime macro module-field probe: helper returned non-module carrier", pos);
			}
			sawCarrier = true;
			final statics = classType.statics.get();
			if (statics.length < 7)
				Context.fatalError("runtime macro module-field probe: expected synthetic module statics", pos);
			var sawRouter = false;
			var sawSchema = false;
			var sawRouteTag = false;
			var sawRetryCount = false;
			var sawFeatureEnabled = false;
			var sawRenderSummary = false;
			var sawSourceTag = false;
			for (field in statics) {
				rendered.push(field.name);
				if (field.name == "routerMarker")
					sawRouter = field.meta.has(":router");
				if (field.name == "schemaMarker")
					sawSchema = field.meta.has(":schema");
				if (field.name == "routerMarker" || field.name == "schemaMarker") {
					final summary = TypeTools.toString(field.type);
					if (summary != "() -> String")
						Context.fatalError("runtime macro module-field probe: expected zero-arg String function type for "
							+ field.name
							+ " but got "
							+ summary, pos);
				}
				if (field.name == "routeTag") {
					sawRouteTag = field.meta.has(":routeTag");
					final expr = field.expr();
					if (expr == null || TypedExprTools.toString(expr, false) != "\"router\"")
						Context.fatalError("runtime macro module-field probe: expected routeTag string expr", pos);
					if (TypeTools.toString(field.type) != "String")
						Context.fatalError("runtime macro module-field probe: expected routeTag type String", pos);
					switch (field.kind) {
						case FVar(_, AccNever):
						case _:
							Context.fatalError("runtime macro module-field probe: expected routeTag final kind", pos);
					}
				}
				if (field.name == "retryCount") {
					sawRetryCount = field.meta.has(":retry");
					final expr = field.expr();
					if (expr == null || TypedExprTools.toString(expr, false) != "3")
						Context.fatalError("runtime macro module-field probe: expected retryCount int expr", pos);
					if (TypeTools.toString(field.type) != "Int")
						Context.fatalError("runtime macro module-field probe: expected retryCount type Int", pos);
					switch (field.kind) {
						case FVar(_, AccNever):
						case _:
							Context.fatalError("runtime macro module-field probe: expected retryCount final kind", pos);
					}
				}
				if (field.name == "featureEnabled") {
					sawFeatureEnabled = field.meta.has(":enabled");
					final expr = field.expr();
					if (expr == null || TypedExprTools.toString(expr, false) != "true")
						Context.fatalError("runtime macro module-field probe: expected featureEnabled bool expr", pos);
					if (TypeTools.toString(field.type) != "Bool")
						Context.fatalError("runtime macro module-field probe: expected featureEnabled type Bool", pos);
					switch (field.kind) {
						case FVar(_, AccNormal):
						case _:
							Context.fatalError("runtime macro module-field probe: expected featureEnabled var kind", pos);
					}
				}
				if (field.name == "renderSummary") {
					sawRenderSummary = field.meta.has(":summary");
					if (field.expr() != null)
						Context.fatalError("runtime macro module-field probe: expected renderSummary expr to remain null in synthetic carrier", pos);
					switch (field.kind) {
						case FMethod(MethNormal):
						case _:
							Context.fatalError("runtime macro module-field probe: expected renderSummary method kind", pos);
					}
					final signature = TypeTools.toString(field.type);
					if (signature != "(String, Int) -> String")
						Context.fatalError("runtime macro module-field probe: expected renderSummary function type but got " + signature, pos);
				}
				if (field.name == "sourceTag") {
					sawSourceTag = field.meta.has(":sourceTag");
					if (field.expr() != null)
						Context.fatalError("runtime macro module-field probe: expected sourceTag expr fallback path", pos);
					if (TypeTools.toString(field.type) != "Dynamic")
						Context.fatalError("runtime macro module-field probe: expected sourceTag type Dynamic", pos);
					final fromSource = extractStringConstFromSource(field);
					if (fromSource != "from-source")
						Context.fatalError("runtime macro module-field probe: expected source fallback string but got " + Std.string(fromSource), pos);
					final posInfo = Context.getPosInfos(field.pos);
					if (posInfo.file == null || posInfo.file.indexOf("RuntimeModuleFieldCarrier.hx") < 0)
						Context.fatalError("runtime macro module-field probe: expected real source file position", pos);
					if (posInfo.min >= posInfo.max)
						Context.fatalError("runtime macro module-field probe: expected non-empty source position range", pos);
					switch (field.kind) {
						case FVar(_, AccNever):
						case _:
							Context.fatalError("runtime macro module-field probe: expected sourceTag final kind", pos);
					}
				}
			}
			if (!sawRouter)
				Context.fatalError("runtime macro module-field probe: missing :router metadata", pos);
			if (!sawSchema)
				Context.fatalError("runtime macro module-field probe: missing :schema metadata", pos);
			if (!sawRouteTag)
				Context.fatalError("runtime macro module-field probe: missing :routeTag metadata", pos);
			if (!sawRetryCount)
				Context.fatalError("runtime macro module-field probe: missing :retry metadata", pos);
			if (!sawFeatureEnabled)
				Context.fatalError("runtime macro module-field probe: missing :enabled metadata", pos);
			if (!sawRenderSummary)
				Context.fatalError("runtime macro module-field probe: missing :summary metadata", pos);
			if (!sawSourceTag)
				Context.fatalError("runtime macro module-field probe: missing :sourceTag metadata", pos);
		}

		if (!sawCarrier)
			Context.fatalError("runtime macro module-field probe: expected KModuleFields carrier", pos);

		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");
		Compiler.define("HXHX_RUNTIME_MODULE_FIELDS", summary);
		return "moduleFields=" + summary;
	}

	public static function probeBuildFieldsSnapshot():String {
		final pos = Context.currentPos();
		final fields = Context.getBuildFields();
		if (fields == null || fields.length != 3)
			Context.fatalError("runtime macro build-fields probe: expected three fields", pos);
		final rendered = new Array<String>();
		for (field in fields) {
			final info = Context.getPosInfos(field.pos);
			if (info.file == null || info.file.indexOf("RuntimeBuildFieldCarrier.hx") < 0)
				Context.fatalError("runtime macro build-fields probe: expected real source file for " + field.name, pos);
			if (info.min >= info.max)
				Context.fatalError("runtime macro build-fields probe: expected non-empty source range for " + field.name, pos);
			final metaNames = [for (entry in (field.meta == null ? [] : field.meta)) entry.name];
			final metaSummary = metaNames.join("|");
			switch (field.name) {
				case "answer":
					if (field.access == null || field.access.indexOf(AFinal) < 0)
						Context.fatalError("runtime macro build-fields probe: expected final access for answer", pos);
					switch (field.kind) {
						case FVar(t, e):
							if (TypeTools.toString(Context.resolveType(t, pos)) != "Int")
								Context.fatalError("runtime macro build-fields probe: expected Int type for answer", pos);
							if (!exprIsIntLiteral(e, "7")) Context.fatalError("runtime macro build-fields probe: expected answer expr 7", pos);
						case _:
							Context.fatalError("runtime macro build-fields probe: expected FVar for answer", pos);
					}
					if (metaSummary.indexOf(":fieldMeta") < 0)
						Context.fatalError("runtime macro build-fields probe: missing :fieldMeta on answer", pos);
				case "routeTag":
					switch (field.kind) {
						case FProp(get, set, t, e):
							if (get != "default" || set != "null")
								Context.fatalError("runtime macro build-fields probe: expected default/null property accessors", pos);
							if (TypeTools.toString(Context.resolveType(t, pos)) != "String")
								Context.fatalError("runtime macro build-fields probe: expected String type for routeTag", pos);
							if (!exprIsStringLiteral(e, "ready")) Context.fatalError("runtime macro build-fields probe: expected routeTag expr \"ready\"", pos);
						case _:
							Context.fatalError("runtime macro build-fields probe: expected FProp for routeTag", pos);
					}
					if (metaSummary.indexOf(":propMeta") < 0)
						Context.fatalError("runtime macro build-fields probe: missing :propMeta on routeTag", pos);
				case "render":
					switch (field.kind) {
						case FFun(fn):
							if (fn == null || fn.args == null || fn.args.length != 2)
								Context.fatalError("runtime macro build-fields probe: expected two render args", pos);
							if (fn.args[0].name != "label" || TypeTools.toString(Context.resolveType(fn.args[0].type, pos)) != "String")
								Context.fatalError("runtime macro build-fields probe: expected label:String arg", pos);
							if (fn.args[1].name != "count" || !fn.args[1].opt)
								Context.fatalError("runtime macro build-fields probe: expected optional count arg", pos);
							if (TypeTools.toString(Context.resolveType(fn.args[1].type, pos)) != "Int")
								Context.fatalError("runtime macro build-fields probe: expected count:Int arg", pos);
							if (!exprIsIntLiteral(fn.args[1].value, "3"))
								Context.fatalError("runtime macro build-fields probe: expected count default 3", pos);
							if (fn.ret == null || TypeTools.toString(Context.resolveType(fn.ret, pos)) != "String")
								Context.fatalError("runtime macro build-fields probe: expected render return String", pos);
							if (fn.expr == null)
								Context.fatalError("runtime macro build-fields probe: expected render body expr", pos);
							if (!exprHasRenderBodyShape(fn.expr)) Context.fatalError("runtime macro build-fields probe: expected render body snapshot", pos);
						case _:
							Context.fatalError("runtime macro build-fields probe: expected FFun for render", pos);
					}
					if (metaSummary.indexOf(":funMeta") < 0)
						Context.fatalError("runtime macro build-fields probe: missing :funMeta on render", pos);
				case _:
					Context.fatalError("runtime macro build-fields probe: unexpected field " + field.name, pos);
			}
			rendered.push(field.name + "=" + metaSummary);
		}
		rendered.sort(function(a:String, b:String):Int {
			return Reflect.compare(a, b);
		});
		final summary = rendered.join(";");
		Compiler.define("HXHX_RUNTIME_BUILD_FIELDS", summary);
		return "buildFields=" + summary;
	}

	static function findField(fields:Array<haxe.macro.Type.ClassField>, name:String):Null<haxe.macro.Type.ClassField> {
		if (fields == null || name == null)
			return null;
		for (field in fields)
			if (field != null && field.name == name)
				return field;
		return null;
	}

	public static function probeSyntheticTypeStatics():String {
		final pos = Context.currentPos();
		final classType = Context.getType("hxhxmacros.RuntimeSyntheticStatics");
		final classRef = RuntimeMacroTypes.classRefOf(classType);
		if (classRef == null)
			Context.fatalError("runtime macro synthetic statics probe: expected class ref", pos);
		final classStatics = classRef.get().statics.get();
		final classLabel = findField(classStatics, "classLabel");
		final classBuilder = findField(classStatics, "buildTag");
		if (classLabel == null || classBuilder == null)
			Context.fatalError("runtime macro synthetic statics probe: missing class statics", pos);
		if (!classLabel.meta.has(":classLabel"))
			Context.fatalError("runtime macro synthetic statics probe: missing :classLabel metadata", pos);
		if (!classBuilder.meta.has(":classSummary"))
			Context.fatalError("runtime macro synthetic statics probe: missing :classSummary metadata", pos);
		final classLabelExpr = classLabel.expr();
		if (classLabelExpr == null || TypedExprTools.toString(classLabelExpr, false) != "\"class-label\"")
			Context.fatalError("runtime macro synthetic statics probe: expected classLabel expr", pos);
		if (TypeTools.toString(classLabel.type) != "String")
			Context.fatalError("runtime macro synthetic statics probe: expected classLabel type String", pos);
		if (classBuilder.expr() != null)
			Context.fatalError("runtime macro synthetic statics probe: expected buildTag expr to remain null", pos);
		if (TypeTools.toString(classBuilder.type) != "(String, Int) -> String")
			Context.fatalError("runtime macro synthetic statics probe: expected buildTag function type", pos);
		final classPos = Context.getPosInfos(classLabel.pos);
		if (classPos.file == null || classPos.file.indexOf("RuntimeSyntheticStatics.hx") < 0 || classPos.min >= classPos.max)
			Context.fatalError("runtime macro synthetic statics probe: expected real class static position", pos);

		final abstractType = Context.getType("hxhxmacros.RuntimeSyntheticStatics.RuntimeSyntheticAbstract");
		final abstractImpl = RuntimeMacroTypes.abstractImplClassRefOf(abstractType);
		if (abstractImpl == null)
			Context.fatalError("runtime macro synthetic statics probe: expected abstract impl statics carrier", pos);
		final abstractStatics = abstractImpl.get().statics.get();
		final abstractLabel = findField(abstractStatics, "abstractLabel");
		final abstractRender = findField(abstractStatics, "renderTag");
		if (abstractLabel == null || abstractRender == null)
			Context.fatalError("runtime macro synthetic statics probe: missing abstract statics", pos);
		if (!abstractLabel.meta.has(":abstractLabel"))
			Context.fatalError("runtime macro synthetic statics probe: missing :abstractLabel metadata", pos);
		if (!abstractRender.meta.has(":abstractSummary"))
			Context.fatalError("runtime macro synthetic statics probe: missing :abstractSummary metadata", pos);
		final abstractLabelExpr = abstractLabel.expr();
		if (abstractLabelExpr == null || TypedExprTools.toString(abstractLabelExpr, false) != "\"abstract-label\"")
			Context.fatalError("runtime macro synthetic statics probe: expected abstractLabel expr", pos);
		if (TypeTools.toString(abstractLabel.type) != "String")
			Context.fatalError("runtime macro synthetic statics probe: expected abstractLabel type String", pos);
		if (abstractRender.expr() != null)
			Context.fatalError("runtime macro synthetic statics probe: expected renderTag expr to remain null", pos);
		if (TypeTools.toString(abstractRender.type) != "(String, Bool) -> String")
			Context.fatalError("runtime macro synthetic statics probe: expected renderTag function type", pos);
		final abstractPos = Context.getPosInfos(abstractLabel.pos);
		if (abstractPos.file == null || abstractPos.file.indexOf("RuntimeSyntheticStatics.hx") < 0 || abstractPos.min >= abstractPos.max)
			Context.fatalError("runtime macro synthetic statics probe: expected real abstract static position", pos);

		final summary = "class=buildTag,classLabel;abstract=abstractLabel,renderTag";
		Compiler.define("HXHX_RUNTIME_TYPE_STATICS", summary);
		return "typeStatics=" + summary;
	}

	static function extractStringConstFromSource(field:haxe.macro.Type.ClassField):Null<String> {
		if (field == null)
			return null;
		final posInfos = Context.getPosInfos(field.pos);
		if (posInfos == null || posInfos.file == null || posInfos.file.length == 0)
			return null;
		final content = try File.getContent(posInfos.file) catch (_:haxe.io.Error) {
			null;
		} catch (_:String) {
			null;
		}
		if (content == null)
			return null;
		var min = posInfos.min;
		var max = posInfos.max;
		if (min < 0)
			min = 0;
		if (max > content.length)
			max = content.length;
		if (min >= max)
			return null;
		final eq = content.indexOf("=", min);
		if (eq == -1 || eq >= max)
			return null;
		var i = eq + 1;
		while (i < max && content.charCodeAt(i) != '"'.code)
			i += 1;
		if (i >= max)
			return null;
		i += 1;
		final out = new StringBuf();
		var escaping = false;
		while (i < max) {
			final c = content.charCodeAt(i);
			if (escaping) {
				escaping = false;
				out.addChar(c);
				i += 1;
				continue;
			}
			if (c == "\\".code) {
				escaping = true;
				i += 1;
				continue;
			}
			if (c == '"'.code)
				return out.toString();
			out.addChar(c);
			i += 1;
		}
		return null;
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

		final roundTrippedExpr = Context.getTypedExpr(typedExpr);
		switch (roundTrippedExpr.expr) {
			case EBinop(OpAdd, left, right):
				switch ([left.expr, right.expr]) {
					case [EConst(CInt("1", _)), EConst(CInt("2", _))]:
					case _:
						Context.fatalError("runtime macro typed-expr probe: getTypedExpr roundtrip mismatch", pos);
				}
			case _:
				Context.fatalError("runtime macro typed-expr probe: expected binop from getTypedExpr", pos);
		}

		Compiler.define("HXHX_RUNTIME_TYPED_EXPR", typedExprString);
		Compiler.define("HXHX_RUNTIME_TYPED_EXPR_VISITS", Std.string(visitedNodes));

		return "typedExpr=" + typedExprString + ";typedType=" + typedExprType + ";visits=" + visitedNodes;
	}

	public static function probeTypedVarExprPlumbing():String {
		final pos = Context.currentPos();
		final typedExpr = Context.typeExpr(macro var prefix:String = "ready");
		final typedExprType = TypeTools.toString(typedExpr.t);
		if (typedExprType != "Void")
			Context.fatalError("runtime macro typed-var probe: expected Void typed expr type", pos);

		final varType = switch (typedExpr.expr) {
			case TVar(tvar, initExpr):
				if (TypeTools.toString(tvar.t) != "String")
					Context.fatalError("runtime macro typed-var probe: expected String TVar type", pos);
				switch (initExpr == null ? null : initExpr.expr) {
					case TConst(TString("ready")):
					case _:
						Context.fatalError("runtime macro typed-var probe: expected string initializer", pos);
				}
				TypeTools.toString(tvar.t);
			case _:
				Context.fatalError("runtime macro typed-var probe: expected TVar typed expr", pos);
				"";
		}

		var visitedNodes = 0;
		TypedExprTools.iter(typedExpr, function(_:haxe.macro.Type.TypedExpr):Void {
			visitedNodes++;
		});
		if (visitedNodes <= 0)
			Context.fatalError("runtime macro typed-var probe: TypedExprTools.iter did not visit initializer", pos);

		final typedExprString = TypedExprTools.toString(typedExpr, false);
		if (typedExprString.indexOf("var prefix") < 0)
			Context.fatalError("runtime macro typed-var probe: expected stringified var declaration", pos);

		final typedExprMapped = TypedExprTools.map(typedExpr, function(node:haxe.macro.Type.TypedExpr):haxe.macro.Type.TypedExpr {
			return node;
		});
		if (TypeTools.toString(typedExprMapped.t) != "Void")
			Context.fatalError("runtime macro typed-var probe: identity map changed outer expression type", pos);

		final roundTrippedExpr = Context.getTypedExpr(typedExpr);
		switch (roundTrippedExpr.expr) {
			case EVars(vars) if (vars.length == 1 && vars[0].name == "prefix"):
				if (vars[0].type == null)
					Context.fatalError("runtime macro typed-var probe: expected roundtrip type hint", pos);
				switch (vars[0].expr == null ? null : vars[0].expr.expr) {
					case EConst(CString("ready", _)):
					case _:
						Context.fatalError("runtime macro typed-var probe: roundtrip initializer mismatch", pos);
				}
			case _:
				Context.fatalError("runtime macro typed-var probe: expected EVars roundtrip", pos);
		}

		Compiler.define("HXHX_RUNTIME_TYPED_VAR_EXPR", typedExprString);
		Compiler.define("HXHX_RUNTIME_TYPED_VAR_TYPE", varType);

		return "typedVarExpr=" + typedExprString + ";typedVarType=" + typedExprType + ";varType=" + varType + ";visits=" + visitedNodes;
	}

	public static function probeMainExpr():String {
		final pos = Context.currentPos();
		final mainExpr = Context.getMainExpr();
		if (mainExpr == null)
			Context.fatalError("runtime macro main-expr probe: expected seeded main expression", pos);

		final rendered = TypedExprTools.toString(mainExpr, false);
		if (rendered.indexOf("+") < 0)
			Context.fatalError("runtime macro main-expr probe: expected binop main expression", pos);

		final roundTripped = Context.getTypedExpr(mainExpr);
		switch (roundTripped.expr) {
			case EBinop(OpAdd, left, right):
				switch ([left.expr, right.expr]) {
					case [EConst(CInt("1", _)), EConst(CInt("2", _))]:
					case _:
						Context.fatalError("runtime macro main-expr probe: getMainExpr roundtrip mismatch", pos);
				}
			case _:
				Context.fatalError("runtime macro main-expr probe: expected binop main expression", pos);
		}

		final typeText = TypeTools.toString(mainExpr.t);
		if (typeText != "Int")
			Context.fatalError("runtime macro main-expr probe: expected Int typed main expression", pos);

		Compiler.define("HXHX_RUNTIME_MAIN_EXPR", rendered);
		return "mainExpr=" + rendered + ";mainType=" + typeText;
	}

	public static function probeStoreExprPlumbing():String {
		final pos = Context.currentPos();
		final storedExpr = Context.storeExpr(macro "ok");
		switch (storedExpr.expr) {
			case EConst(CString("ok", _)):
			case _:
				Context.fatalError("runtime macro storeExpr probe: expected stored string expression", pos);
		}

		final storedTypedExpr = Context.storeTypedExpr(Context.typeExpr(macro 1 + 2));
		switch (storedTypedExpr.expr) {
			case EBinop(OpAdd, left, right):
				switch ([left.expr, right.expr]) {
					case [EConst(CInt("1", _)), EConst(CInt("2", _))]:
					case _:
						Context.fatalError("runtime macro storeExpr probe: storeTypedExpr roundtrip mismatch", pos);
				}
			case _:
				Context.fatalError("runtime macro storeExpr probe: expected typed-expression roundtrip", pos);
		}

		Compiler.define("HXHX_RUNTIME_STORE_EXPR", "ok");
		return "storeExpr=ok;storeTypedExpr=binop";
	}

	public static function probeCompilerInclude():String {
		final modulePath = "hxhxmacros.RuntimeContextApiMacros";
		Compiler.include(modulePath);
		Compiler.include("hxhxmacros", true, ["hxhxmacros.RuntimeContextApiMacros"], ["test/fixtures/hxhx-macros/src"], true);
		final included = [
			modulePath,
			"hxhxmacros.ArgsMacros",
			"hxhxmacros.BuildFieldMacros",
			"hxhxmacros.ExprMacroShim",
			"hxhxmacros.ExternalMacros",
			"hxhxmacros.FieldPrinterMacros",
			"hxhxmacros.HaxelibInitMacros",
			"hxhxmacros.PluginFixtureMacros",
			"hxhxmacros.ReturnFieldMacros"
		];
		final summary = included.join(";");
		Compiler.define("HXHX_RUNTIME_INCLUDE", summary);
		return "include=" + summary;
	}

	public static function probeCompilerMetadataRegistration():String {
		Compiler.addGlobalMetadata("", "@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())", true, true, false);
		Compiler.addGlobalMetadata("demo.Target", "@:demoMeta", false, true, true);
		Compiler.nullSafety("demo.strict", Strict, true);
		Compiler.registerCustomMetadata({
			metadata: ":demoCustom",
			doc: "runtime metadata probe"
		}, "runtime-probe");
		Compiler.define("HXHX_RUNTIME_METADATA", "ok");
		return "metadata=ok";
	}

	public static function probeOnTypeNotFoundRegistration():String {
		Context.onTypeNotFound(function(name:String) {
			return null;
		});
		Compiler.define("HXHX_RUNTIME_ON_TYPE_NOT_FOUND", "registered");
		return "onTypeNotFound=registered";
	}

	public static function registerOnTypeNotFoundDefineType():String {
		Context.onTypeNotFound(function(name:String) {
			if (name != "generated.runtime.RuntimeMissingType")
				return null;
			return {
				pack: ["generated", "runtime"],
				name: "RuntimeMissingType",
				pos: Context.currentPos(),
				meta: [],
				params: [],
				isExtern: false,
				fields: [],
				kind: TDClass(null, [], false, false, false)
			};
		});
		Compiler.define("HXHX_RUNTIME_ON_TYPE_NOT_FOUND", "semantic");
		return "onTypeNotFound=semantic";
	}

	public static function probeRegisterModuleDependency():String {
		final modulePath = "hxhxmacros.RuntimeContextApiMacros";
		final externFile = "runtime/macro-probe.txt";
		Context.registerModuleDependency(modulePath, externFile);
		Compiler.define("HXHX_RUNTIME_MODULE_DEP", modulePath + "->" + externFile);
		return "moduleDependency=" + modulePath + "->" + externFile;
	}

	public static function probeDefineType():String {
		final pos = Context.currentPos();
		final typeDef:TypeDefinition = {
			pack: ["generated", "runtime"],
			name: "RuntimeMacroDefined",
			pos: pos,
			meta: [],
			params: [],
			isExtern: false,
			fields: [],
			kind: TDClass(null, [], false, false, false)
		};
		Context.defineType(typeDef, "runtime/generated-defined.txt");
		Compiler.define("HXHX_RUNTIME_DEFINE_TYPE", "generated.runtime.RuntimeMacroDefined");
		return "defineType=generated.runtime.RuntimeMacroDefined";
	}

	public static function probeDefineModule():String {
		final pos = Context.currentPos();
		final primary:TypeDefinition = {
			pack: ["generated", "runtime"],
			name: "RuntimeMacroModule",
			pos: pos,
			meta: [],
			params: [],
			isExtern: false,
			fields: [],
			kind: TDClass(null, [], false, false, false)
		};
		final helper:TypeDefinition = {
			pack: ["generated", "runtime"],
			name: "RuntimeMacroHelper",
			pos: pos,
			meta: [],
			params: [],
			isExtern: false,
			fields: [],
			kind: TDClass(null, [], false, false, false)
		};
		final imports:Array<ImportExpr> = [
			{
				path: [{name: "haxe", pos: pos}, {name: "Template", pos: pos}],
				mode: IAsName("Tpl")
			}
		];
		final usings:Array<TypePath> = [
			{
				pack: [],
				name: "StringTools",
				params: [],
				sub: null
			}
		];
		Context.defineModule("generated.runtime.RuntimeMacroModule", [primary, helper], imports, usings);
		Compiler.define("HXHX_RUNTIME_DEFINE_MODULE", "generated.runtime.RuntimeMacroModule");
		return "defineModule=generated.runtime.RuntimeMacroModule";
	}

	public static function probeResources():String {
		final pos = Context.currentPos();
		final key = "runtime-macro-resource";
		final payload = Bytes.ofString("resource=ok");
		Context.addResource(key, payload);

		final resources = Context.getResources();
		if (resources == null || !resources.exists(key))
			Context.fatalError("runtime macro resource probe: missing resource " + key, pos);

		final roundTripped = resources.get(key);
		if (roundTripped == null)
			Context.fatalError("runtime macro resource probe: null resource payload", pos);

		final text = roundTripped.toString();
		if (text != "resource=ok")
			Context.fatalError("runtime macro resource probe: payload mismatch " + text, pos);

		Compiler.define("HXHX_RUNTIME_RESOURCE", text);
		return "resource=" + text;
	}

	public static function probeParse():String {
		final pos = Context.currentPos();
		final parsed = Context.parse("demo.call(1 + 2, new js.lib.ArrayBuffer(8), cast value, [1, 2], { ok: true })", pos);
		final inlineParsed = Context.parseInlineString("items[0] ? \"yes\" : \"no\"", pos);

		switch (parsed.expr) {
			case ECall(target, args):
				switch (target.expr) {
					case EField(owner, "call"):
						switch (owner.expr) {
							case EConst(CIdent("demo")):
							case _:
								Context.fatalError("runtime macro parse probe: expected demo.call target owner", pos);
						}
					case _:
						Context.fatalError("runtime macro parse probe: expected field call target", pos);
				}
				if (args.length != 5)
					Context.fatalError("runtime macro parse probe: expected five call args", pos);
				switch (args[0].expr) {
					case EBinop(OpAdd, left, right):
						switch ([left.expr, right.expr]) {
							case [EConst(CInt("1", _)), EConst(CInt("2", _))]:
							case _:
								Context.fatalError("runtime macro parse probe: expected integer add", pos);
						}
					case _:
						Context.fatalError("runtime macro parse probe: expected binop arg", pos);
				}
				switch (args[1].expr) {
					case ENew(tp, ctorArgs):
						if (tp.pack.join(".") != "js.lib" || tp.name != "ArrayBuffer" || ctorArgs.length != 1)
							Context.fatalError("runtime macro parse probe: expected ArrayBuffer ctor", pos);
					case _:
						Context.fatalError("runtime macro parse probe: expected new expr arg", pos);
				}
				switch (args[2].expr) {
					case ECast(inner, null):
						switch (inner.expr) {
							case EConst(CIdent("value")):
							case _:
								Context.fatalError("runtime macro parse probe: expected cast value", pos);
						}
					case _:
						Context.fatalError("runtime macro parse probe: expected cast expr arg", pos);
				}
				switch (args[3].expr) {
					case EArrayDecl(values):
						if (values.length != 2) Context.fatalError("runtime macro parse probe: expected array decl arg", pos);
					case _:
						Context.fatalError("runtime macro parse probe: expected array decl", pos);
				}
				switch (args[4].expr) {
					case EObjectDecl(fields):
						if (fields.length != 1 || fields[0].field != "ok") Context.fatalError("runtime macro parse probe: expected object field", pos);
					case _:
						Context.fatalError("runtime macro parse probe: expected object decl", pos);
				}
			case _:
				Context.fatalError("runtime macro parse probe: expected call root", pos);
		}

		switch (inlineParsed.expr) {
			case ETernary(cond, thenExpr, elseExpr):
				switch (cond.expr) {
					case EArray(base, index):
						switch ([base.expr, index.expr]) {
							case [EConst(CIdent("items")), EConst(CInt("0", _))]:
							case _:
								Context.fatalError("runtime macro parse probe: expected array access ternary condition", pos);
						}
					case _:
						Context.fatalError("runtime macro parse probe: expected array access condition", pos);
				}
				switch ([thenExpr.expr, elseExpr.expr]) {
					case [EConst(CString("yes", _)), EConst(CString("no", _))]:
					case _:
						Context.fatalError("runtime macro parse probe: expected ternary string branches", pos);
				}
			case _:
				Context.fatalError("runtime macro parse probe: expected inline ternary", pos);
		}

		Compiler.define("HXHX_RUNTIME_PARSE", "call+inline");
		return "parse=call+inline";
	}

	public static function probeMessages():String {
		final pos = Context.currentPos();
		Context.warning("runtime-warning", pos);
		Context.info("runtime-info", pos);

		final messages = Context.getMessages();
		if (messages == null || messages.length < 2)
			Context.fatalError("runtime macro message probe: expected warning/info snapshot", pos);

		final rendered = [
			for (message in messages)
				switch (message) {
					case Warning(msg, p):
						"warning:" + msg + "@" + PositionTools.getInfos(p).file;
					case Info(msg, p):
						"info:" + msg + "@" + PositionTools.getInfos(p).file;
				}
		];
		final summary = rendered.join(";");
		if (summary.indexOf("warning:runtime-warning@") < 0)
			Context.fatalError("runtime macro message probe: missing warning in " + summary, pos);
		if (summary.indexOf("info:runtime-info@") < 0)
			Context.fatalError("runtime macro message probe: missing info in " + summary, pos);

		Context.filterMessages(function(message:Message):Bool {
			return switch (message) {
				case Warning(_, _): true;
				case Info(_, _): false;
			};
		});

		final filtered = Context.getMessages();
		if (filtered == null || filtered.length != 1)
			Context.fatalError("runtime macro message probe: expected one filtered warning", pos);
		switch (filtered[0]) {
			case Warning(msg, _):
				if (msg != "runtime-warning")
					Context.fatalError("runtime macro message probe: wrong filtered warning", pos);
			case _:
				Context.fatalError("runtime macro message probe: info survived filter", pos);
		}

		Compiler.define("HXHX_RUNTIME_MESSAGES", summary + ";filtered=warning");
		return summary + ";filtered=warning";
	}

	public static function probeMakeExprAndSignature():String {
		final pos = Context.currentPos();
		final expr = Context.makeExpr({
			ok: true,
			items: [1, 2],
			label: "demo"
		}, pos);

		switch (expr.expr) {
			case EObjectDecl(fields):
				if (fields.length != 3)
					Context.fatalError("runtime macro makeExpr probe: expected three object fields", pos);
			case _:
				Context.fatalError("runtime macro makeExpr probe: expected object decl", pos);
		}

		final sigA = Context.signature({ok: true, items: [1, 2], label: "demo"});
		final sigB = Context.signature({ok: true, items: [1, 2], label: "demo"});
		if (sigA == null || sigA.length != 32)
			Context.fatalError("runtime macro signature probe: expected md5-sized signature", pos);
		if (sigA != sigB)
			Context.fatalError("runtime macro signature probe: expected deterministic signature", pos);

		Compiler.define("HXHX_RUNTIME_MAKE_EXPR", "object");
		Compiler.define("HXHX_RUNTIME_SIGNATURE", sigA);
		return "makeExpr=object;signature=" + sigA;
	}

	public static function probeTimer():String {
		final end = Context.timer("runtime-probe");
		if (end == null)
			Context.fatalError("runtime macro timer probe: expected non-null timer closure", Context.currentPos());
		end();
		Compiler.define("HXHX_RUNTIME_TIMER", "ok");
		return "timer=ok";
	}
}
