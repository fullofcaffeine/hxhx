/** Shadowing a lexical local introduces a capture; an unshadowed static constant still restricts a pattern. */
class M14PatternCaptureCoverageTest {
	static function main():Void {
		final cases = [
			{
				name: "local",
				source: 'class Main {static function main(){var value=99; var result=switch(4){case value:value;}; Sys.println(result); Sys.println(value);}}',
				expected: "4\n99\n"
			},
			{
				name: "local_over_constant",
				source: 'class Main {static inline var value=99; static function main(){var value=88; var result=switch(4){case value:value;}; Sys.println(result); Sys.println(value);}}',
				expected: "4\n88\n"
			},
			{
				name: "nested",
				source: 'enum A {A2(value:B);} enum B {BB(value:Float);} class Main {static function read(value:A):Float return switch(value){case A2(value):switch(value){case BB(value):value++;}}; static function main(){var value=A.A2(B.BB(12)); Sys.println(read(value)); Sys.println(read(value));}}',
				expected: "12\n12\n"
			}
		];
		for (entry in cases) {
			final root = ".tmp/pattern_capture_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, entry.source);
			requireOutput(run("haxe", ["-cp", root, "-main", "Main", "--interp"]), entry.expected);
			final typed = typeSource(entry.source, path);
			final functions = [for (cls in typed.getTypedClasses()) for (fn in cls.getFunctions()) fn];
			final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
			typed.getBackendProjection();
			for (index in 0...functions.length) {
				if (revisions[index] != CompilerTypedTreeRevision.functionBody(functions[index]))
					throw "coverage projection changed authored source";
				final lowered = TypedControlLowering.functionBody(functions[index]);
				if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
					throw "capture coverage changed on repeated lowering";
			}
			#if pattern_capture_ocaml
			final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root + "/ocaml", true);
			requireOutput(run("gtimeout", ["30", executable]), entry.expected);
			#else
			final context = new backend.BackendContext(root, root + "/local.n", "Main", true, false, HxDefineMap.fromRawDefines(["neko=1"]));
			final generated = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
			sys.io.File.saveContent(root + "/local.neko", generated);
			run("nekoc", [root + "/local.neko"]);
			requireOutput(run("gtimeout", ["30", "neko", root + "/local.n"]), entry.expected);
			#end
			Sys.println("PATTERN_CAPTURE_COVERAGE:PASS " + entry.name);
		}
		final source = 'class Main {static inline var value=99; static function main(){var result=switch(4){case value:1;}; Sys.println(result);}}';
		final root = ".tmp/pattern_capture_constant";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		run("haxe", ["-cp", root, "-main", "Main", "--interp"], "Unmatched patterns");
		var rejected = false;
		try {
			typeSource(source, root + "/Main.hx").getBackendProjection();
		} catch (error:String) {
			rejected = error.indexOf("exact exhaustive coverage") >= 0;
		}
		if (!rejected)
			throw "static constant incorrectly proved exhaustive capture coverage";
		Sys.println("PATTERN_CAPTURE_CONSTANT_REJECTION:PASS");
	}

	static function typeSource(source:String, path:String):TypedModule {
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function requireOutput(actual:String, expected:String):Void {
		if (actual != expected)
			throw "capture result differs: " + actual + " expected " + expected;
	}

	/** Negative compilation must fail for the required diagnostic, not a missing tool or unrelated error. */
	static function run(command:String, arguments:Array<String>, ?diagnostic:String):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (diagnostic == null ? code != 0 : code == 0 || (output + errors).indexOf(diagnostic) < 0)
			throw command + " failed contract: " + output + errors;
		return output;
	}
}
