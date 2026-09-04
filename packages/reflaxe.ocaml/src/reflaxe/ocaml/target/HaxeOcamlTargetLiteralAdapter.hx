package reflaxe.ocaml.target;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end

/** Copies admitted public Haxe macro literals into target-owned facts. **/
class HaxeOcamlTargetLiteralAdapter {
	#if (macro || reflaxe_runtime)
	public static function fromConstant(constant:TConstant, semanticType:Type):Null<OcamlTargetLiteralFact> {
		if (constant == null || semanticType == null)
			throw "standalone OCaml literal adapter requires a typed constant";
		final typeDisplay = TypeTools.toString(semanticType);
		return switch (constant) {
			case TNull: OcamlTargetLiteralFact.nullValue(typeDisplay);
			case TThis: OcamlTargetLiteralFact.thisValue(typeDisplay);
			case TSuper: OcamlTargetLiteralFact.superValue(typeDisplay);
			case TBool(value): OcamlTargetLiteralFact.boolLiteral(value, typeDisplay);
			case TInt(value): OcamlTargetLiteralFact.intLiteral(value, typeDisplay);
			case TString(value): OcamlTargetLiteralFact.stringLiteral(value, typeDisplay);
			case TFloat(_): null;
		};
	}
	#end
}
