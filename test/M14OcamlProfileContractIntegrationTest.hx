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

		final metalExplicit = makeContext(["ocaml_profile=metal"]);
		assertTrue(metalExplicit.ensureOcamlProfileDefine() == OcamlProfile.Metal, "explicit metal profile should resolve");
		assertTrue(metalExplicit.defineValue("ocaml_profile") == "metal", "metal profile should be normalized");

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
