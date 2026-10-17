/** Alias construction must reach generic direct-call selection with its resolved element type. */
class M14TypedefArrayConstructorTest {
	static function main():Void {
		final path = "test/oracle/generic_array_alias_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final main = functions.filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main");
		if (main.length != 1)
			throw "alias fixture lost its entry function";
		final statements = main[0].getBody().getStatements();
		final constructed = statements[0].getExpressions()[0];
		final identity = constructed.getType().getNominalIdentity();
		final pathName = identity == null ? constructed.getType().getUnresolvedPath() : identity.getCanonicalName();
		final arguments = constructed.getType().getTypeArguments();
		if (pathName != "Array" || arguments.length != 1 || arguments[0].getSemanticKey() != "primitive:Int")
			throw "alias constructor lost Array<Int>";
		final call = statements[1].getExpressions()[0];
		if (call.getDeclaration() == null || call.getType().getSemanticKey() != constructed.getType().getSemanticKey())
			throw "generic call lost its selected declaration or alias target type";
		Sys.println("TYPEDEF_ARRAY_CONSTRUCTOR:PASS");
	}
}
