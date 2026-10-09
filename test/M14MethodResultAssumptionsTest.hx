/** Independent inference graphs distinguish provisional recursion from completed helper facts. */
class M14MethodResultAssumptionsTest {
	static function main():Void {
		for (inputs in [false, true])
			for (throwsFirst in [false, true])
				for (recursiveHelper in [false, true])
					checkGraph(inputs, throwsFirst, recursiveHelper);
		Sys.println("METHOD_RESULT_ASSUMPTIONS:PASS");
	}

	/**
		Root reads a direct dependent, then a cached copy through Indirect.
		The provisional Unknown root makes Direct return Bool; later candidates
		make it return Int. Keeping a provisional result would stop at Bool.
		Stable never reads Root and must survive both retries and exceptions.
	 */
	static function checkGraph(inputs:Bool, throwsFirst:Bool, recursiveHelper:Bool):Void {
		final source = 'class Main {static function root(){return 1;} '
			+ (inputs ? 'static function direct(value):Int {return 1;} ' : 'static function direct(){return 1;} ')
			+ 'static function indirect(){return 1;} static function stable(){return 1;} static function main():Void {}}';
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Main");
		final declarations = new haxe.ds.StringMap<TyDeclarationInfo>();
		final counts = new haxe.ds.StringMap<Int>();
		for (name in ["root", "direct", "indirect", "stable"])
			declarations.set(name, owner.declarationForSignature(owner.staticMethod(name)));
		final results = new TyMethodBodyResults();
		final integer = TyType.fromHintText("Int");
		final boolean = TyType.fromHintText("Bool");
		function direct():TyType {
			return inputs ? results.signature(declarations.get("direct")).getArgs()[0] : results.result(declarations.get("direct"));
		}
		results.configure(declaration -> {
			final name = declaration.getSignature().getName();
			final count = counts.exists(name) ? counts.get(name) + 1 : 1;
			counts.set(name, count);
			final type = switch name {
				case "stable":
					if (recursiveHelper)
						results.result(declaration);
					integer;
				case "direct":
					final provisional = results.result(declarations.get("root"));
					final selected = provisional.isUnknown() ? boolean : integer;
					if (inputs)
						return {type: integer, complete: true, parameters: [selected]};
					selected;
				case "indirect": direct();
				case "root":
					results.result(declarations.get("stable"));
					direct();
					final selected = results.result(declarations.get("indirect"));
					if (throwsFirst && count == 1)
						throw new haxe.Exception("planned inference failure");
					selected;
				case _: throw "unexpected inference graph node";
			};
			return {type: type, complete: true, parameters: []};
		});
		if (throwsFirst) {
			var rejected = false;
			try
				results.result(declarations.get("root"))
			catch (error:haxe.Exception) {
				if (error.message != "planned inference failure")
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "inference graph lost its failure control";
		}
		if (results.result(declarations.get("root")).getSemanticKey() != "primitive:Int")
			throw "root reused a provisional dependent result";
		final attempts = throwsFirst ? 4 : 3;
		for (name in ["root", "direct", "indirect"])
			if (counts.get(name) != attempts)
				throw "dependent did not follow candidate changes: " + name + "/" + counts.get(name);
		if (counts.get("stable") != (recursiveHelper ? 2 : 1))
			throw "independent helper was discarded with an unrelated candidate: " + counts.get("stable");
		if (results.result(declarations.get("indirect")).getSemanticKey() != "primitive:Int"
			|| results.result(declarations.get("root")).getSemanticKey() != "primitive:Int"
			|| counts.get("root") != attempts)
			throw "completed result did not survive after provisional assumptions were discharged";
		Sys.println("METHOD_ASSUMPTION_CASE:PASS inputs=" + inputs + " failure=" + throwsFirst + " recursiveHelper=" + recursiveHelper);
	}
}
