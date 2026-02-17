package backend.js;

import backend.BackendCapabilities;
import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.IBackend;
import haxe.io.Path;

private typedef JsClassUnit = {
	final fullName:String;
	final jsRef:String;
	final decl:HxClassDecl;
};

/**
	Stage3 JS backend MVP (`js-native`).

	Why
	- `hxhx` needs a first non-delegating JS emission rung so `--target js-native`
	  can run without stage0 delegation.
	- We intentionally keep this as a constrained subset and fail fast on unsupported
	  expression shapes.

	What
	- Emits one JavaScript file with:
	  - static classes/functions/fields from the typed module graph
	  - basic statement/expression lowering via `JsStmtEmitter` / `JsExprEmitter`
	  - optional IIFE wrapper (`js-classic` disables it)
	- Returns a non-executable artifact (`entry_js`), executed by Stage3 runner via `node`.

	How
	- Keep output deterministic and readable.
	- Keep unsupported behavior explicit (throws with actionable error).
**/
class JsBackend implements IBackend {
	public function new() {}

	public function id():String {
		return "js-native";
	}

	public function describe():String {
		return "Native JS backend (MVP)";
	}

	public function capabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	static function ensureDirectory(path:String):Void {
		if (path == null || path.length == 0) return;
		if (sys.FileSystem.exists(path)) return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path) ensureDirectory(parent);
		sys.FileSystem.createDirectory(path);
	}

	static function collectClassUnits(program:MacroExpandedProgram):{ units:Array<JsClassUnit>, bySimpleName:haxe.ds.StringMap<String>, byFullName:haxe.ds.StringMap<String> } {
		final bySimpleName = new haxe.ds.StringMap<String>();
		final byFullName = new haxe.ds.StringMap<String>();
		final units = new Array<JsClassUnit>();

		for (typed in program.getTypedModules()) {
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

	static function emitClass(writer:JsWriter, unit:JsClassUnit, classRefs:haxe.ds.StringMap<String>):Void {
		writer.writeln("var " + unit.jsRef + " = {};");
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

	public function emit(program:MacroExpandedProgram, context:BackendContext):EmitResult {
		final hint = context.outputFileHint;
		final outputPath = (hint != null && hint.length > 0) ? hint : Path.join([context.outputDir, "out.js"]);
		final outputDir = Path.directory(outputPath);
		if (outputDir != null && outputDir.length > 0) ensureDirectory(outputDir);

		final classes = collectClassUnits(program);
		final writer = new JsWriter();
		final jsClassic = context.hasDefine("js-classic");

		if (!jsClassic) {
			writer.writeln("(function () {");
			writer.pushIndent();
			writer.writeln("\"use strict\";");
		}

		for (unit in classes.units) {
			emitClass(writer, unit, classes.bySimpleName);
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
