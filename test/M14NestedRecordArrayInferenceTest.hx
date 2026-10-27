/**
	Selected record arguments constrain their original empty-array children.
	Candidate field storage types alone must not leave replay with Array<Dynamic>.
 */
class M14NestedRecordArrayInferenceTest {
	static function main():Void {
		checkOccurrences();
		final prefix = 'typedef Row={var items:Array<Int>;};'
			+ 'class Sink{public function new(){}public function take(row:Row):Void{row.items.push(3);trace(row.items[0]);}}'
			+ 'class Main{static function take(row:Row):Void{row.items.push(7);trace(row.items[0]);}'
			+ 'static function nested(row:{inner:Row}):Void{row.inner.items.push(9);trace(row.inner.items[0]);}';
		for (entry in [
			{name: "runtime",
				declarations: "",
				body: 'take({items:[]});var rows=new Array<Row>();rows.push({items:[]});'
				+ 'rows[0].items.push(4);trace(rows[0].items[0]);trace(rows[0].items.length);'
				+ 'new Sink().take({items:[]});nested(({inner:({items:[]})}));'
				+ 'var direct:Row={items:[]};direct.items.push(8);trace(direct.items[0]);',
				accepted: true
			},
			{
				name: "overload_int",
				declarations: 'extern class Host{@:overload(function(row:{items:Array<String>},marker:String):Void{})' +
				'public static function choose(row:Row,marker:Int):Void;}',
				body: 'Host.choose({items:[]},1);',
				accepted: true
			},
			{
				name: "overload_string",
				declarations: 'extern class Host{@:overload(function(row:{items:Array<String>},marker:String):Void{})' +
				'public static function choose(row:Row,marker:Int):Void;}',
				body: 'Host.choose({items:[]},"text");',
				accepted: true
			},
			{
				name: "wrong_element",
				declarations: "",
				body: 'var rows=new Array<Row>();rows.push({items:["wrong"]});',
				accepted: false
			},
			{
				name: "explicit_dynamic",
				declarations: "",
				body: 'var values:Array<Dynamic>=[];take({items:values});',
				accepted: false
			}
		]) {
			final root = ".tmp/nested-record-array-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.declarations + prefix + 'static function main():Void{' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted)
				throw "upstream nested record acceptance differs: " + entry.name + output + errors;
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
				typed.getBackendProjection();
			} catch (error:TyperError) {
				if (entry.accepted || error.message.indexOf("No compatible method signature") < 0)
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "local nested record acceptance differs: " + entry.name;
			if (typed != null) {
				final expected = entry.name == "overload_string" ? "primitive:String" : "primitive:Int";
				var observed = 0;
				function inspect(expression:TypedExpr):Void {
					if (expression.getTag() == ArrayDecl && expression.getExpressions().length == 0) {
						final arguments = expression.getType().getTypeArguments();
						if (arguments.length != 1 || arguments[0].getSemanticKey() != expected)
							throw "nested child lost selected element identity: " + expression.getType().getSemanticKey();
						observed++;
					}
					for (child in expression.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						for (statement in method.getBody().getStatements())
							for (expression in statement.getExpressions())
								inspect(expression);
				if (observed == 0)
					throw "nested record observer missed its original empty children";
				if (entry.name == "runtime") {
					final expectedOutput = "7\n4\n1\n3\n9\n8\n";
					// Observe both generated artifacts; compilation alone cannot prove
					// that the selected fields retain their allocated array values.
					final process = new sys.io.Process("node", [root + "/upstream.js"]);
					final actual = process.stdout.readAll().toString();
					final stderr = process.stderr.readAll().toString();
					final status = process.exitCode();
					process.close();
					final upstreamOutput = expectedOutput.split("\n")
						.filter(line -> line.length > 0)
						.map(line -> path + ":1: " + line + "\n")
						.join("");
					if (status != 0 || actual != upstreamOutput || stderr != "")
						throw "upstream nested record runtime differs: " + actual + stderr;
					JsRuntimeFixture.assertRuntime(typed, "Main", expectedOutput);
				}
			}
			Sys.println("NESTED_RECORD_ARRAY:PASS " + entry.name);
		}
	}

	/** A later failure must not partially solve an earlier child in the same selected-call transaction. */
	static function checkOccurrences():Void {
		final index = TyperIndex.buildHeaders([]);
		final array = new TyNominalTypeId("Array");
		final intArray = TyType.nominal(array, [TyType.fromHintText("Int")]);
		final stringArray = TyType.nominal(array, [TyType.fromHintText("String")]);
		final scope = new TyFunctionEnv("nested-record-transaction", [], [], TyType.unknown(), TyType.unknown());
		final first:HxExpr = EArrayDecl([]);
		final second:HxExpr = EArrayDecl([]);
		final record:HxExpr = EParenthesized(EAnon(["first", "inner"], [first, EAnon(["second"], [second])]), HxPos.unknown());
		final inference = scope.getInference();
		inference.inferredArray(first, array);
		inference.contextualCollection(second, stringArray);
		final wrong = TyType.anonymous(["first", "inner"], [intArray, TyType.anonymous(["second"], [intArray])]);
		if (inference.constrain([record], [wrong], scope, index))
			throw "nested record transaction accepted conflicting second child";
		if (!inference.expressionType(first, TyType.unknown(), scope).hasUnknownComponent())
			throw "failed nested record transaction committed its first child";
		final right = TyType.anonymous(["first", "inner"], [stringArray, TyType.anonymous(["second"], [stringArray])]);
		if (!inference.constrain([record], [right], scope, index))
			throw "selected nested record context was rejected";
		inference.seal([]);
		if (inference.expressionType(first, TyType.unknown(), scope).getSemanticKey() != stringArray.getSemanticKey())
			throw "selected nested record context missed its original first child";

		final mapScope = new TyFunctionEnv("nested-record-map-transaction", [], [], TyType.unknown(), TyType.unknown());
		final mapChild:HxExpr = EArrayDecl([]);
		final mapSecond:HxExpr = EArrayDecl([]);
		final mapRecord:HxExpr = EAnon(["first", "second"], [mapChild, mapSecond]);
		final mapInference = mapScope.getInference();
		mapInference.inferredArray(mapChild, array);
		mapInference.contextualCollection(mapSecond, stringArray);
		final mapType = TyType.nominal(new TyNominalTypeId("haxe.ds.Map"), [TyType.fromHintText("Int"), TyType.fromHintText("String")]);
		if (mapInference.constrain([mapRecord], [TyType.anonymous(["first", "second"], [mapType, intArray])], mapScope, index))
			throw "nested record Map transaction accepted conflicting second child";
		final uncommitted = mapInference.expressionType(mapChild, TyType.unknown(), mapScope);
		if (uncommitted.getNominalIdentity().getCanonicalName() != "Array" || !uncommitted.hasUnknownComponent())
			throw "failed nested record transaction committed its staged Map constructor";
		if (!mapInference.constrain([mapRecord], [TyType.anonymous(["first", "second"], [mapType, stringArray])], mapScope, index))
			throw "selected nested record Map transaction was rejected";
		mapInference.seal([]);
		if (mapInference.expressionType(mapChild, TyType.unknown(), mapScope).getSemanticKey() != mapType.getSemanticKey())
			throw "selected nested record Map constructor was not committed";

		final genericScope = new TyFunctionEnv("nested-record-binder", [], [], TyType.unknown(), TyType.unknown());
		final genericChild:HxExpr = EArrayDecl([]);
		genericScope.getInference().inferredArray(genericChild, array);
		final binder = TyType.typeParameter(TyTypeParameterId.method(new TyNominalTypeId("Owner"), true, "take", 0, 0, "T"));
		final genericArray = TyType.nominal(array, [binder]);
		if (!genericScope.getInference().constrain([EAnon(["items"], [genericChild])], [TyType.anonymous(["items"], [genericArray])], genericScope, index))
			throw "nested record lost its enclosing method binder";
		genericScope.getInference().seal([]);
		if (genericScope.getInference().expressionType(genericChild, TyType.unknown(), genericScope).getSemanticKey() != genericArray.getSemanticKey())
			throw "nested record replaced exact method binder identity";
		Sys.println("NESTED_RECORD_ARRAY:PASS original_occurrences_rollback_binder");
	}
}
