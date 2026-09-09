import backend.ocaml.Stage3OcamlLocalNames;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that Stage3 emits locals from exact typed projections.

	The fixture combines lexical shadowing, OCaml keyword collisions, an
	unknown typed parameter, same-spelled instance members, and the synthetic
	instance receiver. The generated executable is the final observer for the
	bindings that participate in runtime behavior.
	Expression-local inference also preserves written annotations, argument order,
	and shadowed reads when the parser represents a binding as a lambda call.
**/
class M14Stage3TypedLocalProjectionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
	}

	/** Require the exact rejection family instead of accepting any unrelated failure. **/
	static function assertRejected(action:() -> Void, diagnostic:String):Void {
		var actual = "";
		try {
			action();
		} catch (message:String) {
			actual = message;
		}
		assertContains(actual, diagnostic, "invalid typed facts did not fail at their owning boundary");
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function run(command:String, arguments:Array<String>):{exitCode:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		return {exitCode: exitCode, stdout: stdout, stderr: stderr};
	}

	static function findFunction(projection:TypedBackendClassProjection, name:String):TypedBackendFunctionProjection {
		for (fn in projection.getFunctions())
			if (HxFunctionDecl.getName(fn.getDeclaration()) == name)
				return fn;
		throw "fixture projection is missing Main." + name;
	}

	/** Check the semantic binding, since equal runtime values can hide an unintended Dynamic conversion. */
	static function assertLocalType(functionProjection:TypedBackendFunctionProjection, sourceName:String, expected:String):Void {
		for (local in functionProjection.getLocalCatalog().getEntries())
			if (local.getBinding().getSourceName() == sourceName) {
				assertTrue(local.getBinding().getType().getDisplay() == expected, sourceName + " lost its selected " + expected + " type");
				return;
			}
		throw "missing local binding " + sourceName;
	}

	static function main():Void {
		final root = Path.normalize(".tmp/m14_stage3_typed_local_projection_" + Std.string(Date.now().getTime()));
		final sourcePath = Path.join([root, "Main.hx"]);
		final outDir = Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final source = [
			"class Main {",
			"  static var increment = (match:Int) -> match + 1;",
			"  var value:Int = 99;",
			"  public function new() {}",
			"  function helper():Int return 88;",
			"  function chooseField(value:Int):Int return value;",
			"  function chooseMethod(helper:Int):Int return helper;",
			"  function invoke(helper:Int->Int):Int return helper(5);",
			"  function invokeZero(helper:()->Int):Int return helper();",
			"  function invokeTwo(helper:(Int,Int)->Int):Int return helper(4, 5);",
			"  function receiver(this_:Int):Int return this_;",
			"  static function unknownValue(value):Dynamic return value;",
			"  static function unknownCollision(match, match_:Int):Dynamic return match;",
			"  static function addTen(n:Int):Int return n + 10;",
			"  static function eleven():Int return 11;",
			"  static function sum(a:Int, b:Int):Int return a + b;",
			"  static function branch(key:String):Int return switch(key) { case \"a\": var inferred = sum(7, 8) % 12; inferred == 0 ? 12 : inferred; default: 0; };",
			"  static function annotated(key:String):Dynamic return switch(key) { case \"a\": var explicit:Dynamic = 15; explicit; default: 0; };",
			"  static function written(key:String):Int return switch(key) { case \"a\": var precise:Int = 16; precise; default: 0; };",
			"  static function observe(value:Int):Int { Sys.println(value); return value; }",
			"  static function ordered():Int return (left -> (right -> left * 10 + right)(observe(2)))(observe(1));",
			"  static function shadowed():Int return (value -> (value -> value)(value + 1))(4);",
			"  static function cycleA(cycleB:Int):Int return cycleB;",
			"  static function cycleB():Int return cycleA(3);",
			"  static function collide(match:Int, match_:Int, method:Int, method_:Int):Int return match + match_ + method + method_;",
			"  static function main() {",
			"    var outer:Int = 1;",
			"    {",
			"      var outer:Int = 2;",
			"      Sys.println(outer);",
			"    }",
			"    Sys.println(outer);",
			"    Sys.println(collide(1, 2, 3, 4));",
			"    var instance = new Main();",
			"    Sys.println(instance.chooseField(7));",
			"    Sys.println(instance.chooseMethod(8));",
			"    Sys.println(instance.receiver(9));",
			"    Sys.println(instance.invoke(addTen));",
			"    Sys.println(instance.invokeZero(eleven));",
			"    Sys.println(instance.invokeTwo(sum));",
			"    Sys.println(branch(\"a\"));",
			"    Sys.println(annotated(\"a\"));",
			"    Sys.println(written(\"a\"));",
			"    Sys.println(ordered());",
			"    Sys.println(shadowed());",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);

		var failure:Null<String> = null;
		try {
			final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(source, sourcePath));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final firstModuleProjection = typed.getBackendProjection();
			assertTrue(firstModuleProjection == typed.getBackendProjection(), "typed module rebuilt its strict backend projection on repeated access");
			assertTrue(firstModuleProjection != typed.withTypedClasses(typed.getTypedClasses()).getBackendProjection(),
				"a new typed module revision retained the previous projection cache");
			final mainDeclaration = HxModuleDecl.getMainClass(firstModuleProjection.getDeclaration());
			final mainProjection = firstModuleProjection.findClass(mainDeclaration);
			assertTrue(mainProjection != null, "strict module projection could not select its exact main-class declaration");
			assertTrue(firstModuleProjection.findClass(new HxClassDecl("Main", true, [], [])) == null,
				"strict module projection selected a same-named but unrelated class declaration");

			final unknown = findFunction(mainProjection, "unknownValue");
			assertLocalType(findFunction(mainProjection, "branch"), "inferred", "Int");
			assertLocalType(findFunction(mainProjection, "annotated"), "explicit", "Dynamic");
			assertLocalType(findFunction(mainProjection, "written"), "precise", "Int");
			final unknownParameters = unknown.getParameters();
			assertTrue(unknownParameters.length == 1 && unknownParameters[0].getBinding().getType().isUnknown(),
				"unannotated parameter did not retain its exact Unknown typed fact");
			final collide = findFunction(mainProjection, "collide");
			final unknownCollision = findFunction(mainProjection, "unknownCollision");
			@:privateAccess EmitterStage.currentFunctionLocalOcamlNames = new Stage3OcamlLocalNames(unknownCollision.getLocalCatalog(), false,
				name -> @:privateAccess EmitterStage.ocamlValueIdent(name));
			final misleadingHints:Map<String, TyType> = ["match_" => TyType.fromHintText("Int")];
			@:privateAccess EmitterStage.currentFunctionLocalTypeHints = misleadingHints;
			assertTrue((@:privateAccess EmitterStage.stage3TyForIdent("match", misleadingHints)) == "Unknown",
				"Unknown local borrowed the type of a different binding after keyword escaping");
			EmitterStage.resetRequestState();
			assertTrue((@:privateAccess EmitterStage.currentFunctionLocalOcamlNames) == null, "request cleanup retained a previous body catalog");
			final reversedParameters = collide.getParameterBindingIdentities();
			reversedParameters.reverse();
			assertRejected(() -> {
				new TypedBackendFunctionProjection(collide.getStableIdentity(), collide.getBodyRevision(), collide.getDeclaration(),
					collide.getLocalCatalog(), collide.getReturnType(), collide.getFieldReadCatalog(), reversedParameters).getParameters();
			}, "parameter name mismatch");
			assertRejected(() -> {
				new TypedBackendFunctionProjection("another-function", collide.getBodyRevision(), collide.getDeclaration(), collide.getLocalCatalog(),
					collide.getReturnType());
			}, "local from another function");
			final originalBinding = collide.getParameters()[0].getBinding();
			assertRejected(() -> {
				collide.getLocalCatalog()
					.projectedName(new TyLocalBinding(originalBinding.getIdentity(), originalBinding.getSourceName(), TyType.fromHintText("String"),
						originalBinding.getKind()));
			}, "stale local facts");
			final collideNames = new Stage3OcamlLocalNames(collide.getLocalCatalog(), false, name -> @:privateAccess EmitterStage.ocamlValueIdent(name));
			final collideParameters = collide.getParameters();
			final targetNames = [
				for (parameter in collideParameters)
					collideNames.targetName(parameter.getProjectedName())
			];
			assertTrue(targetNames.join(",") == "match_,match__1,method_,method__1",
				"OCaml normalization collapsed exact keyword-colliding parameters: " + targetNames.join(","));
			final caseOwner = "Main.caseCollision#fixture";
			final upper = new TyLocalBinding(TyLocalId.forSourceDeclaration(caseOwner, 0, Variable, "Value"), "Value", TyType.fromHintText("Int"), Variable);
			final lower = new TyLocalBinding(TyLocalId.forSourceDeclaration(caseOwner, 1, Variable, "value"), "value", TyType.fromHintText("Int"), Variable);
			final caseProjection = new TypedBackendFunctionProjection(caseOwner, "case-collision-revision",
				new HxFunctionDecl("caseCollision", Public, true, [], "Void", [], ""), new TypedBackendLocalCatalog([upper, lower]), TyType.unknown());
			final caseNames = new Stage3OcamlLocalNames(caseProjection.getLocalCatalog(), false, name -> @:privateAccess EmitterStage.ocamlValueIdent(name));
			assertTrue(caseNames.targetName("Value") == "value" && caseNames.targetName("value") == "value_1",
				"OCaml case normalization collapsed two exact typed bindings");
			final receiver = findFunction(mainProjection, "receiver");
			final receiverNames = new Stage3OcamlLocalNames(receiver.getLocalCatalog(), true, name -> @:privateAccess EmitterStage.ocamlValueIdent(name));
			assertTrue(receiverNames.targetName(receiver.getParameters()[0].getProjectedName()) == "this__1",
				"typed parameter collided with the separate synthetic instance receiver");

			var missingFailed = false;
			try {
				collideNames.targetName("missing");
			} catch (_:String) {
				missingFailed = true;
			}
			assertTrue(missingFailed, "Stage3 local naming accepted a binding outside the sealed function catalog");

			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir, true);
			final generated = File.getContent(Path.join([outDir, "Main.ml"]));
			assertContains(generated, "collide (match_ : int) (match__1 : int) (method_ : int) (method__1 : int)",
				"Stage3 signature did not preserve exact target-local identities");
			assertContains(generated, "receiver (this_ : _) (this__1 : int)", "Stage3 merged a typed parameter with its synthetic receiver");
			assertContains(generated, "unknownValue (value : _)", "Unknown typed parameter was treated as unbound during emission");
			assertContains(generated, "chooseField (this_ : _) (value : int)", "same-named field displaced the exact parameter binding");
			assertContains(generated, "chooseMethod (this_ : _) (helper : int)", "same-named method displaced the exact parameter binding");
			assertTrue(generated.indexOf("and cycleA ") < 0 && generated.indexOf("and cycleB ") < 0,
				"a local parameter created a false recursive dependency on a same-named function");

			final result = run(executable, []);
			assertTrue(result.exitCode == 0, "native exact-local fixture failed: " + result.stderr);
			assertTrue(result.stdout == "2\n1\n10\n7\n8\n9\n15\n11\n9\n3\n15\n16\n1\n2\n12\n5\n",
				"native exact-local fixture observed the wrong bindings: " + result.stdout);
			final upstream = run("haxe", ["-cp", root, "--run", "Main"]);
			assertTrue(upstream.exitCode == 0, "upstream binding fixture failed: " + upstream.stderr);
			assertTrue(upstream.stdout == result.stdout, "native binding behavior differs from upstream Haxe");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		deleteRecursive(root);
		if (failure != null)
			throw failure;
		Sys.println("M14_STAGE3_TYPED_LOCAL_PROJECTION:PASS");
	}
}
