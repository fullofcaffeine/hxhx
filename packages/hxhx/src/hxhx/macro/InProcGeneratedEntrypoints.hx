package hxhx.macro;

import hxhx.runtime.NullableRuntimeString;

/**
	Exact-string generated entrypoint registry for the in-process macro runtime.

	Why
	- External-host mode already supports a generated entrypoint registry for a curated
	  set of non-builtin bring-up macros.
	- Inproc mode previously stopped at builtin macros only, which meant the two runtime
	  modes diverged before the macro API parity work even began.
	- This registry closes that gap for the current bring-up surface by reproducing the
	  same observable compiler effects directly against `MacroState`.

	What
	- `run(expr, sink)` handles the current exact-string entrypoint set required by the
	  Stage4 bring-up fixtures and returns `null` when `expr` is not registered.
	- `expandExpr(expr)` handles the generated expression-macro subset.

	How
	- Dispatch stays intentionally explicit and deterministic: exact string match, then a
	  tiny amount of argument parsing for the one supported String-literal form.
	- Effects are routed through `InProcMacroEffectSink` instead of the external-host RPC
	  layer, so inproc mode can stay stage0-free.

	Gotchas
	- This is still a bring-up registry, not general-purpose runtime reflection.
	- Keep this file behaviorally aligned with the entrypoint set generated for
	  `hxhx-macro-host` until both modes share a stronger manifest/story.
**/
class InProcGeneratedEntrypoints {
	public static function handles(expr:String):Bool {
		final e = StringTools.trim(expr == null ? "" : expr);
		if (e.length == 0)
			return false;
		if (parseStringLiteralCallArg(e, "hxhxmacros.ArgsMacros.setArg") != null)
			return true;
		return switch (e) {
			case "Macro.init()", "hxhxmacros.ExternalMacros.external()", "hxhxmacros.BuildFieldMacros.addGeneratedField()",
				"hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()", "hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn()",
				"hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar()", "hxhxmacros.HaxelibInitMacros.init()", "hxhxmacros.PluginFixtureMacros.init()",
				"hxhxmacros.ExprMacroShim.hello()":
				true;
			case _:
				false;
		};
	}

	public static function run(expr:String, sink:InProcMacroEffectSink):Null<String> {
		final e = StringTools.trim(expr == null ? "" : expr);
		if (e.length == 0 || sink == null)
			return null;

		final argValue = parseStringLiteralCallArg(e, "hxhxmacros.ArgsMacros.setArg");
		if (argValue != null) {
			sink.setDefine("HXHX_ARG", argValue);
			return "ok";
		}

		return switch (e) {
			case "Macro.init()":
				sink.registerOnGenerateHook(() -> {});
				"ok";
			case "hxhxmacros.ExternalMacros.external()":
				final flag = sink.definedValue("HXHX_FLAG");
				sink.setDefine("HXHX_EXTERNAL", "1");
				sink.emitOcamlModule("HxHxExternal", "let external_flag : string = \"" + escapeOcamlString(flag) + "\"");
				"external=ok";
			case "hxhxmacros.BuildFieldMacros.addGeneratedField()":
				final modulePath = sink.definedValue("HXHX_BUILD_MODULE");
				if (modulePath.length == 0) {
					sink.setDefine("HXHX_BUILD_ERROR", "missing_module_path");
					"ok";
				} else {
					sink.setDefine("HXHX_BUILD_RAN", "1");
					final variant = sink.definedValue("HXHX_BUILD_VARIANT");
					final generated = switch (variant) {
						case "int": "public static function generated_answer():Int return 42;";
						case "int-body": "public static function generated_answer():Int return 43;";
						case "string": 'public static function generated_answer():String return "private-generated-value";';
						case _:
							[
								"public static function generated():Void {",
								'  trace("from_hxhx_build_macro");',
								"}"
							].join("\n");
					};
					sink.emitBuildFields(modulePath, generated);
					"ok";
				}
			case "hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()":
				emitBuildFunction(sink, "generated_return", "from_hxhx_build_macro_return");
				"ok";
			case "hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn()":
				emitBuildFunction(sink, "generated_replace", "from_hxhx_build_macro_replaced");
				"ok";
			case "hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar()":
				final modulePath = sink.definedValue("HXHX_BUILD_MODULE");
				if (modulePath.length == 0) {
					sink.setDefine("HXHX_BUILD_ERROR", "missing_module_path");
					"ok";
				} else {
					sink.emitBuildFields(modulePath, [
						"public static function generated_with_args(a, b):Void {",
						'  trace("from_hxhx_field_printer");',
						"}",
						"public static var generated_var = 123;"
					].join("\n"));
					"ok";
				}
			case "hxhxmacros.HaxelibInitMacros.init()":
				sink.setDefine("HXHX_HAXELIB_INIT", "1");
				sink.registerAfterTypingHook(() -> sink.setDefine("HXHX_HAXELIB_INIT_AFTER_TYPING", "1"));
				sink.registerOnGenerateHook(() -> {
					sink.setDefine("HXHX_HAXELIB_INIT_ON_GENERATE", "1");
					sink.emitOcamlModule("HxHxHaxelibInitGen", "let haxelib_init_generated : int = 1");
				});
				sink.registerAfterGenerateHook(() -> sink.setDefine("HXHX_HAXELIB_INIT_AFTER_GENERATE", "1"));
				"ok";
			case "hxhxmacros.PluginFixtureMacros.init()":
				sink.setDefine("HXHX_PLUGIN_FIXTURE", "1");
				final cp = NullableRuntimeString.trimToEmpty(Sys.getEnv("HXHX_PLUGIN_FIXTURE_CP"));
				if (cp.length > 0)
					sink.addClassPath(cp);
				sink.registerAfterTypingHook(() -> sink.setDefine("HXHX_PLUGIN_FIXTURE_AFTER_TYPING", "1"));
				sink.registerOnGenerateHook(() -> {
					sink.setDefine("HXHX_PLUGIN_FIXTURE_ON_GENERATE", "1");
					sink.emitOcamlModule("HxHxPluginFixtureGen", 'let plugin_fixture_generated : string = "ok"');
				});
				"ok";
			case "hxhxmacros.ExprMacroShim.hello()":
				'"HELLO"';
			case _:
				null;
		};
	}

	public static function expandExpr(expr:String):Null<String> {
		final e = StringTools.trim(expr == null ? "" : expr);
		return switch (e) {
			case "hxhxmacros.ExprMacroShim.hello()":
				'"HELLO"';
			case _:
				null;
		};
	}

	static function parseStringLiteralCallArg(expr:String, callPrefix:String):Null<String> {
		if (!StringTools.startsWith(expr, callPrefix + "("))
			return null;
		if (!StringTools.endsWith(expr, ")"))
			return null;
		final inside = expr.substr(callPrefix.length + 1, expr.length - callPrefix.length - 2);
		if (inside == null)
			return null;
		final t = StringTools.trim(inside);
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

	static function emitBuildFunction(sink:InProcMacroEffectSink, name:String, traceValue:String):Void {
		final modulePath = sink.definedValue("HXHX_BUILD_MODULE");
		if (modulePath.length == 0) {
			sink.setDefine("HXHX_BUILD_ERROR", "missing_module_path");
			return;
		}
		sink.emitBuildFields(modulePath, [
			"public static function " + name + "():Void {",
			'  trace("' + traceValue + '");',
			"}"
		].join("\n"));
	}

	static function escapeOcamlString(s:String):String {
		if (s == null)
			return "";
		return s.split("\\").join("\\\\").split("\"").join("\\\"");
	}
}
