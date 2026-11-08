import sys.io.File;

/**
	Pass bare enum-abstract values as call arguments, as Haxe 4.3.7 allows.

	`takesInt(T1)`, where `T1` is a member of `enum abstract ET(Int) to Int`, stopped
	hxhx with the internal error "selected call conversion does not satisfy its retained
	parameter: unknown -> primitive:Int". Call publication rebuilt the argument from its
	identifier form, which had no type (haxe_ocaml-ikppg). A bare `Map<EA, Int>` key such
	as `counts.set(Uno, 1)` was rejected on main for the same reason (haxe_ocaml-jl3s8).

	`Main` covers static, instance and constructor arguments, a return value, an array
	literal and a String-backed member. It runs with upstream Haxe first, then is built
	natively with Stage3, and both outputs must equal `expected.stdout`. `TypedOnly`
	holds a function-value call and Map keys; it runs with upstream and is typed by hxhx.
 */
class M14Stage3EnumAbstractArgumentsTest {
	static function main():Void {
		final root = "test/fixtures/stage3_enum_abstract_arguments";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_ARGUMENTS_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3_enum_abstract_arguments", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_ARGUMENTS_NATIVE:PASS");

		// These forms are checked by typing only; Stage3 cannot build them natively yet.
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", root, "--run", "TypedOnly"],
			expected: "20\n3\n2\n3\n7\n3\n11 2 true\n"
		});
		// Load it under its own module name, with the production class paths.
		CppResolvedFixture.load({sourceRoot: root, mainModule: "TypedOnly", requiredModules: []});
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_ARGUMENTS_TYPED_ONLY:PASS");
	}
}
