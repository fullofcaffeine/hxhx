import hxhxmacrohost.NativeMacroModuleHostAbi;

class M14NativeMacroModuleHostAbiIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (error:haxe.Exception) {
			message = error.message;
		} catch (error:String) {
			message = error;
		}
		assertTrue(message.length > 0, "expected failure containing: " + expected);
		assertTrue(message.indexOf(expected) >= 0, "error mismatch: " + message);
	}

	static function main():Void {
		final snapshot = "v2\n" + "abiVersion=1\n" + "macroApiVersion=1\n" + "fixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke()\n";
		final exprs = NativeMacroModuleHostAbi.exprsForPlugin(snapshot, "fixture.native.macro.plugin", "fixture://ok");
		assertTrue(exprs.length == 1, "expected one registered macro expr");
		assertTrue(exprs[0] == "FixtureNativeMacroPlugin.smoke()", "unexpected macro expr value");

		assertFailsContains(function() NativeMacroModuleHostAbi.exprsForPlugin("v2\nabiVersion=1\nmacroApiVersion=1\n", "fixture.native.macro.plugin",
			"fixture://empty"),
			"did not register any macro expressions");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.exprsForPlugin("v2\nabiVersion=1\nmacroApiVersion=1\nfixture.other\tFixtureNativeMacroPlugin.smoke()\n",
				"fixture.native.macro.plugin", "fixture://mismatch"),
			"registration pluginId mismatch");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.exprsForPlugin("v2\nabiVersion=1\nmacroApiVersion=1\nfixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke()\nfixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke()\n",
			"fixture.native.macro.plugin", "fixture://duplicate"),
			"duplicate expr registration");
		assertFailsContains(function() NativeMacroModuleHostAbi.decodeSnapshot("", "fixture://missing-version"), "snapshot is missing version header");
		assertFailsContains(function() NativeMacroModuleHostAbi.decodeSnapshot("v1\nabiVersion=1\nmacroApiVersion=1\nfixture.native.macro.plugin\texpr\n",
			"fixture://bad-version"),
			"invalid snapshot version");
		assertFailsContains(function() NativeMacroModuleHostAbi.decodeSnapshot("v2\nabiVersion=2\nmacroApiVersion=1\nfixture.native.macro.plugin\texpr\n",
			"fixture://abi-mismatch"),
			"abiVersion mismatch");
		assertFailsContains(function() NativeMacroModuleHostAbi.decodeSnapshot("v2\nabiVersion=1\nmacroApiVersion=2\nfixture.native.macro.plugin\texpr\n",
			"fixture://macro-api-mismatch"),
			"macroApiVersion mismatch");
	}
}
