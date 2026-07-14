package hxhx.macro;

/**
	Stage4 in-process macro runtime (bring-up subset).

	Why
	- The long-term direction is in-process macro execution by default.
	- This class provides the first selectable in-process mode without requiring
	  the external `hxhx-macro-host` process.

	Scope
	- Supports builtin macro entrypoints plus the current exact-string generated entrypoint
	  set used by the Stage4 bring-up fixtures.
	- Does not yet provide generic runtime `haxe.macro.*` parity for arbitrary macro modules;
	  that remains tracked by the macro API closure work.
**/
class InProcMacroRuntime {
	public static function openSession():MacroRuntimeSession {
		final impl = new InProcMacroSession();
		try {
			final programPath = Sys.programPath().toLowerCase();
			final usesBytecodePlugin = StringTools.endsWith(programPath, ".bc") || StringTools.endsWith(programPath, ".byte");
			final artifactKind = usesBytecodePlugin ? hxhxmacrohost.NativeMacroModuleReceipt.BYTECODE_ARTIFACT : hxhxmacrohost.NativeMacroModuleReceipt.NATIVE_ARTIFACT;
			NativeMacroModuleRuntimeLoader.loadConfigured(artifactKind, impl.loadNativeModule);
		} catch (error:String) {
			impl.close();
			throw error;
		} catch (error:haxe.Exception) {
			impl.close();
			throw error.message;
		}
		return {
			run: impl.run,
			runHook: impl.runHook,
			runTypeNotFoundHook: impl.runTypeNotFoundHook,
			expandExpr: impl.expandExpr,
			close: impl.close
		};
	}

	public static function parseOneStringLiteralArg(s:String):Null<String> {
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

	public static function builtinTypeDesc(name:String):String {
		return switch (name) {
			case "Int", "Float", "Bool", "String", "Void":
				"builtin:" + name;
			case _:
				"unknown:" + name;
		}
	}

	public static function isBuiltin(expr:String):Bool {
		return StringTools.startsWith(expr, "BuiltinMacros.") || StringTools.startsWith(expr, "hxhxmacrohost.BuiltinMacros.");
	}

	public static function withoutBuiltinPrefix(expr:String):String {
		if (StringTools.startsWith(expr, "BuiltinMacros."))
			return expr.substr("BuiltinMacros.".length);
		if (StringTools.startsWith(expr, "hxhxmacrohost.BuiltinMacros."))
			return expr.substr("hxhxmacrohost.BuiltinMacros.".length);
		return expr;
	}
}
