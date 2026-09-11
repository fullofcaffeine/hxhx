import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralCarrier;

/** Exercises the real lowerer and its carrier from an ordinary native consumer. */
class Main {
	static function main():Void {
		final value = OcamlTargetLiteralLowerer.buildNonNull(OcamlTargetLiteralFact.intLiteral(7, "Int"), Direct);
		switch value {
			case EConst(CInt(number)):
				Sys.println(number);
			case _:
				throw "Expected the direct integer literal";
		}
	}
}
