import hxhx.macro.MacroRuntimeMode;
import hxhx.macro.MacroState;

class M14MacroRuntimeModeSwitchIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertEq(label:String, actual:String, expected:String):Void {
		if (actual == expected)
			return;
		fail(label + ': expected "' + expected + '" but got "' + actual + '"');
	}

	static function assertContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function expectThrow(label:String, run:() -> Void, expected:String):Void {
		var caught = "";
		try {
			run();
		} catch (e:String) {
			caught = e;
		}
		if (caught.length == 0)
			fail(label + ": expected exception");
		assertContains(label + " message", caught, expected);
	}

	static function main():Void {
		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", null);
		assertEq("default mode", MacroRuntimeMode.resolve(null), MacroRuntimeMode.EXTERNAL_HOST);

		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", MacroRuntimeMode.INPROC);
		assertEq("env mode", MacroRuntimeMode.resolve(null), MacroRuntimeMode.INPROC);
		assertEq("explicit mode", MacroRuntimeMode.resolve(MacroRuntimeMode.EXTERNAL_HOST), MacroRuntimeMode.EXTERNAL_HOST);
		expectThrow("invalid mode", () -> MacroRuntimeMode.resolve("weird"), "invalid macro runtime mode");

		Sys.putEnv("HXHX_MACRO_HOST_EXE", null);
		MacroState.reset();
		MacroState.seedFromCliDefines(["HXHX_FLAG=abc"]);
		MacroState.setGeneratedHxDir(".tmp/m14_macro_runtime_mode");

		final session = MacroRuntimeMode.openSession(MacroRuntimeMode.INPROC);
		final smoke = session.run("BuiltinMacros.smoke()");
		assertContains("smoke result", smoke, "smoke:type=builtin:String;define=yes");
		assertEq("smoke define", MacroState.definedValue("HXHX_SMOKE"), "1");

		final readFlag = session.run("BuiltinMacros.readFlag()");
		assertEq("read flag", readFlag, "flag=abc");

		final hookResult = session.run("BuiltinMacros.registerHooks()");
		assertEq("hook registration", hookResult, "hooks=ok");

		for (id in MacroState.listAfterTypingHookIds())
			session.runHook("afterTyping", id);
		for (id in MacroState.listOnGenerateHookIds())
			session.runHook("onGenerate", id);

		assertEq("afterTyping define", MacroState.definedValue("HXHX_AFTER_TYPING"), "1");
		assertEq("onGenerate define", MacroState.definedValue("HXHX_ON_GENERATE"), "1");
		assertContains("generated module name", MacroState.listOcamlModuleNames().join(","), "HxHxHook");

		session.close();
		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", null);
		Sys.println("OK m14 macro runtime mode switch");
	}
}
