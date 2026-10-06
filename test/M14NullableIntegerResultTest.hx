import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Preserve nullable operands while publishing exact integer results through locals and calls. */
class M14NullableIntegerResultTest {
	static function main():Void {
		final root = "test/oracle/nullable_integer_result_seed";
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "--macro", "TypeCheck.verify()", "--interp"]) != 0)
			throw "upstream nullable integer result contract failed";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var results = 0;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Binary
				&& value.getExpressions().length == 2
				&& value.getExpressions()[0].getType().unwrapNull().getSemanticKey() == "primitive:Int"
				&& value.getExpressions()[1].getType().unwrapNull().getSemanticKey() == "primitive:Int"
				&& (value.getExpressions()[0].getType().isNullable() || value.getExpressions()[1].getType().isNullable())) {
				if (value.getType().getSemanticKey() != "primitive:Int")
					throw "nullable integer arithmetic lost its exact result";
				results++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (results != 12)
			throw "nullable operands were erased or arithmetic cases were lost: " + results;
		Sys.println("NULLABLE_INTEGER_RESULT:TYPED:PASS");
		final output = ".tmp/nullable-integer-result";
		CppTargetCore.emit(new MacroExpandedProgram([typed], false), new BackendContext(output, null, "Main", true, false, new haxe.ds.StringMap()));
		CppManagedAssertionFixture.sanitizers(output, "NULLABLE_INTEGER_RESULT");
		Sys.println("NULLABLE_INTEGER_RESULT:PASS");
	}
}
