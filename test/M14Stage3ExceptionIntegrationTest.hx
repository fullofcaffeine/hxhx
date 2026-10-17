import haxe.io.Path;
import sys.io.File;

/** Compile the same authored exception program upstream and through native Stage3 OCaml. */
class M14Stage3ExceptionIntegrationTest {
	static final sourceRoot = Sys.args().indexOf("nominal") >= 0 ? "test/fixtures/stage3_exception_nominal_seed" : "test/fixtures/stage3_exception_seed";

	/** Recreated source text cannot borrow a thrown operand's type from another projection. */
	static function assertExactThrowOwnership(typed:TypedModule):Void {
		function operands(projection:TypedBackendFunctionProjection):Array<HxExpr> {
			final values = new Array<HxExpr>();
			function visit(statement:HxStmt):Void {
				switch statement {
					case SThrow(value, _):
						values.push(value);
					case _:
				}
				TypedBackendSourceWalk.statementChildren(statement, _ -> {}, visit);
			}
			for (statement in projection.getBody())
				visit(statement);
			return values;
		}
		for (functionValue in typed.getTypedClasses()[0].getFunctions()) {
			final projection = TypedBodySource.functionProjection(functionValue);
			final values = operands(projection);
			if (values.length == 0)
				continue;
			for (value in values)
				projection.requireThrownValue(value);
			final other = TypedBodySource.functionProjection(functionValue);
			var rejected = false;
			try {
				projection.requireThrownValue(operands(other)[0]);
			} catch (_:String) {
				rejected = true;
			}
			if (!rejected)
				throw "throw types accepted a same-source foreign projection";
			for (value in values)
				switch value {
					case ECall(_, arguments):
						arguments.push(ENull);
						var mutationRejected = false;
						try {
							projection.requireThrownValue(value);
						} catch (_:String) {
							mutationRejected = true;
						}
						if (!mutationRejected)
							throw "throw types accepted a mutated operand";
					case _:
				}
		}
	}

	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(Path.join([sourceRoot, "expected.stdout"])))
			throw "exception observer failed for " + command + ": " + stdout + stderr;
	}

	static function main():Void {
		observe("haxe", ["-cp", sourceRoot, "--run", "Main"]);
		final path = Path.join([sourceRoot, "Main.hx"]);
		final parsed = ParserStage.parse(File.getContent(path), path);
		final resolved = new ResolvedModule("Main", path, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		assertExactThrowOwnership(typed);
		final output = Sys.args().indexOf("nominal") >= 0 ? ".tmp/stage3-exception-nominal-seed" : ".tmp/stage3-exception-seed";
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), output, true);
		observe(executable, []);
		Sys.println("M14_STAGE3_EXCEPTION:PASS");
	}
}
