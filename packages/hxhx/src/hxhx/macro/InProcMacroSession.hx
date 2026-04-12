package hxhx.macro;

/**
	In-process macro runtime session implementation.

	Why
	- `InProcMacroRuntime.openSession` needs a concrete object whose bound
	  methods back the structural `MacroRuntimeSession` callbacks.
	- Keeping this as a module-local private class forced Stage3 full-emit to
	  route it through the lightweight helper-stub path, which is meant for
	  simple module-local providers and not for a stateful macro-session class
	  with callback arrays and side-effect methods.

	What
	- Stores the callback hooks registered during one in-process macro session.
	- Implements the current bring-up macro effect surface by forwarding effects
	  into `MacroState`.
	- Provides exact-string builtin macro behavior used by Stage4 fixtures.

	How
	- The class remains in the same package as `InProcMacroRuntime`, so existing
	  call sites still use `new InProcMacroSession()` without imports.
	- Moving it into its own module lets Stage3 emit it as a normal typed module
	  instead of synthesizing a placeholder module-local stub.
**/
class InProcMacroSession {
	final afterTypingHooks:Array<Void->Void>;
	final onGenerateHooks:Array<Void->Void>;
	final afterGenerateHooks:Array<Void->Void>;
	final effectSink:InProcMacroEffectSink;

	public function new() {
		afterTypingHooks = [];
		onGenerateHooks = [];
		afterGenerateHooks = [];
		effectSink = {
			setDefine: setDefine,
			definedValue: definedValue,
			addClassPath: addClassPath,
			emitOcamlModule: emitOcamlModule,
			emitBuildFields: emitBuildFields,
			registerAfterTypingHook: registerAfterTypingHook,
			registerOnGenerateHook: registerOnGenerateHook,
			registerAfterGenerateHook: registerAfterGenerateHook
		};
	}

	public function run(expr:String):String {
		final e = StringTools.trim(expr == null ? "" : expr);
		if (e.length == 0)
			throw "macro.run: missing expr";

		if (StringTools.startsWith(e, "include(") && StringTools.endsWith(e, ")")) {
			final inside = StringTools.trim(e.substr("include(".length, e.length - "include(".length - 1));
			final moduleName = parseIncludeStringLiteralArg(inside);
			if (moduleName != null && moduleName.length > 0) {
				MacroState.includeModule(moduleName);
				return "include=ok";
			}
		}

		final generated = InProcGeneratedEntrypoints.run(e, effectSink);
		if (generated != null)
			return generated;

		if (!isBuiltinExpr(e))
			return "ran:" + e;

		final builtin = withoutBuiltinPrefixExpr(e);
		return switch (builtin) {
			case "smoke()":
				MacroState.setDefine("HXHX_SMOKE", "1");
				"smoke:type=" + builtinTypeDescExpr("String") + ";define=" + (MacroState.defined("HXHX_SMOKE") ? "yes" : "no");
			case "genModule()":
				MacroState.emitOcamlModule("HxHxGen", "let generated : string = \"" + builtinTypeDescExpr("String") + "\"");
				MacroState.setDefine("HXHX_GEN", "1");
				"genModule=ok";
			case "addCpFromEnv()":
				final cp = Sys.getEnv("HXHX_ADD_CP");
				if (cp != null && StringTools.trim(cp).length > 0) {
					MacroState.addClassPath(cp);
					"addCp=ok";
				} else {
					"addCp=skip";
				}
			case "genHxModule()":
				MacroState.emitHxModule("Gen", "class Gen {}");
				MacroState.setDefine("HXHX_HXGEN", "1");
				"genHx=ok";
			case "readFlag()":
				"flag=" + MacroState.definedValue("HXHX_FLAG");
			case "dumpDefines()":
				MacroState.setDefine("HXHX_ENUM", "1");
				final defs = MacroState.listDefinesPairsSorted();
				final map:Map<String, String> = [];
				for (kv in defs)
					map.set(kv[0], kv[1]);
				final flagMap = map.exists("HXHX_FLAG") ? map.get("HXHX_FLAG") : null;
				final enumMap = map.exists("HXHX_ENUM") ? map.get("HXHX_ENUM") : null;
				final flagGet = map.exists("HXHX_FLAG") ? map.get("HXHX_FLAG") : null;
				final enumGet = map.exists("HXHX_ENUM") ? map.get("HXHX_ENUM") : null;
				"defines:flag_map="
				+ Std.string(flagMap)
				+ ";flag_get="
				+ Std.string(flagGet)
				+ ";enum_map="
				+ Std.string(enumMap)
				+ ";enum_get="
				+ Std.string(enumGet);
			case "registerHooks()":
				final afterTypingId = afterTypingHooks.length;
				afterTypingHooks.push(() -> MacroState.setDefine("HXHX_AFTER_TYPING", "1"));
				MacroState.registerHook("afterTyping", afterTypingId);

				final onGenerateId = onGenerateHooks.length;
				onGenerateHooks.push(() -> {
					MacroState.emitOcamlModule("HxHxHook", "let hook_generated : int = 1");
					MacroState.setDefine("HXHX_ON_GENERATE", "1");
				});
				MacroState.registerHook("onGenerate", onGenerateId);
				"hooks=ok";
			case "fail()":
				throw "intentional macro host failure (for position payload tests)";
			case _:
				"ran:" + e;
		}
	}

	public function runHook(kind:String, id:Int):Void {
		switch (kind == null ? "" : kind) {
			case "afterTyping":
				if (id < 0 || id >= afterTypingHooks.length)
					throw "macro.runHook: unknown afterTyping hook id: " + id;
				afterTypingHooks[id]();
			case "onGenerate":
				if (id < 0 || id >= onGenerateHooks.length)
					throw "macro.runHook: unknown onGenerate hook id: " + id;
				onGenerateHooks[id]();
			case "afterGenerate":
				if (id < 0 || id >= afterGenerateHooks.length)
					throw "macro.runHook: unknown afterGenerate hook id: " + id;
				afterGenerateHooks[id]();
			case _:
				throw "macro.runHook: unknown kind: " + kind;
		}
	}

	public function runTypeNotFoundHook(id:Int, typePath:String):Bool {
		if (id != -1 || typePath == "__hxhx_never__")
			return false;
		return false;
	}

	public function expandExpr(expr:String):String {
		final e = StringTools.trim(expr == null ? "" : expr);
		if (e.length == 0)
			throw "macro.expandExpr: empty expr";
		final generated = InProcGeneratedEntrypoints.expandExpr(e);
		if (generated != null)
			return generated;
		return switch (e) {
			case "unit.HelperMacros.getCompilationDate()", "HelperMacros.getCompilationDate()":
				"\"<compilation-date>\"";
			case _:
				throw "macro.expandExpr: expr not registered: " + e;
		}
	}

	public function setDefine(name:String, value:String):Void {
		MacroState.setDefine(name, value);
	}

	public function definedValue(name:String):String {
		return MacroState.definedValue(name);
	}

	public function addClassPath(path:String):Void {
		MacroState.addClassPath(path);
	}

	public function emitOcamlModule(name:String, source:String):Void {
		MacroState.emitOcamlModule(name, source);
	}

	public function emitBuildFields(modulePath:String, membersSource:String):Void {
		MacroState.emitBuildFields(modulePath, membersSource);
	}

	public function registerAfterTypingHook(cb:Void->Void):Void {
		final id = afterTypingHooks.length;
		afterTypingHooks.push(cb);
		MacroState.registerHook("afterTyping", id);
	}

	public function registerOnGenerateHook(cb:Void->Void):Void {
		final id = onGenerateHooks.length;
		onGenerateHooks.push(cb);
		MacroState.registerHook("onGenerate", id);
	}

	public function registerAfterGenerateHook(cb:Void->Void):Void {
		final id = afterGenerateHooks.length;
		afterGenerateHooks.push(cb);
		MacroState.registerHook("afterGenerate", id);
	}

	public function close():Void {}

	static function parseIncludeStringLiteralArg(s:String):Null<String> {
		if (s == null)
			return null;
		final t = StringTools.trim(s);
		if (t.length < 2)
			return null;
		final q = t.charCodeAt(0);
		if (q != "\"".code && q != "'".code)
			return null;
		if (t.charCodeAt(t.length - 1) != q)
			return null;
		var body = t.substr(1, t.length - 2);
		body = StringTools.replace(body, "\\\\", "\\");
		body = StringTools.replace(body, "\\\"", "\"");
		body = StringTools.replace(body, "\\'", "'");
		return body;
	}

	static function isBuiltinExpr(expr:String):Bool {
		return StringTools.startsWith(expr, "BuiltinMacros.") || StringTools.startsWith(expr, "hxhxmacrohost.BuiltinMacros.");
	}

	static function withoutBuiltinPrefixExpr(expr:String):String {
		if (StringTools.startsWith(expr, "BuiltinMacros."))
			return expr.substr("BuiltinMacros.".length);
		if (StringTools.startsWith(expr, "hxhxmacrohost.BuiltinMacros."))
			return expr.substr("hxhxmacrohost.BuiltinMacros.".length);
		return expr;
	}

	static function builtinTypeDescExpr(name:String):String {
		return switch (name) {
			case "Int", "Float", "Bool", "String", "Void":
				"builtin:" + name;
			case _:
				"unknown:" + name;
		}
	}
}
