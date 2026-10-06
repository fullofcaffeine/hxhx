import sys.io.File;

/** Compare abstract-header constructor inference with upstream before checking exact typed publication. */
class M14GenericConstructorAbstractFromTest {
	static function main():Void {
		check("AbstractFromCases");
		check("AbstractDynamicCases");
		reject("AbstractMissingHeader", "Array<String> should be Box<Unknown<0>>");
		reject("AbstractConflictingInputs", "Array<Int> should be Box<String>");
		reject("AbstractChangingRepresentation", "You can only declare from/to with compatible types");
	}

	/** Each case uses the real Array declaration, without typing unrelated library bodies. */
	static function fixture(module:String):{resolved:ResolvedModule, index:TyperIndex} {
		final path = "test/fixtures/generic_constructor_context/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", module], true);
		final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args);
		final defines = hxhx.Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final providers = ResolverStage.parseProjectRoots([standardRoot + "/js/_std", standardRoot], ["Array"], defines);
		return {resolved: resolved, index: TyperIndex.build([resolved].concat(providers))};
	}

	/** Upstream diagnostics define rejected inputs; local failure must occur at constructor selection. */
	static function reject(module:String, diagnostic:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"60",
			"node_modules/.bin/haxe",
			"-cp",
			"test/fixtures/generic_constructor_context",
			"--run",
			module
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 1 || stderr.indexOf(diagnostic) < 0)
			throw "upstream abstract rejection differs: " + module + ": " + stdout + stderr;
		final input = fixture(module);
		var rejection = "";
		try {
			TyperStage.typeResolvedModule(input.resolved, input.index);
		} catch (error:haxe.Exception) {
			rejection = error.message;
		}
		if (rejection.indexOf("generic constructor has no unique applicable declaration") < 0)
			throw "abstract constructor rejection differs: " + module + ": " + rejection;
		Sys.println("ABSTRACT_CONSTRUCTOR_REJECTION:" + module + ":PASS");
	}

	static function check(module:String):Void {
		final root = "test/fixtures/generic_constructor_context";
		final expected = module == "AbstractFromCases" ? "operand\nconstructed\ndone\n" : "constructed\ndone\n";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", module]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || stdout != expected)
			throw "upstream abstract constructor contract differs: " + stdout + stderr;
		Sys.println("ABSTRACT_CONSTRUCTOR_UPSTREAM:" + module + ":PASS");
		final input = fixture(module);
		final index = input.index;
		final typed = TyperStage.typeResolvedModule(input.resolved, index);
		final binder = index.getAbstractByFullName(module + ".Box").getTypeParameterIds()[0];
		var concreteCount = 0;
		var binderCount = 0;
		function inspect(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				final type = node.getType();
				final application = node.getConstructorApplication();
				if (type.getNominalIdentity() == null
					|| type.getNominalIdentity().getCanonicalName() != module + ".Holder"
					|| type.getTypeArguments().length != 1
					|| application == null
					|| node.getDeclaration() != application.getDeclaration())
					throw "abstract constructor lost its exact owner or selected declaration";
				final argument = type.getTypeArguments()[0];
				final parameter = application.getParameterTypes()[0];
				if (parameter.getNominalIdentity() == null
					|| parameter.getNominalIdentity().getCanonicalName() != module + ".Box"
					|| parameter.getTypeArguments().length != 1
					|| parameter.getTypeArguments()[0].getSemanticKey() != argument.getSemanticKey())
					throw "abstract constructor signature lost its inferred argument";
				if (argument.getSemanticKey() == "primitive:String")
					concreteCount++;
				else if (argument.getTypeParameterIdentity() != null
					&& argument.getTypeParameterIdentity().getCanonicalKey() == binder.getCanonicalKey())
					binderCount++;
				else
					throw "abstract constructor inferred the wrong concrete type or enclosing binder";
			}
			for (child in node.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		if (binderCount != 1 || concreteCount != (module == "AbstractFromCases" ? 1 : 0))
			throw "abstract constructor publication omitted an expected occurrence";
		Sys.println("ABSTRACT_CONSTRUCTOR_TYPES:" + module + ":PASS");
		if (module == "AbstractFromCases")
			M14GenericConstructorArgumentTest.assertRuntime(typed, module, expected);
	}
}
