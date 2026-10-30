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
		final snapshot = "v3\n" + "abiVersion=2\n" + "macroApiVersion=1\n" + "fixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke\n";
		final declarations = NativeMacroModuleHostAbi.declarationsForPlugin(snapshot, "fixture.native.macro.plugin", "fixture://ok");
		assertTrue(declarations.length == 1, "expected one registered macro declaration");
		assertTrue(declarations[0] == "FixtureNativeMacroPlugin.smoke", "unexpected macro declaration value");

		assertFailsContains(function() NativeMacroModuleHostAbi.declarationsForPlugin("v3\nabiVersion=2\nmacroApiVersion=1\n", "fixture.native.macro.plugin",
			"fixture://empty"),
			"did not register any macro declarations");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.declarationsForPlugin("v3\nabiVersion=2\nmacroApiVersion=1\nfixture.other\tFixtureNativeMacroPlugin.smoke\n",
				"fixture.native.macro.plugin", "fixture://mismatch"),
			"registration pluginId mismatch");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.declarationsForPlugin("v3\nabiVersion=2\nmacroApiVersion=1\nfixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke\nfixture.native.macro.plugin\tFixtureNativeMacroPlugin.smoke\n",
			"fixture.native.macro.plugin", "fixture://duplicate"),
			"duplicate declaration registration");
		// A row must name a declaration (`pack.Type.method`); standard macro API owners are reserved.
		assertFailsContains(function()
			NativeMacroModuleHostAbi.declarationsForPlugin("v3\nabiVersion=2\nmacroApiVersion=1\nfixture.native.macro.plugin\tsmoke()\n",
				"fixture.native.macro.plugin", "fixture://not-a-declaration"),
			"is not a macro declaration");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.declarationsForPlugin("v3\nabiVersion=2\nmacroApiVersion=1\nfixture.native.macro.plugin\thaxe.macro.Context.parse\n",
				"fixture.native.macro.plugin",
			"fixture://reserved"),
			"reserved standard macro API owner");
		assertFailsContains(function() NativeMacroModuleHostAbi.decodeSnapshot("", "fixture://missing-version"), "snapshot is missing version header");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.decodeSnapshot("v2\nabiVersion=1\nmacroApiVersion=1\nfixture.native.macro.plugin\tFixture.smoke\n",
				"fixture://bad-version"),
			"invalid snapshot version");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.decodeSnapshot("v3\nabiVersion=1\nmacroApiVersion=1\nfixture.native.macro.plugin\tFixture.smoke\n",
				"fixture://abi-mismatch"),
			"abiVersion mismatch");
		assertFailsContains(function()
			NativeMacroModuleHostAbi.decodeSnapshot("v3\nabiVersion=2\nmacroApiVersion=2\nfixture.native.macro.plugin\tFixture.smoke\n",
				"fixture://macro-api-mismatch"),
			"macroApiVersion mismatch");
	}
}
