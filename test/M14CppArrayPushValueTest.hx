import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedArrayPushValue;

/** Compare stored native Array.push behavior and prove receiver cycles die under collection. */
class M14CppArrayPushValueTest {
	static function main():Void {
		final root = "test/oracle/cpp_array_push_value_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		observe("haxe", ["-cp", root, "-main", "Main", "--interp"], sys.io.File.getContent(root + "/expected.eval.stdout"));
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Array", "Sys"]});
		final prepared = CppResolvedFixture.prepare(fixture);
		ownership(new CppTypedProgramProjection(prepared));
		final directory = ".tmp/cpp-array-push-value";
		final result = CppTargetCore.emit(prepared, new BackendContext(directory, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "Array.push method values require a native executable";
		observe(result.entryPath, [], expected);
		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/stress" + optimization.substr(1);
			if (Sys.command("c++", [
				"-std=c++17",
				optimization,
				"-Wall",
				"-Wextra",
				"-Werror",
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-I" + directory + "/src",
				root + "/Stress.cpp",
				"-o",
				executable
			]) != 0)
				throw "Array.push method value observer did not compile: " + optimization;
			observe(executable, [], expected + expected);
			Sys.println("CPP_ARRAY_PUSH_VALUE:PASS " + optimization);
		}
	}

	/** Native bindings retain occurrence ownership even though they do not select authored method bodies. */
	static function ownership(program:CppTypedProgramProjection):Void {
		final classes = new CppManagedClassStorage(program);
		final other = new CppManagedClassStorage(program);
		final main = program.requireClass(program.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		final values = new Array<TypedBackendMethodOccurrence>();
		for (statement in main.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final occurrence = classes.methods.bound.functionValue(main, expression);
				if (occurrence != null)
					values.push(occurrence);
			}, _ -> {});
		if (values.length < 3)
			throw "Array.push fixture lost its real stored method occurrences";
		for (value in values) {
			CppManagedArrayPushValue.require(value, null, classes);
			reject(() -> CppManagedArrayPushValue.require(value, null, other), "another program or occurrence");
			switch value.getExpression() {
				case EField(receiver, name):
					if (classes.methods.bound.functionValue(main, EField(receiver, name)) != null)
						throw "copied method expression borrowed native binding evidence";
				case _:
					throw "stored Array.push lost its field expression";
			}
		}
		final body = main.getBody();
		body.push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> CppManagedArrayPushValue.require(values[0], null, classes), "projection was mutated");
		body.pop();
		CppManagedArrayPushValue.require(values[0], null, classes);
		Sys.println("CPP_ARRAY_PUSH_VALUE_OWNERSHIP:PASS");
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw "Array.push value accepted foreign or stale ownership";
	}

	/** Check process status and stderr as well as the independently recorded target output. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final child = new sys.io.Process(command, arguments);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0 || stdout != expected)
			throw "Array.push value runtime differs: exit=" + code + " stdout=" + stdout + " stderr=" + stderr;
	}
}
