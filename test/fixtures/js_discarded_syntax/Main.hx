/**
	Use the real target-syntax boundary to reproduce the standard library's split
	statement fragments. These fragments are statements, never assignment values.
 */
class Main {
	static function main():Void {
		if (true) untyped {
			js.Syntax.code("{");
			js.Syntax.code("console.log({0})", 7);
			js.Syntax.code("}");
		};
			(untyped {
				js.Syntax.code("{");
				js.Syntax.code("console.log({0})", 8);
				js.Syntax.code("}");
			});
		var value:Int = untyped {
			js.Syntax.code("({0} + {1})", 4, 5);
		};
		js.Syntax.code("console.log({0})", value);
	}
}
