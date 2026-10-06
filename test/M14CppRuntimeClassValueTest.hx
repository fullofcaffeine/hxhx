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
			M14CppArrayClassValueTransferContract.check(new backend.cpp.CppTypedProgramProjection(program));
		final directory = ".tmp/cpp-runtime-class-value/" + input.name;
		final result = CppTargetCore.emit(program, new BackendContext(directory, null, "Main", true, true, fixture.defines));
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
}
