import sys.io.File;

/**
	Compare a native Stage3 program with upstream Haxe 4.3.7 for the fixture
	test/fixtures/ocaml_local_function_optional_arguments.

	The fixture first runs under upstream Haxe, so `expected.stdout` stays an
	upstream observation. The same source is then emitted through the native
	Stage3 OCaml emitter, built, and run; its output must match line for line.
 */
class M14Stage3LocalFunctionOptionalArgumentsTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_local_function_optional_arguments";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		// HAXE_BIN lets a worktree without node_modules use another checkout's pinned Haxe.
		final haxe = Sys.getEnv("HAXE_BIN");
		M14Stage3RuntimeFixture.observe({
			command: haxe == null || haxe.length == 0 ? "node_modules/.bin/haxe" : haxe,
			arguments: ["-cp", root, "--run", "Main"],
			expected: expected
		});
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_OPTIONAL_ARGUMENTS_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_local_function_optional_arguments", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_OPTIONAL_ARGUMENTS_NATIVE:PASS");
		// An omitted argument arrives as null. A Bool is an unboxed native bool and an
		// abstract uses its backing value, so neither slot can hold null; emission must
		// stop instead of reading null as a real value. Upstream prints 0/1 and -1/4.
		requireUnsupportedEmitFailure(root, "bool_optional",
			"class Main { static function main():Void { function f(?flag:Bool):Int { return flag == null ? 0 : 1; } Sys.println(f()); } }", "Null<Bool>");
		requireUnsupportedEmitFailure(root, "bool_default",
			"class Main { static function main():Void { function g(on:Bool = false):Int { return on ? 1 : 2; } Sys.println(g()); } }", "Bool");
		requireUnsupportedEmitFailure(root, "abstract_optional",
			"abstract Id(Int) { public function new(v:Int) this = v; public function get():Int return this; }\n" +
			"class Main { static function main():Void { function show(?id:Id):Int { return id == null ? -1 : id.get(); } Sys.println(show()); } }",
			"Id");
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_OPTIONAL_ARGUMENTS_UNSUPPORTED:PASS");
		dynamicAndForeignCallees(root);
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_OPTIONAL_ARGUMENTS_CALLEES:PASS");
	}

	/**
		A Dynamic local has no parameter list, so nothing is filled and no typed call
		is required. Any other callee that is not a function stops emission. A local
		with no declared type and no typed call has nothing to read parameters from.
	**/
	static function dynamicAndForeignCallees(root:String):Void {
		final slots:backend.ocaml.Stage3OcamlLocalCallOmissions.SentinelSlots = {isEnumBox: _ -> false, referenceCarrier: _ -> null};
		for (hint in ["Dynamic", "Null<Dynamic>"])
			if (backend.ocaml.Stage3OcamlLocalCallOmissions.omitted(TyType.fromHintText(hint), null, [], slots).length != 0)
				throw hint + " local must not receive filled arguments";
		requireOmissionFailure(TyType.fromHintText("Int"), slots, "requires a function-typed callee");
		requireOmissionFailure(null, slots, "requires its exact typed call");
		// Emission only: this proves the call reaches native code with its written arguments.
		final source = "class Main { static function run(load:Dynamic):Dynamic { return load(\"x\", 2); } static function main():Void {} }";
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		final outDir = ".tmp/ocaml_local_function_optional_dynamic";
		EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), outDir, false);
		final generated = File.getContent(outDir + "/Main.ml");
		if (generated.indexOf("__hx_call_function = (load)") < 0 || generated.indexOf("HxRuntime.hx_null") >= 0)
			throw "a Dynamic local call must keep exactly its written arguments: " + generated;
	}

	static function requireOmissionFailure(localType:Null<TyType>, slots:backend.ocaml.Stage3OcamlLocalCallOmissions.SentinelSlots, expected:String):Void {
		final message = try {
			backend.ocaml.Stage3OcamlLocalCallOmissions.omitted(localType, null, [], slots);
			null;
		} catch (error:String) {
			error;
		}
		if (message == null || message.indexOf(expected) < 0)
			throw "expected omission failure `" + expected + "`, got: " + message;
	}

	static function requireUnsupportedEmitFailure(root:String, label:String, source:String, typeText:String):Void {
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_local_function_optional_" + label, true);
			null;
		} catch (error:String) {
			error;
		}
		final expected = "OCaml local function optional parameter has no native null slot: ";
		if (message == null || message.indexOf(expected) < 0 || message.indexOf(typeText) < 0)
			throw label + ": an optional parameter without a null slot must fail at emit time, got: " + message;
	}
}
