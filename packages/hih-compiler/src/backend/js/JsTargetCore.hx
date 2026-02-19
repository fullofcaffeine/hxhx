package backend.js;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.ITargetCore;
import haxe.io.Path;

private typedef JsClassUnit = {
	final fullName:String;
	final jsRef:String;
	final decl:HxClassDecl;
};

/**
	Reusable JS target core for Stage3 builtin/promotion paths.

	Why
	- JS emission logic should be reusable across activation modes (builtin wrapper now,
	  plugin wrapper later) without duplicating codegen behavior.
	- This is the JS counterpart to `OcamlTargetCore` in the promotion model.

	What
	- Emits one JavaScript artifact from `GenIrProgram`.
	- Preserves current MVP semantics (`js-classic`, runtime prelude, explicit unsupported
	  expression failures via existing emitters).

	How
	- Move existing emission logic from `JsBackend` into this core class unchanged.
	- Keep wrapper backends thin so promotion is packaging-oriented.
**/
class JsTargetCore implements ITargetCore {
	public static inline var CORE_ID = "hxhx.js.target-core";

	public function new() {}

	public function coreId():String {
		return CORE_ID;
	}

	static function ensureDirectory(path:String):Void {
		if (path == null || path.length == 0) return;
		if (sys.FileSystem.exists(path)) return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path) ensureDirectory(parent);
		sys.FileSystem.createDirectory(path);
	}

	static function collectClassUnits(program:GenIrProgram):{ units:Array<JsClassUnit>, bySimpleName:haxe.ds.StringMap<String>, byFullName:haxe.ds.StringMap<String> } {
		final bySimpleName = new haxe.ds.StringMap<String>();
		final byFullName = new haxe.ds.StringMap<String>();
		final units = new Array<JsClassUnit>();
		final typedModules:Array<TypedModule> = program.getTypedModules();

		for (typed in typedModules) {
			final pm = typed.getParsed();
			final decl = pm.getDecl();
			final pkg = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = HxClassDecl.getName(cls);
				final fullName = (pkg == null || pkg.length == 0) ? className : (pkg + "." + className);
				if (byFullName.exists(fullName)) continue;
				final jsRef = JsNameMangler.classVarName(fullName);
				byFullName.set(fullName, jsRef);
				if (!bySimpleName.exists(className)) bySimpleName.set(className, jsRef);
				units.push({
					fullName: fullName,
					jsRef: jsRef,
					decl: cls
				});
			}
		}

		return {
			units: units,
			bySimpleName: bySimpleName,
			byFullName: byFullName
		};
	}

	static function simpleName(fullName:String):String {
		final parts = fullName == null ? [] : fullName.split(".");
		return parts.length == 0 ? fullName : parts[parts.length - 1];
	}

	static function emitRuntimePrelude(writer:JsWriter):Void {
		writer.writeln("var __hx_classes = Object.create(null);");
		writer.writeln("var Type = {");
		writer.pushIndent();
		writer.writeln("resolveClass: function (name) {");
		writer.pushIndent();
		writer.writeln("return Object.prototype.hasOwnProperty.call(__hx_classes, name) ? __hx_classes[name] : null;");
		writer.popIndent();
		writer.writeln("},");
		writer.writeln("getClassName: function (cls) {");
		writer.pushIndent();
		writer.writeln("return (cls && cls.__hx_name != null) ? String(cls.__hx_name) : null;");
		writer.popIndent();
		writer.writeln("},");
		writer.writeln("enumConstructor: function (value) {");
		writer.pushIndent();
		writer.writeln("if (value == null) return null;");
		writer.writeln("if (typeof value === \"string\") return value;");
		writer.writeln("if (typeof value === \"object\" && value.__hx_ctor != null) return String(value.__hx_ctor);");
		writer.writeln("return null;");
		writer.popIndent();
		writer.writeln("},");
		writer.writeln("enumIndex: function (value) {");
		writer.pushIndent();
		writer.writeln("if (value == null) return -1;");
		writer.writeln("if (typeof value === \"number\") return value | 0;");
		writer.writeln("if (typeof value === \"string\") return 0;");
		writer.writeln("if (typeof value === \"object\" && typeof value.__hx_index === \"number\") return value.__hx_index | 0;");
		writer.writeln("return -1;");
		writer.popIndent();
		writer.writeln("},");
		writer.writeln("enumParameters: function (value) {");
		writer.pushIndent();
		writer.writeln("if (value != null && typeof value === \"object\" && Array.isArray(value.__hx_params)) return value.__hx_params.slice();");
		writer.writeln("return [];");
		writer.popIndent();
		writer.writeln("}");
		writer.popIndent();
		writer.writeln("};");
	}

	static function emitClass(
		writer:JsWriter,
		unit:JsClassUnit,
		classRefs:haxe.ds.StringMap<String>,
		simpleNameRefs:haxe.ds.StringMap<String>
	):Void {
		writer.writeln("var " + unit.jsRef + " = {};");
		writer.writeln(unit.jsRef + ".__hx_name = " + JsNameMangler.quoteString(unit.fullName) + ";");
		writer.writeln("__hx_classes[" + JsNameMangler.quoteString(unit.fullName) + "] = " + unit.jsRef + ";");
		final simple = simpleName(unit.fullName);
		if (simpleNameRefs.get(simple) == unit.jsRef) {
			writer.writeln("__hx_classes[" + JsNameMangler.quoteString(simple) + "] = " + unit.jsRef + ";");
		}
		final staticScope = new JsFunctionScope(classRefs);

		for (field in HxClassDecl.getFields(unit.decl)) {
			if (!HxFieldDecl.getIsStatic(field)) continue;
			final suffix = JsNameMangler.propertySuffix(HxFieldDecl.getName(field));
			final init = HxFieldDecl.getInit(field);
			final value = init == null ? "null" : JsExprEmitter.emit(init, staticScope.exprScope());
			writer.writeln(unit.jsRef + suffix + " = " + value + ";");
		}

		for (fn in HxClassDecl.getFunctions(unit.decl)) {
			if (!HxFunctionDecl.getIsStatic(fn)) continue;

			final fnScope = new JsFunctionScope(classRefs);
			final params = new Array<String>();
			for (a in HxFunctionDecl.getArgs(fn)) {
				params.push(fnScope.declareLocal(HxFunctionArg.getName(a)));
			}

			final suffix = JsNameMangler.propertySuffix(HxFunctionDecl.getName(fn));
			writer.writeln(unit.jsRef + suffix + " = function(" + params.join(", ") + ") {");
			writer.pushIndent();
			JsStmtEmitter.emitFunctionBody(writer, HxFunctionDecl.getBody(fn), fnScope);
			writer.popIndent();
			writer.writeln("};");
		}
	}

	static function resolveMainRef(main:String, bySimpleName:haxe.ds.StringMap<String>, byFullName:haxe.ds.StringMap<String>):Null<String> {
		if (main == null || main.length == 0) return null;

		final direct = byFullName.get(main);
		if (direct != null) return direct;

		final parts = main.split(".");
		if (parts.length == 0) return null;
		return bySimpleName.get(parts[parts.length - 1]);
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		final hint = context.outputFileHint;
		final outputPath = (hint != null && hint.length > 0) ? hint : Path.join([context.outputDir, "out.js"]);
		final outputDir = Path.directory(outputPath);
		if (outputDir != null && outputDir.length > 0) ensureDirectory(outputDir);

		final typedProgram = GenIrBoundary.requireProgram(program);
		final classes = collectClassUnits(typedProgram);
		final writer = new JsWriter();
		final jsClassic = context.hasDefine("js-classic");

		if (!jsClassic) {
			writer.writeln("(function () {");
			writer.pushIndent();
			writer.writeln("\"use strict\";");
		}

		emitRuntimePrelude(writer);

		for (unit in classes.units) {
			emitClass(writer, unit, classes.bySimpleName, classes.bySimpleName);
		}

		final mainRef = resolveMainRef(context.mainModule, classes.bySimpleName, classes.byFullName);
		if (mainRef != null) {
			writer.writeln(mainRef + JsNameMangler.propertySuffix("main") + "();");
		}

		if (!jsClassic) {
			writer.popIndent();
			writer.writeln("})();");
		}

		sys.io.File.saveContent(outputPath, writer.toString());
		return new EmitResult(outputPath, [new EmitArtifact("entry_js", outputPath)], false);
	}
}
