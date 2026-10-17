import sys.io.File;

/** Observe native object storage against an independent upstream expectation. */
class M14Stage3ObjectStorageTest {
	static final root = "test/fixtures/stage3_object_storage";

	/** Same-spelled accesses from another projection cannot obtain conversion facts. */
	static function checkOwnership(fn:TypedFunction):Void {
		final projection = TypedBodySource.functionProjection(fn);
		final other = TypedBodySource.functionProjection(fn);
		final accesses = new Array<HxExpr>();
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				if (projection.findObjectAccess(expression) != null)
					accesses.push(expression);
			}, _ -> {});
		if (accesses.length == 0)
			throw "object fixture has no owned accesses";
		for (expression in accesses) {
			if (other.findObjectAccess(expression) != null)
				throw "object access borrowed another projection's facts";
			switch expression {
				case EField(receiver, field):
					if (projection.findObjectAccess(EField(receiver, field)) != null)
						throw "equal field syntax borrowed an original access";
				case _:
			}
		}
		final body = projection.getBody();
		body.splice(0, body.length);
		var rejected = false;
		try {
			projection.findObjectAccess(accesses[0]);
		} catch (error:String) {
			rejected = error.indexOf("absent") >= 0 || error.indexOf("changed") >= 0 || error.indexOf("mutat") >= 0;
		}
		if (!rejected)
			throw "removed object access retained conversion authority";
	}

	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(root + "/expected.stdout"))
			throw "object storage observer failed for " + command + ": " + stdout + stderr;
	}

	static function main():Void {
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		for (fn in typed.getTypedClasses()[0].getFunctions())
			if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
				checkOwnership(fn);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-object-storage", true);
		observe(executable, []);
		Sys.println("M14_STAGE3_OBJECT_STORAGE:PASS");
	}
}
