package hxhx;

import haxe.ds.StringMap;
import hxhx.macro.MacroRuntimeMode;
import hxhx.macro.MacroRuntimeSession;

/**
	Runs supported `@:build` macros before a module becomes visible to typing.

	Stage3 deliberately discovers some imported modules only when type checking
	reaches them. This request-owned preparer gives eagerly resolved roots and
	lazily loaded dependencies the same sequence:

	1. collect the module's build-macro expressions;
	2. start the selected macro runtime when required;
	3. run each expression once in source order;
	4. merge the generated members into the parsed declaration; and
	5. return the rebuilt module carrying its generated-declaration revision.

	Prepared modules are remembered only for the current request. The class does
	not cache macro results or typed modules across compiler-server requests.
**/
class Stage3BuildMacroPreparer {
	final runtimeMode:String;
	final typeOnly:Bool;
	final hadConfiguredExternalHost:Bool;
	final macroHostClassPaths:Array<String>;
	final requestContext:CompilationRequestContext;
	final output:CompilationRequestOutput;
	final prepared:StringMap<ResolvedModule>;
	final autoBuiltEntrypoints:StringMap<Bool>;
	var session:Null<MacroRuntimeSession>;
	var autoBuiltExternalHost:Bool;
	var skippedIndex:Int;
	var closed:Bool;

	public function new(runtimeMode:String, typeOnly:Bool, hadConfiguredExternalHost:Bool, macroHostClassPaths:Array<String>,
			requestContext:CompilationRequestContext, initialSession:Null<MacroRuntimeSession>) {
		this.runtimeMode = runtimeMode;
		this.typeOnly = typeOnly;
		this.hadConfiguredExternalHost = hadConfiguredExternalHost;
		this.macroHostClassPaths = macroHostClassPaths == null ? [] : macroHostClassPaths.copy();
		this.requestContext = requestContext;
		this.output = requestContext.output;
		this.session = initialSession;
		this.prepared = new StringMap<ResolvedModule>();
		this.autoBuiltEntrypoints = new StringMap<Bool>();
		this.autoBuiltExternalHost = false;
		this.skippedIndex = 0;
		this.closed = false;
	}

	public function getSession():Null<MacroRuntimeSession> {
		return session;
	}

	/** Prepare a known root set while preserving its deterministic resolver order. **/
	public function prepareAll(modules:Array<ResolvedModule>):Array<ResolvedModule> {
		if (modules == null || modules.length == 0)
			return [];
		if (!typeOnly && session == null) {
			final expressions = new Array<String>();
			for (module in modules)
				for (expression in expressionsFor(module))
					if (expressions.indexOf(expression) == -1)
						expressions.push(expression);
			if (expressions.length > 0) {
				ensureRequestMayRunMacros();
				ensureSession(expressions);
			}
		}
		final result = new Array<ResolvedModule>();
		for (module in modules)
			result.push(prepare(module));
		return result;
	}

	/** Prepare one newly discovered module before the loader indexes it. **/
	public function prepare(module:ResolvedModule):ResolvedModule {
		if (closed)
			throw new Stage3BuildMacroPreparationError("build-macro preparation is already closed");
		if (module == null)
			throw new Stage3BuildMacroPreparationError("build-macro preparation requires a resolved module");
		final modulePath = ResolvedModule.getModulePath(module);
		final existing = prepared.get(modulePath);
		if (existing != null)
			return existing;

		final expressions = expressionsFor(module);
		if (expressions.length == 0) {
			prepared.set(modulePath, module);
			return module;
		}
		if (typeOnly) {
			for (expression in expressions) {
				output.stdoutLine("build_macro_skipped[" + skippedIndex + "]=" + modulePath + ":" + expression);
				skippedIndex += 1;
			}
			prepared.set(modulePath, module);
			return module;
		}

		ensureRequestMayRunMacros();
		ensureSession(expressions);
		hxhx.macro.MacroState.clearBuildFields(modulePath);
		hxhx.macro.MacroState.setDefine("HXHX_BUILD_MODULE", modulePath);
		hxhx.macro.MacroState.setDefine("HXHX_BUILD_FILE", ResolvedModule.getFilePath(module));
		hxhx.macro.MacroState.setBuildFieldsPayload(Stage3BuildMacroSupport.buildFieldsPayloadForParsed(ResolvedModule.getParsed(module)));

		for (index in 0...expressions.length) {
			ensureRequestMayRunMacros();
			final expression = expressions[index];
			output.stdoutLine("build_macro[" + modulePath + "][" + index + "]=" + expression);
			try {
				output.stdoutLine("build_macro_run[" + modulePath + "][" + index + "]=" + session.run(expression));
			} catch (error:String) {
				throw new Stage3BuildMacroPreparationError("build macro failed: " + modulePath + ": " + error);
			} catch (error:haxe.Exception) {
				throw new Stage3BuildMacroPreparationError("build macro failed: " + modulePath + ": " + error.message);
			}
		}

		final snippets = hxhx.macro.MacroState.listBuildFields(modulePath);
		output.stdoutLine("build_fields[" + modulePath + "]=" + snippets.length);
		final result = if (snippets.length == 0) {
			module;
		} else {
			try {
				Stage3BuildMacroSupport.applyGeneratedMembers(module, snippets);
			} catch (error:String) {
				throw new Stage3BuildMacroPreparationError("build fields parse failed: " + modulePath + ": " + error);
			} catch (error:haxe.Exception) {
				throw new Stage3BuildMacroPreparationError("build fields parse failed: " + modulePath + ": " + error.message);
			}
		}
		prepared.set(modulePath, result);
		return result;
	}

	/** Close the request's macro session exactly once. **/
	public function close():Void {
		if (closed)
			return;
		closed = true;
		var closeFailure:Null<String> = null;
		if (session != null) {
			try {
				session.close();
			} catch (error:String) {
				closeFailure = error;
			} catch (error:haxe.Exception) {
				closeFailure = error.message;
			}
			session = null;
		}
		// Auto-built hosts are request-specific. Leaving their executable in the process
		// environment would make the next compiler-server request reuse the wrong entrypoints.
		if (runtimeMode == MacroRuntimeMode.EXTERNAL_HOST && !hadConfiguredExternalHost)
			Sys.putEnv("HXHX_MACRO_HOST_EXE", null);
		if (closeFailure != null)
			throw closeFailure;
	}

	function expressionsFor(module:ResolvedModule):Array<String> {
		final parsed = ResolvedModule.getParsed(module);
		return Stage3BuildMacroSupport.collectBuildMacroExprs(parsed.getSource(), ResolvedModule.getModulePath(module));
	}

	function ensureRequestMayRunMacros():Void {
		if (!requestContext.checkpoint("macros"))
			throw new Stage3BuildMacroPreparationError("build-macro preparation was cancelled", true);
	}

	function ensureSession(expressions:Array<String>):Void {
		if (session != null) {
			validateAutoBuiltEntrypoints(expressions);
			return;
		}
		if (runtimeMode == MacroRuntimeMode.EXTERNAL_HOST
			&& !hadConfiguredExternalHost
			&& Stage3MacroHostSupport.shouldAutoBuildMacroHost()) {
			final entrypoints = nonBuiltinEntrypoints(expressions);
			final repoRoot = Stage3PathSupport.inferRepoRootForScripts();
			if (repoRoot.length == 0)
				throw new Stage3BuildMacroPreparationError("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");
			try {
				final executable = Stage3MacroHostSupport.buildMacroHostExe(repoRoot, macroHostClassPaths, entrypoints);
				Sys.putEnv("HXHX_MACRO_HOST_EXE", executable);
				autoBuiltExternalHost = true;
				for (entrypoint in entrypoints)
					autoBuiltEntrypoints.set(entrypoint, true);
			} catch (error:String) {
				throw new Stage3BuildMacroPreparationError("macro host auto-build failed (build macros): " + error);
			}
		}

		try {
			session = MacroRuntimeMode.openSession(runtimeMode);
		} catch (error:String) {
			throw new Stage3BuildMacroPreparationError("macro runtime required for @:build, but could not be started: " + error);
		}
	}

	function validateAutoBuiltEntrypoints(expressions:Array<String>):Void {
		if (!autoBuiltExternalHost)
			return;
		for (entrypoint in nonBuiltinEntrypoints(expressions))
			if (!autoBuiltEntrypoints.exists(entrypoint))
				throw new Stage3BuildMacroPreparationError("a lazily discovered @:build entrypoint was not compiled into the active macro host: "
					+ entrypoint
					+ "; configure a macro host containing all project entrypoints or rerun without macro-host auto-build");
	}

	static function nonBuiltinEntrypoints(expressions:Array<String>):Array<String> {
		final result = new Array<String>();
		for (expression in expressions)
			if (!Stage3MacroHostSupport.isBuiltinMacroExpr(expression) && result.indexOf(expression) == -1)
				result.push(expression);
		return result;
	}
}
