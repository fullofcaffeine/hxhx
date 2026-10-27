import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Run the complete shared guard contract through the production native C++ target. */
class M14CppSwitchGuardIntegrationTest {
	static function main():Void {
		final source = "test/fixtures/stage3_switch_guard";
		final expected = sys.io.File.getBytes(source + "/expected.stdout");
		observe("haxe", ["-cp", source, "-main", "Main", "--interp"], expected);
		Sys.println("CPP_SWITCH_GUARD_UPSTREAM:PASS");
		final fixture = CppResolvedFixture.load({sourceRoot: source, mainModule: "Main", requiredModules: ["Array", "Sys"]});
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new BackendContext(".tmp/cpp-switch-guard-complete", null, "Main", true, fixture.defines));
		if (!result.builtExecutable)
			throw "guarded switch acceptance requires a native executable";
		// A returning default case must remain unconditional after native value conversion.
		observe("c++", [
			"-std=c++17",
			"-Werror=return-type",
			"-fsyntax-only",
			".tmp/cpp-switch-guard-complete/src/Main.cpp"
		], haxe.io.Bytes.alloc(0));
		Sys.println("CPP_SWITCH_GUARD_RETURN_PATHS:PASS");
		observe(result.entryPath, [], expected);
		Sys.println("CPP_SWITCH_GUARD_COMPLETE:PASS");
	}

	/** Compare unchanged output and process status, preserving every shared fixture assertion. */
	static function observe(command:String, arguments:Array<String>, expected:haxe.io.Bytes):Void {
		final child = new sys.io.Process(command, arguments);
		final stdout = child.stdout.readAll();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0 || stdout.compare(expected) != 0)
			throw "guarded switch runtime differs: exit=" + code + " stdout=" + stdout.toString() + " stderr=" + stderr;
	}
}
