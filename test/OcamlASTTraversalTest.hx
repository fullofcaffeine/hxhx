import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlASTTraversal;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlDebugPos;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.runtimegen.RuntimeUsageCollector;

/** Verifies exhaustive, deterministic traversal of the OCaml target AST. */
class OcamlASTTraversalTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertArrayEquals(expected:Array<String>, actual:Array<String>, label:String):Void {
		if (expected.length != actual.length)
			throw label + ": length mismatch expected=" + expected.length + " actual=" + actual.length + "\nexpected=" + expected.join(",") + "\nactual="
				+ actual.join(",");
		for (index in 0...expected.length) {
			if (expected[index] != actual[index])
				throw label + ": mismatch at " + index + " expected=" + expected[index] + " actual=" + actual[index];
		}
	}

	static function sortedUnique(values:Array<String>):Array<String> {
		final seen:Map<String, Bool> = [];
		for (value in values)
			seen.set(value, true);
		final result = [for (value in seen.keys()) value];
		result.sort(compareStrings);
		return result;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function allTypeConstructors():OcamlTypeExpr {
		return OcamlTypeExpr.TRecord([
			{name: "ident", isMutable: false, typ: OcamlTypeExpr.TIdent("type_ident")},
			{name: "app", isMutable: false, typ: OcamlTypeExpr.TApp("type_app", [OcamlTypeExpr.TVar("a")])},
			{name: "arrow", isMutable: false, typ: OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("type_from"), OcamlTypeExpr.TIdent("type_to"))},
			{name: "tuple", isMutable: true, typ: OcamlTypeExpr.TTuple([OcamlTypeExpr.TIdent("type_tuple")])}
		]);
	}

	static function allPatternConstructors():Array<OcamlPat> {
		return [
			OcamlPat.PAny,
			OcamlPat.PVar("pattern_var"),
			OcamlPat.PConst(OcamlConst.CInt(1)),
			OcamlPat.PTuple([OcamlPat.PVar("pattern_tuple")]),
			OcamlPat.POr([OcamlPat.PVar("pattern_or_left"), OcamlPat.PVar("pattern_or_right")]),
			OcamlPat.PConstructor("PatternCtor", [OcamlPat.PVar("pattern_constructor_arg")]),
			OcamlPat.PRecord([
				{
					name: "field",
					pat: OcamlPat.PVar("pattern_record")
				}
			]),
			OcamlPat.PAnnot(OcamlPat.PVar("pattern_annot"), allTypeConstructors())
		];
	}

	static function allExpressionConstructors():OcamlExpr {
		final debugPosition:OcamlDebugPos = {file: "Traversal.hx", line: 7, col: 3};
		return OcamlExpr.ESeq([
			OcamlExpr.EConst(OcamlConst.CUnit),
			OcamlExpr.EIdent("ident_leaf"),
			OcamlExpr.ERaw("raw_leaf"),
			OcamlExpr.EPos(debugPosition, OcamlExpr.EIdent("position_child")),
			OcamlExpr.ERaise(OcamlExpr.EIdent("raise_child")),
			OcamlExpr.ELet("binding", OcamlExpr.EIdent("let_value"), OcamlExpr.EIdent("let_body"), false),
			OcamlExpr.EFun(allPatternConstructors(), OcamlExpr.EIdent("function_body")),
			OcamlExpr.EApp(OcamlExpr.EIdent("application_function"), [OcamlExpr.EIdent("application_argument")]),
			OcamlExpr.EAppArgs(OcamlExpr.EIdent("labelled_function"),
				[
					{
						label: "required",
						isOptional: false,
						expr: OcamlExpr.EIdent("labelled_argument")
					},
					{label: "optional", isOptional: true, expr: OcamlExpr.EIdent("optional_argument")}
				]),
			OcamlExpr.EBinop(OcamlBinop.Add, OcamlExpr.EIdent("binary_left"), OcamlExpr.EIdent("binary_right")),
			OcamlExpr.EUnop(OcamlUnop.Not, OcamlExpr.EIdent("unary_child")),
			OcamlExpr.EIf(OcamlExpr.EIdent("if_condition"), OcamlExpr.EIdent("if_then"), OcamlExpr.EIdent("if_else")),
			OcamlExpr.EMatch(OcamlExpr.EIdent("match_scrutinee"), [
				{
					pat: OcamlPat.PVar("match_pattern"),
					guard: OcamlExpr.EIdent("match_guard"),
					expr: OcamlExpr.EIdent("match_body")
				},
				{pat: OcamlPat.PAny, guard: null, expr: OcamlExpr.EIdent("match_unguarded_body")}
			]),
			OcamlExpr.ETry(OcamlExpr.EIdent("try_body"),
				[
					{pat: OcamlPat.PVar("try_pattern"), guard: OcamlExpr.EIdent("try_guard"), expr: OcamlExpr.EIdent("try_handler")}
				]),
			OcamlExpr.ESeq([OcamlExpr.EIdent("nested_sequence_child")]),
			OcamlExpr.EWhile(OcamlExpr.EIdent("while_condition"), OcamlExpr.EIdent("while_body")),
			OcamlExpr.EList([OcamlExpr.EIdent("list_child")]),
			OcamlExpr.ERecord([
				{
					name: "value",
					value: OcamlExpr.EIdent("record_child")
				}
			]),
			OcamlExpr.EField(OcamlExpr.EIdent("field_owner"), "field"),
			OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent("assignment_left"), OcamlExpr.EIdent("assignment_right")),
			OcamlExpr.ETuple([OcamlExpr.EIdent("tuple_child")]),
			OcamlExpr.EAnnot(OcamlExpr.EIdent("annotation_child"), allTypeConstructors())
		]);
	}

	static function verifyConstructorCoverage(root:OcamlExpr):Void {
		final expressionConstructors:Array<String> = [];
		final patternConstructors:Array<String> = [];
		final typeConstructors:Array<String> = [];
		OcamlASTTraversal.walkExprPre(root, expression -> expressionConstructors.push(Type.enumConstructor(expression)),
			pattern -> patternConstructors.push(Type.enumConstructor(pattern)), type -> typeConstructors.push(Type.enumConstructor(type)));

		final expectedExpressions = Type.getEnumConstructs(OcamlExpr);
		final expectedPatterns = Type.getEnumConstructs(OcamlPat);
		final expectedTypes = Type.getEnumConstructs(OcamlTypeExpr);
		expectedExpressions.sort(compareStrings);
		expectedPatterns.sort(compareStrings);
		expectedTypes.sort(compareStrings);
		assertArrayEquals(expectedExpressions, sortedUnique(expressionConstructors), "expression constructor coverage");
		assertArrayEquals(expectedPatterns, sortedUnique(patternConstructors), "pattern constructor coverage");
		assertArrayEquals(expectedTypes, sortedUnique(typeConstructors), "type constructor coverage");
	}

	static function verifyEveryExpressionChild(root:OcamlExpr):Void {
		final identifiers:Array<String> = [];
		OcamlASTTraversal.walkExprPre(root, expression -> switch (expression) {
			case EIdent(name): identifiers.push(name);
			case _:
		}, _ -> {}, _ -> {});
		identifiers.sort(compareStrings);
		final expected = [
			"annotation_child",
			"application_argument",
			"application_function",
			"assignment_left",
			"assignment_right",
			"binary_left",
			"binary_right",
			"field_owner",
			"function_body",
			"ident_leaf",
			"if_condition",
			"if_else",
			"if_then",
			"labelled_argument",
			"labelled_function",
			"let_body",
			"let_value",
			"list_child",
			"match_body",
			"match_guard",
			"match_scrutinee",
			"match_unguarded_body",
			"nested_sequence_child",
			"optional_argument",
			"position_child",
			"raise_child",
			"record_child",
			"try_body",
			"try_guard",
			"try_handler",
			"tuple_child",
			"unary_child",
			"while_body",
			"while_condition"
		];
		expected.sort(compareStrings);
		assertArrayEquals(expected, identifiers, "expression child sentinels");
	}

	static function verifyIdentityAndWalkFoldOrder(root:OcamlExpr):Void {
		final mapped = OcamlASTTraversal.mapExprTree(root, expression -> expression, pattern -> pattern, type -> type);
		assertTrue(haxe.Serializer.run(mapped) == haxe.Serializer.run(root), "identity mapping must preserve the complete target AST");
		assertTrue(mapped == root, "identity mapping must reuse the original root node");
		switch ([root, mapped]) {
			case [ESeq(originalItems), ESeq(mappedItems)]:
				assertTrue(mappedItems == originalItems, "identity mapping must reuse unchanged child arrays");
			case _:
				throw "constructor corpus must remain an ESeq root";
		}

		final walked:Array<String> = [];
		OcamlASTTraversal.walkExprPre(root, expression -> walked.push("E:" + Type.enumConstructor(expression)),
			pattern -> walked.push("P:" + Type.enumConstructor(pattern)), type -> walked.push("T:" + Type.enumConstructor(type)));
		final folded = OcamlASTTraversal.foldExpr(root, [], (events, expression) -> {
			events.push("E:" + Type.enumConstructor(expression));
			return events;
		}, (events, pattern) -> {
			events.push("P:" + Type.enumConstructor(pattern));
			return events;
		}, (events, type) -> {
			events.push("T:" + Type.enumConstructor(type));
			return events;
		});
		assertArrayEquals(walked, folded, "walk/fold event order");
	}

	static function verifyRuntimeUsageMigration():Void {
		final expression = OcamlExpr.ESeq([
			OcamlExpr.EAppArgs(OcamlExpr.EIdent("HxFn.call"), [{label: "value", isOptional: false, expr: OcamlExpr.EIdent("HxLabel.value")}]),
			OcamlExpr.EMatch(OcamlExpr.EIdent("HxScrutinee.value"), [
				{
					pat: OcamlPat.PConstructor("HxPattern.C", []),
					guard: OcamlExpr.EIdent("HxGuard.value"),
					expr: OcamlExpr.EAnnot(OcamlExpr.ERecord([{name: "value", value: OcamlExpr.EIdent("HxRecord.value")}]),
						OcamlTypeExpr.TApp("HxType.t", [OcamlTypeExpr.TIdent("HxNested.t")]))
				}
			]),
			OcamlExpr.ERaw("HxRaw.hidden")
		]);
		final items:Array<OcamlModuleItem> = [
			OcamlModuleItem.ILet([{name: "value", expr: expression}], false),
			OcamlModuleItem.IType([
				{name: "native", params: [], kind: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TIdent("HxDecl.t"))}
			], false)
		];
		final modules:Map<String, Bool> = [];
		RuntimeUsageCollector.collectFromModuleItems(items, moduleName -> modules.set(moduleName, true));
		final actual = [for (moduleName in modules.keys()) moduleName];
		actual.sort(compareStrings);
		final expected = [
			"HxDecl",
			"HxFn",
			"HxGuard",
			"HxLabel",
			"HxNested",
			"HxPattern",
			"HxRecord",
			"HxScrutinee",
			"HxType"
		];
		expected.sort(compareStrings);
		assertArrayEquals(expected, actual, "runtime usage through shared traversal");
		assertTrue(!modules.exists("HxRaw"), "raw OCaml text must remain opaque to structural runtime collection");
	}

	static function verifyDeepWalkIsStackSafe():Void {
		var expression:OcamlExpr = OcamlExpr.EIdent("HxDeep.value");
		final nestingDepth = 50000;
		for (_ in 0...nestingDepth)
			expression = OcamlExpr.EUnop(OcamlUnop.Not, expression);

		var visitedExpressions = 0;
		OcamlASTTraversal.walkExprPre(expression, _ -> visitedExpressions++, _ -> {}, _ -> {});
		assertTrue(visitedExpressions == nestingDepth + 1, "deep expression walk must visit every node without using the Haxe process call stack");

		final modules:Map<String, Bool> = [];
		RuntimeUsageCollector.collectFromModuleItems([OcamlModuleItem.ILet([{name: "deep", expr: expression}], false)],
			moduleName -> modules.set(moduleName, true));
		assertTrue(modules.exists("HxDeep"), "runtime usage collection must reach the leaf of a deeply nested expression");
	}

	public static function run():Void {
		final root = allExpressionConstructors();
		verifyConstructorCoverage(root);
		verifyEveryExpressionChild(root);
		verifyIdentityAndWalkFoldOrder(root);
		verifyRuntimeUsageMigration();
		verifyDeepWalkIsStackSafe();
		Sys.println("OCAML_AST_TRAVERSAL:PASS");
	}
}
