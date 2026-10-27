/** Indexed contexts constrain the original generic allocation, including aliases and declared ancestor views. */
class M14IndexedElementInferenceTest {
	static function main():Void {
		checkOccurrenceTransaction();
		final cases = [
			{
				name: "write_alias",
				declarations: "",
				body: 'var values=new Array();var alias=values;alias[0]=7;var value:Int=values[0];',
				accepted: true
			},
			{
				name: "contextual_read",
				declarations: "",
				body: 'var values=new Array();var value:Int=values[0];',
				accepted: true
			},
			{
				name: "array_ancestor",
				declarations: 'extern class Store<T> extends Array<T>{}',
				body: 'var values=new Store();values[0]=7;',
				accepted: true
			},
			{
				name: "interface",
				declarations: 'extern class Store<T> implements ArrayAccess<T>{public function new(size:Int);}',
				body: 'var values=new Store(1);values[0]=7;',
				accepted: true
			},
			{
				name: "interface_ancestor",
				declarations: 'extern class Base<A,B> implements ArrayAccess<B>{}extern class Store<T> extends Base<String,T>{public function new(size:Int);}',
				body: 'var values=new Store(1);var value:Int=values[0];',
				accepted: true
			},
			{
				name: "wrong_index",
				declarations: "",
				body: 'var values=new Array();values["bad"]=7;',
				accepted: false
			},
			{
				name: "wrong_payload",
				declarations: "",
				body: 'var values=new Array();values[0]=7;values[1]="bad";',
				accepted: false
			},
			{
				name: "explicit_dynamic",
				declarations: "",
				body: 'var values:Array<Dynamic>=new Array();values[0]=7;values[1]="text";',
				accepted: true
			}
		];
		for (entry in cases) {
			final root = JsRuntimeFixture.reserveOutput();
			final path = root + "/Main.hx";
			final source = entry.declarations + 'class Main{static function main():Void{' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted)
				throw "upstream indexed inference differs: " + entry.name + stdout + stderr;
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
				typed.getBackendProjection();
			} catch (error:TyperError) {
				if (entry.accepted || error.message.indexOf("array index") < 0 && error.message.indexOf("indexed element") < 0)
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "local indexed inference differs: " + entry.name;
			if (typed != null) {
				var found = false;
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						for (local in fn.getEnvironment().getLocals())
							if (local.getName() == "values" || local.getName() == "alias") {
								final arguments = local.getType().getTypeArguments();
								final expected = entry.name == "explicit_dynamic" ? "dynamic" : "primitive:Int";
								if (arguments.length != 1 || arguments[0].getSemanticKey() != expected)
									throw "indexed inference lost original receiver argument: " + entry.name + local.getType().getSemanticKey();
								found = true;
							}
				if (!found)
					throw "indexed inference observer missed the allocation";
			}
			Sys.println("INDEXED_ELEMENT_INFERENCE:PASS " + entry.name);
		}
		checkRuntime();
		TyperStage.typeModule(ParserStage.parse('class Legacy{static function main(){var values=[];values[0]=7;}}', "Legacy.hx"));
		Sys.println("INDEXED_ELEMENT_INFERENCE:PASS legacy_unindexed_typing");
	}

	/** Failure on a later operand must leave the original constructor and its nullable alias unsolved. */
	static function checkOccurrenceTransaction():Void {
		final array = new TyNominalTypeId("Array");
		final index = TyperIndex.build([
			new ResolvedModule("Array", "Array.hx", ParserStage.parse("extern class Array<T>{}", "Array.hx"))
		]);
		final scope = new TyFunctionEnv("indexed-transaction", [], [], TyType.unknown(), TyType.unknown());
		final inference = scope.getInference();
		final allocation:HxExpr = ENew("Array", []);
		final original = inference.construct(allocation, TyType.nominal(array, []), 1);
		final originalTerm = inference.sourceTerm(allocation, scope);
		final first = scope.declareLocal("values", original);
		final alias = scope.declareLocal("alias", TyType.nullable(original));
		inference.recordLocal(first, originalTerm);
		inference.recordLocal(alias, Nullable(originalTerm));
		final read:HxExpr = EArrayAccess(EIdent("values"), EInt(0));
		final aliasRead:HxExpr = EArrayAccess(EIdent("alias"), EInt(0));
		inference.recordIndexedResult(read, EIdent("values"), scope, index);
		inference.recordIndexedResult(aliasRead, EIdent("alias"), scope, index);
		if (inference.sourceTerm(read, scope) == null || inference.sourceTerm(read, scope) != inference.sourceTerm(aliasRead, scope))
			throw "indexed alias did not retain the exact constructor child";
		final fixed:HxExpr = EArrayDecl([]);
		inference.contextualCollection(fixed, TyType.nominal(array, [TyType.fromHintText("String")]));
		if (inference.constrain([read, fixed], [TyType.fromHintText("Int"), TyType.nominal(array, [TyType.fromHintText("Int")])], scope, index))
			throw "indexed transaction accepted a conflicting later operand";
		if (!inference.expressionType(allocation, original, scope).hasUnknownComponent())
			throw "indexed transaction partially solved its original constructor";
		if (!inference.constrain([aliasRead], [TyType.fromHintText("Int")], scope, index))
			throw "indexed alias rejected its selected context";
		inference.seal(scope.getLocals());
		if (inference.expressionType(allocation, original, scope).getTypeArguments()[0].getSemanticKey() != "primitive:Int")
			throw "indexed alias solved a copied child instead of its constructor";
		final copied:HxExpr = EArrayAccess(EIdent("values"), EInt(0));
		if (inference.sourceTerm(copied, scope) != null)
			throw "copied indexed syntax inherited another occurrence";
		Sys.println("INDEXED_ELEMENT_INFERENCE:PASS original_nullable_alias_rollback");
	}

	/** Observe mutation and exactly-once index/value effects through the inferred array. */
	static function checkRuntime():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		final source = 'class Main{static var effects=0;static function index():Int{effects=effects*10+1;return 0;}'
			+ 'static function value():Int{effects=effects*10+2;return 7;}'
			+ 'static function main():Void{var values=new Array();var alias=values;alias[index()]=value();'
			+ 'trace(values[0]);trace(effects);trace(values.length);}}';
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0)
			throw "upstream indexed runtime failed: " + stdout + stderr;
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [root + "/upstream.js"],
			expected: path + ":1: 7\n" + path + ":1: 12\n" + path + ":1: 1\n"
		});
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root}), "Main", "7\n12\n1\n");
		Sys.println("INDEXED_ELEMENT_INFERENCE:PASS runtime");
	}
}
