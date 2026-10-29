/**
	A conditional shares the original empty Array child with its complete peer.
	Keep aliases, transactional failure and replay observable independently of
	printed type names; generated execution checks branch effects and values.
 */
class M14ConditionalArrayInferenceTest {
	static function main():Void {
		checkOccurrences();
		final declarations = 'typedef Rows<T>=Array<T>;class Item{public var value:Int;public function new(value:Int){this.value=value;}}'
			+ 'class Owner<T>{var rows:Rows<T>;public function new(rows:Rows<T>){this.rows=rows;}'
			+ 'public function select(flag:Bool):Rows<T>{var selected=flag?[]:rows;return selected;}}';
		final helpers = 'class Main{static function members():{items:Array<Item>}{return {items:[new Item(7)]};}'
			+ 'static function take(items:Array<Item>):Void{for(item in items)trace(item.value);}';
		for (entry in [
			{name: "empty_left", body: 'var member=members();var items=member.items==null?[]:member.items;take(items);', accepted: true},
			{name: "empty_right", body: 'var member=members();var items=member.items!=null?member.items:[];take(items);', accepted: true},
			{name: "source_if_left", body: 'var member=members();var items=if(false) [] else member.items;take(items);', accepted: true},
			{name: "source_if_right", body: 'var member=members();var items=if(true) member.items else [];take(items);', accepted: true},
			{name: "written_context", body: 'var member=members();var items:Array<Item>=false?[]:member.items;take(items);', accepted: true},
			{
				name: "alias_write",
				body: 'var left=[];var right:Array<Int>=[1];var selected=true?left:right;var copy=selected;copy.push(7);var value:Int=left[0];',
				accepted: true
			},
			{name: "alias_wrong_write", body: 'var left=[];var right:Array<Int>=[1];var selected=true?left:right;left.push("wrong");', accepted: false},
			{name: "applied_alias", body: 'var owner=new Owner<Int>([7]);var selected=owner.select(false);var value:Int=selected[0];', accepted: true},
			{name: "explicit_dynamic", body: 'var peer:Array<Dynamic>=[7];var selected=true?[]:peer;selected.push("text");', accepted: true},
			{name: "wrong_nonempty", body: 'var peer:Array<Int>=[7];var selected:Array<Int>=true?["wrong"]:peer;', accepted: false},
			{
				name: "branch_declarations",
				body: 'var peer:Array<Int>=[7];var selected=true?[]:{var same=peer;same;};var other=if(false) [] else {var same=peer;same;};var value:Int=selected.length+other[0];',
				accepted: true
			}
		]) {
			final root = JsRuntimeFixture.reserveOutput();
			final path = root + "/Main.hx";
			final source = declarations + helpers + 'static function main():Void{' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			upstream(root, entry.accepted);
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
				typed.getBackendProjection();
			} catch (error:TyperError) {
				if (entry.accepted
					|| error.message.indexOf("not compatible") < 0
					&& error.message.indexOf("No compatible") < 0
					&& !(entry.name == "alias_wrong_write"
						&& error.message == "member call conflicts with generic constructor constraints"))
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "conditional Array acceptance differs: " + entry.name;
			if (typed != null) {
				var observed = false;
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						if (HxFunctionDecl.getName(method.getSourceDeclaration()) == "main")
							for (local in method.getEnvironment().getLocals())
								if (["items", "selected", "left"].indexOf(local.getName()) >= 0) {
									final type = TyAliasExpansion.reveal(local.getType());
									final expected = entry.name == "explicit_dynamic" ? "dynamic" : entry.name.indexOf("alias") >= 0
										|| entry.name == "branch_declarations" ? "primitive:Int" : "nominal:Main.Item";
									if (type.getNominalIdentity() == null
										|| type.getNominalIdentity().getCanonicalName() != "Array"
										|| type.getTypeArguments().length != 1
										|| type.getTypeArguments()[0].getSemanticKey() != expected)
										throw "conditional Array lost its exact child: " + entry.name + type.getSemanticKey();
									observed = true;
								}
				if (!observed)
					throw "conditional Array observer missed its local: " + entry.name;
			}
			Sys.println("CONDITIONAL_ARRAY_INFERENCE:PASS " + entry.name);
		}
		checkRuntime();
	}

	/** Original terms survive aliasing, failed late fields and read-only replay. */
	static function checkOccurrences():Void {
		final index = TyperIndex.build([
			new ResolvedModule("Array", "Array.hx", ParserStage.parse("extern class Array<T>{}", "Array.hx"))
		]);
		final array = new TyNominalTypeId("Array");
		final intArray = TyType.nominal(array, [TyType.fromHintText("Int")]);
		final stringArray = TyType.nominal(array, [TyType.fromHintText("String")]);
		final scope = new TyFunctionEnv("conditional-array", [], [], TyType.unknown(), TyType.unknown());
		final inference = scope.getInference();
		final children:Array<HxExpr> = [];
		final empty:HxExpr = EArrayDecl(children);
		final peer:HxExpr = EIdent("peer");
		final source:HxExpr = ETernary(EBool(true), empty, peer);
		final incomplete = inference.inferredArray(empty, array);
		final original = inference.sourceTerm(empty, scope);
		if (inference.conditionalArrayResult(source, incomplete, original, intArray, null, index).getSemanticKey() != intArray.getSemanticKey()
			|| inference.sourceTerm(source, scope) != original
			|| inference.expressionType(empty, TyType.unknown(), scope).getSemanticKey() != intArray.getSemanticKey())
			throw "conditional did not retain its original child";
		final alias = scope.declareLocal("copy", intArray);
		inference.recordLocal(alias, inference.sourceTerm(source, scope));
		if (inference.constrain([EIdent("copy")], [stringArray], scope, index) || inference.sourceTerm(EIdent("copy"), scope) != original)
			throw "conditional alias lost its exact child constraint";
		inference.seal([]);
		if (inference.conditionalArrayResult(source, stringArray, null, stringArray, null, index).getSemanticKey() != intArray.getSemanticKey())
			throw "sealed conditional replaced an earlier occurrence";
		if (inference.conditionalArrayResult(ETernary(EBool(true), EArrayDecl([]), peer), incomplete, original, intArray, null, index) != null)
			throw "sealed conditional invented a new occurrence";
		children.push(EInt(1));
		var changedRejected = false;
		try {
			inference.conditionalArrayResult(source, incomplete, original, intArray, null, index);
		} catch (error:String) {
			changedRejected = error == "inferred result source changed during inference";
		}
		if (!changedRejected)
			throw "conditional source fingerprint was not retained";

		final rollbackScope = new TyFunctionEnv("conditional-rollback", [], [], TyType.unknown(), TyType.unknown());
		final rollback = rollbackScope.getInference();
		final allocation:HxExpr = EArrayDecl([]);
		rollback.inferredArray(allocation, array);
		final indexed:HxExpr = EArrayAccess(allocation, EInt(0));
		rollback.recordIndexedResult(indexed, allocation, rollbackScope, index);
		final first:HxExpr = EField(indexed, "first");
		final second:HxExpr = EField(indexed, "second");
		rollback.sourceTerm(first, rollbackScope);
		rollback.sourceTerm(second, rollbackScope);
		if (!rollback.constrain([second], [TyType.fromHintText("String")], rollbackScope, index))
			throw "rollback setup could not constrain its later field";
		final originalTerm = rollback.sourceTerm(allocation, rollbackScope);
		final before = rollback.expressionType(allocation, TyType.unknown(), rollbackScope);
		final wrong = TyType.nominal(array, [
			TyType.anonymous(["first", "second"], [TyType.fromHintText("Int"), TyType.fromHintText("Int")])
		]);
		final conditional:HxExpr = ETernary(EBool(true), allocation, EIdent("complete"));
		if (rollback.conditionalArrayResult(conditional, before, originalTerm, wrong, null, index) != null
			|| !rollback.expressionType(first, TyType.unknown(), rollbackScope).isUnknown()
			|| rollback.sourceTerm(conditional, rollbackScope) != null)
			throw "failed late conditional field committed an earlier child or occurrence";
		final right = TyType.nominal(array, [
			TyType.anonymous(["first", "second"], [TyType.fromHintText("Int"), TyType.fromHintText("String")])
		]);
		if (rollback.conditionalArrayResult(conditional, before, originalTerm, right, null, index) == null
			|| rollback.expressionType(first, TyType.unknown(), rollbackScope).getSemanticKey() != "primitive:Int")
			throw "successful conditional did not solve the original field";

		final declinedScope = new TyFunctionEnv("conditional-declines", [], [], TyType.unknown(), TyType.unknown());
		final declined = declinedScope.getInference();
		final left:HxExpr = EArrayDecl([]);
		final rightEmpty:HxExpr = EArrayDecl([]);
		final leftType = declined.inferredArray(left, array);
		final rightType = declined.inferredArray(rightEmpty, array);
		final leftTerm = declined.sourceTerm(left, declinedScope);
		if (declined.conditionalArrayResult(ETernary(EBool(true), left, rightEmpty), leftType, leftTerm, rightType,
			declined.sourceTerm(rightEmpty, declinedScope), index) != null
			|| declined.conditionalArrayResult(ETernary(EBool(true), left, peer), leftType, leftTerm, TyType.nullable(intArray), null, index) != null)
			throw "unsupported conditional gained inferred Array permission";
		final candidate = declinedScope.copyForInference();
		if (candidate.getInference().conditionalArrayResult(source, leftType, leftTerm, intArray, null, index) == null
			|| !declined.expressionType(left, TyType.unknown(), declinedScope).hasUnknownComponent())
			throw "speculative conditional leaked its child solution";
		final fixed:HxExpr = EArrayDecl([]);
		declined.contextualCollection(fixed, intArray);
		if (declined.conditionalArrayResult(ETernary(EBool(true), left, fixed), leftType, leftTerm, stringArray, declined.sourceTerm(fixed, declinedScope),
			index) != null)
			throw "stale complete peer supplied conditional permission";
		if (!declined.constrain([left], [intArray], declinedScope, index)
			|| declined.conditionalArrayResult(ETernary(EBool(true), left, fixed), leftType, leftTerm, intArray, declined.sourceTerm(fixed, declinedScope),
				index) != null)
			throw "stale incomplete preview supplied conditional permission";
		final knownUnknown:HxExpr = EArrayDecl([]);
		final unknownArray = TyType.nominal(array, [TyType.unknown()]);
		declined.contextualCollection(knownUnknown, unknownArray);
		final missingVariable:HxExpr = ETernary(EBool(true), knownUnknown, fixed);
		if (declined.conditionalArrayResult(missingVariable, unknownArray, declined.sourceTerm(knownUnknown, declinedScope), intArray,
			declined.sourceTerm(fixed, declinedScope), index) != null
			|| declined.sourceTerm(missingVariable, declinedScope) != null)
			throw "a display-only Unknown gained a new inference variable";
		Sys.println("CONDITIONAL_ARRAY_INFERENCE:PASS occurrence_transaction_replay");
	}

	/** Check selected values, once-only condition effects and the unselected abrupt branch in real generated JavaScript. */
	static function checkRuntime():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		final source = 'class Main{static var events="";static function condition(value:Bool):Bool{events+="c";return value;}'
			+ 'static function peer():Array<Int>{events+="p";return [7];}static function main():Void{'
			+ 'var first=condition(true)?[]:peer();first.push(3);var second=condition(false)?[]:peer();trace(first[0]);trace(second[0]);'
			+ 'var third=if(condition(false)) [] else peer();trace(third[0]);'
			+ 'try{var stopped=condition(true)?throw "stop":peer();trace(stopped);}catch(error:String){events+="x";}trace(events);}}';
		sys.io.File.saveContent(path, source);
		upstream(root, true);
		final expected = "3\n7\n7\nccpcpcx\n";
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [root + "/upstream.js"],
			expected: expected.split("\n")
				.filter(line -> line.length > 0)
				.map(line -> path + ":1: " + line + "\n")
				.join("")});
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("CONDITIONAL_ARRAY_INFERENCE:PASS generated_runtime");
	}

	static function upstream(root:String, accepted:Bool):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepted)
			throw "upstream conditional acceptance differs: " + stdout + stderr;
	}
}
