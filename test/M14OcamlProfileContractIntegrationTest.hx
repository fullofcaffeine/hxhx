import backend.BackendContext;
import backend.OcamlProfile;

class M14OcamlProfileContractIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function makeContext(rawDefines:Array<String>):BackendContext {
		final defines = HxDefineMap.fromRawDefines(rawDefines);
		return new BackendContext("out", null, "demo.Main", false, false, defines);
	}

	static function main():Void {
		final portableDefault = makeContext([]);
		assertTrue(portableDefault.ensureOcamlProfileDefine() == OcamlProfile.Portable, "missing profile should default to portable");
		assertTrue(portableDefault.defineValue("ocaml_profile") == "portable", "portable default should be written back as define");

		final portableExplicit = makeContext(["ocaml_profile=portable"]);
		assertTrue(portableExplicit.ensureOcamlProfileDefine() == OcamlProfile.Portable, "explicit portable profile should resolve");
		assertTrue(portableExplicit.defineValue("ocaml_profile") == "portable", "portable explicit value should remain normalized");

		final metalExplicit = makeContext(["ocaml_profile=metal"]);
		assertTrue(metalExplicit.ensureOcamlProfileDefine() == OcamlProfile.Metal, "explicit metal profile should resolve");
		assertTrue(metalExplicit.defineValue("ocaml_profile") == "metal", "metal profile should be normalized");

		final metalMixedCase = makeContext(["ocaml_profile=MeTaL"]);
		assertTrue(metalMixedCase.ensureOcamlProfileDefine() == OcamlProfile.Metal, "mixed-case metal should resolve");
		assertTrue(metalMixedCase.defineValue("ocaml_profile") == "metal", "mixed-case metal should normalize to lowercase");

		final portableEmpty = makeContext(["ocaml_profile="]);
		assertTrue(portableEmpty.ensureOcamlProfileDefine() == OcamlProfile.Portable, "empty profile should default to portable");
		assertTrue(portableEmpty.defineValue("ocaml_profile") == "portable", "empty profile should be written back as portable");

		final invalid = makeContext(["ocaml_profile=unsupported"]);
		var failed = false;
		try {
			invalid.ensureOcamlProfileDefine();
		} catch (e:String) {
			failed = e.indexOf("ocaml_profile") != -1;
		}
		assertTrue(failed, "invalid ocaml_profile value should fail with actionable message");
	}
}
