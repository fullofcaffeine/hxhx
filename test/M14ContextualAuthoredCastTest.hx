/** An unchecked authored cast gets its destination context without changing its operand type. */
class M14ContextualAuthoredCastTest {
	static function main():Void {
		final source = "class Main { static var box:Box<Int> = 7; static var plain:Int = cast box;"
			+ "static var grouped:Int = (cast box); static function output(value:Int):Void {}"
			+ "static function result(value:Box<Int>):Int { return cast value; } static function consume(value:Box<Int>):Void {}"
			+
			"static function main():Void { var local:Int = cast box; output(cast box); consume(cast 9); local = cast box; plain = (cast box); } } abstract Box<T>(T) from T {}";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var casts = 0;
		var location = "";
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Cast && value.getTexts()[0] == "") {
				casts++;
				final input = value.getExpressions()[0];
				final enteringAbstract = input.getTag() == IntValue && input.getIntValue() == 9;
				final expected = enteringAbstract ? "nominal:Main.Box<primitive:Int>" : "primitive:Int";
				if (value.getType().getSemanticKey() != expected)
					throw "authored cast lost its destination context in " + location + ": " + value.getType().getSemanticKey();
				if (input.getType().getSemanticKey() != (enteringAbstract ? "primitive:Int" : "nominal:Main.Box<primitive:Int>"))
					throw "destination context changed the cast operand";
				if (value.isRepresentationPreservingCast())
					throw "authored cast borrowed an implicit conversion guarantee";
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
		for (owner in typed.getTypedClasses()) {
			for (initializer in owner.getFieldInitializers()) {
				location = initializer.getField().getName();
				expression(initializer.getExpression());
			}
			for (method in owner.getFunctions())
				for (child in method.getBody().getStatements()) {
					location = method.getStableIdentity() + "/" + Std.string(child.getTag());
					statement(child);
				}
		}
		if (casts != 8)
			throw "missing contextual cast coverage: " + casts;
		Sys.println("CONTEXTUAL_AUTHORED_CAST:PASS");
	}
}
