package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Closed literal shapes in the first host-neutral typed-expression tracer. **/
enum OcamlTargetLiteralKind {
	NullValue;
	ThisValue;
	SuperValue;
	BoolValue;
	IntValue;
	StringValue;
}

/**
	One copied literal expression that does not retain a host typed-AST object.

	The semantic type remains Haxe-shaped input. This record does not select an
	OCaml representation, boxing operation, runtime helper, or printed spelling.
	Float literals are intentionally outside revision 1 until the numeric review
	gate defines a cross-host lexical contract.
**/
class OcamlTargetLiteralFact {
	public static final SCHEMA_REVISION = "reflaxe-ocaml-target-literal-v1";

	public final kind:OcamlTargetLiteralKind;
	public final semanticTypeDisplay:String;
	public final boolValue:Bool;
	public final intValue:Int;
	public final stringValue:String;

	final canonicalIdentity:String;

	function new(kind:OcamlTargetLiteralKind, semanticTypeDisplay:String, boolValue:Bool = false, intValue:Int = 0, stringValue:String = "") {
		this.kind = kind;
		this.semanticTypeDisplay = required(semanticTypeDisplay);
		this.boolValue = boolValue;
		this.intValue = intValue;
		this.stringValue = stringValue == null ? "" : stringValue;
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationRequest.encode([
			SCHEMA_REVISION,
			Std.string(kind),
			this.semanticTypeDisplay,
			boolValue ? "1" : "0",
			Std.string(intValue),
			this.stringValue
		]));
	}

	public static function nullValue(semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(NullValue, semanticTypeDisplay);

	public static function thisValue(semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(ThisValue, semanticTypeDisplay);

	public static function superValue(semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(SuperValue, semanticTypeDisplay);

	public static function boolLiteral(value:Bool, semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(BoolValue, semanticTypeDisplay, value);

	public static function intLiteral(value:Int, semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(IntValue, semanticTypeDisplay, false, value);

	public static function stringLiteral(value:String, semanticTypeDisplay:String):OcamlTargetLiteralFact
		return new OcamlTargetLiteralFact(StringValue, semanticTypeDisplay, false, 0, value);

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	static function required(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target literal fact requires a semantic type";
		return normalized;
	}
}
