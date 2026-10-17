import backend.BackendContext;
import backend.source.SourceNativeTarget;
import backend.source.SourceTargetCommon;

/**
	Execute guarded switches with real target compilers and runtimes.
	The ordinary fixture loads standard-library declarations through Stage3.
	Closed enum fixtures use a complete local declaration index to isolate enum
	decisions from unrelated source-target standard-library packaging failures.
	This proves source adaptation and native execution, not full CLI readiness.
 */
class M14SourceGuardedControlTest {
	static function main():Void {
		final root = "test/fixtures";
		final output = ".tmp/source_guarded_control_" + Std.string(Std.int(haxe.Timer.stamp() * 1000));
		final fixtures:Array<{name:String, targets:Array<SourceNativeTarget>, loadStandardLibrary:Bool}> = [
			{name: "source_guarded_control", targets: [Python, Php, Java], loadStandardLibrary: true},
			{name: "source_guarded_array_alternatives", targets: [Python, Php], loadStandardLibrary: true},
			{name: "source_guarded_enum_coverage", targets: [Cs], loadStandardLibrary: false},
			{name: "source_guarded_enum_alternatives", targets: [Cs], loadStandardLibrary: false}
		];
		for (fixture in fixtures) {
			final directory = root + "/" + fixture.name;
			final path = directory + "/Main.hx";
			final source = sys.io.File.getContent(path);
			final expected = sys.io.File.getContent(directory + "/expected.stdout");
			M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", directory, "--run", "Main"], expected: expected});
			final typed = if (fixture.loadStandardLibrary) {
				M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: directory});
			} else {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]), null, true);
			};
			final program = new MacroExpandedProgram([typed], false);
			for (target in fixture.targets) {
				final targetOutput = output + "/" + fixture.name + "/" + Std.string(target);
				final result = SourceTargetCommon.emitTarget(target, program,
					new BackendContext(targetOutput, null, "Main", true, target == Cs, new haxe.ds.StringMap<String>()));
				switch target {
					case Java:
						M14Stage3RuntimeFixture.observe({
							command: "javac",
							arguments: [result.entryPath],
							expected: "",
							timeoutSeconds: 90
						});
						M14Stage3RuntimeFixture.observe({command: "java", arguments: ["-cp", targetOutput, "Main"], expected: expected});
					case Cs:
						M14Stage3RuntimeFixture.observe({command: "mono", arguments: [result.entryPath], expected: expected});
					case Python | Php:
						M14Stage3RuntimeFixture.observe({command: target == Python ? "python3" : "php", arguments: [result.entryPath], expected: expected});
					case Lua:
						throw "this fixture does not select Lua";
				}
				Sys.println("SOURCE_GUARDED_CONTROL:PASS " + fixture.name + " " + Std.string(target));
			}
		}
	}
}
