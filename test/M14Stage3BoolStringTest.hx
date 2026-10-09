import sys.io.File;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** String conversion must keep Boolean identity without changing integers or evaluation order. */
class M14Stage3BoolStringTest {
	static final root = "test/fixtures/stage3_bool_string";

	static function observe(command:String, arguments:Array<String>, label:String, expectation:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(root + "/" + expectation))
			throw label + " string conversion failed with exit " + code + ": " + stdout + stderr;
	}

	static function main():Void {
		run("Main", "expected.stdout");
		Sys.println("M14_STAGE3_BOOL_STRING:PASS");
	}

	/** Same-looking and changed expressions must not acquire another occurrence's type. */
	static function checkArguments(typed:TypedModule):Void {
		var checked = false;
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions()) {
				if (fn.findCallArgumentType(EBool(true)) != null)
					throw "copied Boolean expression borrowed a call argument type";
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						// Real dependency loading selects exact static declarations.
						// Decoding keeps each original argument object for these checks.
						final exact = TypedExactStaticCallSource.decode(expression);
						final call = exact == null ? expression : TypedExactStaticCallSource.ordinaryCall(exact);
						switch call {
							case ECall(EField(EIdent("Std"), "string"), [argument]):
								final type = fn.findCallArgumentType(argument);
								if (type == null)
									throw "original call lost its exact argument type";
								for (other in owner.getFunctions())
									if (other != fn && other.findCallArgumentType(argument) != null)
										throw "another function supplied a call argument type";
								switch argument {
									case ECall(_, arguments):
										arguments.push(EBool(true));
										var rejected = false;
										try {
											fn.findCallArgumentType(argument);
										} catch (error:String) {
											rejected = error.indexOf("changed after projection") >= 0;
										}
										arguments.pop();
										if (!rejected || fn.findCallArgumentType(argument).getSemanticKey() != type.getSemanticKey())
											throw "changed call operand retained stale conversion facts";
										checked = true;
									case _:
								}
							case _:
						}
					}, _ -> {});
			}
		if (!checked)
			throw "call mutation control did not run";
	}

	/** The combined suite retains independent scalar and collection expectations. */
	public static function run(moduleName:String, expectation:String):Void {
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", moduleName], "upstream", expectation);
		final typed = typeModule(moduleName);
		if (moduleName == "Main")
			checkArguments(typed);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-string-" + moduleName, true);
		observe(executable, [], "native", expectation);
	}

	/** Positive and rejected programs share the real declaration-loading boundary. */
	public static function typeModule(moduleName:String):TypedModule {
		final path = root + "/" + moduleName + ".hx";
		final resolved = new ResolvedModule(moduleName, path, ParserStage.parse(File.getContent(path), path));
		final arguments = Stage1Args.parse(["-cp", root, "-main", moduleName], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: ""
		});
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(paths, new haxe.ds.StringMap<String>(), index, null, false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader);
	}
}
