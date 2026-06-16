import hxhx.CliRouting;
import hxhx.Hxml;
import hxhx.Stage3Args;
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

	static function countDefine(args:Array<String>, defineValue:String):Int {
		var count = 0;
		var i = 0;
		while (i < args.length) {
			if (args[i] == "-D" && i + 1 < args.length && args[i + 1] == defineValue)
				count += 1;
			i += 1;
		}
		return count;
	}

	static function plan(args:Array<String>):Dynamic {
		return CliRouting.plan(args, args.copy());
	}

	static function main():Void {
		expectThrowMessage(function() plan(["--target", "ocaml"]), "--target removed");
		expectThrowMessage(function() plan(["--js"]), "Missing value after --js/ -js");
		expectThrowMessage(function() plan(["--ocaml-eval", "--js", "out.js"]), "--ocaml-eval is the target; remove other targets.");
		expectThrowMessage(function() plan(["--compat", "--ocaml"]), "--compat is pure upstream passthrough.");
		expectThrowMessage(function() plan(["-D", "elixir_output=out", "-main", "Main"]), 'Native source-host Reflaxe target "elixir" is not implemented');
		expectThrowMessage(function() plan(["-D", "reflaxe-target=elixir", "-main", "Main"]), 'Native source-host Reflaxe target "elixir" is not implemented');

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

		final nativeNeko = plan(["--neko", "out.n", "-main", "Main"]);
		assertEquals(nativeNeko.lane, "native-neko", "native neko lane");
		assertEquals(nativeNeko.backendId, "neko-native", "native neko backend");
		assertTrue(hasDefine(nativeNeko.forwarded, "neko"), "native neko define");
		assertEquals(Stage3Args.findTargetOutputFileHint(["--neko", "out.n", "-main", "Main"], "neko-native"), "out.n", "native neko output file hint");

		final commandOnly = plan(["--cmd", "haxelib dev dummy_ndll dummy_ndll"]);
		assertEquals(commandOnly.lane, "native-neko", "command-only setup lane");
		assertEquals(commandOnly.backendId, "neko-native", "command-only setup backend");
		assertTrue(commandOnly.forwarded.indexOf("--cmd") != -1, "command-only setup must preserve --cmd for Stage3");

		final nativeHl = plan(["--hl", "out.hl", "-main", "Main"]);
		assertEquals(nativeHl.lane, "native-hl", "native hl lane");
		assertEquals(nativeHl.backendId, "hl-native", "native hl backend");
		assertTrue(hasDefine(nativeHl.forwarded, "hl"), "native hl define");

		final nativeCpp = plan(["--cpp", "cpp_out", "-main", "Main"]);
		assertEquals(nativeCpp.lane, "native-cpp", "native cpp lane");
		assertEquals(nativeCpp.backendId, "cpp-native", "native cpp backend");
		assertTrue(hasDefine(nativeCpp.forwarded, "cpp"), "native cpp define");
		assertEquals(Stage3Args.findTargetOutputDirectoryHint(["--cpp", "cpp_out", "-main", "Main"], "cpp-native"), "cpp_out",
			"native cpp output directory hint");

		final nativePython = plan(["--python", "py_out", "-main", "Main"]);
		assertEquals(nativePython.lane, "native-python", "native python lane");
		assertEquals(nativePython.backendId, "python-native", "native python backend");
		assertTrue(hasDefine(nativePython.forwarded, "python"), "native python define");

		final nativeJava = plan(["--java", "java_out", "-main", "Main"]);
		assertEquals(nativeJava.lane, "native-java", "native java lane");
		assertEquals(nativeJava.backendId, "java-native", "native java backend");
		assertTrue(hasDefine(nativeJava.forwarded, "java"), "native java define");

		final nativeJvm = plan(["--jvm", "jvm.jar", "-main", "Main"]);
		assertEquals(nativeJvm.lane, "native-java", "native jvm lane should use the Java source backend");
		assertEquals(nativeJvm.backendId, "java-native", "native jvm backend should use the Java source backend");
		assertTrue(hasDefine(nativeJvm.forwarded, "java"), "native jvm define");

		final nativeCs = plan(["--cs", "cs_out", "-main", "Main"]);
		assertEquals(nativeCs.lane, "native-cs", "native cs lane");
		assertEquals(nativeCs.backendId, "cs-native", "native cs backend");
		assertTrue(hasDefine(nativeCs.forwarded, "cs"), "native cs define");
		assertEquals(Stage3Args.findTargetOutputDirectoryHint(["--cs", "cs_out", "-main", "Main"], "cs-native"), "cs_out", "native cs output directory hint");

		final nativePhp = plan(["--php", "php_out", "-main", "Main"]);
		assertEquals(nativePhp.lane, "native-php", "native php lane");
		assertEquals(nativePhp.backendId, "php-native", "native php backend");
		assertTrue(hasDefine(nativePhp.forwarded, "php"), "native php define");

		final nativeLua = plan(["--lua", "lua_out", "-main", "Main"]);
		assertEquals(nativeLua.lane, "native-lua", "native lua lane");
		assertEquals(nativeLua.backendId, "lua-native", "native lua backend");
		assertTrue(hasDefine(nativeLua.forwarded, "lua"), "native lua define");

		final nativeJsRun = plan(["--run", "Main", "arg1"]);
		assertEquals(nativeJsRun.lane, "native-js", "native js --run lane");
		assertEquals(nativeJsRun.backendId, "js-native", "native js --run backend");
		assertTrue(hasArgPair(nativeJsRun.forwarded, "--js", ".hxhx-run.js"), "native js --run temp output");
		assertTrue(hasDefine(nativeJsRun.forwarded, "js"), "native js --run define");
		assertTrue(hasToken(nativeJsRun.forwarded, "--run"), "native js --run preserves run flag");

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
		assertEquals(evalFromHxml.lane, "stage0-ocaml-eval", "ocaml eval hxml lane");
		assertIntEquals(countArgPair(evalFromHxml.forwarded, "--library", "reflaxe.ocaml"), 0, "ocaml eval hxml duplicate library injection");
		assertTrue(!hasDefine(evalFromHxml.forwarded, "ocaml_output=out"), "ocaml eval hxml keeps explicit output define");
		assertIntEquals(countDefine(evalFromHxml.forwarded, "ocaml_output=custom_out"), 0, "ocaml eval hxml avoids duplicate explicit output define");
		assertTrue(!hasToken(evalFromHxml.forwarded, "--no-output"), "ocaml eval hxml avoids duplicate no-output token");
		assertTrue(hasDefine(evalFromHxml.forwarded, "reflaxe-target=ocaml"), "ocaml eval hxml still injects reflaxe target define");

		final multiHxmlPath = tmpDir + "/multi-target.hxml";
		File.saveContent(multiHxmlPath, "-cp src\n--each\n--python py_out\n--next\n--java java_out\n");
		expectThrowMessage(function() plan([multiHxmlPath]), "Target not supported natively");

		final jsEachHxmlPath = tmpDir + "/js-each.hxml";
		File.saveContent(jsEachHxmlPath, "-cp src\n--each\n--js a.js\n-main A\n--next\n--js b.js\n-main B\n");
		final jsEach = plan([jsEachHxmlPath]);
		assertEquals(jsEach.lane, "native-js", "multi-unit js hxml lane");
		assertTrue(hasDefine(jsEach.forwarded, "js"), "multi-unit js hxml define");

		final sysEachHxmlPath = tmpDir + "/compile-each.hxml";
		File.saveContent(sysEachHxmlPath,
			"-p src\n--main ExitCode\n-neko bin/neko/ExitCode.n\n-lib utest\n-cmd nekotools boot bin/neko/ExitCode.n\n\n--next\n-D source-header=''\n--debug\n-lib utest\n-p src\n");
		final sysJsHxmlPath = tmpDir + "/compile-js.hxml";
		File.saveContent(sysJsHxmlPath,
			"compile-each.hxml\n--main Main\n-js bin/js/sys.js\n-lib hxnodejs\n\n--next\ncompile-each.hxml\n--main UtilityProcess\n-js bin/js/UtilityProcess.js\n-lib hxnodejs\n");
		final sysJs = plan([sysJsHxmlPath]);
		assertEquals(sysJs.lane, "native-js", "sys-style mixed helper js hxml lane");
		assertTrue(hasDefine(sysJs.forwarded, "js"), "sys-style mixed helper js hxml define");

		final sysJavaHxmlPath = tmpDir + "/compile-java.hxml";
		File.saveContent(sysJavaHxmlPath,
			"compile-each.hxml\n--main Main\n-java bin/java\n\n--next\ncompile-each.hxml\n--main UtilityProcess\n-java bin/java\n");
		final sysJava = plan([sysJavaHxmlPath]);
		assertEquals(sysJava.lane, "native-java", "sys-style mixed helper java hxml lane");
		assertEquals(sysJava.backendId, "java-native", "sys-style mixed helper java hxml backend");
		assertTrue(hasDefine(sysJava.forwarded, "java"), "sys-style mixed helper java hxml define");

		final sysCsHxmlPath = tmpDir + "/compile-cs.hxml";
		File.saveContent(sysCsHxmlPath, "compile-each.hxml\n--main Main\n-cs bin/cs\n\n--next\ncompile-each.hxml\n--main UtilityProcess\n-cs bin/cs\n");
		final sysCs = plan([sysCsHxmlPath]);
		assertEquals(sysCs.lane, "native-cs", "sys-style mixed helper cs hxml lane");
		assertEquals(sysCs.backendId, "cs-native", "sys-style mixed helper cs hxml backend");
		assertTrue(hasDefine(sysCs.forwarded, "cs"), "sys-style mixed helper cs hxml define");
		assertEquals(Stage3Args.findTargetOutputDirectoryHint(["--main", "Main", "-cs", "bin/cs"], "cs-native"), "bin/cs",
			"sys-style cs hxml output directory hint");

		final sysCppHxmlPath = tmpDir + "/compile-cpp.hxml";
		File.saveContent(sysCppHxmlPath, "compile-each.hxml\n--main Main\n-cpp bin/cpp\n\n--next\ncompile-each.hxml\n--main UtilityProcess\n-cpp bin/cpp\n");
		final sysCpp = plan([sysCppHxmlPath]);
		assertEquals(sysCpp.lane, "native-cpp", "sys-style mixed helper cpp hxml lane");
		assertEquals(sysCpp.backendId, "cpp-native", "sys-style mixed helper cpp hxml backend");
		assertTrue(hasDefine(sysCpp.forwarded, "cpp"), "sys-style mixed helper cpp hxml define");
		assertEquals(Stage3Args.findTargetOutputDirectoryHint(["--main", "Main", "-cpp", "bin/cpp"], "cpp-native"), "bin/cpp",
			"sys-style cpp hxml output directory hint");

		final cwdHxmlDir = tmpDir + "/cwd-java";
		if (!FileSystem.exists(cwdHxmlDir))
			FileSystem.createDirectory(cwdHxmlDir);
		File.saveContent(cwdHxmlDir + "/build.hxml", "--java java_out\n-main Main\n");
		final javaCwdHxml = plan(["--cwd", cwdHxmlDir, "build.hxml"]);
		assertEquals(javaCwdHxml.lane, "native-java", "cwd-relative java hxml lane");
		assertTrue(hasDefine(javaCwdHxml.forwarded, "java"), "cwd-relative java hxml define");

		final inlineCmdHxmlPath = tmpDir + "/inline-cmd.hxml";
		File.saveContent(inlineCmdHxmlPath, "--main Main --neko bin/main.n -lib dummy_ndll --cmd neko bin/main.n\n");
		final inlineCmdTokens = Hxml.parseFile(inlineCmdHxmlPath);
		assertTrue(inlineCmdTokens != null, "inline --cmd hxml should parse");
		assertIntEquals(inlineCmdTokens.indexOf("bin/main.n"), 3, "target output should remain the -neko value");
		assertTrue(hasArgPair(inlineCmdTokens, "--cmd", "neko bin/main.n"), "inline --cmd should consume the rest of the hxml line");
		assertIntEquals(inlineCmdTokens.lastIndexOf("bin/main.n"), 3, "inline --cmd payload should not leave a stray positional artifact");

		assertTrue(CliRouting.isJsNativeHelperUnit([
			"-p",
			"src",
			"--main",
			"ExitCode",
			"-neko",
			"bin/neko/ExitCode.n",
			"-cmd",
			"nekotools boot bin/neko/ExitCode.n"
		]), "neko command helper unit should be recognized for js routing");
	}
}
