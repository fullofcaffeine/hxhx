import sys.io.File;

/** Generic self arguments preserve exact enclosing binder identity through constructor publication. */
class M14GenericConstructorSelfTest {
	static function main():Void {
		check("SelfCases", "self\n");
	}

	public static function check(module:String, expected:String, execute:Bool = true):Void {
		final root = "test/fixtures/generic_constructor_context";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", "node_modules/.bin/haxe", "-cp", root, "--run", module]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "upstream generic self contract failed: " + stdout + stderr;
		final path = root + "/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final binder = TyNominalApplication.parameterIds(index.getByFullName(module + ".Box"))[0];
		var checked = 0;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "wrap") {
					final construction = fn.getBody().getStatements()[0].getExpressions()[0];
					final type = construction.getType();
					if (construction.getTag() != NewValue
						|| construction.getConstructorApplication() == null
						|| type.getNominalIdentity().getCanonicalName() != module + ".Holder"
						|| type.getTypeArguments().length != 1
						|| type.getTypeArguments()[0].getTypeParameterIdentity() == null
						|| !type.getTypeArguments()[0].getTypeParameterIdentity().equals(binder))
						throw "constructor self argument lost its exact enclosing binder";
					checked++;
				}
		if (checked != 1)
			throw "generic self fixture lost its constructor return";
		if (execute)
			M14GenericConstructorArgumentTest.assertRuntime(typed, module, expected);
		Sys.println("GENERIC_CONSTRUCTOR_SELF:" + module + (execute ? ":TYPES_AND_RUNTIME:PASS" : ":TYPES:PASS"));
	}
}
