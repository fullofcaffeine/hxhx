import hxhx.CliRouting;
import sys.FileSystem;
import sys.io.File;

class M14DirectFlagCliContractTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
	}

	static function assertIntEquals(actual:Int, expected:Int, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
	}

	static function assertContains(message:String, needle:String, label:String):Void {
		assertTrue(message.indexOf(needle) >= 0, label + " missing `" + needle + "` in: " + message);
	}

	static function expectThrowMessage(fn:Void->Void, needle:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		} catch (raw:Dynamic) {
			message = Std.string(raw);
		}
		assertTrue(message.length > 0, "expected throw containing `" + needle + "`");
		assertContains(message, needle, "throw message");
	}

	static function hasArgPair(args:Array<String>, key:String, value:String):Bool {
		var i = 0;
		while (i < args.length) {
			if (args[i] == key && i + 1 < args.length && args[i + 1] == value)
				return true;
			i += 1;
		}
		return false;
	}

	static function countArgPair(args:Array<String>, key:String, value:String):Int {
		var count = 0;
		var i = 0;
		while (i < args.length) {
			if (args[i] == key && i + 1 < args.length && args[i + 1] == value)
				count += 1;
			i += 1;
		}
		return count;
	}

	static function hasDefine(args:Array<String>, defineValue:String):Bool {
		var i = 0;
		while (i < args.length) {
			if (args[i] == "-D" && i + 1 < args.length && args[i + 1] == defineValue)
				return true;
			i += 1;
		}
		return false;
	}

	static function hasToken(args:Array<String>, token:String):Bool {
		for (a in args)
			if (a == token)
				return true;
		return false;
	}

	static function plan(args:Array<String>):Dynamic {
		return CliRouting.plan(args, args.copy());
	}

	static function main():Void {
		expectThrowMessage(function() plan(["--target", "ocaml"]), "--target removed");
		expectThrowMessage(function() plan(["--js"]), "Missing value after --js/ -js");
		expectThrowMessage(function() plan(["--ocaml-eval", "--js", "out.js"]), "--ocaml-eval is the target; remove other targets.");
		expectThrowMessage(function() plan(["--compat", "--ocaml"]), "--compat is pure upstream passthrough.");

		final nativeOcaml = plan(["--ocaml", "-cp", "src", "-main", "Main"]);
		assertEquals(nativeOcaml.lane, "native-ocaml", "native ocaml lane");
		assertEquals(nativeOcaml.backendId, "ocaml-stage3", "native ocaml backend");
		assertTrue(hasArgPair(nativeOcaml.forwarded, "--hxhx-out", "out"), "native ocaml default out dir");
		assertTrue(hasDefine(nativeOcaml.forwarded, "ocaml_output=out"), "native ocaml output define");
		assertTrue(hasDefine(nativeOcaml.forwarded, "reflaxe-target=ocaml"), "native ocaml reflaxe target define");

		final nativeOcamlWithDefine = plan(["--ocaml", "-D", "ocaml_output=foo", "-main", "Main"]);
		assertTrue(hasArgPair(nativeOcamlWithDefine.forwarded, "--hxhx-out", "foo"), "native ocaml output define mirrored to --hxhx-out");

		expectThrowMessage(function() plan(["--ocaml", "-D", "ocaml_output=foo", "--hxhx-out", "bar", "-main", "Main"]), "conflicting output directories");

		final nativeJs = plan(["--js", "out.js", "-main", "Main"]);
		assertEquals(nativeJs.lane, "native-js", "native js lane");
		assertEquals(nativeJs.backendId, "js-native", "native js backend");
		assertTrue(hasDefine(nativeJs.forwarded, "js"), "native js define");

		final compat = plan(["--compat", "--js", "out.js", "-main", "Main"]);
		assertEquals(compat.lane, "stage0-compat", "compat lane");
		assertTrue(!hasToken(compat.forwarded, "--compat"), "compat forwarding strips --compat");
		assertTrue(hasArgPair(compat.forwarded, "--js", "out.js"), "compat preserves target flags");

		final eval = plan(["--ocaml-eval", "-main", "Main"]);
		assertEquals(eval.lane, "stage0-ocaml-eval", "ocaml eval lane");
		assertTrue(hasToken(eval.forwarded, "--no-output"), "ocaml eval auto no-output");
		assertTrue(hasArgPair(eval.forwarded, "--library", "reflaxe.ocaml"), "ocaml eval library injection");
		assertTrue(hasDefine(eval.forwarded, "reflaxe-target=ocaml"), "ocaml eval reflaxe define");
		assertTrue(hasDefine(eval.forwarded, "reflaxe-target-code-injection=ocaml"), "ocaml eval code injection define");
		assertTrue(hasDefine(eval.forwarded, "retain-untyped-meta"), "ocaml eval retain untyped define");
		assertTrue(hasDefine(eval.forwarded, "ocaml_output=out"), "ocaml eval output define");
		assertTrue(hasDefine(eval.forwarded, "ocaml_build=1"), "ocaml eval build define");
		assertTrue(hasDefine(eval.forwarded, "ocaml_bin=main"), "ocaml eval bin define");

		final tmpDir = ".tmp/m14_direct_flag_cli_contract";
		if (!FileSystem.exists(tmpDir))
			FileSystem.createDirectory(tmpDir);
		final hxmlPath = tmpDir + "/build.hxml";
		File.saveContent(hxmlPath, "-lib reflaxe.ocaml\n-D ocaml_output=custom_out\n--no-output\n");
		final evalFromHxml = plan(["--ocaml-eval", hxmlPath, "-main", "Main"]);
		assertIntEquals(countArgPair(evalFromHxml.forwarded, "--library", "reflaxe.ocaml"), 0, "ocaml eval hxml duplicate library injection");
		assertTrue(!hasDefine(evalFromHxml.forwarded, "ocaml_output=out"), "ocaml eval hxml keeps explicit output define");
	}
}
