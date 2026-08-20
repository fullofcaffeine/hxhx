import hxhx.CompilationRequestOutput;
import hxhx.Stage3DiagnosticsSupport;
import hxhx.macro.MacroState;

/**
	Proves that ordinary Stage3 macro diagnostics do not expose private values.

	Macro execution still receives exact compiler state. Only the text printed to
	users and retained server logs is reduced to a safe marker.
**/
class M14Stage3MacroDefineDiagnosticPrivacyIntegrationTest {
	static function main():Void {
		final firstRoot = "/private/first workspace/project/Api.hx";
		final secondRoot = "/private/second workspace/project/Api.hx";
		final secretValue = "token-shaped-private-value";
		final firstDiagnostics = macroDefineDiagnostics(firstRoot, secretValue);
		final secondDiagnostics = macroDefineDiagnostics(secondRoot, secretValue);
		assertTrue(firstDiagnostics == secondDiagnostics, "macro diagnostics should not change with an absolute workspace root");
		assertTrue(firstDiagnostics.indexOf(firstRoot) == -1, "macro diagnostics should not expose the first absolute build path");
		assertTrue(secondDiagnostics.indexOf(secondRoot) == -1, "macro diagnostics should not expose the second absolute build path");
		assertTrue(firstDiagnostics.indexOf(secretValue) == -1, "macro diagnostics should not expose an unknown private define value");
		assertTrue(firstDiagnostics.indexOf("macro_define[HXHX_BUILD_FILE]=<set>") >= 0, "macro diagnostics should report only that the build file is set");
		assertTrue(firstDiagnostics.indexOf("macro_define[HXHX_UNKNOWN_PRIVATE]=<set>") >= 0, "unknown internal defines should use the safe default marker");
		assertTrue(firstDiagnostics.indexOf("macro_define[HXHX_SMOKE]=1") >= 0, "the documented lifecycle marker should keep its stable value");
		assertTrue(firstDiagnostics.indexOf("macro_define[HXHX_EXTERNAL]=<set>") >= 0,
			"a lifecycle define with an unexpected value should use the safe marker");
		assertTrue(firstDiagnostics.indexOf("unexpected-private-value") == -1, "a lifecycle define should not expose an unexpected value");
		assertTrue(MacroState.definedValue("HXHX_BUILD_FILE") == secondRoot, "diagnostic redaction must not change the build file that macro execution reads");
		assertTrue(MacroState.definedValue("HXHX_UNKNOWN_PRIVATE") == secretValue, "diagnostic redaction must not change private macro state");
		MacroState.reset();
	}

	static function macroDefineDiagnostics(buildFile:String, privateValue:String):String {
		MacroState.reset();
		MacroState.setDefine("HXHX_BUILD_FILE", buildFile);
		MacroState.setDefine("HXHX_UNKNOWN_PRIVATE", privateValue);
		MacroState.setDefine("HXHX_SMOKE", "1");
		MacroState.setDefine("HXHX_EXTERNAL", "unexpected-private-value");
		final output = new CompilationRequestOutput(true);
		Stage3DiagnosticsSupport.printHxMacroDefines("macro_define", output);
		final text = new StringBuf();
		for (event in output.events())
			text.add(event.text);
		output.close();
		return text.toString();
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
