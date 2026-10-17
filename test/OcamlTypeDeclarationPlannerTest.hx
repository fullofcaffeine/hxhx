import reflaxe.ocaml.ast.OcamlTypeDeclarationPlanner;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** Verifies stable OCaml declaration order and exact cycle rejection. */
class OcamlTypeDeclarationPlannerTest {
	static function assertEquals(expected:String, actual:String, label:String):Void {
		if (expected != actual)
			throw '$label: expected "$expected", received "$actual"';
	}

	static function main():Void {
		final orderedTypeGroups = OcamlTypeDeclarationPlanner.plan([
			{name: "holder", params: [], kind: Record([{name: "value", isMutable: true, typ: TIdent("value")}])},
			{name: "unrelated", params: [], kind: Record([{name: "flag", isMutable: false, typ: TIdent("bool")}])},
			{name: "value", params: [], kind: Record([{name: "label", isMutable: true, typ: TIdent("string")}])}
		]);
		assertEquals("value|holder|unrelated", declarationNames(orderedTypeGroups), "acyclic declarations");
		final mixed = OcamlTypeDeclarationPlanner.plan([
			{name: "link", params: [], kind: Variant([{name: "Next", args: [TIdent("node")]}])},
			{name: "node", params: [], kind: Record([{name: "link", isMutable: false, typ: TIdent("link")}])},
			{name: "holder", params: [], kind: Record([{name: "node", isMutable: false, typ: TIdent("node")}])}
		]);
		assertEquals("link+node|holder", declarationNames(mixed), "mixed recursive component before its user");
		final nested = OcamlTypeDeclarationPlanner.plan([
			{name: "node", params: [], kind: Record([{name: "kind", isMutable: false, typ: TIdent("kind")}])},
			{name: "kind", params: [], kind: Variant([{name: "Fields", args: [TIdent("field")]}])},
			{name: "field", params: [], kind: Variant([{name: "Value", args: [TIdent("node"), TIdent("leaf")]}])},
			{name: "leaf", params: [], kind: Variant([{name: "End", args: []}])}
		]);
		assertEquals("leaf|node+kind+field", declarationNames(nested), "external dependency precedes the complete recursive group");

		try {
			final recursiveTypeGroups = OcamlTypeDeclarationPlanner.plan([
				{name: "left", params: [], kind: Record([{name: "right", isMutable: true, typ: TIdent("right")}])},
				{name: "right", params: [], kind: Record([{name: "left", isMutable: true, typ: TIdent("left")}])}
			]);
			throw "recursive declarations unexpectedly succeeded: " + declarationNames(recursiveTypeGroups);
		} catch (error:Dynamic) {
			final message = Std.string(error);
			if (message.indexOf("[ocaml-type-order:unsupported-cycle]") < 0 || message.indexOf("left, right") < 0)
				throw "recursive declaration diagnostic changed: " + message;
		}
		Sys.println("OCAML_TYPE_DECLARATION_PLANNER:PASS");
	}

	static function declarationNames(groups:Array<Array<reflaxe.ocaml.ast.OcamlTypeDecl>>):String
		return groups.map(group -> group.map(declaration -> declaration.name).join("+")).join("|");
}
