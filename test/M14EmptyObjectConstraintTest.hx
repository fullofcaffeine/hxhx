import sys.io.File;

/** A method's empty object bound accepts object shapes without becoming a wildcard for scalar values. */
class M14EmptyObjectConstraintTest {
	static function main():Void {
		for (name in [
			"class",
			"object",
			"empty",
			"array",
			"string",
			"class_value",
			"interface",
			"null",
			"abstract_to_object"
		])
			check(name, true);
		for (name in ["int", "float", "bool", "function", "enum", "abstract_int", "abstract_object"])
			check(name, false);
		Sys.println("EMPTY_OBJECT_CONSTRAINT:PASS");
	}

	static var standardProviders:Null<Array<ResolvedModule>> = null;

	/**
		Index the real standard-library `Array` declaration next to each case.

		Typing names `Array<Int>` for `[1, 2]`. Without its provider that name stays
		unresolved, and call publication correctly refuses an unresolved named type, as it
		would in any real build. Parse it once and reuse it.
	**/
	static function providers():Array<ResolvedModule> {
		if (standardProviders == null) {
			final arguments = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
			final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(arguments);
			standardProviders = ResolverStage.parseProjectRootsShallow([standardRoot], ["Array"], new haxe.ds.StringMap<String>());
		}
		return standardProviders;
	}

	static function check(name:String, accepted:Bool):Void {
		final path = "test/oracle/empty_object_constraint_seed/" + name + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved].concat(providers())));
		} catch (error:TyperError) {
			if (accepted || error.getMessage() != "Constraint check failure for echo.T" || error.getFilePath() != path)
				throw error;
			rejected = true;
		}
		if (rejected == accepted)
			throw "object constraint acceptance differs for " + name;
		Sys.println("EMPTY_OBJECT_CONSTRAINT_CASE:PASS " + name);
	}
}
