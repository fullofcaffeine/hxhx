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

	static function check(name:String, accepted:Bool):Void {
		final path = "test/oracle/empty_object_constraint_seed/" + name + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
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
