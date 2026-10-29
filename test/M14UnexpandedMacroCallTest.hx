/**
	Typer contracts that the Python standard library needs before any Python code is emitted.

	1. A call to a `macro` function passes syntax: an `Expr` parameter accepts any
	   source expression and a trailing `Array<Expr>` collects the rest, as in
	   `python.Syntax.arrayAccess(b, pos)` inside `haxe.io.Bytes.get`. The call keeps
	   its exact selected declaration and has a `Dynamic` value until expansion.
	2. A generic constructor infers its owner arguments through an actual abstract's
	   declared `to` conversion, as `new HaxeIterator(this.__iter__())` does in
	   `python.NativeIterable`.

	Each case is first checked against upstream Haxe (`--no-output`) so the expected
	verdict is observed, never assumed.
 */
class M14UnexpandedMacroCallTest {
	static final syntax = 'import haxe.macro.Expr;class Syn{'
		+ 'macro public static function at(x:Expr,rest:Array<Expr>):ExprOf<Dynamic> return macro null;'
		+ 'macro public static function named(x:Expr,name:String):Expr return macro null;}';
	static final iterator = 'typedef Raw<T>={function next():T;}'
		+ 'abstract Nat<T>(Raw<T>) to Raw<T>{public inline function new(p:Raw<T>) this=p;}'
		+ 'abstract Closed<T>(Raw<T>){public inline function new(p:Raw<T>) this=p;}'
		+ 'class Wrap<T>{var it:Raw<T>;public function new(it:Raw<T>){this.it=it;}}';

	static function main():Void {
		final selected = check("macro_value_operands",
			syntax
			+ 'class Main{static function code(s:String):Int return 0;'
			+ 'static function get(b:Array<Int>,i:Int):Int return Syn.at(b,i);'
			+ 'static function first(b:Array<Int>):Int return code(Syn.at(b));'
			+ 'static function pair(b:Array<Int>,i:Int):Int return Syn.at(b,i,i+1);'
			+ 'static function main():Void{}}',
			true);
		requireMacroSelection(selected, ["get", "first", "pair"]);
		check("macro_constant_parameter", syntax + 'class Main{static function main():Void{Syn.named([1],"label");}}', true);
		check("macro_constant_parameter_wrong_type", syntax + 'class Main{static function main():Void{Syn.named([1],7);}}', false);
		check("abstract_to_constructor",
			iterator + 'class Main{static function f(n:Nat<Int>):Wrap<Int> return new Wrap(n);' +
			'static function g<T>(n:Nat<T>):Wrap<T> return new Wrap(n);static function main():Void{var w=new Wrap(new Nat<String>(null));}}',
			true);
		check("abstract_to_constructor_wrong_argument",
			iterator + 'class Main{static function f(n:Nat<Int>):Wrap<String> return new Wrap(n);' + 'static function main():Void{}}', false);
		check("abstract_without_to", iterator + 'class Main{static function f(n:Closed<Int>):Wrap<Int> return new Wrap(n);static function main():Void{}}',
			false);
	}

	static function check(name:String, source:String, accepted:Bool):Null<TypedModule> {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepted)
			throw "upstream expectation differs: " + name + " " + output;
		var typed:Null<TypedModule> = null;
		try {
			typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
			typed.getBackendProjection();
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			typed = null;
		}
		if ((typed != null) != accepted)
			throw "local expectation differs: " + name;
		Sys.println("UNEXPANDED_MACRO_CALL:PASS " + name);
		return typed;
	}

	/** Every listed function must call the declared `Syn.at` macro, not a lookalike. */
	static function requireMacroSelection(typed:TypedModule, functions:Array<String>):Void {
		final found = new Array<String>();
		var current = "";
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Call && value.getDeclaration() != null) {
				final declaration = value.getDeclaration();
				if (declaration.getOwner().getCanonicalName() == "Main.Syn" && declaration.getSignature().getName() == "at") {
					if (!TyMacroCallSignature.isMacro(declaration))
						throw "macro selection lost its declaration modifier";
					if (found.indexOf(current) < 0)
						found.push(current);
				}
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
			for (fn in owner.getFunctions()) {
				current = HxFunctionDecl.getName(fn.getSourceDeclaration());
				for (stmt in fn.getBody().getStatements())
					statement(stmt);
			}
		for (name in functions)
			if (found.indexOf(name) < 0)
				throw "macro call did not select Syn.at in " + name;
		Sys.println("UNEXPANDED_MACRO_CALL:PASS exact_macro_declaration");
	}
}
