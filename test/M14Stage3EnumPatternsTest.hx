import haxe.io.Path;
import sys.io.File;

/** Compare real enum construction and payload matching with independent expected output. */
class M14Stage3EnumPatternsTest {
	static final root = "test/fixtures/stage3_enum_patterns";

	static function program(source:String, path:String):TypedModule {
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function rejects(action:Void->Void, expected:String):Void {
		var diagnostic = "";
		try {
			action();
		} catch (error:String) {
			diagnostic = error;
		}
		if (diagnostic.indexOf(expected) < 0)
			throw "missing enum rejection " + expected + ": " + diagnostic;
	}

	/** Invalid transport cannot silently choose another declaration with the same name. */
	static function checkSelection(typed:TypedModule):Void {
		final catalog = new backend.ocaml.Stage3OcamlEnums(name -> name.toLowerCase(), value -> '"' + value + '"');
		for (owner in typed.getBackendProjection().getClasses())
			catalog.add(owner, "Main_" + HxClassDecl.getName(owner.getDeclaration()), "");
		catalog.validate();
		final names = new backend.ocaml.Stage3OcamlLocalNames(new TypedBackendLocalCatalog([]), false, name -> name);
		var checked = false;
		for (owner in typed.getBackendProjection().getClasses()) {
			final facts = owner.requireSemanticFacts();
			for (constructor in facts.copyEnumConstructors())
				switch (constructor.member) {
					case Callable(method) if (constructor.name == "Pair"):
						function selected(ownerName:String, moduleName:String, declaration:String,
								arguments:Array<HxExpr>):TypedExactEnumConstructorSource.TypedExactEnumConstructorCall {
							return {
								owner: ownerName,
								modulePath: moduleName,
								declaration: declaration,
								constructor: "Pair",
								callee: EIdent("ignored"),
								arguments: arguments
							};
						}
						final args:Array<HxExpr> = [EInt(7), EBool(true)];
						final identity = facts.getClassIdentity();
						final moduleName = facts.getModuleIdentity();
						final exact = method.canonicalIdentity;
						rejects(() -> catalog.call(selected("Missing", moduleName, exact, args), _ -> "0", names), "exact program owner");
						rejects(() -> catalog.call(selected(identity, "Missing", exact, args), _ -> "0", names), "exact program owner");
						rejects(() -> catalog.call(selected(identity, moduleName, "Missing", args), _ -> "0", names), "exact constructor declaration");
						rejects(() -> catalog.call(selected(identity, moduleName, exact, []), _ -> "0", names), "exact constructor declaration");
						checked = true;
					case _:
				}
		}
		if (!checked)
			throw "enum selection controls did not exercise a payload constructor";
	}

	static function observe(command:String, arguments:Array<String>, label:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(Path.join([root, "expected.stdout"])))
			throw label + " enum observer failed with exit " + code + ": " + stdout + stderr;
	}

	static function main():Void {
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], "upstream");
		final path = Path.join([root, "Main.hx"]);
		final typed = program(File.getContent(path), path);
		checkSelection(typed);
		final unsupported = program("enum Choice { Values(values:Array<Int>); } class Main { static function main():Void {} }", "unsupported-enum/Main.hx");
		rejects(() -> EmitterStage.emitToDir(new MacroExpandedProgram([unsupported], false), ".tmp/stage3-enum-unsupported", true, false),
			"enum payload representation is not implemented");
		// A failed request must not retain its different Choice declaration.
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-enum-patterns", true);
		observe(executable, [], "native");
		EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-enum-patterns-repeat", true, false);
		Sys.println("M14_STAGE3_ENUM_PATTERNS:PASS");
	}
}
