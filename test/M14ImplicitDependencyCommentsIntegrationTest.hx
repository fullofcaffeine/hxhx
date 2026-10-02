/** Checks that documentation cannot add modules to either dependency discovery path. */
@:access(ResolverStage)
@:access(ModuleLoader)
class M14ImplicitDependencyCommentsIntegrationTest {
	static function check(label:String, actual:Array<String>, expected:String):Void {
		if (actual.join(",") != expected)
			throw label + ": expected " + expected + ", got " + actual.join(",");
	}

	static function main():Void {
		final source = [
			"// documentation.LineOnly",
			"/** documentation.BlockOnly */",
			"class Main { static function main() { real.Dependency.run(); } }"
		].join("\n");
		check("eager discovery", ResolverStage.implicitQualifiedTypeDeps(source), "real.Dependency");
		check("lazy discovery", ModuleLoader.implicitQualifiedTypeDeps(source), "real.Dependency");

		final separated = [
			"real /* comment */ . /* spanning",
			"lines */ Dependency.run();",
			"split/* boundary */name.NotJoined.run();",
			"@:build(macros.Excluded.build())"
		].join("\n");
		check("eager token boundaries", ResolverStage.implicitQualifiedTypeDeps(separated), "name.NotJoined,real.Dependency");
		check("lazy token boundaries", ModuleLoader.implicitQualifiedTypeDeps(separated), "name.NotJoined,real.Dependency");

		final samePackage = [
			"// new CommentConstructor(); CommentStatic.run();",
			"/* extends CommentBase implements CommentFace */",
			"class Main extends /* gap */ Base implements Face {",
			"static function main() { new/* gap */ Nearby(); Static/* gap */.run(); } }"
		].join("\n");
		final decl = new HxParser("package app; class Main {}").parseModule();
		check("same-package discovery", ResolverStage.implicitSamePackageDeps(samePackage, "app.Main", decl),
			"Base,Face,Nearby,Static,app.Base,app.Face,app.Nearby,app.Static");

		final literals = "var a = \"https://example/\\\"/*text*/\"; var b = '/*text*/'; var c = ~/[/][*]text[*][/]/;";
		if (HxLexer.maskComments(literals) != literals)
			throw "Comment-looking string or regular-expression text changed";
		final comments = "a/*x\r\ny*/b//z\n";
		if (HxLexer.maskComments(comments) != "a   \r\n   b   \n")
			throw "Comment masking changed source length, newlines, or token boundaries";
		Sys.println("IMPLICIT_DEPENDENCY_COMMENTS:PASS");
	}
}
