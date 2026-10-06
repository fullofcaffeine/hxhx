import sys.io.File;

/** Independent upstream observations pin declaration order and rejected-bound rollback for conversion calls. */
class M14AbstractMethodConversionTest {
	static function index(source:String):TyperIndex {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperIndex.build([module]);
	}

	static function main():Void {
		final cases = [
			{
				name: "first",
				methods: '@:from static function first(value:String):Token{Sys.println("first");return new Token(1);} @:from static function second(value:String):Token{Sys.println("second");return new Token(2);}'
			},
			{
				name: "second",
				methods: '@:from static function second(value:String):Token{Sys.println("second");return new Token(2);} @:from static function first(value:String):Token{Sys.println("first");return new Token(1);}'
			},
			{
				name: "generic",
				methods: '@:from static function generic<T>(value:T):Token{Sys.println("generic");return new Token(1);} @:from static function exact(value:String):Token{Sys.println("exact");return new Token(2);}'
			},
			{
				name: "exact",
				methods: '@:from static function bounded<T:Int>(value:T):Token{Sys.println("bounded");return new Token(1);} @:from static function exact(value:String):Token{Sys.println("exact");return new Token(2);}'
			},
			{name: "unused", methods: '@:from static function unused<T>(value:String):Token{Sys.println("unused");return new Token(1);}'},
			{name: "dynamicInput", methods: '@:from static function dynamicInput(value:Dynamic):Token{Sys.println("dynamicInput");return new Token(1);}'}
		];
		for (entry in cases) {
			final source = 'abstract Token(Int){public function new(value:Int){this=value;}'
				+ entry.methods
				+ '}class Main{static function main(){var value:Token="input";}}';
			upstream(entry.name, source, entry.name + "\n");
			final plan = TyAbstractMethodConversion.select(index(source), TyType.nominal(new TyNominalTypeId("Main.Token"), []), TyType.fromHintText("String"));
			if (plan == null || plan.getDeclaration().getSignature().getName() != entry.name)
				throw "conversion declaration order differs: " + entry.name;
			final operand = TypedExpr.stringLiteral("input", TyType.fromHintText("String"), HxPos.unknown());
			final call = plan.apply(operand);
			if (call.getDeclaration() != plan.getDeclaration() || call.getExpressions().length != 2 || call.getExpressions()[1] != operand)
				throw "conversion lost the original operand or exact declaration";
			var rejectedForeign = false;
			try {
				plan.apply(TypedExpr.intLiteral(1, TyType.fromHintText("Int"), HxPos.unknown()));
			} catch (message:String) {
				if (message != "abstract method conversion received a different source type")
					throw message;
				rejectedForeign = true;
			}
			if (!rejectedForeign)
				throw "selected conversion accepted a different source operand type";
		}
		for (entry in [
			{name: "missing", method: 'static function ordinary(value:String):Token{return new Token(1);}'},
			{name: "input", method: '@:from static function wrong(value:Bool):Token{return new Token(1);}'},
			{name: "result", method: '@:from static function wrong(value:String):String{return value;}'}
		]) {
			final source = 'abstract Token(Int){public function new(value:Int){this=value;}'
				+ entry.method
				+ '}class Main{static function main(){var value:Token="input";}}';
			upstream(entry.name, source, "", false);
			if (TyAbstractMethodConversion.select(index(source), TyType.nominal(new TyNominalTypeId("Main.Token"), []), TyType.fromHintText("String")) != null)
				throw "unsupported conversion was selected: " + entry.name;
		}
		genericResult(false);
		genericResult(true);
		final headerSource = 'abstract Token(String) from String {public function new(value:String){this=value;} public function value():String{return this;} @:from static function convert(value:String):Token{Sys.println("convert");return new Token("converted");}}class Main{static function main(){var value:Token="hello";Sys.println(value.value());}}';
		upstream("header", headerSource, "hello\n");
		if (TyAbstractMethodConversion.select(index(headerSource), TyType.nominal(new TyNominalTypeId("Main.Token"), []),
			TyType.fromHintText("String")) != null)
			throw "an executable method displaced an applicable header conversion";
		headerInferencePriority();
		runtime();
		Sys.println("ABSTRACT_METHOD_CONVERSION_SELECTION:PASS order=6 header=1 inference=1 rollback=1 negatives=3");
	}

	/** The method selector must leave an unresolved higher-priority header choice to its owning inference path. */
	static function headerInferencePriority():Void {
		final source = 'class Cell<T>{public function new(){}}abstract Token(Dynamic) from Cell<String>{@:from static function fromInt(value:Cell<Int>):Token{return null;}}';
		final solver = new TyInferenceSolver("conversion-header-priority");
		final variable = solver.fresh();
		final plan = TyAbstractMethodConversion.constrain(index(source), solver, Nominal(new TyNominalTypeId("Main.Cell"), [variable]),
			TyType.nominal(new TyNominalTypeId("Main.Token"), []));
		if (plan != null || !solver.preview(variable).isUnknown())
			throw "method inference displaced unresolved header evidence";
	}

	/** The selected conversion and its source operand each execute once in the generated program. */
	static function runtime():Void {
		final path = "test/fixtures/abstract_method_conversion/Main.hx";
		final source = File.getContent(path);
		final expected = "convert\ntrue\nconvert\ntrue\noperand\nconvert\ntrue\nconvert\nfalse\npayload\nchanged\nchanged\nmeasure\n4\n";
		upstream("runtime", source, expected);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var conversions = 0;
		var representationChanges = 0;
		function expression(node:TypedExpr):Void {
			final declaration = node.getDeclaration();
			if (node.getTag() == Call
				&& declaration != null
				&& declaration.getOwner().getCanonicalName() == "Main.Size"
				&& declaration.getSignature().getName() == "measure") {
				representationChanges++;
				if (node.getType().getSemanticKey() != "nominal:Main.Size"
					|| node.getExpressions()[1].getType().getSemanticKey() != "primitive:String")
					throw "representation-changing method lost its source or result type";
			}
			if (node.getTag() == Call
				&& declaration != null
				&& declaration.getOwner().getCanonicalName() == "Main.Tagged"
				&& declaration.getSignature().getName() == "convert") {
				conversions++;
				if (node.getType().getSemanticKey() != "nominal:Main.Tagged<primitive:String>"
					|| node.getExpressions()[1].getType().getSemanticKey() != "nominal:Main.Cell<primitive:String>")
					throw "conversion lost its applied input or output type";
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (conversions != 4)
			throw "typed value boundaries did not retain exactly four selected conversions";
		if (representationChanges != 1)
			throw "representation-changing conversion was not an exact typed call";
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("ABSTRACT_METHOD_CONVERSION_RUNTIME:PASS");
	}

	/** A result context solves the source allocation; a failed method bound leaves it untouched. */
	static function genericResult(reject:Bool):Void {
		final source = 'class Cell<T>{public function new(){}}abstract Tagged<T>(Cell<T>){'
			+ 'public function new(value:Cell<T>){this=value;}@:from static function convert<U'
			+ (reject ? ':Int' : '')
			+ '>(value:Cell<U>):Tagged<U>{return new Tagged(value);}}';
		final types = index(source);
		final solver = new TyInferenceSolver("conversion-test");
		final variable = solver.fresh();
		final actual = TyInferenceTerm.Nominal(new TyNominalTypeId("Main.Cell"), [variable]);
		final expected = TyType.nominal(new TyNominalTypeId("Main.Tagged"), [TyType.fromHintText("String")]);
		final plan = TyAbstractMethodConversion.constrain(types, solver, actual, expected);
		if (reject) {
			if (plan != null || !solver.preview(variable).isUnknown())
				throw "failed conversion leaked its tentative solution";
			if (!solver.constrain(variable, TyInferenceSolver.fromType(TyType.fromHintText("Int"))))
				throw "failed conversion froze its source variable";
		} else {
			if (plan == null || solver.requireSolved(variable).getSemanticKey() != "primitive:String")
				throw "conversion result did not infer the source argument";
			if (plan.getInputType().getSemanticKey() != "nominal:Main.Cell<primitive:String>"
				|| plan.getResultType().getSemanticKey() != expected.getSemanticKey())
				throw "conversion plan contains an unspecialized signature";
		}
	}

	static function upstream(name:String, source:String, expected:String, accepted:Bool = true):Void {
		final root = ".tmp/abstract_method_conversion/" + name;
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (accepted ? code != 0 || output != expected : code != 1 || errors.length == 0)
			throw "upstream conversion selection differs: " + output + errors;
	}
}
