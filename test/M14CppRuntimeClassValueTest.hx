import backend.BackendContext;
import backend.cpp.CppTargetCore;

/**
	Runtime class values must preserve identity and ordinary type predicates.
	These existing portable Haxe fixtures keep their independent expectations;
	the C++ runner uses real providers and requires native execution.
 */
class M14CppRuntimeClassValueTest {
	static function main():Void {
		final selected = M14SmokeGroupSelection.selected([
			"class_lookup",
			"type_predicate",
			"secondary_names",
			"reflection_boundaries",
			"unsupported_reflection",
			"erased_array_alias",
			"array_recovery",
			"array_class_values",
			"int64_predicate"
		]);
		final failures = new Array<String>();
		for (fixture in [
			{
				name: "class_lookup",
				source: "test/portable/fixtures/type_reflection_basic/src",
				expected: "test/portable/fixtures/type_reflection_basic/expected.stdout"
			},
			{
				name: "type_predicate",
				source: "test/neko_std_is_of_type",
				expected: "test/neko_std_is_of_type/expected.stdout"
			},
			{
				name: "secondary_names",
				source: "test/oracle/runtime_class_value_seed/names",
				expected: "test/oracle/runtime_class_value_seed/names/expected.stdout"
			},
			{
				name: "reflection_boundaries",
				source: "test/oracle/cpp_managed_reflection_seed/src",
				expected: "test/oracle/cpp_managed_reflection_seed/expected.stdout"
			},
			{
				name: "unsupported_reflection",
				source: "test/oracle/cpp_managed_reflection_seed/unsupported",
				expected: ""
			},
			{
				name: "erased_array_alias",
				source: "test/oracle/runtime_class_value_seed/array",
				expected: "test/oracle/runtime_class_value_seed/array/expected.stdout"
			},
			{
				name: "array_recovery",
				source: "test/oracle/cpp_managed_array_recovery_seed/src",
				expected: "test/oracle/cpp_managed_array_recovery_seed/expected.cpp.stdout"
			},
			{
				name: 'array_class_values',
				source: 'test/oracle/cpp_array_class_value_seed/src',
				expected: 'test/oracle/cpp_array_class_value_seed/expected.stdout'
			},
			{
				name: 'int64_predicate',
				source: 'test/oracle/cpp_int64_class_predicate_seed/src',
				expected: 'test/oracle/cpp_int64_class_predicate_seed/expected.cpp.stdout'
			}
		]) {
			if (selected != "all" && selected != fixture.name)
				continue;
			Sys.println("CPP_RUNTIME_CLASS_VALUE:START " + fixture.name);
			Sys.stdout().flush();
			try {
				check(fixture);
				Sys.println("CPP_RUNTIME_CLASS_VALUE:PASS " + fixture.name);
			} catch (error:haxe.Exception) {
				final failure = fixture.name + ": " + error.message;
				failures.push(failure);
				Sys.println("CPP_RUNTIME_CLASS_VALUE:FAIL " + failure);
			}
		}
		if (failures.length != 0)
			throw failures.join("\n");
	}

	/** Keep every loaded provider in the program and compare the actual native process output. */
	static function check(input:{name:String, source:String, expected:String}):Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: input.source,
			mainModule: "Main",
			requiredModules: switch input.name {
				case 'array_class_values': ['Array'];
				case 'int64_predicate': ['haxe.Int64', 'Std'];
				case _: ['Std'];
			}
		});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		if (input.name == 'array_class_values')
			M14CppArrayClassValueTransferContract.check(new backend.cpp.CppTypedProgramProjection(program), fixture.index);
		final directory = ".tmp/cpp-runtime-class-value/" + input.name;
		if (input.name == "unsupported_reflection") {
			rejectUnsupportedReflection(program, fixture.defines, directory);
			return;
		}
		final result = CppTargetCore.emit(program, new BackendContext(directory, null, "Main", true, fixture.defines));
		if (!result.builtExecutable)
			throw "runtime class-value contract requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(input.expected))
			throw "native runtime class-value behavior differs: " + stdout + stderr;
	}

	/** Reject an unbound host descriptor before the target can overwrite prior generated output. */
	static function rejectUnsupportedReflection(program:MacroExpandedProgram, defines:haxe.ds.StringMap<String>, directory:String):Void {
		sys.FileSystem.createDirectory(directory);
		final output = directory + "/Main.cpp";
		final retained = "retained prior source\n";
		sys.io.File.saveContent(output, retained);
		final before = sys.FileSystem.readDirectory(directory);
		before.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		var rejected = false;
		try {
			CppTargetCore.emit(program, new BackendContext(directory, output, "Main", false, defines));
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("extern reflection requires a target-owned runtime identity") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "unsupported host reflection published a program";
		final after = sys.FileSystem.readDirectory(directory);
		after.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (sys.io.File.getContent(output) != retained || before.join("\n") != after.join("\n"))
			throw "unsupported host reflection changed generated artifacts";
	}
}
