import haxe.io.Path;
import sys.io.File;

/** Compare real enum construction and payload matching with independent expected output. */
class M14Stage3EnumPatternsTest {
	static final root = "test/fixtures/stage3_enum_patterns";

	static function program(source:String, path:String):TypedModule {
		return M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: Path.directory(path)});
	}

	/** Negative sources own their classpath so lookup cannot reload the positive Main. */
	static function negativeProgram(source:String, name:String):TypedModule {
		final sourceRoot = ".tmp/stage3-enum-negative-" + name;
		sys.FileSystem.createDirectory(sourceRoot);
		final path = Path.join([sourceRoot, "Main.hx"]);
		File.saveContent(path, source);
		return program(source, path);
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
		var checked = 0;
		var checkedDynamic = 0;
		for (owner in typed.getBackendProjection().getClasses()) {
			final facts = owner.requireSemanticFacts();
			for (constructor in facts.copyEnumConstructors())
				switch (constructor.member) {
					case Callable(method) if (constructor.name == "Pair" || constructor.name == "NullableNumber"):
						function selected(ownerName:String, moduleName:String, declaration:String,
								arguments:Array<HxExpr>):TypedExactEnumConstructorSource.TypedExactEnumConstructorCall {
							return {
								owner: ownerName,
								modulePath: moduleName,
								declaration: declaration,
								constructor: constructor.name,
								callee: EIdent("ignored"),
								arguments: arguments
							};
						}
						final args:Array<HxExpr> = constructor.name == "Pair" ? [EInt(7), EBool(true)] : [ENull];
						final identity = facts.getClassIdentity();
						final moduleName = facts.getModuleIdentity();
						final exact = method.canonicalIdentity;
						rejects(() -> catalog.call(selected("Missing", moduleName, exact, args), _ -> "0", names, _ -> null), "exact program owner");
						rejects(() -> catalog.call(selected(identity, "Missing", exact, args), _ -> "0", names, _ -> null), "exact program owner");
						rejects(() -> catalog.call(selected(identity, moduleName, "Missing", args), _ -> "0", names, _ -> null),
							"exact constructor declaration");
						rejects(() -> catalog.call(selected(identity, moduleName, exact, []), _ -> "0", names, _ -> null), "exact constructor declaration");
						checked++;
					case Callable(method) if (constructor.name == "AnyValue"):
						final selected:TypedExactEnumConstructorSource.TypedExactEnumConstructorCall = {
							owner: facts.getClassIdentity(),
							modulePath: facts.getModuleIdentity(),
							declaration: method.canonicalIdentity,
							constructor: constructor.name,
							callee: EIdent("ignored"),
							arguments: [EBool(true)]
						};
						rejects(() -> catalog.call(selected, _ -> "true", names, _ -> null), "exact typed operand");
						checkedDynamic++;
					case _:
				}
		}
		if (checked != 3)
			throw "enum selection controls did not exercise both Pair owners and the required nullable payload";
		if (checkedDynamic != 1)
			throw "Dynamic enum selection did not reject a missing operand type";
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
		final unsupported = negativeProgram("enum Choice { Values(value:Float); } class Main { static function main():Void {} }", "float");
		rejects(() -> EmitterStage.emitToDir(new MacroExpandedProgram([unsupported], false), ".tmp/stage3-enum-unsupported", false),
			"enum payload representation is not implemented");
		final optionalFloat = negativeProgram("enum Choice { Values(?value:Float); } class Main { static function main():Void {} }", "optional-float");
		rejects(() -> EmitterStage.emitToDir(new MacroExpandedProgram([optionalFloat], false), ".tmp/stage3-enum-optional-unsupported", false),
			"enum payload representation is not implemented");
		// A failed request must not retain its different Choice declaration.
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-enum-patterns");
		observe(executable, [], "native");
		EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-enum-patterns-repeat", false);
		Sys.println("M14_STAGE3_ENUM_PATTERNS:PASS");
	}
}
