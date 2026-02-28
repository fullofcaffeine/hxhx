import hxhx.TargetPresets;

class M14TargetPresetNamingCutoverIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
	}

	static function assertThrowsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		} catch (raw:Dynamic) {
			message = Std.string(raw);
		}
		assertTrue(message.length > 0, "expected throw containing `" + expected + "`");
		assertTrue(message.indexOf(expected) >= 0, "unexpected throw message: " + message);
	}

	static function main():Void {
		final listed = TargetPresets.listTargets();
		assertTrue(listed.length == 4, "unexpected preset count");
		assertEquals(listed[0], "ocaml", "list[0]");
		assertEquals(listed[1], "ocaml-compat", "list[1]");
		assertEquals(listed[2], "js", "list[2]");
		assertEquals(listed[3], "js-compat", "list[3]");

		final ocamlNative = TargetPresets.resolve("ocaml", []);
		assertEquals(ocamlNative.id, "ocaml-stage3", "native ocaml id");
		assertEquals(ocamlNative.runMode, TargetPresets.RUN_MODE_BUILTIN_STAGE3, "native ocaml mode");

		final ocamlCompat = TargetPresets.resolve("ocaml-compat", []);
		assertEquals(ocamlCompat.id, "ocaml-compat", "compat ocaml id");
		assertEquals(ocamlCompat.runMode, TargetPresets.RUN_MODE_DELEGATE_STAGE0, "compat ocaml mode");

		final jsNative = TargetPresets.resolve("js", []);
		assertEquals(jsNative.id, "js-native", "native js id");
		assertEquals(jsNative.runMode, TargetPresets.RUN_MODE_BUILTIN_STAGE3, "native js mode");

		final jsCompat = TargetPresets.resolve("js-compat", []);
		assertEquals(jsCompat.id, "js-compat", "compat js id");
		assertEquals(jsCompat.runMode, TargetPresets.RUN_MODE_DELEGATE_STAGE0, "compat js mode");

		assertThrowsContains(function() TargetPresets.resolve("ocaml-stage3", []), "Unknown target");
		assertThrowsContains(function() TargetPresets.resolve("js-native", []), "Unknown target");
	}
}
