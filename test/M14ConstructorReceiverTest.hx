import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native constructor state must preserve the public capture, rebinding, and null-transport observations. */
class M14ConstructorReceiverTest {
	static function main():Void {
		final failures = new Array<String>();
		for (name in ["primitive_capture", "array_capture", "nullable_transport"])
			try {
				check(name);
			} catch (error:haxe.Exception) {
				failures.push(name + ": " + error.message);
			}
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("CONSTRUCTOR_RECEIVER_NATIVE:PASS");
	}

	/** Each program uses its real dependency closure and must produce an executable with the retained baseline output. */
	static function check(name:String):Void {
		final root = "test/oracle/constructor_receiver_seed/" + name;
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: name == "primitive_capture" ? [] : ["Array"]});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program,
			new BackendContext(".tmp/constructor-receiver-candidate/" + name, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "constructor receiver contract requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "native constructor receiver differs from the retained baseline: " + stdout + stderr;
		Sys.println("CONSTRUCTOR_RECEIVER_NATIVE:PASS " + name);
	}
}
