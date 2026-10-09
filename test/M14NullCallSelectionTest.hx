/** Null cannot invent a generic binding, break reference overload ties, or excuse another invalid argument. */
class M14NullCallSelectionTest {
	static function calls(source:String):Array<TypedExpr> {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final found = new Array<TypedExpr>();
		function expression(node:TypedExpr):Void {
			if (node.getTag() == Call)
				found.push(node);
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (type in typed.getTypedClasses())
			for (fn in type.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
					for (body in fn.getBody().getStatements())
						statement(body);
		return found;
	}

	static function selected(source:String, results:Array<String>):Void {
		final found = calls(source);
		if (found.length != results.length)
			throw "Null call fixture changed its call count";
		for (index in 0...found.length)
			if (found[index].getDeclaration() == null || found[index].getType().getDisplay() != results[index])
				throw "Null call lost its declaration or result type at " + index + ": " + found[index].getType().getDisplay();
	}

	static function main():Void {
		selected('class Main { static function choose<T>(first:T, second:T):T { return second; } static function main():Void { choose(null, "ok"); choose("ok", null); } }',
			["String", "String"]);
		selected('class Main { static function choose<T>(value:T):T { return value; } static function main():Void { choose(null); } }', ["Unknown"]);
		selected('class Main { static function choose<T>(value:Array<T>, fallback:T):T { return fallback; } static function main():Void { choose(null, "ok"); } }',
			["String"]);
		selected('class Main { static function nullable(value:Null<Int>):Bool { return value == null; } static function optional(value:Int = 7):Int { return value; } static function main():Void { nullable(null); optional(null); optional(); } }',
			["Bool", "Int", "Int"]);
		selected('class Box {} enum Signal { Ready; } abstract Text(String) {} abstract Wrapped<T>(T) {} class Main { static function box(value:Box):Void {} static function signal(value:Signal):Void {} static function text(value:Text):Void {} static function wrapped(value:Wrapped<String>):Void {} static function main():Void { box(null); signal(null); text(null); wrapped(null); } }',
			["Void", "Void", "Void", "Void"]);
		final invalid = calls('class Main { static function accept(value:String, count:Int):Void {} static function main():Void { accept(null, "wrong"); } }');
		if (invalid.length != 1 || invalid[0].getDeclaration() != null)
			throw "Null caused an invalid second argument to select a declaration";
		var ambiguous = false;
		try {
			calls('extern class Api { overload static function choose(value:String):Int; overload static function choose(value:Array<Int>):Int; } class Main { static function main():Void { Api.choose(null); } }');
		} catch (error:TyperError) {
			if (error.message.indexOf("Ambiguous overload, candidates follow") < 0)
				throw error;
			ambiguous = true;
		}
		if (!ambiguous)
			throw "Null broke a reference overload tie";
		Sys.println("M14_NULL_CALL_SELECTION:PASS");
	}
}
