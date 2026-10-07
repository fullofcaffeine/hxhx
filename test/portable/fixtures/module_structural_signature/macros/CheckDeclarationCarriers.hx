import haxe.macro.Context;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks declaration carriers without running the complete native compiler build. */
class CheckDeclarationCarriers {
	public static function check():Void {
		final registry = new OcamlRepresentationRegistry();
		final context = new CompilationContext();
		final failures:Array<String> = [];
		for (source in ["Null<{value:Int}>", "Null<First.Item>", "Float"]) {
			final type = Context.typeExpr(Context.parse("(null : " + source + ")", Context.currentPos())).t;
			final expected = source == "Float" ? "float" : "Obj.t";
			final signature = projectDeclarationSignature([type], type, registry, _ -> TIdent(expected), context);
			if (signature == null
				|| new OcamlASTPrinter().printType(signature.parameters[0]) != expected
					|| new OcamlASTPrinter().printType(signature.result) != expected)
				failures.push("missing declaration carrier: " + source);
			if (source != "Float")
				for (wrong in ["int", "bool", "float", "unit"])
					if (projectDeclarationSignature([type], type, registry, _ -> TIdent(wrong), context) != null)
						failures.push("unboxed nullable record accepted: " + wrong);
		}
		for (source in ["Null<Iterator<Int>>", "Null<{key:Int, value:Int}>", "Null<Float>"]) {
			final type = Context.typeExpr(Context.parse("(null : " + source + ")", Context.currentPos())).t;
			if (projectDeclarationSignature([type], type, registry, _ -> TIdent("Obj.t"), context) != null)
				failures.push("unsupported declaration admitted: " + source);
		}
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("NULLABLE_RECORD_FLOAT_DECLARATIONS:PASS");
	}
}
