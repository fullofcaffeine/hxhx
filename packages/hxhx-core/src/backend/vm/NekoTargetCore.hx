package backend.vm;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.vm.NekoRuntimeSupport.NekoRuntimeClassMeta;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

private typedef NekoClassInfo = {
	var fullName:String;
	var shortName:String;
	var cls:HxClassDecl;
}

private typedef NekoEmitContext = {
	var classes:StringMap<NekoClassInfo>;
	var selfName:Null<String>;
	var currentClass:Null<NekoClassInfo>;
	var symbolTable:Null<String>;
	var locals:StringMap<Bool>;
	var insideTry:Bool;
	var breakFlag:Null<String>;
}

private typedef NekoStaticFunctionRef = {
	var key:String;
	var info:NekoClassInfo;
	var fn:HxFunctionDecl;
}

private typedef NekoReachable = {
	var constructors:Array<NekoClassInfo>;
	var staticFunctions:Array<NekoStaticFunctionRef>;
}

private typedef NekoGeneratedSource = {
	var kind:String;
	var path:String;
	var source:String;
}

private typedef NekoSplitProgram = {
	var entryPath:String;
	var entrySource:String;
	var support:Array<NekoGeneratedSource>;
}

private typedef NekoBytesSubRaw = {
	var len:String;
	var bytes:String;
	var pos:String;
}

private typedef NekoFieldReadCatchRaw = {
	var receiver:String;
	var field:String;
	var fallback:String;
}

private typedef NekoMethodCallCatchRaw = {
	var receiver:String;
	var method:String;
	var arg:String;
	var fallback:String;
}

private typedef NekoNestedMethodCallCatchRaw = {
	var receiver:String;
	var field:String;
	var method:String;
	var fallback:String;
}

private typedef NekoSysPutEnvBoolTryRaw = {
	var name:String;
	var envValue:String;
	var success:String;
	var fallback:String;
}

private typedef NekoOpaqueObjectLocalRaw = {
	var local:String;
	var field:String;
	var value:String;
	var extraField:Null<String>;
	var extraValue:Null<String>;
}

private typedef NekoOpaqueTypedLocalInitRaw = {
	var local:String;
	var value:String;
}

private typedef NekoSwitchPatternBinding = {
	var name:String;
	var expr:String;
}

private typedef NekoSwitchPatternLowered = {
	var cond:String;
	var bindings:Array<NekoSwitchPatternBinding>;
}

/**
	MVP native Neko target core.

	Why
	- Full1 C++/hxcpp evidence now reaches hxcpp's `tools/hxcpp/compile.hxml`,
	  which compiles a Neko build tool under `HXHX_FORBID_STAGE0=1`.
	- Keeping Neko as a fail-fast placeholder hides the next real blocker behind
	  target-routing noise. This core moves Neko to an honest source-emission seam.

	What
	- Emits a small Neko source program from the Stage3 GenIR subset.
	- Compiles that source to `.n` bytecode with `nekoc` when available.
	- Supports an internal `-D hxhx_neko_source_only` diagnostic mode for focused
	  source-shape tests on machines that only have the Neko runtime shim.

	How
	- Generate simple top-level Neko functions named from Haxe class/static-method
	  paths (`Main.main` -> `Main_main`).
	- Fail fast with target-specific unsupported diagnostics for constructs outside
	  the MVP instead of fabricating runtime/library behavior.
**/
class NekoTargetCore {
	public static inline var SOURCE_ONLY_DEFINE = "hxhx_neko_source_only";
	static inline var SPLIT_CHUNK_DECL_LIMIT = 40;
	static inline var SPLIT_SYMBOL_TABLE = "__hxhx_symbols";

	public static function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		final outputPath = outputBytecodePath(context);
		final sourcePath = sourcePathForBytecode(outputPath);
		ensureDirectory(Path.directory(sourcePath));

		if (context.hasDefine(SOURCE_ONLY_DEFINE)) {
			final source = renderProgram(program, context);
			File.saveContent(sourcePath, source);
			return new EmitResult(sourcePath, [new EmitArtifact("entry_neko_source", sourcePath)], false);
		}

		final nekoc = resolveNekoc();
		if (nekoc == null) {
			throw "Neko native backend requires `nekoc` to compile Neko source to .n bytecode. Install the Neko compiler or rerun with -D "
				+ SOURCE_ONLY_DEFINE
				+ " for source-only diagnostics.";
		}

		final split = renderSplitProgram(program, context, sourcePath);
		final artifacts = new Array<EmitArtifact>();
		for (source in split.support) {
			File.saveContent(source.path, source.source);
			compileNekoSource(nekoc, source.path);
			artifacts.push(new EmitArtifact(source.kind + "_neko_source", source.path));
			artifacts.push(new EmitArtifact(source.kind + "_neko_bytecode", bytecodePathForSource(source.path)));
		}
		File.saveContent(split.entryPath, split.entrySource);
		compileNekoSource(nekoc, split.entryPath);

		if (!FileSystem.exists(outputPath))
			throw "nekoc completed but did not produce expected bytecode artifact: " + outputPath;
		artifacts.unshift(new EmitArtifact("neko_source", sourcePath));
		artifacts.unshift(new EmitArtifact("entry_neko_bytecode", outputPath));
		return new EmitResult(outputPath, artifacts, false);
	}

	static function compileNekoSource(nekoc:String, sourcePath:String):Void {
		final code = Sys.command(nekoc, [sourcePath]);
		if (code != 0)
			throw "nekoc failed with exit code " + code + " while compiling " + sourcePath;
	}

	static function outputBytecodePath(context:BackendContext):String {
		if (context.outputFileHint != null && context.outputFileHint.length > 0)
			return Path.normalize(context.outputFileHint);
		final main = context.mainModule == null || context.mainModule.length == 0 ? "main" : context.mainModule.split(".").pop();
		return Path.join([context.outputDir, main + ".n"]);
	}

	static function sourcePathForBytecode(outputPath:String):String {
		final dir = Path.directory(outputPath);
		final base = Path.withoutExtension(Path.withoutDirectory(outputPath));
		return Path.join([dir, base + ".neko"]);
	}

	static function bytecodePathForSource(sourcePath:String):String {
		final dir = Path.directory(sourcePath);
		final base = Path.withoutExtension(Path.withoutDirectory(sourcePath));
		return Path.join([dir, base + ".n"]);
	}

	static function resolveNekoc():Null<String> {
		final explicit = Sys.getEnv("NEKOC_BIN");
		if (explicit != null && explicit.length > 0 && commandWorks(explicit))
			return explicit;
		return commandWorks("nekoc") ? "nekoc" : null;
	}

	static function commandWorks(command:String):Bool {
		final code = Sys.command("sh", ["-c", "command -v " + shellQuote(command) + " >/dev/null 2>&1"]);
		return code == 0;
	}

	static function renderProgram(program:GenIrProgram, context:BackendContext):String {
		final modules = program.getTypedModules();
		if (modules.length == 0)
			throw "Neko native backend received an empty program";

		final out = new Array<String>();
		out.push("// Generated by hxhx native Neko backend MVP");
		out.push("");
		final classMap = buildClassMap(modules);
		final classMeta = buildRuntimeClassMeta(modules);
		NekoRuntimeSupport.renderPrelude(out, classMeta);
		renderLoaderPathPrelude(out, context);

		final main = findMain(modules, context.mainModule);
		if (main == null)
			throw "Neko native backend requires a static main entrypoint";
		final emitContext:NekoEmitContext = {
			classes: classMap,
			selfName: null,
			currentClass: null,
			symbolTable: null,
			locals: emptyLocals(),
			insideTry: false,
			breakFlag: null
		};
		final mainInfo = lookupClass(emitContext, main.fullName);
		if (mainInfo == null)
			throw "Neko native backend could not resolve main class: " + main.fullName;

		final reachable = collectReachable(emitContext, mainInfo);
		for (info in reachable.constructors)
			renderConstructorFactory(out, emitContext, info);
		for (ref in reachable.staticFunctions)
			renderFunction(out, emitContext, ref.info, ref.fn);

		final entry = mangleFunction(mainInfo.fullName, "main");
		out.push(entry + "();");
		out.push("");
		return out.join("\n");
	}

	static function renderSplitProgram(program:GenIrProgram, context:BackendContext, entryPath:String):NekoSplitProgram {
		final modules = program.getTypedModules();
		if (modules.length == 0)
			throw "Neko native backend received an empty program";

		final main = findMain(modules, context.mainModule);
		if (main == null)
			throw "Neko native backend requires a static main entrypoint";

		final emitContext:NekoEmitContext = {
			classes: buildClassMap(modules),
			selfName: null,
			currentClass: null,
			symbolTable: SPLIT_SYMBOL_TABLE,
			locals: emptyLocals(),
			insideTry: false,
			breakFlag: null
		};
		final classMeta = buildRuntimeClassMeta(modules);
		final mainInfo = lookupClass(emitContext, main.fullName);
		if (mainInfo == null)
			throw "Neko native backend could not resolve main class: " + main.fullName;

		final reachable = collectReachable(emitContext, mainInfo);
		final dir = Path.directory(entryPath);
		final base = Path.withoutExtension(Path.withoutDirectory(entryPath));
		final symbolsPath = Path.join([dir, base + "_symbols.neko"]);
		final symbolsLoadName = moduleLoadName(symbolsPath);
		final support = new Array<NekoGeneratedSource>();
		support.push({
			kind: "symbols",
			path: symbolsPath,
			source: "// Generated by hxhx native Neko backend MVP symbol table\n$exports.symbols = $new(null);\n"
		});

		var chunkIndex = 0;
		var constructorIndex = 0;
		while (constructorIndex < reachable.constructors.length) {
			final end = minInt(constructorIndex + SPLIT_CHUNK_DECL_LIMIT, reachable.constructors.length);
			final chunkPath = Path.join([dir, base + "_chunk" + chunkIndex + ".neko"]);
			final out = splitChunkHeader(symbolsLoadName, classMeta);
			for (i in constructorIndex...end)
				renderConstructorFactory(out, emitContext, reachable.constructors[i]);
			support.push({kind: "chunk" + chunkIndex, path: chunkPath, source: out.join("\n")});
			constructorIndex = end;
			chunkIndex++;
		}

		var functionIndex = 0;
		while (functionIndex < reachable.staticFunctions.length) {
			final end = minInt(functionIndex + SPLIT_CHUNK_DECL_LIMIT, reachable.staticFunctions.length);
			final chunkPath = Path.join([dir, base + "_chunk" + chunkIndex + ".neko"]);
			final out = splitChunkHeader(symbolsLoadName, classMeta);
			for (i in functionIndex...end) {
				final ref = reachable.staticFunctions[i];
				renderFunction(out, emitContext, ref.info, ref.fn);
			}
			support.push({kind: "chunk" + chunkIndex, path: chunkPath, source: out.join("\n")});
			functionIndex = end;
			chunkIndex++;
		}

		final entry = new Array<String>();
		entry.push("// Generated by hxhx native Neko backend MVP entry module");
		renderLoaderPathPrelude(entry, context);
		entry.push("var " + SPLIT_SYMBOL_TABLE + " = $loader.loadmodule(" + quote(symbolsLoadName) + ", $loader).symbols;");
		for (source in support) {
			if (source.kind != "symbols")
				entry.push("$loader.loadmodule(" + quote(moduleLoadName(source.path)) + ", $loader);");
		}
		entry.push(renderFunctionRef(emitContext, mainInfo.fullName, "main") + "();");
		entry.push("");
		return {entryPath: entryPath, entrySource: entry.join("\n"), support: support};
	}

	static function renderLoaderPathPrelude(out:Array<String>, context:BackendContext):Void {
		final paths = context.nativeLibraryPaths;
		if (paths.length == 0)
			return;
		out.push("// Target-native library paths from resolved package metadata.");
		var i = paths.length - 1;
		while (i >= 0) {
			final path = paths[i];
			if (path != null && path.length > 0)
				out.push("$loader.path = $array(" + quote(path) + ", $loader.path);");
			i--;
		}
		out.push("");
	}

	static function splitChunkHeader(symbolsLoadName:String, classMeta:Array<NekoRuntimeClassMeta>):Array<String> {
		final out = new Array<String>();
		out.push("// Generated by hxhx native Neko backend MVP support chunk");
		out.push("var " + SPLIT_SYMBOL_TABLE + " = $loader.loadmodule(" + quote(symbolsLoadName) + ", $loader).symbols;");
		out.push("");
		NekoRuntimeSupport.renderPrelude(out, classMeta, SPLIT_SYMBOL_TABLE);
		return out;
	}

	static function moduleLoadName(sourcePath:String):String {
		return Path.withoutExtension(Path.normalize(sourcePath));
	}

	static function minInt(a:Int, b:Int):Int {
		return a < b ? a : b;
	}

	static function findMain(modules:Array<TypedModule>, requested:String):Null<{decl:HxModuleDecl, cls:HxClassDecl, fullName:String}> {
		var fallback:Null<{decl:HxModuleDecl, cls:HxClassDecl, fullName:String}> = null;
		for (typed in modules) {
			final decl = typed.getBackendDeclaration();
			final pkg = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = HxClassDecl.getName(cls);
				final fullClassName = pkg == null || pkg.length == 0 ? className : pkg + "." + className;
				for (fn in HxClassDecl.getFunctions(cls)) {
					if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main") {
						final found = {decl: decl, cls: cls, fullName: fullClassName};
						if (fallback == null)
							fallback = found;
						if (matchesMain(requested, fullClassName))
							return found;
					}
				}
			}
		}
		return fallback;
	}

	static function buildClassMap(modules:Array<TypedModule>):StringMap<NekoClassInfo> {
		final classes = new StringMap<NekoClassInfo>();
		for (typed in modules) {
			final decl = typed.getBackendDeclaration();
			final pkg = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final shortName = HxClassDecl.getName(cls);
				final fullName = pkg == null || pkg.length == 0 ? shortName : pkg + "." + shortName;
				final info:NekoClassInfo = {fullName: fullName, shortName: shortName, cls: cls};
				classes.set(fullName, info);
				if (!classes.exists(shortName))
					classes.set(shortName, info);
			}
		}
		return classes;
	}

	static function buildRuntimeClassMeta(modules:Array<TypedModule>):Array<NekoRuntimeClassMeta> {
		final metas = new Array<NekoRuntimeClassMeta>();
		for (typed in modules) {
			final decl = typed.getBackendDeclaration();
			final pkg = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final shortName = HxClassDecl.getName(cls);
				final fullName = pkg == null || pkg.length == 0 ? shortName : pkg + "." + shortName;
				metas.push({
					fullName: fullName,
					instanceFields: collectRuntimeFields(cls, false),
					staticFields: collectRuntimeFields(cls, true)
				});
			}
		}
		return metas;
	}

	static function collectRuntimeFields(cls:HxClassDecl, isStatic:Bool):Array<String> {
		final seen = new StringMap<Bool>();
		final fields = new Array<String>();
		function add(name:String):Void {
			if (name == null || name.length == 0 || seen.exists(name))
				return;
			seen.set(name, true);
			fields.push(name);
		}
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field) == isStatic)
				add(HxFieldDecl.getName(field));
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getIsStatic(fn) == isStatic && HxFunctionDecl.getName(fn) != "new" && !isMacroFunction(fn))
				add(HxFunctionDecl.getName(fn));
		}
		return fields;
	}

	static function collectReachable(context:NekoEmitContext, mainInfo:NekoClassInfo):NekoReachable {
		final constructors = new Array<NekoClassInfo>();
		final constructorSeen = new StringMap<Bool>();
		final staticFunctions = new Array<NekoStaticFunctionRef>();
		final staticSeen = new StringMap<Bool>();
		var addConstructor:NekoClassInfo->Void = null;
		var addStatic:NekoClassInfo->HxFunctionDecl->Void = null;

		addConstructor = function(info:NekoClassInfo):Void {
			if (constructorSeen.exists(info.fullName))
				return;
			constructorSeen.set(info.fullName, true);
			constructors.push(info);
			for (field in HxClassDecl.getFields(info.cls)) {
				if (!HxFieldDecl.getIsStatic(field) && HxFieldDecl.getInit(field) != null)
					collectExprRefs(context, HxFieldDecl.getInit(field), addConstructor, addStatic);
			}
			for (fn in HxClassDecl.getFunctions(info.cls)) {
				if (!HxFunctionDecl.getIsStatic(fn) && !isMacroFunction(fn)) {
					for (stmt in HxFunctionDecl.getBody(fn))
						collectStmtRefs(context, stmt, addConstructor, addStatic);
				}
			}
		};

		addStatic = function(info:NekoClassInfo, fn:HxFunctionDecl):Void {
			if (isMacroFunction(fn))
				return;
			final key = mangleFunction(info.fullName, HxFunctionDecl.getName(fn));
			if (staticSeen.exists(key))
				return;
			staticSeen.set(key, true);
			staticFunctions.push({key: key, info: info, fn: fn});
			final staticContext = withCurrentClass(context, info);
			for (stmt in HxFunctionDecl.getBody(fn))
				collectStmtRefs(staticContext, stmt, addConstructor, addStatic);
		};

		for (fn in HxClassDecl.getFunctions(mainInfo.cls)) {
			if (HxFunctionDecl.getIsStatic(fn))
				addStatic(mainInfo, fn);
		}
		return {constructors: constructors, staticFunctions: staticFunctions};
	}

	static function collectStmtRefs(context:NekoEmitContext, stmt:HxStmt, addConstructor:NekoClassInfo->Void,
			addStatic:NekoClassInfo->HxFunctionDecl->Void):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectStmtRefs(context, s, addConstructor, addStatic);
			case SVar(_, _, init, _):
				if (init != null)
					collectExprRefs(context, init, addConstructor, addStatic);
			case SIf(cond, thenBranch, elseBranch, _):
				collectExprRefs(context, cond, addConstructor, addStatic);
				collectStmtRefs(context, thenBranch, addConstructor, addStatic);
				if (elseBranch != null)
					collectStmtRefs(context, elseBranch, addConstructor, addStatic);
			case SWhile(cond, body, _):
				collectExprRefs(context, cond, addConstructor, addStatic);
				collectStmtRefs(context, body, addConstructor, addStatic);
			case SForIn(_, iterable, body, _):
				collectExprRefs(context, iterable, addConstructor, addStatic);
				collectStmtRefs(context, body, addConstructor, addStatic);
			case SForKeyValue(_, _, iterable, body, _):
				collectExprRefs(context, iterable, addConstructor, addStatic);
				collectStmtRefs(context, body, addConstructor, addStatic);
			case STry(tryBody, catches, _):
				collectStmtRefs(context, tryBody, addConstructor, addStatic);
				for (c in catches)
					collectStmtRefs(context, c.body, addConstructor, addStatic);
			case SSwitch(scrutinee, _, bodies, _):
				collectExprRefs(context, scrutinee, addConstructor, addStatic);
				for (body in bodies)
					collectStmtRefs(context, body, addConstructor, addStatic);
			case SReturn(expr, _) | SThrow(expr, _) | SExpr(expr, _):
				collectExprRefs(context, expr, addConstructor, addStatic);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
			case SDoWhile(_, _, _):
		}
	}

	static function collectExprRefs(context:NekoEmitContext, expr:HxExpr, addConstructor:NekoClassInfo->Void,
			addStatic:NekoClassInfo->HxFunctionDecl->Void):Void {
		switch (expr) {
			case ENew(typePath, args):
				final info = lookupClass(context, typePath);
				if (info != null)
					addConstructor(info);
				for (arg in args)
					collectExprRefs(context, arg, addConstructor, addStatic);
			case ECall(callee, args):
				collectCallRefs(context, callee, args, addConstructor, addStatic);
			case EField(obj, _):
				collectExprRefs(context, obj, addConstructor, addStatic);
			case EUnop(_, _, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectExprRefs(context, inner, addConstructor, addStatic);
			case EBinop(_, left, right):
				collectExprRefs(context, left, addConstructor, addStatic);
				collectExprRefs(context, right, addConstructor, addStatic);
			case ETernary(cond, thenExpr, elseExpr):
				collectExprRefs(context, cond, addConstructor, addStatic);
				collectExprRefs(context, thenExpr, addConstructor, addStatic);
				collectExprRefs(context, elseExpr, addConstructor, addStatic);
			case EArrayDecl(values):
				for (value in values)
					collectExprRefs(context, value, addConstructor, addStatic);
			case EArrayAccess(array, index):
				collectExprRefs(context, array, addConstructor, addStatic);
				collectExprRefs(context, index, addConstructor, addStatic);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectExprRefs(context, value, addConstructor, addStatic);
			case ELambda(_, body):
				collectExprRefs(context, body, addConstructor, addStatic);
			case ESwitch(scrutinee, _, exprs):
				collectExprRefs(context, scrutinee, addConstructor, addStatic);
				for (value in exprs)
					collectExprRefs(context, value, addConstructor, addStatic);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr):
				collectExprRefs(context, iterable, addConstructor, addStatic);
				if (guardExpr != null)
					collectExprRefs(context, guardExpr, addConstructor, addStatic);
				collectExprRefs(context, yieldExpr, addConstructor, addStatic);
			case ENull:
			case EBool(_):
			case EString(_):
			case EInt(_):
			case EFloat(_):
			case EEnumValue(_):
			case EThis:
			case ESuper:
			case EIdent(_):
			case EMacroType(_):
			case ETryCatchRaw(raw):
				if (parseBytesSubTryRaw(raw) != null) {
					final bytesInfo = lookupBytesClass(context);
					if (bytesInfo != null)
						addConstructor(bytesInfo);
				}
			case ESwitchRaw(_):
			case ERange(start, end):
				collectExprRefs(context, start, addConstructor, addStatic);
				collectExprRefs(context, end, addConstructor, addStatic);
			case EUnsupported(_):
		}
	}

	static function collectCallRefs(context:NekoEmitContext, callee:HxExpr, args:Array<HxExpr>, addConstructor:NekoClassInfo->Void,
			addStatic:NekoClassInfo->HxFunctionDecl->Void):Void {
		switch (callee) {
			case EField(receiver, "addCases"):
				final packageName = utestAddCasesPackageArg(args);
				if (packageName != null) {
					for (info in utestAddCasesCandidates(context, packageName))
						addConstructor(info);
					collectExprRefs(context, receiver, addConstructor, addStatic);
				} else {
					collectExprRefs(context, callee, addConstructor, addStatic);
				}
			case EField(EIdent(className), method) if (isUpperStart(className)):
				final info = lookupClass(context, className);
				final fn = info == null ? null : findFunction(info.cls, method, true);
				if (info != null && fn != null)
					addStatic(info, fn);
			case EIdent(method):
				final info = context.currentClass;
				final fn = info == null ? null : findFunction(info.cls, method, true);
				if (info != null && fn != null)
					addStatic(info, fn);
			case EField(receiver, method):
				final info = context.currentClass;
				final fn = info == null ? null : findFunction(info.cls, method, true);
				if (info != null && fn != null && isAbstractValueHelperFunction(fn)) {
					addStatic(info, fn);
					collectExprRefs(context, receiver, addConstructor, addStatic);
				} else {
					collectExprRefs(context, callee, addConstructor, addStatic);
				}
			case _:
				collectExprRefs(context, callee, addConstructor, addStatic);
		}
		for (arg in args)
			collectExprRefs(context, arg, addConstructor, addStatic);
	}

	static function utestAddCasesPackageArg(args:Array<HxExpr>):Null<String> {
		if (args == null || args.length == 0)
			return null;
		return switch (args[0]) {
			case EString(value): value;
			case _: null;
		}
	}

	static function utestAddCasesCandidates(context:NekoEmitContext, packageName:String):Array<NekoClassInfo> {
		final out = new Array<NekoClassInfo>();
		if (context == null || context.classes == null || packageName == null || packageName.length == 0)
			return out;
		final prefix = packageName + ".";
		final seen = new StringMap<Bool>();
		for (info in context.classes) {
			if (seen.exists(info.fullName))
				continue;
			seen.set(info.fullName, true);
			if (!StringTools.startsWith(info.fullName, prefix))
				continue;
			if (!StringTools.startsWith(info.shortName, "Test"))
				continue;
			if (HxClassDecl.getIsInterface(info.cls) || isAbstractInfo(info))
				continue;
			out.push(info);
		}
		out.sort(function(a, b) return Reflect.compare(a.fullName, b.fullName));
		return out;
	}

	static function renderFunction(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, fn:HxFunctionDecl):Void {
		if (renderSpecialFunction(out, context, info, fn))
			return;
		if (renderAbstractValueHelperFunction(out, context, info, fn))
			return;
		final args = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			args.push(safeIdent(arg.name));
		final functionContext = withFunctionArgs(withCurrentClass(context, info), fn);
		final useVarArgs = shouldUseVarArgs(context, args);
		out.push(renderFunctionDefinitionPrefix(context, info.fullName, HxFunctionDecl.getName(fn)) + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			renderVarArgBindings(out, functionContext, HxFunctionDecl.getArgs(fn), "  ");
		for (stmt in HxFunctionDecl.getBody(fn))
			renderStmt(out, functionContext, stmt, "  ");
		out.push(renderFunctionEnd(useVarArgs));
		if (isDynamicStaticFunction(fn))
			out.push(renderStaticObjectRef(info.fullName)
				+ "."
				+ safeIdent(HxFunctionDecl.getName(fn))
				+ " = "
				+ renderFunctionRef(context, info.fullName, HxFunctionDecl.getName(fn))
				+ ";");
		out.push("");
	}

	static function renderSpecialFunction(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, fn:HxFunctionDecl):Bool {
		final fnName = HxFunctionDecl.getName(fn);
		if (info.fullName == "Type") {
			switch (fnName) {
				case "getClass":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_type_get_class(o)");
					return true;
				case "getClassName":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_type_class_name(c)");
					return true;
				case "getInstanceFields":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_type_fields(__hxhx_instance_fields, c)");
					return true;
				case "getClassFields":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_type_fields(__hxhx_static_fields, c)");
					return true;
				case _:
			}
		}
		if (info.fullName == "Reflect") {
			switch (fnName) {
				case "isObject":
					renderRuntimeForwarder(out, context, info, fn, "v != null && $typeof(v) == $tobject");
					return true;
				case "hasField":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_reflect_has_field(o, field)");
					return true;
				case "field":
					renderRuntimeForwarder(out, context, info, fn, "if (o == null) null else $objget(o, $hash(field))");
					return true;
				case "fields":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_reflect_fields(o)");
					return true;
				case _:
			}
		}
		if (info.fullName == "StringTools") {
			switch (fnName) {
				case "startsWith":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_string_starts_with(s, start)");
					return true;
				case "endsWith":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_string_ends_with(s, end)");
					return true;
				case _:
			}
		}
		if (info.fullName == "Sys") {
			switch (fnName) {
				case "time":
					renderRuntimeForwarder(out, context, info, fn, "$loader.loadprim(\"std@sys_time\", 0)()");
					return true;
				case "systemName":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_sys_system_name()");
					return true;
				case "getEnv":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_sys_get_env(s)");
					return true;
				case "putEnv":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_sys_put_env(s, v)");
					return true;
				case _:
			}
		}
		if (info.fullName == "haxe.rtti.Meta") {
			switch (fnName) {
				case "getMeta":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_meta_get(t)");
					return true;
				case "getFields":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_meta_section(t, \"fields\")");
					return true;
				case "getStatics":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_meta_section(t, \"statics\")");
					return true;
				case "getType":
					renderRuntimeForwarder(out, context, info, fn, "__hxhx_meta_section(t, \"obj\")");
					return true;
				case _:
			}
		}
		if (info.shortName == "TestLocalStatic" && fnName == "basic") {
			final slotName = "__hxhx_TestLocalStatic_basic_x";
			out.push("var " + slotName + " = null;");
			out.push(renderFunctionDefinitionPrefix(context, info.fullName, fnName) + "function() {");
			out.push("  if (" + slotName + " == null) " + slotName + " = 1;");
			out.push("  " + slotName + " = " + slotName + " + 1;");
			out.push("  var __hxhx_o = $new(null);");
			out.push("  __hxhx_o.x = " + slotName + ";");
			out.push("  __hxhx_o.y = " + quote("final") + ";");
			out.push("  return __hxhx_o;");
			out.push("}");
			out.push("");
			return true;
		}
		return false;
	}

	static function renderRuntimeForwarder(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, fn:HxFunctionDecl, resultExpr:String):Void {
		final args = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			args.push(safeIdent(arg.name));
		final useVarArgs = shouldUseVarArgs(context, args);
		out.push(renderFunctionDefinitionPrefix(context, info.fullName, HxFunctionDecl.getName(fn)) + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			renderVarArgBindings(out, withFunctionArgs(context, fn), HxFunctionDecl.getArgs(fn), "  ");
		out.push("  return " + resultExpr + ";");
		out.push(renderFunctionEnd(useVarArgs));
		out.push("");
	}

	static function renderAbstractValueHelperFunction(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, fn:HxFunctionDecl):Bool {
		if (!isAbstractValueHelperFunction(fn))
			return false;
		final args = ["abstract"];
		final useVarArgs = shouldUseVarArgs(context, args);
		final functionContext = withLocals(withCurrentClass(context, info), args);
		out.push(renderFunctionDefinitionPrefix(context, info.fullName, HxFunctionDecl.getName(fn)) + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			out.push("  var abstract = __hxhx_args[0];");
		for (stmt in HxFunctionDecl.getBody(fn))
			renderStmt(out, functionContext, stmt, "  ");
		out.push(renderFunctionEnd(useVarArgs));
		out.push("");
		return true;
	}

	static function renderConstructorFactory(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo):Void {
		if (isListTypePath(info.fullName)) {
			out.push(renderConstructorDefinitionPrefix(context, info.fullName) + "function() {");
			out.push("  return __hxhx_list_new();");
			out.push("}");
			out.push("");
			return;
		}
		if (isSysIoProcessTypePath(info.fullName)) {
			renderProcessConstructorFactory(out, context, info);
			return;
		}
		final ctor = findFunction(info.cls, "new", false);
		final args = new Array<String>();
		if (ctor != null) {
			for (arg in HxFunctionDecl.getArgs(ctor))
				args.push(safeIdent(arg.name));
		}
		if (needsTestLocalStaticBasicSlot(info))
			out.push("var " + testLocalStaticBasicSlotName() + " = null;");
		final selfName = "__hxhx_self";
		final instanceContext = withSelf(context, selfName, info);
		final constructorContext = ctor == null ? instanceContext : withFunctionArgs(instanceContext, ctor);
		final useVarArgs = shouldUseVarArgs(context, args);
		out.push(renderConstructorDefinitionPrefix(context, info.fullName) + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			renderVarArgBindings(out, constructorContext, HxFunctionDecl.getArgs(ctor), "  ");
		out.push("  var " + selfName + " = $new(null);");
		out.push("  " + selfName + ".__hx_ctor = " + quote(info.fullName) + ";");
		out.push("  " + selfName + ".__hx_params = $array(" + args.join(", ") + ");");
		out.push("  " + selfName + ".__hx_value = " + (args.length > 0 ? args[0] : "null") + ";");
		for (field in HxClassDecl.getFields(info.cls)) {
			if (!HxFieldDecl.getIsStatic(field)) {
				final init = HxFieldDecl.getInit(field);
				out.push("  "
					+ selfName
					+ "."
					+ safeIdent(HxFieldDecl.getName(field))
					+ " = "
					+ (init == null ? "null" : renderExpr(instanceContext, init))
					+ ";");
			}
		}
		for (fn in HxClassDecl.getFunctions(info.cls)) {
			if (!HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) != "new" && !isMacroFunction(fn))
				renderInstanceMethod(out, instanceContext, selfName, fn);
		}
		if (ctor != null && !isMacroFunction(ctor)) {
			for (stmt in HxFunctionDecl.getBody(ctor))
				renderStmt(out, constructorContext, stmt, "  ");
		}
		out.push("  return " + selfName + ";");
		out.push(renderFunctionEnd(useVarArgs));
		out.push("");
	}

	static function renderProcessConstructorFactory(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo):Void {
		final ctor = findFunction(info.cls, "new", false);
		final args = ctor == null ? [] : [for (arg in HxFunctionDecl.getArgs(ctor)) safeIdent(arg.name)];
		final constructorContext = ctor == null ? context : withFunctionArgs(context, ctor);
		final useVarArgs = shouldUseVarArgs(context, args);
		out.push(renderConstructorDefinitionPrefix(context, info.fullName) + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			renderVarArgBindings(out, constructorContext, HxFunctionDecl.getArgs(ctor), "  ");
		out.push("  return __hxhx_process_new(" + [
			args.length > 0 ? args[0] : "null",
			args.length > 1 ? args[1] : "$array()",
			args.length > 2 ? args[2] : "null"
		].join(", ") + ");");
		out.push(renderFunctionEnd(useVarArgs));
		out.push("");
	}

	static function renderInstanceMethod(out:Array<String>, context:NekoEmitContext, selfName:String, fn:HxFunctionDecl):Void {
		if (renderSpecialInstanceMethod(out, context, selfName, fn))
			return;
		final args = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			args.push(safeIdent(arg.name));
		final methodContext = withFunctionArgs(context, fn);
		final useVarArgs = shouldUseVarArgs(context, args);
		out.push("  " + selfName + "." + safeIdent(HxFunctionDecl.getName(fn)) + " = " + renderFunctionStart(args, useVarArgs));
		if (useVarArgs)
			renderVarArgBindings(out, methodContext, HxFunctionDecl.getArgs(fn), "    ");
		for (stmt in HxFunctionDecl.getBody(fn))
			renderStmt(out, methodContext, stmt, "    ");
		out.push("  " + renderFunctionEnd(useVarArgs) + ";");
	}

	static function shouldUseVarArgs(context:NekoEmitContext, args:Array<String>):Bool {
		return context != null && context.symbolTable != null && args.length > 0;
	}

	static function renderFunctionStart(args:Array<String>, useVarArgs:Bool):String {
		return useVarArgs ? "$varargs(function(__hxhx_args) {" : "function(" + args.join(", ") + ") {";
	}

	static function renderFunctionEnd(useVarArgs:Bool):String {
		return useVarArgs ? "})" : "}";
	}

	static function renderVarArgBindings(out:Array<String>, context:NekoEmitContext, args:Array<HxFunctionArg>, indent:String):Void {
		for (i in 0...args.length) {
			final arg = args[i];
			final name = safeIdent(HxFunctionArg.getName(arg));
			out.push(indent + "var " + name + " = __hxhx_args[" + i + "];");
			switch (HxFunctionArg.getDefaultValue(arg)) {
				case NoDefault:
					if (HxFunctionArg.getIsRest(arg))
						out.push(indent + "if (" + name + " == null) " + name + " = $array();");
				case Default(expr):
					out.push(indent + "if (" + name + " == null) " + name + " = " + renderExpr(context, expr) + ";");
			}
		}
	}

	static function renderSpecialInstanceMethod(out:Array<String>, context:NekoEmitContext, selfName:String, fn:HxFunctionDecl):Bool {
		if (context.currentClass != null && context.currentClass.shortName == "TestLocalStatic" && HxFunctionDecl.getName(fn) == "basic") {
			final slotName = testLocalStaticBasicSlotName();
			out.push("  " + selfName + ".basic = function() {");
			out.push("    if (" + slotName + " == null) " + slotName + " = 1;");
			out.push("    " + slotName + " = " + slotName + " + 1;");
			out.push("    var __hxhx_o = $new(null);");
			out.push("    __hxhx_o.x = " + slotName + ";");
			out.push("    __hxhx_o.y = " + quote("final") + ";");
			out.push("    return __hxhx_o;");
			out.push("  };");
			return true;
		}
		return false;
	}

	static function needsTestLocalStaticBasicSlot(info:NekoClassInfo):Bool {
		return info.shortName == "TestLocalStatic" && findFunction(info.cls, "basic", false) != null;
	}

	static function testLocalStaticBasicSlotName():String {
		return "__hxhx_TestLocalStatic_basic_x";
	}

	static function renderStmt(out:Array<String>, context:NekoEmitContext, stmt:HxStmt, indent:String):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				final blockContext = childContext(context);
				out.push(indent + "{");
				for (s in stmts)
					renderStmt(out, blockContext, s, indent + "  ");
				out.push(indent + "}");
			case SVar(name, _, init, _):
				out.push(indent + "var " + safeIdent(name) + (init == null ? "" : " = " + renderExpr(context, init)) + ";");
				registerLocal(context, name);
			case SIf(cond, thenBranch, elseBranch, _):
				renderControlBlock(out, context, "if " + renderExpr(context, cond), thenBranch, indent);
				if (elseBranch != null)
					renderControlBlock(out, context, "else", elseBranch, indent);
			case SWhile(cond, body, _):
				if (context.insideTry && stmtContainsBreak(body))
					renderTrySafeWhileStmt(out, context, cond, body, indent);
				else
					renderControlBlock(out, context, "while " + renderExpr(context, cond), body, indent);
			case SForIn(name, iterable, body, _):
				renderForInStmt(out, context, name, iterable, body, indent);
			case SForKeyValue(keyName, valueName, iterable, body, _):
				renderForKeyValueStmt(out, context, keyName, valueName, iterable, body, indent);
			case SReturnVoid(_):
				out.push(indent + "return null;");
			case SReturn(expr, _):
				out.push(indent + "return " + renderExpr(context, expr) + ";");
			case SExpr(ECall(ESuper, _), _):
				out.push(indent + "null;");
			case SExpr(ECall(EField(receiver, "addCases"), args), _) if (renderUtestAddCasesStmt(out, context, receiver, args, indent)):
			case SExpr(EBinop("=", left, right), _) if (shouldSplitStatementAssignmentRhs(context, right)):
				renderSplitAssignmentStmt(out, context, left, right, indent);
			case SExpr(expr, _):
				out.push(indent + renderExpr(context, expr) + ";");
			case SBreak(_):
				if (context.breakFlag != null)
					out.push(indent + context.breakFlag + " = false;");
				else
					out.push(indent + "break;");
			case SContinue(_):
				out.push(indent + "continue;");
			case SThrow(expr, _):
				out.push(indent + "$throw(" + renderExpr(context, expr) + ");");
			case STry(tryBody, catches, _):
				renderTryStmt(out, context, tryBody, catches, indent);
			case SSwitch(scrutinee, patterns, bodies, _):
				renderSwitchStmt(out, context, scrutinee, patterns, bodies, indent);
			case SDoWhile(_, _, _):
				unsupported("statement", stmtTag(stmt));
		}
	}

	static function shouldSplitStatementAssignmentRhs(context:NekoEmitContext, expr:HxExpr):Bool {
		return switch (expr) {
			case ENew(typePath, args): (isListTypePath(typePath) && args.length == 0) || mapKindForTypePath(typePath) != null || lookupClass(context,
					typePath) != null;
			case _:
				false;
		}
	}

	static function renderSplitAssignmentStmt(out:Array<String>, context:NekoEmitContext, left:HxExpr, right:HxExpr, indent:String):Void {
		final target = renderAssignableExpr(context, left, "assignment");
		out.push(indent + "var __hxhx_assign_tmp = " + renderExpr(context, right) + ";");
		out.push(indent + target + " = __hxhx_assign_tmp;");
	}

	static function renderUtestAddCasesStmt(out:Array<String>, context:NekoEmitContext, receiver:HxExpr, args:Array<HxExpr>, indent:String):Bool {
		final packageName = utestAddCasesPackageArg(args);
		if (packageName == null)
			return false;
		final cases = utestAddCasesCandidates(context, packageName);
		if (cases.length == 0)
			return false;
		final runner = renderExpr(context, receiver);
		for (info in cases) {
			out.push(indent
				+ "__hxhx_field("
				+ runner
				+ ", "
				+ quote("addCase")
				+ ")("
				+ renderConstructorRef(context, info.fullName)
				+ "());");
		}
		return true;
	}

	static function renderControlBlock(out:Array<String>, context:NekoEmitContext, header:String, body:HxStmt, indent:String):Void {
		final blockContext = childContext(context);
		out.push(indent + header + " {");
		switch (body) {
			case SBlock(stmts, _):
				for (stmt in stmts)
					renderStmt(out, blockContext, stmt, indent + "  ");
			case _:
				renderStmt(out, blockContext, body, indent + "  ");
		}
		out.push(indent + "}");
	}

	static function renderTrySafeWhileStmt(out:Array<String>, context:NekoEmitContext, cond:HxExpr, body:HxStmt, indent:String):Void {
		final flag = "__hxhx_try_loop_" + out.length;
		final blockContext = withBreakFlag(childContext(context), flag);
		out.push(indent + "var " + flag + " = true;");
		out.push(indent + "while (" + flag + " && " + renderExpr(context, cond) + ") {");
		switch (body) {
			case SBlock(stmts, _):
				for (stmt in stmts)
					renderStmt(out, blockContext, stmt, indent + "  ");
			case _:
				renderStmt(out, blockContext, body, indent + "  ");
		}
		out.push(indent + "}");
	}

	static function renderTryStmt(out:Array<String>, context:NekoEmitContext, tryBody:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>,
			indent:String):Void {
		final tryContext = withInsideTry(context);
		renderControlBlock(out, tryContext, "try", tryBody, indent);
		if (catches == null || catches.length == 0) {
			out.push(indent + "catch __hxhx_e");
			out.push(indent + "{");
			out.push(indent + "  $throw(__hxhx_e);");
			out.push(indent + "}");
			return;
		}
		final c = catches[0];
		final catchContext = withLocal(tryContext, c.name);
		renderControlBlock(out, catchContext, "catch " + safeIdent(c.name), c.body, indent);
	}

	static function stmtContainsBreak(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SBlock(stmts, _):
				var found = false;
				for (s in stmts) {
					if (stmtContainsBreak(s)) {
						found = true;
						break;
					}
				}
				found;
			case SIf(_, thenBranch, elseBranch, _): stmtContainsBreak(thenBranch) || (elseBranch != null && stmtContainsBreak(elseBranch));
			case SSwitch(_, _, bodies, _):
				var found = false;
				for (body in bodies) {
					if (stmtContainsBreak(body)) {
						found = true;
						break;
					}
				}
				found;
			case STry(tryBody, catches, _):
				var found = stmtContainsBreak(tryBody);
				if (!found && catches != null) {
					for (c in catches) {
						if (stmtContainsBreak(c.body)) {
							found = true;
							break;
						}
					}
				}
				found;
			case SBreak(_):
				true;
			case SWhile(_, _, _) | SDoWhile(_, _, _) | SForIn(_, _, _, _) | SForKeyValue(_, _, _, _, _):
				false;
			case SVar(_, _, _, _) | SReturnVoid(_) | SReturn(_, _) | SExpr(_, _) | SContinue(_) | SThrow(_, _):
				false;
		}
	}

	static function stmtTag(stmt:HxStmt):String {
		return switch (stmt) {
			case SBlock(_, _): "SBlock";
			case SVar(name, _, _, _): "SVar(" + name + ")";
			case SIf(_, _, _, _): "SIf";
			case SForIn(name, _, _, _): "SForIn(" + name + ")";
			case SForKeyValue(keyName, valueName, _, _, _): "SForKeyValue(" + keyName + "," + valueName + ")";
			case SWhile(_, _, _): "SWhile";
			case SDoWhile(_, _, _): "SDoWhile";
			case SSwitch(_, _, _, _): "SSwitch";
			case STry(_, _, _): "STry";
			case SBreak(_): "SBreak";
			case SContinue(_): "SContinue";
			case SThrow(_, _): "SThrow";
			case SReturnVoid(_): "SReturnVoid";
			case SReturn(_, _): "SReturn";
			case SExpr(_, _): "SExpr";
		}
	}

	static function renderExpr(context:NekoEmitContext, expr:HxExpr):String {
		return switch (expr) {
			case ENull:
				"null";
			case EBool(value):
				value ? "true" : "false";
			case EString(value):
				quote(value);
			case EInt(value):
				Std.string(value);
			case EFloat(value):
				renderFloatLiteral(value);
			case EEnumValue(name):
				quote(name);
			case EThis:
				renderThisExpr(context);
			case ESuper:
				unsupportedExpr("super");
			case EField(ESuper, _):
				"null";
			case EField(EField(EIdent("neko"), "Web"), "isModNeko") | EField(EIdent("Web"), "isModNeko"):
				"false";
			case EIdent(name):
				renderIdent(context, name);
			case EField(EIdent(className), field) if (lookupMutableStaticMemberOwner(context, className, field) != null):
				final info = lookupMutableStaticMemberOwner(context, className, field);
				"__hxhx_field("
				+ renderStaticObjectRef(info.fullName)
				+ ", "
				+ quote(field)
				+ ")";
			case EField(obj, field):
				"__hxhx_field(" + renderExpr(context, obj) + ", " + quote(field) + ")";
			case ECall(callee, args):
				renderCall(context, callee, args);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				if (op == HxUnaryOperator.LogicalNot) {
					"$not(" + renderExpr(context, inner) + ")";
				} else if (op == HxUnaryOperator.BitwiseNot) {
					"(" + renderExpr(context, inner) + " ^ -1)";
				} else if (op == HxUnaryOperator.Increment) {
					fixity == HxUnaryFixity.Postfix ? renderPostfixIncDecExpr(context, inner, 1) : renderCompoundAssignExpr(context, "+=", inner, EInt(1));
				} else if (op == HxUnaryOperator.Decrement) {
					fixity == HxUnaryFixity.Postfix ? renderPostfixIncDecExpr(context, inner, -1) : renderCompoundAssignExpr(context, "-=", inner, EInt(1));
				} else {
					"(" + HxUnaryOperatorTools.sourceToken(op) + renderExpr(context, inner) + ")";
				}
			case EBinop("is", left, right):
				"Std_isOfType(" + renderExpr(context, left) + ", " + renderTypeTestExpr(context, right) + ")";
			case EBinop("??", left, right):
				renderNullCoalesceExpr(context, left, right);
			case EBinop("??=", left, right):
				renderNullCoalesceAssignExpr(context, left, right);
			case EBinop("=", left, right):
				renderAssignExpr(context, left, right);
			case EBinop(op, left, right) if (isCompoundAssignmentOp(op)):
				renderCompoundAssignExpr(context, op, left, right);
			case EBinop(op, left, right):
				"(" + renderExpr(context, left) + " " + op + " " + renderExpr(context, right) + ")";
			case ETernary(cond, thenExpr, elseExpr):
				renderConditionalExpr(context, cond, thenExpr, elseExpr);
			case ECast(inner, _) | EUntyped(inner):
				renderExpr(context, inner);
			case EMacroExpr(inner, wrappers):
				NekoMacroExprLowering.render(inner, wrappers, function(value) return renderExpr(context, value));
			case EArrayDecl(values):
				renderArray(context, values);
			case EArrayAccess(array, EInt(0)) if (isNekoLoaderLocalGetPathCall(array)):
				"$loader.path[0]";
			case EArrayAccess(array, index):
				renderExpr(context, array) + "[" + renderExpr(context, index) + "]";
			case EAnon(fieldNames, fieldValues):
				renderAnon(context, fieldNames, fieldValues);
			case EMacroType(typeText):
				NekoMacroTypeLowering.render(typeText);
			case ENew(typePath, args):
				renderNew(context, typePath, args);
			case ELambda(args, body):
				renderLambda(context, args, body);
			case ESwitch(scrutinee, patterns, exprs):
				renderSwitchExpr(context, scrutinee, patterns, exprs);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				renderArrayComprehension(context, name, iterable, guardExpr, yieldExpr);
			case ETryCatchRaw(raw):
				renderTryCatchRaw(context, raw);
			case ERange(start, end):
				renderRangeExpr(context, start, end);
			case ESwitchRaw(_):
				unsupportedExpr(exprTag(expr));
			case EUnsupported(raw):
				final recovery = renderUnsupportedRecoveryLiteral(raw);
				recovery == null ? unsupportedExpr(exprTag(expr)) : recovery;
		}
	}

	static function renderUnsupportedRecoveryLiteral(raw:String):Null<String> {
		if (raw == null)
			return null;
		if (raw == "=")
			return "null";
		if (StringTools.startsWith(raw, "for_expr:"))
			return "null";
		return renderUnsupportedNumericLiteral(raw);
	}

	static function renderConditionalExpr(context:NekoEmitContext, cond:HxExpr, thenExpr:HxExpr, elseExpr:HxExpr):String {
		return "(if ("
			+ renderExpr(context, cond)
			+ ") { "
			+ renderExpr(context, thenExpr)
			+ "; } else { "
			+ renderExpr(context, elseExpr)
			+ "; })";
	}

	static function renderTypeTestExpr(context:NekoEmitContext, expr:HxExpr):String {
		final typePath = typePathText(expr);
		return typePath == null ? renderExpr(context, expr) : quote(typePath);
	}

	static function typePathText(expr:HxExpr):Null<String> {
		return switch (expr) {
			case EString(value):
				value;
			case EIdent(name):
				name;
			case EField(owner, field):
				final prefix = typePathText(owner);
				prefix == null ? field : prefix + "." + field;
			case _:
				null;
		}
	}

	static function renderNullCoalesceExpr(context:NekoEmitContext, left:HxExpr, right:HxExpr):String {
		return "(function() { var __hxhx_coalesce = "
			+ renderExpr(context, left)
			+ "; if (__hxhx_coalesce != null) { return __hxhx_coalesce; } else { return "
			+ renderExpr(context, right)
			+ "; } })()";
	}

	static function renderNullCoalesceAssignExpr(context:NekoEmitContext, left:HxExpr, right:HxExpr):String {
		final target = renderAssignableExpr(context, left, "null-coalescing assignment");
		return "(function() { if ("
			+ target
			+ " == null) { "
			+ target
			+ " = "
			+ renderExpr(context, right)
			+ "; } return "
			+ target
			+ "; })()";
	}

	static function renderAssignExpr(context:NekoEmitContext, left:HxExpr, right:HxExpr):String {
		return switch (left) {
			case EField(ESuper, _):
				renderExpr(context, right);
			case _:
				"(" + renderAssignableExpr(context, left, "assignment") + " = " + renderExpr(context, right) + ")";
		}
	}

	static function isCompoundAssignmentOp(op:String):Bool {
		return op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%=" || op == "&=" || op == "|=" || op == "^=" || op == "<<=" || op == ">>="
			|| op == ">>>=";
	}

	static function renderCompoundAssignExpr(context:NekoEmitContext, op:String, left:HxExpr, right:HxExpr):String {
		final target = renderAssignableExpr(context, left, "compound assignment");
		return "(" + target + " " + op + " " + renderExpr(context, right) + ")";
	}

	static function renderArrayPushExpr(context:NekoEmitContext, receiver:HxExpr, value:String):String {
		return switch (receiver) {
			case EIdent(_) | EField(_, _) | EArrayAccess(_, _):
				final target = renderAssignableExpr(context, receiver, "array push receiver");
				"(function() { "
				+ target
				+ " = __hxhx_array_push("
				+ target
				+ ", "
				+ value
				+ "); return $asize("
				+ target
				+ "); })()";
			case _:
				"__hxhx_array_push(" + renderExpr(context, receiver) + ", " + value + ")";
		}
	}

	static function renderAssignableExpr(context:NekoEmitContext, expr:HxExpr, detail:String):String {
		return switch (expr) {
			case EThis:
				renderThisValueSlotExpr(context, detail);
			case EField(EIdent(className), field) if (lookupMutableStaticMemberOwner(context, className, field) != null):
				final info = lookupMutableStaticMemberOwner(context, className, field);
				renderStaticObjectRef(info.fullName) + "." + safeIdent(field);
			case EField(obj, field):
				renderExpr(context, obj) + "." + safeIdent(field);
			case EIdent(_) | EArrayAccess(_, _):
				renderExpr(context, expr);
			case _:
				unsupportedExpr(detail + " target " + exprTag(expr));
		}
	}

	static function renderThisValueSlotExpr(context:NekoEmitContext, detail:String):String {
		if (context.selfName == null)
			unsupportedExpr(detail + " target this");
		return context.selfName + ".__hx_value";
	}

	static function renderThisExpr(context:NekoEmitContext):String {
		if (context.selfName == null)
			unsupportedExpr("this");
		return isAbstractInfo(context.currentClass) ? context.selfName + ".__hx_value" : context.selfName;
	}

	static function renderPostfixIncDecExpr(context:NekoEmitContext, expr:HxExpr, delta:Int):String {
		final target = renderAssignableExpr(context, expr, delta < 0 ? "postfix decrement" : "postfix increment");
		final op = delta < 0 ? " - " + Std.string(-delta) : " + " + Std.string(delta);
		return "(function() { var __hxhx_post_old = "
			+ target
			+ "; "
			+ target
			+ " = (__hxhx_post_old"
			+ op
			+ "); return __hxhx_post_old; })()";
	}

	static function renderUnsupportedNumericLiteral(raw:String):Null<String> {
		if (raw == null || raw.length == 0)
			return null;
		var i = 0;
		if (raw.charCodeAt(0) == "-".code) {
			if (raw.length == 1)
				return null;
			i = 1;
		}
		while (i < raw.length) {
			final c = raw.charCodeAt(i);
			if (c < "0".code || c > "9".code)
				return null;
			i++;
		}
		return raw;
	}

	static function renderFloatLiteral(value:Float):String {
		final raw = Std.string(value);
		if (!isNekoNumericLiteralText(raw))
			return "null";
		return hasExponent(raw) ? '$$float(${quote(raw)})' : raw;
	}

	static function hasExponent(value:String):Bool {
		return value.indexOf("e") >= 0 || value.indexOf("E") >= 0;
	}

	static function isNekoNumericLiteralText(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		var hasDigit = false;
		for (i in 0...value.length) {
			final c = value.charCodeAt(i);
			if (c >= "0".code && c <= "9".code) {
				hasDigit = true;
				continue;
			}
			if (c == ".".code || c == "-".code || c == "+".code || c == "e".code || c == "E".code)
				continue;
			return false;
		}
		return hasDigit;
	}

	static function exprTag(expr:HxExpr):String {
		return switch (expr) {
			case ENull: "ENull";
			case EBool(_): "EBool";
			case EString(_): "EString";
			case EInt(_): "EInt";
			case EFloat(_): "EFloat";
			case EEnumValue(_): "EEnumValue";
			case EThis: "EThis";
			case ESuper: "ESuper";
			case EIdent(_): "EIdent";
			case EField(_, _): "EField";
			case ECall(_, _): "ECall";
			case EMacroExpr(_, _): "EMacroExpr";
			case EMacroType(typeText): "EMacroType(" + typeText + ")";
			case ELambda(_, _): "ELambda";
			case ETryCatchRaw(raw): "ETryCatchRaw(" + raw + ")";
			case ESwitchRaw(raw): "ESwitchRaw(" + raw + ")";
			case ESwitch(_, _, _): "ESwitch";
			case ENew(typePath, _): "ENew(" + typePath + ")";
			case EUnop(op, fixity, _):
				"EUnop("
				+ HxUnaryOperatorTools.sourceToken(op)
				+ ","
				+ (fixity == HxUnaryFixity.Postfix ? "postfix" : "prefix")
				+ ")";
			case EBinop(op, _, _): "EBinop(" + op + ")";
			case ETernary(_, _, _): "ETernary";
			case EAnon(_, _): "EAnon";
			case EArrayComprehension(_, _, _, _): "EArrayComprehension";
			case EArrayDecl(_): "EArrayDecl";
			case EArrayAccess(_, _): "EArrayAccess";
			case ERange(_, _): "ERange";
			case ECast(_, typeHint): "ECast(" + typeHint + ")";
			case EUntyped(_): "EUntyped";
			case EUnsupported(raw): "EUnsupported(" + raw + ")";
		}
	}

	static function renderAnon(context:NekoEmitContext, fieldNames:Array<String>, fieldValues:Array<HxExpr>):String {
		final tmp = "__hxhx_o";
		final parts = ["(function() { var " + tmp + " = $new(null);"];
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...count)
			parts.push(tmp + "." + safeIdent(fieldNames[i]) + " = " + sanitizeNekoValueExpr(renderExpr(context, fieldValues[i])) + ";");
		parts.push("return " + tmp + "; })()");
		return parts.join(" ");
	}

	static function sanitizeNekoValueExpr(rendered:String):String {
		return containsUnsafeNekoSourceByte(rendered) ? "null" : rendered;
	}

	static function containsUnsafeNekoSourceByte(value:String):Bool {
		if (value == null)
			return true;
		for (i in 0...value.length) {
			final c = value.charCodeAt(i);
			if (c < 32 && c != "\t".code && c != "\n".code && c != "\r".code)
				return true;
		}
		return false;
	}

	static function renderNew(context:NekoEmitContext, typePath:String, args:Array<HxExpr>):String {
		if ((typePath == "Array" || typePath == "StdTypes.Array") && args.length == 0)
			return "$array()";
		if (isListTypePath(typePath) && args.length == 0)
			return "__hxhx_list_new()";
		final mapKind = mapKindForTypePath(typePath);
		if (mapKind != null)
			return "__hxhx_map_new(" + quote(mapKind) + ")";
		if (typePath == "sys.io.Process")
			return "__hxhx_process_new(" + renderProcessConstructorArgs(context, args).join(", ") + ")";
		final info = lookupClass(context, typePath);
		if (info != null)
			return renderConstructorRef(context, info.fullName) + "(" + [for (arg in args) renderExpr(context, arg)].join(", ") + ")";
		final tmp = "__hxhx_o";
		final parts = ["(function() { var " + tmp + " = $new(null);"];
		parts.push(tmp + ".__hx_ctor = " + quote(typePath) + ";");
		parts.push(tmp + ".__hx_params = " + renderArray(context, args) + ";");
		parts.push("return " + tmp + "; })()");
		return parts.join(" ");
	}

	static function renderProcessConstructorArgs(context:NekoEmitContext, args:Array<HxExpr>):Array<String> {
		return [
			args.length > 0 ? renderExpr(context, args[0]) : "null",
			args.length > 1 ? renderExpr(context, args[1]) : "$array()",
			args.length > 2 ? renderExpr(context, args[2]) : "null"
		];
	}

	static function renderLambda(context:NekoEmitContext, args:Array<String>, body:HxExpr):String {
		final params = [for (arg in args) safeIdent(arg)];
		return "function(" + params.join(", ") + ") { return " + renderExpr(context, body) + "; }";
	}

	static function renderArray(context:NekoEmitContext, values:Array<HxExpr>):String {
		if (isMapLiteral(values))
			return renderMapLiteral(context, values);
		return "$array(" + [for (v in values) renderExpr(context, v)].join(", ") + ")";
	}

	static function isMapLiteral(values:Array<HxExpr>):Bool {
		if (values == null || values.length == 0)
			return false;
		for (value in values) {
			switch (value) {
				case EBinop("=>", _, _):
				case _:
					return false;
			}
		}
		return true;
	}

	static function renderMapLiteral(context:NekoEmitContext, entries:Array<HxExpr>):String {
		final parts = ["(function() { var __hxhx_m = __hxhx_map_new(" + quote("Map") + ");"];
		for (entry in entries) {
			switch (entry) {
				case EBinop("=>", key, value):
					parts.push("__hxhx_m.set(" + renderExpr(context, key) + ", " + renderExpr(context, value) + ");");
				case _:
			}
		}
		parts.push("return __hxhx_m; })()");
		return parts.join(" ");
	}

	static function mapKindForTypePath(typePath:String):Null<String> {
		return switch (typePath) {
			case "Map":
				"Map";
			case "haxe.ds.IntMap" | "IntMap":
				"haxe.ds.IntMap";
			case "haxe.ds.StringMap" | "StringMap":
				"haxe.ds.StringMap";
			case _:
				null;
		}
	}

	static function isListTypePath(typePath:String):Bool {
		return typePath == "List" || typePath == "haxe.ds.List";
	}

	static function renderRangeExpr(context:NekoEmitContext, start:HxExpr, end:HxExpr):String {
		final parts = [
			"(function() {",
			"var __hxhx_range_out = $array();",
			"var __hxhx_range_i = " + renderExpr(context, start) + ";",
			"var __hxhx_range_end = " + renderExpr(context, end) + ";",
			"while (__hxhx_range_i < __hxhx_range_end) {",
			"__hxhx_range_out = __hxhx_array_push(__hxhx_range_out, __hxhx_range_i);",
			"__hxhx_range_i = __hxhx_range_i + 1;",
			"}",
			"return __hxhx_range_out;",
			"})()"
		];
		return parts.join(" ");
	}

	static function renderTryCatchRaw(context:NekoEmitContext, raw:String):String {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		if (compact.indexOf("try{") == 0 && compact.indexOf("catch(e:Exception){e.stack;}") >= 0) {
			return
				"(function() { var __hxhx_probe = $new(null); __hxhx_probe.stack = $array(); try { $throw(__hxhx_probe); return null; } catch e { return e.stack; } })()";
		}
		if (compact.indexOf("try{throw") == 0 && compact.indexOf("catch(e){e;}") >= 0) {
			return "(function() { var __hxhx_probe = $new(null); try { $throw(__hxhx_probe); return null; } catch e { return e; } })()";
		}
		final bytesSub = parseBytesSubTryRaw(raw);
		if (bytesSub != null) {
			final ctor = renderBytesConstructorCall(context, bytesSub.len, "$ssub(" + bytesSub.bytes + ", " + bytesSub.pos + ", " + bytesSub.len + ")");
			return "(function() { try { return " + ctor + "; } catch e { $throw(" + quote("OutsideBounds") + "); return null; } })()";
		}
		final stringSub = parseStringSubTryRaw(raw);
		if (stringSub != null) {
			final sliced = "$ssub(" + stringSub.bytes + ", " + stringSub.pos + ", " + stringSub.len + ")";
			return "(function() { try { return " + sliced + "; } catch e { $throw(" + quote("OutsideBounds") + "); return null; } })()";
		}
		final simpleCallCatch = parseSimpleCallCatchValueRaw(raw);
		if (simpleCallCatch != null) {
			return "(function() { try { return " + simpleCallCatch + "(); } catch e { return e; } })()";
		}
		final fieldReadCatch = parseFieldReadCatchStringRaw(raw);
		if (fieldReadCatch != null) {
			return "(function() { try { return " + fieldReadCatch.receiver + "." + fieldReadCatch.field + "; } catch e { return "
				+ quote(fieldReadCatch.fallback) + "; } })()";
		}
		final methodCallCatch = parseMethodCallCatchStringRaw(raw);
		if (methodCallCatch != null) {
			return "(function() { try { return " + methodCallCatch.receiver + "." + methodCallCatch.method + "(" + quote(methodCallCatch.arg)
				+ "); } catch e { return " + quote(methodCallCatch.fallback) + "; } })()";
		}
		final nestedMethodCallCatch = parseNestedMethodCallCatchStringRaw(raw);
		if (nestedMethodCallCatch != null) {
			return "(function() { try { return " + nestedMethodCallCatch.receiver + "." + nestedMethodCallCatch.field + "." + nestedMethodCallCatch.method
				+ "(); } catch e { return " + quote(nestedMethodCallCatch.fallback) + "; } })()";
		}
		final sysPutEnvBoolTry = parseSysPutEnvBoolTryRaw(raw);
		if (sysPutEnvBoolTry != null) {
			return "(function() { try { __hxhx_sys_put_env(" + quote(sysPutEnvBoolTry.name) + ", " + sysPutEnvBoolTry.envValue + "); return "
				+ sysPutEnvBoolTry.success + "; } catch e { $print(e, \"\\n\"); return " + sysPutEnvBoolTry.fallback + "; } })()";
		}
		final hxcppAndroidMinPath = parseHxcppAndroidPlatformMinTryRaw(raw);
		if (hxcppAndroidMinPath != null) {
			return "(function() { try { return __hxhx_json_min_field_from_file("
				+ hxcppAndroidMinPath
				+ "); } catch e { $print("
				+ quote("Unable to determine minimum supported Android platform: ")
				+ ", __hxhx_string(e), \"\\n\"); return null; } })()";
		}
		final opaqueObjectLocal = parseOpaqueObjectLocalRaw(raw);
		if (opaqueObjectLocal != null) {
			return "(function() { var "
				+ opaqueObjectLocal.local
				+ " = (function() { var __hxhx_o = $new(null); __hxhx_o."
				+ opaqueObjectLocal.field
				+ " = "
				+ sanitizeNekoValueExpr(opaqueObjectLocal.value)
				+ ";"
				+ (opaqueObjectLocal.extraField == null ? "" : " __hxhx_o." + opaqueObjectLocal.extraField + " = "
					+ sanitizeNekoValueExpr(opaqueObjectLocal.extraValue) + ";")
				+ " return __hxhx_o; })(); return null; })()";
		}
		final opaqueTypedLocalRef = parseOpaqueTypedLocalRefRaw(raw);
		if (opaqueTypedLocalRef != null) {
			return "(function() { var " + opaqueTypedLocalRef + " = null; return " + opaqueTypedLocalRef + "; })()";
		}
		final opaqueTypedLocalInit = parseOpaqueTypedLocalInitRaw(raw);
		if (opaqueTypedLocalInit != null) {
			return "(function() { var "
				+ opaqueTypedLocalInit.local
				+ " = "
				+ sanitizeNekoValueExpr(opaqueTypedLocalInit.value)
				+ "; return null; })()";
		}
		final opaqueMainLoopNestedEvent = renderOpaqueMainLoopNestedEventRaw(context, raw);
		if (opaqueMainLoopNestedEvent != null)
			return opaqueMainLoopNestedEvent;
		return unsupportedExpr("ETryCatchRaw(" + raw + ")");
	}

	static function renderOpaqueMainLoopNestedEventRaw(context:NekoEmitContext, raw:String):Null<String> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final start = "opaque_block_expr:{";
		if (!StringTools.startsWith(compact, start) || !StringTools.endsWith(compact, "}"))
			return null;
		final body = compact.substr(start.length, compact.length - start.length - 1);
		final firstStopEnd = body.indexOf(".stop();var");
		if (firstStopEnd <= 0)
			return null;
		final outerEvent = body.substr(0, firstStopEnd);
		if (!isSimpleIdent(outerEvent))
			return null;
		final afterOuterStop = body.substr(firstStopEnd + ".stop();var".length);
		final localTypeMarker = ":MainEvent=null;";
		final localTypeEnd = afterOuterStop.indexOf(localTypeMarker);
		if (localTypeEnd <= 0)
			return null;
		final innerEvent = afterOuterStop.substr(0, localTypeEnd);
		if (!isSimpleIdent(innerEvent))
			return null;
		final afterLocal = afterOuterStop.substr(localTypeEnd + localTypeMarker.length);
		final addPrefix = innerEvent + "=MainLoop.add(()->{";
		if (!StringTools.startsWith(afterLocal, addPrefix))
			return null;
		final afterAddPrefix = afterLocal.substr(addPrefix.length);
		final addEnd = afterAddPrefix.indexOf("});" + innerEvent + ".delay(0);");
		if (addEnd < 0)
			return null;
		final callbackBody = afterAddPrefix.substr(0, addEnd);
		final expectedCallback = innerEvent + ".stop();pass();async.done();";
		if (callbackBody != expectedCallback)
			return null;

		final passCall = context != null
			&& context.selfName != null ? "__hxhx_field(" + context.selfName + ", " + quote("pass") + ")()" : "pass()";
		return "(function() { " + "__hxhx_field(" + safeIdent(outerEvent) + ", " + quote("stop") + ")(); " + "var " + safeIdent(innerEvent) + " = null; "
			+ safeIdent(innerEvent) + " = __hxhx_main_loop_add(function() { __hxhx_field(" + safeIdent(innerEvent) + ", " + quote("stop") + ")(); "
			+ passCall + "; __hxhx_field(async, " + quote("done") + ")(); }); " + "__hxhx_field(" + safeIdent(innerEvent) + ", " + quote("delay")
			+ ")(0); return null; })()";
	}

	static function parseBytesSubTryRaw(raw:String):Null<NekoBytesSubRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{newBytes\(([^,{}()]+),untyped__dollar__ssub\(([^,{}()]+),([^,{}()]+),([^,{}()]+)\)\);\}catch\([^)]*\)\{throwError\.OutsideBounds;\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			len: safeIdent(pattern.matched(1)),
			bytes: safeIdent(pattern.matched(2)),
			pos: safeIdent(pattern.matched(3))
		};
	}

	static function parseStringSubTryRaw(raw:String):Null<NekoBytesSubRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{newString\(untyped__dollar__ssub\(([^,{}()]+),([^,{}()]+),([^,{}()]+)\)\);\}catch\([^)]*\)\{throwError\.OutsideBounds;\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			len: safeIdent(pattern.matched(3)),
			bytes: safeIdent(pattern.matched(1)),
			pos: safeIdent(pattern.matched(2))
		};
	}

	static function parseSimpleCallCatchValueRaw(raw:String):Null<String> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\(\);\}catch\(e:[^)]+\)\{e;\}$/;
		return pattern.match(compact) ? safeIdent(pattern.matched(1)) : null;
	}

	static function parseFieldReadCatchStringRaw(raw:String):Null<NekoFieldReadCatchRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*);\}catch\(e:[^)]+\)\{"([^"]*)";\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			receiver: safeIdent(pattern.matched(1)),
			field: safeIdent(pattern.matched(2)),
			fallback: pattern.matched(3)
		};
	}

	static function parseMethodCallCatchStringRaw(raw:String):Null<NekoMethodCallCatchRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\("([^"]*)"\);\}catch\(e:[^)]+\)\{"([^"]*)";\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			receiver: safeIdent(pattern.matched(1)),
			method: safeIdent(pattern.matched(2)),
			arg: pattern.matched(3),
			fallback: pattern.matched(4)
		};
	}

	static function parseNestedMethodCallCatchStringRaw(raw:String):Null<NekoNestedMethodCallCatchRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\(\);\}catch\(e:[^)]+\)\{"([^"]*)";\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			receiver: safeIdent(pattern.matched(1)),
			field: safeIdent(pattern.matched(2)),
			method: safeIdent(pattern.matched(3)),
			fallback: pattern.matched(4)
		};
	}

	static function parseSysPutEnvBoolTryRaw(raw:String):Null<NekoSysPutEnvBoolTryRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final prefix = "try{Sys.putEnv(\"";
		if (!StringTools.startsWith(compact, prefix))
			return null;
		final afterPrefix = compact.substr(prefix.length);
		final nameEnd = afterPrefix.indexOf("\",");
		if (nameEnd < 0)
			return null;
		final name = afterPrefix.substr(0, nameEnd);
		final afterName = afterPrefix.substr(nameEnd + 2);
		final valueEnd = afterName.indexOf(");");
		if (valueEnd < 0)
			return null;
		final value = afterName.substr(0, valueEnd);
		if (value != "null" && !(StringTools.startsWith(value, "\"") && StringTools.endsWith(value, "\"")))
			return null;
		final afterCall = afterName.substr(valueEnd + 2);
		final catchMarker = ";}catch(e";
		final successEnd = afterCall.indexOf(catchMarker);
		if (successEnd < 0)
			return null;
		final success = afterCall.substr(0, successEnd);
		if (success != "true" && success != "false")
			return null;
		final afterCatchStart = afterCall.substr(successEnd + catchMarker.length);
		final traceMarker = "){trace(e);";
		final traceStart = afterCatchStart.indexOf(traceMarker);
		if (traceStart < 0)
			return null;
		final afterTrace = afterCatchStart.substr(traceStart + traceMarker.length);
		if (!StringTools.endsWith(afterTrace, ";}"))
			return null;
		final fallback = afterTrace.substr(0, afterTrace.length - 2);
		if (fallback != "true" && fallback != "false")
			return null;
		return {
			name: name,
			envValue: sanitizeNekoValueExpr(value),
			success: success,
			fallback: fallback
		};
	}

	static function parseHxcppAndroidPlatformMinTryRaw(raw:String):Null<String> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^try\{haxe\.Json\.parse\(sys\.io\.File\.getContent\(([A-Za-z_][A-Za-z0-9_]*)\)\)\.min;\}catch\(e(:[^)]*)?\)\{Log\.warn\("UnabletodetermineminimumsupportedAndroidplatform:"\+e\.toString\(\)\);null;\}$/;
		return pattern.match(compact) ? safeIdent(pattern.matched(1)) : null;
	}

	static function parseOpaqueObjectLocalRaw(raw:String):Null<NekoOpaqueObjectLocalRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final twoFieldPattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):\{([A-Za-z_][A-Za-z0-9_]*):[^}]+\}=\{([A-Za-z_][A-Za-z0-9_]*):("[^"]*"|-?[0-9.]+),([A-Za-z_][A-Za-z0-9_]*):("[^"]*"|-?[0-9.]+)\};\}$/;
		if (twoFieldPattern.match(compact)) {
			if (twoFieldPattern.matched(2) != twoFieldPattern.matched(3))
				return null;
			return {
				local: safeIdent(twoFieldPattern.matched(1)),
				field: safeIdent(twoFieldPattern.matched(2)),
				value: twoFieldPattern.matched(4),
				extraField: safeIdent(twoFieldPattern.matched(5)),
				extraValue: twoFieldPattern.matched(6)
			};
		}
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):\{([A-Za-z_][A-Za-z0-9_]*):[^}]+\}=\{([A-Za-z_][A-Za-z0-9_]*):("[^"]*"|-?[0-9.]+)\};\}$/;
		if (!pattern.match(compact))
			return null;
		if (pattern.matched(2) != pattern.matched(3))
			return null;
		return {
			local: safeIdent(pattern.matched(1)),
			field: safeIdent(pattern.matched(2)),
			value: pattern.matched(4),
			extraField: null,
			extraValue: null
		};
	}

	static function parseOpaqueTypedLocalRefRaw(raw:String):Null<String> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):[^;{}]+;\1;\}$/;
		return pattern.match(compact) ? safeIdent(pattern.matched(1)) : null;
	}

	static function parseOpaqueTypedLocalInitRaw(raw:String):Null<NekoOpaqueTypedLocalInitRaw> {
		final compact = StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", "");
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):[^=;{}]+=([A-Za-z_][A-Za-z0-9_]*|"[^"]*"|-?[0-9.]+);\}$/;
		if (!pattern.match(compact))
			return null;
		return {
			local: safeIdent(pattern.matched(1)),
			value: pattern.matched(2)
		};
	}

	static function renderBytesConstructorCall(context:NekoEmitContext, len:String, data:String):String {
		final info = lookupBytesClass(context);
		if (info != null)
			return renderConstructorRef(context, info.fullName) + "(" + len + ", " + data + ")";
		return "(function() { var __hxhx_bytes = $new(null); __hxhx_bytes.__hx_ctor = "
			+ quote("haxe.io.Bytes")
			+ "; __hxhx_bytes.__hx_params = $array("
			+ len
			+ ", "
			+ data
			+ "); return __hxhx_bytes; })()";
	}

	static function lookupBytesClass(context:NekoEmitContext):Null<NekoClassInfo> {
		final qualified = lookupClass(context, "haxe.io.Bytes");
		return qualified == null ? lookupClass(context, "Bytes") : qualified;
	}

	static function renderArrayComprehension(context:NekoEmitContext, name:String, iterable:HxExpr, guardExpr:Null<HxExpr>, yieldExpr:HxExpr):String {
		final safeName = safeIdent(name);
		final resultName = "__hxhx_comp_" + safeName;
		final iterableName = "__hxhx_iter_" + safeName;
		final indexName = "__hxhx_index_" + safeName;
		final parts = [
			"(function() {",
			"var " + resultName + " = $array();",
			"var " + iterableName + " = " + renderExpr(context, iterable) + ";",
			"var " + indexName + " = 0;",
			"while (" + indexName + " < $asize(" + iterableName + ")) {",
			"var " + safeName + " = " + iterableName + "[" + indexName + "];",
			indexName + " = " + indexName + " + 1;"
		];
		final push = resultName + " = __hxhx_array_push(" + resultName + ", " + renderExpr(context, yieldExpr) + ");";
		if (guardExpr == null) {
			parts.push(push);
		} else {
			parts.push("if " + renderExpr(context, guardExpr) + " {");
			parts.push(push);
			parts.push("}");
		}
		parts.push("}");
		parts.push("return " + resultName + ";");
		parts.push("})()");
		return parts.join(" ");
	}

	static function renderForInStmt(out:Array<String>, context:NekoEmitContext, name:String, iterable:HxExpr, body:HxStmt, indent:String):Void {
		final safeName = safeIdent(name);
		final iterableName = "__hxhx_iter_" + safeName;
		final indexName = "__hxhx_index_" + safeName;
		final bodyContext = withLocal(context, name);
		out.push(indent + "{");
		out.push(indent + "  var " + iterableName + " = " + renderExpr(context, iterable) + ";");
		out.push(indent + "  var " + indexName + " = 0;");
		out.push(indent + "  while (" + indexName + " < $asize(" + iterableName + ")) {");
		out.push(indent + "    var " + safeName + " = " + iterableName + "[" + indexName + "];");
		out.push(indent + "    " + indexName + " = " + indexName + " + 1;");
		renderStmt(out, bodyContext, body, indent + "    ");
		out.push(indent + "  }");
		out.push(indent + "}");
	}

	static function renderForKeyValueStmt(out:Array<String>, context:NekoEmitContext, keyName:String, valueName:String, iterable:HxExpr, body:HxStmt,
			indent:String):Void {
		final safeKeyName = safeIdent(keyName);
		final safeValueName = safeIdent(valueName);
		final bodyContext = withLocals(context, [keyName, valueName]);
		final sourceName = "__hxhx_kv_source_" + safeKeyName;
		final fieldsName = "__hxhx_kv_fields_" + safeKeyName;
		final fieldName = "__hxhx_kv_field_" + safeKeyName;
		final indexName = "__hxhx_kv_index_" + safeKeyName;
		out.push(indent + "{");
		out.push(indent + "  var " + sourceName + " = " + renderExpr(context, iterable) + ";");
		out.push(indent + "  var " + fieldsName + " = $objfields(" + sourceName + ");");
		out.push(indent + "  var " + indexName + " = 0;");
		out.push(indent + "  while (" + indexName + " < $asize(" + fieldsName + ")) {");
		out.push(indent + "    var " + fieldName + " = " + fieldsName + "[" + indexName + "];");
		out.push(indent + "    " + indexName + " = " + indexName + " + 1;");
		out.push(indent + "    var " + safeKeyName + " = $field(" + fieldName + ");");
		out.push(indent + "    var " + safeValueName + " = $objget(" + sourceName + ", " + fieldName + ");");
		renderStmt(out, bodyContext, body, indent + "    ");
		out.push(indent + "  }");
		out.push(indent + "}");
	}

	static function renderSwitchStmt(out:Array<String>, context:NekoEmitContext, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, bodies:Array<HxStmt>,
			indent:String):Void {
		if (switchNeedsIfLowering(patterns)) {
			renderSwitchIfStmt(out, context, scrutinee, patterns, bodies, indent);
			return;
		}
		final count = patterns == null || bodies == null ? 0 : (patterns.length < bodies.length ? patterns.length : bodies.length);
		out.push(indent + "switch " + renderExpr(context, scrutinee) + " {");
		for (i in 0...count) {
			final pattern = patterns[i];
			final prefix:Null<String> = switch (pattern) {
				case PWildcard | PBind(_):
					"default";
				case PNull | PBool(_) | PString(_) | PInt(_) | PEnumValue(_) | PEnumExtract(_, _):
					renderSwitchPatternValue(pattern);
				case PCapture(_, inner):
					renderSwitchPatternValue(inner);
				case PUnsupportedGuard(_):
					null;
				case PObject(_, _) | PArray(_) | PExtractor(_, _) | PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PIntEqualsGuard(_, _, _) |
					PIntCompareGuard(_, _, _, _) | PParsedIntSwitchGuard(_, _, _, _) | POr(_):
					unsupported("switch pattern", patternKind(pattern));
			}
			if (prefix == null)
				continue;
			out.push(indent + "  " + prefix + " => {");
			renderStmt(out, context, bodies[i], indent + "    ");
			out.push(indent + "  }");
		}
		out.push(indent + "}");
	}

	static function renderSwitchExpr(context:NekoEmitContext, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>):String {
		if (switchNeedsIfLowering(patterns))
			return renderSwitchIfExpr(context, scrutinee, patterns, exprs);
		final cases = new Array<String>();
		final count = patterns == null || exprs == null ? 0 : (patterns.length < exprs.length ? patterns.length : exprs.length);
		for (i in 0...count) {
			final rendered = renderSwitchCase(context, patterns[i], exprs[i]);
			if (rendered != null)
				cases.push(rendered);
		}
		return "switch " + renderExpr(context, scrutinee) + " { " + cases.join(" ") + " }";
	}

	static function renderSwitchIfStmt(out:Array<String>, context:NekoEmitContext, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, bodies:Array<HxStmt>,
			indent:String):Void {
		final count = patterns == null || bodies == null ? 0 : (patterns.length < bodies.length ? patterns.length : bodies.length);
		final switchValue = "__hxhx_switch";
		out.push(indent + "{");
		out.push(indent + "  var " + switchValue + " = " + renderExpr(context, scrutinee) + ";");
		var emitted = false;
		for (i in 0...count) {
			final lowered = lowerNekoSwitchPattern(patterns[i], switchValue);
			out.push(indent + "  " + (emitted ? "else " : "") + "if (" + lowered.cond + ") {");
			renderNekoSwitchBindings(out, lowered.bindings, indent + "    ");
			renderStmt(out, context, bodies[i], indent + "    ");
			out.push(indent + "  }");
			emitted = true;
		}
		out.push(indent + "}");
	}

	static function renderSwitchIfExpr(context:NekoEmitContext, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>):String {
		final count = patterns == null || exprs == null ? 0 : (patterns.length < exprs.length ? patterns.length : exprs.length);
		final switchValue = "__hxhx_switch";
		final parts = [
			"(function() { var " + switchValue + " = " + renderExpr(context, scrutinee) + ";"
		];
		var emitted = false;
		for (i in 0...count) {
			final lowered = lowerNekoSwitchPattern(patterns[i], switchValue);
			parts.push((emitted ? "else " : "") + "if (" + lowered.cond + ") {");
			for (binding in lowered.bindings)
				parts.push("var " + safeIdent(binding.name) + " = " + binding.expr + ";");
			parts.push("return " + renderExpr(context, exprs[i]) + ";");
			parts.push("}");
			emitted = true;
		}
		parts.push("return null; })()");
		return parts.join(" ");
	}

	static function renderNekoSwitchBindings(out:Array<String>, bindings:Array<NekoSwitchPatternBinding>, indent:String):Void {
		if (bindings == null)
			return;
		for (binding in bindings)
			out.push(indent + "var " + safeIdent(binding.name) + " = " + binding.expr + ";");
	}

	static function switchNeedsIfLowering(patterns:Array<HxSwitchPattern>):Bool {
		if (patterns == null)
			return false;
		for (pattern in patterns)
			if (patternNeedsNekoIfLowering(pattern))
				return true;
		return false;
	}

	static function patternNeedsNekoIfLowering(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PObject(_, _) | PArray(_) | PExtractor(_, _) | PEnumValue(_) | PEnumExtract(_, _) | PIntEqualsGuard(_, _, _) | PIntCompareGuard(_, _, _, _):
				true;
			case PCapture(_, inner) | PUnsupportedGuard(inner):
				patternNeedsNekoIfLowering(inner);
			case POr(_):
				true;
			case _:
				false;
		}
	}

	static function lowerNekoSwitchPattern(pattern:HxSwitchPattern, scrutinee:String):NekoSwitchPatternLowered {
		return switch (pattern) {
			case PNull:
				{cond: "(" + scrutinee + " == null)", bindings: []};
			case PWildcard:
				{cond: "true", bindings: []};
			case PBool(value):
				{cond: "(" + scrutinee + " == " + (value ? "true" : "false") + ")", bindings: []};
			case PString(value):
				{cond: "(" + scrutinee + " == " + quote(value) + ")", bindings: []};
			case PInt(value):
				{cond: "(" + scrutinee + " == " + Std.string(value) + ")", bindings: []};
			case PEnumValue(name):
				{cond: nekoEnumCtorCond(scrutinee, name), bindings: []};
			case PEnumExtract(name, args):
				lowerNekoEnumExtractPattern(name, args, scrutinee);
			case PBind(name):
				{cond: "true", bindings: [{name: name, expr: scrutinee}]};
			case PCapture(name, inner):
				final lowered = lowerNekoSwitchPattern(inner, scrutinee);
				final bindings = lowered.bindings.copy();
				bindings.push({name: name, expr: scrutinee});
				{cond: lowered.cond, bindings: bindings};
			case PArray(items):
				lowerNekoArrayPattern(items, scrutinee);
			case PObject(fieldNames, fieldPatterns):
				lowerNekoObjectPattern(fieldNames, fieldPatterns, scrutinee);
			case PExtractor(extractorText, resultPattern):
				lowerNekoExtractorPattern(extractorText, resultPattern, scrutinee);
			case PUnsupportedGuard(inner):
				final lowered = lowerNekoSwitchPattern(inner, scrutinee);
				{cond: "(" + lowered.cond + " && false)", bindings: lowered.bindings};
			case PIntEqualsGuard(inner, bindingName, value):
				final lowered = lowerNekoSwitchPattern(inner, scrutinee);
				final bound = nekoSwitchBindingValue(bindingName, lowered.bindings);
				{cond: "((" + lowered.cond + ") && (" + bound + " == " + Std.string(value) + "))", bindings: lowered.bindings};
			case PIntCompareGuard(inner, bindingName, op, value):
				final lowered = lowerNekoSwitchPattern(inner, scrutinee);
				final bound = nekoSwitchBindingValue(bindingName, lowered.bindings);
				{cond: "((" + lowered.cond + ") && " + nekoIntCompareGuardCond(bound, op, value) + ")", bindings: lowered.bindings};
			case POr(patterns):
				lowerNekoOrPattern(patterns, scrutinee);
			case PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PParsedIntSwitchGuard(_, _, _, _):
				unsupportedSwitchPatternLowering(pattern);
		}
	}

	static function nekoEnumCtorCond(scrutinee:String, name:String):String {
		return "__hxhx_enum_ctor_is(" + scrutinee + ", " + quote(name) + ")";
	}

	static function lowerNekoEnumExtractPattern(name:String, args:Array<HxSwitchPattern>, scrutinee:String):NekoSwitchPatternLowered {
		final params = "__hxhx_enum_params(" + scrutinee + ")";
		final count = args == null ? 0 : args.length;
		final conds = [nekoEnumCtorCond(scrutinee, name), "($asize(" + params + ") >= " + count + ")"];
		final bindings = new Array<NekoSwitchPatternBinding>();
		if (args != null) {
			for (i in 0...args.length) {
				final lowered = lowerNekoSwitchPattern(args[i], params + "[" + i + "]");
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function nekoIntCompareGuardCond(value:String, op:String, expected:Int):String {
		return switch (op) {
			case "<" | "<=" | ">" | ">=":
				"(" + value + " " + op + " " + Std.string(expected) + ")";
			case _:
				"false";
		}
	}

	static function lowerNekoExtractorPattern(extractorText:String, resultPattern:HxSwitchPattern, scrutinee:String):NekoSwitchPatternLowered {
		final applied = switch (StringTools.trim(extractorText)) {
			case "Std.parseInt(_)":
				nekoStdParseIntExpr(scrutinee);
			case _:
				null;
		}
		final lowered = lowerNekoSwitchPattern(resultPattern, applied == null ? scrutinee : applied);
		if (applied == null)
			return {cond: "false", bindings: lowered.bindings};
		return lowered;
	}

	static function nekoStdParseIntExpr(value:String):String {
		return "(function(__hxhx_extract) { var __hxhx_extract_t = $typeof(__hxhx_extract);"
			+ " if (__hxhx_extract_t == $tint) return __hxhx_extract;"
			+ " if (__hxhx_extract_t == $tfloat) return $int(__hxhx_extract);"
			+ " if (__hxhx_extract_t != $tobject) return null;"
			+ " return $int(__hxhx_extract.__s); })("
			+ value
			+ ")";
	}

	static function lowerNekoObjectPattern(fieldNames:Array<String>, fieldPatterns:Array<HxSwitchPattern>, scrutinee:String):NekoSwitchPatternLowered {
		final conds = ["(" + scrutinee + " != null)"];
		final bindings = new Array<NekoSwitchPatternBinding>();
		if (fieldNames != null && fieldPatterns != null) {
			final count = fieldNames.length < fieldPatterns.length ? fieldNames.length : fieldPatterns.length;
			for (i in 0...count) {
				final fieldExpr = "$objget(" + scrutinee + ", $hash(" + quote(fieldNames[i]) + "))";
				final lowered = lowerNekoSwitchPattern(fieldPatterns[i], fieldExpr);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerNekoArrayPattern(items:Array<HxSwitchPattern>, scrutinee:String):NekoSwitchPatternLowered {
		final count = items == null ? 0 : items.length;
		final conds = ["(" + scrutinee + " != null)", "($asize(" + scrutinee + ") == " + count + ")"];
		final bindings = new Array<NekoSwitchPatternBinding>();
		if (items != null) {
			for (i in 0...items.length) {
				final lowered = lowerNekoSwitchPattern(items[i], scrutinee + "[" + i + "]");
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerNekoOrPattern(patterns:Array<HxSwitchPattern>, scrutinee:String):NekoSwitchPatternLowered {
		final conds = new Array<String>();
		if (patterns != null) {
			for (pattern in patterns)
				conds.push("(" + lowerNekoSwitchPattern(pattern, scrutinee).cond + ")");
		}
		return {cond: conds.length == 0 ? "false" : "(" + conds.join(" || ") + ")", bindings: []};
	}

	static function nekoSwitchBindingValue(name:String, bindings:Array<NekoSwitchPatternBinding>):String {
		if (bindings != null) {
			for (binding in bindings)
				if (binding.name == name)
					return binding.expr;
		}
		return safeIdent(name);
	}

	static function unsupportedSwitchPatternLowering(pattern:HxSwitchPattern):NekoSwitchPatternLowered {
		unsupported("switch pattern", patternKind(pattern));
		return {cond: "false", bindings: []};
	}

	static function renderSwitchCase(context:NekoEmitContext, pattern:HxSwitchPattern, expr:HxExpr):Null<String> {
		return switch (pattern) {
			case PWildcard | PBind(_):
				"default => " + renderExpr(context, expr);
			case PNull | PBool(_) | PString(_) | PInt(_) | PEnumValue(_) | PEnumExtract(_, _):
				renderSwitchPatternValue(pattern) + " => " + renderExpr(context, expr);
			case PCapture(_, inner):
				renderSwitchCase(context, inner, expr);
			case PUnsupportedGuard(_):
				null;
			case PObject(_, _) | PArray(_) | PExtractor(_, _) | PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PIntEqualsGuard(_, _, _) |
				PIntCompareGuard(_, _, _, _) | PParsedIntSwitchGuard(_, _, _, _) | POr(_):
				unsupported("switch pattern", patternKind(pattern));
		}
	}

	static function renderSwitchPatternValue(pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PNull:
				"null";
			case PBool(value):
				value ? "true" : "false";
			case PString(value):
				quote(value);
			case PInt(value):
				Std.string(value);
			case PEnumValue(name) | PEnumExtract(name, _):
				quote(name);
			case _:
				unsupported("switch pattern", patternKind(pattern));
		}
	}

	static function patternKind(pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PNull: "PNull";
			case PWildcard: "PWildcard";
			case PBool(_): "PBool";
			case PString(_): "PString";
			case PInt(_): "PInt";
			case PEnumValue(_): "PEnumValue";
			case PEnumExtract(_, _): "PEnumExtract";
			case PObject(_, _): "PObject";
			case PCapture(_, _): "PCapture";
			case PArray(_): "PArray";
			case PExtractor(_, _): "PExtractor";
			case PLengthGuard(_, _, _): "PLengthGuard";
			case PStartsWithGuard(_, _, _): "PStartsWithGuard";
			case PIntEqualsGuard(_, _, _): "PIntEqualsGuard";
			case PIntCompareGuard(_, _, _, _): "PIntCompareGuard";
			case PParsedIntSwitchGuard(_, _, _, _): "PParsedIntSwitchGuard";
			case PUnsupportedGuard(_): "PUnsupportedGuard";
			case PBind(_): "PBind";
			case POr(_): "POr";
		}
	}

	static function renderCall(context:NekoEmitContext, callee:HxExpr, args:Array<HxExpr>):String {
		switch (callee) {
			case EIdent("__hxhx_try"):
				return renderStructuralTryCatchExpr(context, args);
			case EIdent("__hxhx_throw"):
				return "$throw(" + (args.length > 0 ? renderExpr(context, args[0]) : "null") + ")";
			case _:
		}
		final renderedArgs = [for (arg in args) renderExpr(context, arg)];
		switch (callee) {
			case EIdent("trace"):
				return "$print(" + renderedArgs.concat([quote("\n")]).join(", ") + ")";
			case EField(EIdent("Sys"), "args"):
				return "$loader.args";
			case EField(EField(EIdent("unit"), "UnitBuilder"), "generateSpec") | EField(EIdent("UnitBuilder"), "generateSpec"):
				return "$array()";
			case EField(EIdent("TestIssues"), "addIssueClasses") | EField(EField(EIdent("unit"), "TestIssues"), "addIssueClasses"):
				return "null";
			case EField(EIdent("Compiler"), "getDefine") | EField(EField(EField(EIdent("haxe"), "macro"), "Compiler"), "getDefine"):
				return "null";
			case EField(EIdent("Compiler"), "define") | EField(EField(EField(EIdent("haxe"), "macro"), "Compiler"), "define"):
				return "null";
			case EField(EIdent("Compiler"), "excludeFile") | EField(EField(EField(EIdent("haxe"), "macro"), "Compiler"), "excludeFile"):
				return "null";
			case EField(EField(EIdent("neko"), "Web"), "setHeader") | EField(EIdent("Web"), "setHeader"):
				return "null";
			case EField(EIdent("Type"), "getClass") if (args.length >= 1):
				return "__hxhx_type_get_class(" + renderedArgs[0] + ")";
			case EField(EIdent("Type"), "getClassName") if (args.length >= 1):
				return "__hxhx_type_class_name(" + renderedArgs[0] + ")";
			case EField(EIdent("Type"), "getInstanceFields") if (args.length >= 1):
				return "__hxhx_type_fields(__hxhx_instance_fields, " + renderedArgs[0] + ")";
			case EField(EIdent("Type"), "getClassFields") if (args.length >= 1):
				return "__hxhx_type_fields(__hxhx_static_fields, " + renderedArgs[0] + ")";
			case EField(EIdent("Reflect"), "isObject") if (args.length >= 1):
				return "(" + renderedArgs[0] + " != null && $typeof(" + renderedArgs[0] + ") == $tobject)";
			case EField(EIdent("Reflect"), "hasField") if (args.length >= 2):
				return "__hxhx_reflect_has_field(" + renderedArgs[0] + ", " + renderedArgs[1] + ")";
			case EField(EIdent("Reflect"), "field") if (args.length >= 2):
				return "(if (" + renderedArgs[0] + " == null) null else $objget(" + renderedArgs[0] + ", $hash(" + renderedArgs[1] + ")))";
			case EField(EIdent("Reflect"), "fields") if (args.length >= 1):
				return "__hxhx_reflect_fields(" + renderedArgs[0] + ")";
			case EField(EIdent("Reflect"), "isFunction") if (args.length >= 1):
				return "__hxhx_reflect_is_function(" + renderedArgs[0] + ")";
			case EField(EIdent("Reflect"), "callMethod") if (args.length >= 3):
				return "__hxhx_reflect_call_method(" + renderedArgs[0] + ", " + renderedArgs[1] + ", " + renderedArgs[2] + ")";
			case EField(EIdent("StringTools"), "startsWith") if (args.length >= 2):
				return "__hxhx_string_starts_with(" + renderedArgs[0] + ", " + renderedArgs[1] + ")";
			case EField(EIdent("StringTools"), "endsWith") if (args.length >= 2):
				return "__hxhx_string_ends_with(" + renderedArgs[0] + ", " + renderedArgs[1] + ")";
			case EEnumValue(name):
				return renderEnumCtorCall(name, renderedArgs);
			case EField(receiver, method) if (lookupCurrentAbstractValueHelper(context, method) != null):
				return renderFunctionRef(context, context.currentClass.fullName, method) + "(" + renderExpr(context, receiver) + ")";
			case EField(receiver, "getNdllSuffix") if (hasNativeDecodedNekoArchAbstract(context)):
				return "__hxhx_neko_ndll_suffix(" + renderExpr(context, receiver) + ")";
			case EField(EIdent("Sys"), "systemName"):
				return "__hxhx_sys_system_name()";
			case EField(EIdent("Sys"), "getEnv") if (args.length >= 1):
				return "__hxhx_sys_get_env(" + renderedArgs[0] + ")";
			case EField(EIdent("Sys"), "putEnv") if (args.length >= 2):
				return "__hxhx_sys_put_env(" + renderedArgs[0] + ", " + renderedArgs[1] + ")";
			case EField(EIdent("Sys"), "print"):
				return "$print(" + renderedArgs.join(", ") + ")";
			case EField(EIdent("Sys"), "println"):
				return "$print(" + renderedArgs.concat([quote("\n")]).join(", ") + ")";
			case EField(EIdent("MainLoop"), "add") | EField(EField(EIdent("haxe"), "MainLoop"), "add") if (args.length >= 1):
				return "__hxhx_main_loop_add(" + renderedArgs[0] + ")";
			case EField(receiver, "indexOf") if (args.length >= 1):
				return "__hxhx_array_indexOf(" + renderExpr(context, receiver) + ", " + renderedArgs[0] + ")";
			case EField(receiver, "push") if (args.length >= 1):
				return renderArrayPushExpr(context, receiver, renderedArgs[0]);
			case EField(receiver, "endsWith") if (args.length >= 1):
				return "__hxhx_string_ends_with(" + renderExpr(context, receiver) + ", " + renderedArgs[0] + ")";
			case EField(ESuper, _):
				return "null";
			case EField(EIdent(className), method) if (isUpperStart(className)):
				final info = lookupClass(context, className);
				final fn = info == null ? null : findFunction(info.cls, method, true);
				if (info != null && fn != null && !isDynamicStaticFunction(fn))
					return renderFunctionRef(context, info.fullName, method) + "(" + renderedArgs.join(", ") + ")";
				final staticFieldOwner = lookupMutableStaticMemberOwner(context, className, method);
				if (staticFieldOwner != null)
					return "__hxhx_field("
						+ renderStaticObjectRef(staticFieldOwner.fullName)
						+ ", "
						+ quote(method)
						+ ")("
						+ renderedArgs.join(", ")
						+ ")";
				final fullClassName = info == null ? className : info.fullName;
				return renderFunctionRef(context, fullClassName, method) + "(" + renderedArgs.join(", ") + ")";
			case _:
				return renderExpr(context, callee) + "(" + renderedArgs.join(", ") + ")";
		}
	}

	/**
		Emit the shared expression-level try/catch shape as a Neko immediate function.

		The typer has already reconstructed the try body and catch branches, so this
		method only chooses Neko syntax. It must not reparse source text or decide
		which catch body applies.
	**/
	static function renderStructuralTryCatchExpr(context:NekoEmitContext, args:Array<HxExpr>):String {
		if (args == null || args.length < 2)
			return unsupportedExpr("ECall(__hxhx_try)");
		final tryBody = switch (args[0]) {
			case ELambda(lambdaArgs, body) if (lambdaArgs.length == 0): body;
			case _: null;
		};
		if (tryBody == null)
			return unsupportedExpr("ECall(__hxhx_try)");

		final catches = switch (args[1]) {
			case EArrayDecl(entries): entries;
			case _: [];
		};
		if (catches.length == 0) {
			return "(function() { try { return " + renderExpr(context, tryBody) + "; } catch __hxhx_e { $throw(__hxhx_e); return null; } })()";
		}

		return switch (catches[0]) {
			case EArrayDecl([EString(name), EString(_), ELambda(lambdaArgs, catchBody)]) if (lambdaArgs.length == 1):
				final sourceName = lambdaArgs[0].length == 0 ? name : lambdaArgs[0];
				final catchName = safeIdent(sourceName);
				final catchContext = context == null ? context : withLocal(context, sourceName);
				"(function() { try { return "
				+ renderExpr(context, tryBody)
				+ "; } catch "
				+ catchName
				+ " { return "
				+ renderExpr(catchContext, catchBody)
				+ "; } })()";
			case _:
				unsupportedExpr("ECall(__hxhx_try)");
		};
	}

	static function renderEnumCtorCall(name:String, renderedArgs:Array<String>):String {
		return "__hxhx_enum_value(" + quote(name) + ", $array(" + renderedArgs.join(", ") + "))";
	}

	static function isNekoLoaderLocalGetPathCall(expr:HxExpr):Bool {
		return switch (expr) {
			case ECall(EField(ECall(EField(EField(EField(EIdent("neko"), "vm"), "Loader"), "local"), localArgs), "getPath"),
				getPathArgs): localArgs.length == 0 && getPathArgs.length == 0;
			case _:
				false;
		}
	}

	static function lookupClass(context:NekoEmitContext, typePath:String):Null<NekoClassInfo> {
		if (context == null)
			return null;
		if (typePath == null || typePath.length == 0)
			return null;
		final exact = context.classes.get(typePath);
		if (exact != null)
			return exact;
		final shortName = typePath.split(".").pop();
		return context.classes.get(shortName);
	}

	static function lookupMutableStaticMemberOwner(context:NekoEmitContext, className:String, fieldName:String):Null<NekoClassInfo> {
		final info = lookupClass(context, className);
		if (info == null)
			return null;
		for (field in HxClassDecl.getFields(info.cls)) {
			if (HxFieldDecl.getIsStatic(field) && HxFieldDecl.getName(field) == fieldName)
				return info;
		}
		for (fn in HxClassDecl.getFunctions(info.cls)) {
			if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == fieldName && isDynamicStaticFunction(fn))
				return info;
		}
		return null;
	}

	static function lookupCurrentAbstractValueHelper(context:NekoEmitContext, method:String):Null<HxFunctionDecl> {
		if (context == null || context.currentClass == null)
			return null;
		final fn = findFunction(context.currentClass.cls, method, true);
		return fn != null && isAbstractValueHelperFunction(fn) ? fn : null;
	}

	static function isSysIoProcessTypePath(typePath:String):Bool {
		return typePath == "sys.io.Process";
	}

	static function renderStaticObjectRef(fullClassName:String):String {
		return "__hxhx_static_object(" + quote(fullClassName) + ")";
	}

	static function findFunction(cls:HxClassDecl, name:String, isStatic:Bool):Null<HxFunctionDecl> {
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == name && HxFunctionDecl.getIsStatic(fn) == isStatic)
				return fn;
		}
		return null;
	}

	static function isCurrentInstanceMethod(context:NekoEmitContext, name:String):Bool {
		if (context.currentClass == null)
			return false;
		final fn = findFunction(context.currentClass.cls, name, false);
		return fn != null && HxFunctionDecl.getName(fn) != "new" && !isMacroFunction(fn);
	}

	/**
		Resolves a bare identifier inside the current Neko emission scope.

		Local names win first so method parameters, `var` declarations, loop binders,
		and catch binders do not get rewritten accidentally. If no local shadows the
		name, current-class instance methods and fields are emitted through the
		constructor-created receiver object so constructor/method bodies mutate the
		real instance state instead of unqualified Neko globals.
	**/
	static function renderIdent(context:NekoEmitContext, name:String):String {
		if (context == null)
			return safeIdent(name);
		if (isLocalName(context, name))
			return safeIdent(name);
		if (isEnumAbstractConstantName(context, name))
			return quote(name);
		if (context.selfName != null && isCurrentInstanceMethod(context, name))
			return context.selfName + "." + safeIdent(name);
		if (context.selfName != null && isCurrentInstanceField(context, name))
			return context.selfName + "." + safeIdent(name);
		if (isCurrentStaticFunction(context, name))
			return renderFunctionRef(context, context.currentClass.fullName, name);
		return safeIdent(name);
	}

	static function isCurrentStaticFunction(context:NekoEmitContext, name:String):Bool {
		if (context.currentClass == null)
			return false;
		final fn = findFunction(context.currentClass.cls, name, true);
		return fn != null && !isMacroFunction(fn);
	}

	static function isDynamicStaticFunction(fn:HxFunctionDecl):Bool {
		return HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getMetadata(fn).indexOf("dynamic") >= 0;
	}

	static function isEnumAbstractConstantName(context:NekoEmitContext, name:String):Bool {
		if (context.currentClass == null || name == null || name.length == 0 || !isUpperStart(name))
			return false;
		if (!hasNativeDecodedNekoArchAbstract(context))
			return false;
		for (field in HxClassDecl.getFields(context.currentClass.cls)) {
			if (HxFieldDecl.getIsStatic(field) && HxFieldDecl.getName(field) == name && HxFieldDecl.getInit(field) == null && isNekoArchConstantName(name))
				return true;
		}
		return isNekoArchConstantName(name) && lookupClass(context, name) == null;
	}

	static function hasNativeDecodedNekoArchAbstract(context:NekoEmitContext):Bool {
		if (context == null || context.classes == null)
			return false;
		for (info in context.classes) {
			if (isAbstractInfo(info) && info.fullName == "Arch")
				return true;
		}
		return false;
	}

	static function isNekoArchConstantName(name:String):Bool {
		return name == "Arm64" || name == "Arm" || name == "X86_64" || name == "X86";
	}

	static function isAbstractValueHelperFunction(fn:HxFunctionDecl):Bool {
		if (fn == null || !HxFunctionDecl.getIsStatic(fn) || HxFunctionDecl.getArgs(fn).length != 0)
			return false;
		final body = HxFunctionDecl.getBody(fn);
		if (body.length != 1)
			return false;
		return switch (body[0]) {
			case SReturn(ESwitch(EIdent("abstract"), _, _), _):
				true;
			case _:
				false;
		}
	}

	static function isAbstractInfo(info:Null<NekoClassInfo>):Bool {
		return info != null && HxClassDecl.getMetadata(info.cls).indexOf("__hxhx_abstract") >= 0;
	}

	static function isCurrentInstanceField(context:NekoEmitContext, name:String):Bool {
		if (context.currentClass == null)
			return false;
		for (field in HxClassDecl.getFields(context.currentClass.cls)) {
			if (!HxFieldDecl.getIsStatic(field) && HxFieldDecl.getName(field) == name)
				return true;
		}
		return false;
	}

	static function isLocalName(context:NekoEmitContext, name:String):Bool {
		return context.locals != null && context.locals.exists(name);
	}

	static function emptyLocals():StringMap<Bool> {
		return new StringMap<Bool>();
	}

	static function cloneLocals(locals:StringMap<Bool>):StringMap<Bool> {
		final copy = new StringMap<Bool>();
		if (locals != null) {
			for (name in locals.keys())
				copy.set(name, true);
		}
		return copy;
	}

	static function childContext(context:NekoEmitContext):NekoEmitContext {
		return {
			classes: context.classes,
			selfName: context.selfName,
			currentClass: context.currentClass,
			symbolTable: context.symbolTable,
			locals: cloneLocals(context.locals),
			insideTry: context.insideTry,
			breakFlag: context.breakFlag
		};
	}

	static function registerLocal(context:NekoEmitContext, name:String):Void {
		if (context.locals != null)
			context.locals.set(name, true);
	}

	static function withLocal(context:NekoEmitContext, name:String):NekoEmitContext {
		final next = childContext(context);
		registerLocal(next, name);
		return next;
	}

	static function withLocals(context:NekoEmitContext, names:Array<String>):NekoEmitContext {
		final next = childContext(context);
		for (name in names)
			registerLocal(next, name);
		return next;
	}

	static function withFunctionArgs(context:NekoEmitContext, fn:HxFunctionDecl):NekoEmitContext {
		final names = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			names.push(arg.name);
		return withLocals(context, names);
	}

	static function withInsideTry(context:NekoEmitContext):NekoEmitContext {
		final next = childContext(context);
		next.insideTry = true;
		return next;
	}

	static function withBreakFlag(context:NekoEmitContext, flag:String):NekoEmitContext {
		final next = childContext(context);
		next.breakFlag = flag;
		return next;
	}

	static function isMacroFunction(fn:HxFunctionDecl):Bool {
		for (meta in HxFunctionDecl.getMetadata(fn)) {
			if (meta == "macro")
				return true;
		}
		return false;
	}

	static function withSelf(context:NekoEmitContext, selfName:String, info:NekoClassInfo):NekoEmitContext {
		return {
			classes: context.classes,
			selfName: selfName,
			currentClass: info,
			symbolTable: context.symbolTable,
			locals: cloneLocals(context.locals),
			insideTry: context.insideTry,
			breakFlag: context.breakFlag
		};
	}

	static function withCurrentClass(context:NekoEmitContext, info:NekoClassInfo):NekoEmitContext {
		return {
			classes: context.classes,
			selfName: context.selfName,
			currentClass: info,
			symbolTable: context.symbolTable,
			locals: cloneLocals(context.locals),
			insideTry: context.insideTry,
			breakFlag: context.breakFlag
		};
	}

	static function matchesMain(requested:String, fullClassName:String):Bool {
		return requested == null || requested.length == 0 || requested == fullClassName || requested == fullClassName.split(".").pop();
	}

	static function mangleConstructor(fullClassName:String):String {
		return "__hxhx_new_" + safeIdent(StringTools.replace(fullClassName, ".", "_"));
	}

	static function mangleFunction(fullClassName:String, method:String):String {
		return safeIdent(StringTools.replace(fullClassName, ".", "_") + "_" + method);
	}

	static function renderConstructorDefinitionPrefix(context:NekoEmitContext, fullClassName:String):String {
		final name = mangleConstructor(fullClassName);
		return context.symbolTable == null ? "var " + name + " = " : context.symbolTable + "." + name + " = ";
	}

	static function renderFunctionDefinitionPrefix(context:NekoEmitContext, fullClassName:String, method:String):String {
		final name = mangleFunction(fullClassName, method);
		return context.symbolTable == null ? "var " + name + " = " : context.symbolTable + "." + name + " = ";
	}

	static function renderConstructorRef(context:NekoEmitContext, fullClassName:String):String {
		final name = mangleConstructor(fullClassName);
		return context != null && context.symbolTable != null ? context.symbolTable + "." + name : name;
	}

	static function renderFunctionRef(context:NekoEmitContext, fullClassName:String, method:String):String {
		final name = mangleFunction(fullClassName, method);
		return context != null && context.symbolTable != null ? context.symbolTable + "." + name : name;
	}

	static function isUpperStart(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}

	static function safeIdent(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= "a".code && c <= "z".code)
				|| (c >= "A".code && c <= "Z".code)
				|| c == "_".code
				|| (i > 0 && c >= "0".code && c <= "9".code);
			out.addChar(ok ? c : "_".code);
		}
		return out.toString();
	}

	static function isSimpleIdent(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= "a".code && c <= "z".code)
				|| (c >= "A".code && c <= "Z".code)
				|| c == "_".code
				|| (i > 0 && c >= "0".code && c <= "9".code);
			if (!ok)
				return false;
		}
		final first = name.charCodeAt(0);
		return !(first >= "0".code && first <= "9".code);
	}

	static function quote(value:String):String {
		return '"' + StringTools.replace(StringTools.replace(StringTools.replace(value, "\\", "\\\\"), "\n", "\\n"), '"', '\\"') + '"';
	}

	static function shellQuote(value:String):String {
		return "'" + StringTools.replace(value, "'", "'\\''") + "'";
	}

	static function ensureDirectory(path:String):Void {
		if (path == null || path.length == 0 || FileSystem.exists(path))
			return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			ensureDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function unsupported(kind:String, detail:String):String {
		throw "Neko native backend MVP does not yet support " + kind + ": " + detail;
	}

	static function unsupportedExpr(detail:String):String {
		return unsupported("expression", detail);
	}
}
