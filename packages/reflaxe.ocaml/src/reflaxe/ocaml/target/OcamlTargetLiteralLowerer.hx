package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.target.OcamlTargetLiteralRuntimeUse.OcamlTargetLiteralRuntimeAuthorization;

/** Haxe carrier facts that can change the OCaml form of a literal value. **/
enum OcamlTargetLiteralCarrier {
	Direct;
	NullableInt;
	NullableFloat;
	NullableBool;
	DynamicOrTypeParameter;
}

/**
	Builds OCaml syntax for host-neutral, non-null literal facts.

	This target-owned function is callable from stock Haxe and native `hxhx`.
	Context-sensitive null values stay with the request-owned builder until the
	runtime-requirement service is also independent from macro compiler objects.
**/
class OcamlTargetLiteralLowerer {
	public static function buildNonNull(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier,
			?authorization:OcamlTargetLiteralRuntimeAuthorization):OcamlExpr {
		if (fact == null || carrier == null)
			throw "OCaml target literal lowering requires a fact and carrier";
		final needsRuntimeBox = fact.kind == BoolValue && carrier == DynamicOrTypeParameter;
		if (!needsRuntimeBox && authorization != null)
			throw 'OCaml target literal ${fact.getCanonicalIdentity()} received unexpected private-runtime authority';
		return switch (fact.kind) {
			case NullValue:
				throw "context-sensitive null literal requires the request-owned target builder";
			case ThisValue | SuperValue:
				OcamlExpr.EIdent("self");
			case IntValue:
				final value = OcamlExpr.EConst(OcamlConst.CInt(fact.intValue));
				switch (carrier) {
					case NullableInt: represent(value);
					case NullableFloat: represent(OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [value]));
					case Direct | DynamicOrTypeParameter: value;
					case NullableBool: incompatible(fact, carrier);
				}
			case BoolValue:
				final value = OcamlExpr.EConst(OcamlConst.CBool(fact.boolValue));
				switch (carrier) {
					case NullableBool: represent(value);
					case DynamicOrTypeParameter:
						OcamlExpr.EApp(authorizedBoolBox(fact, carrier, authorization), [value]);
					case Direct: value;
					case NullableInt | NullableFloat: incompatible(fact, carrier);
				}
			case StringValue:
				switch (carrier) {
					case Direct | DynamicOrTypeParameter: OcamlExpr.EConst(OcamlConst.CString(fact.stringValue));
					case NullableInt | NullableFloat | NullableBool: incompatible(fact, carrier);
				}
		};
	}

	static function authorizedBoolBox(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier,
			authorization:Null<OcamlTargetLiteralRuntimeAuthorization>):OcamlExpr {
		if (authorization == null)
			throw 'OCaml target literal ${fact.getCanonicalIdentity()} requires checked Dynamic Boolean runtime authority';
		final reference = authorization.reference;
		if (authorization.literalIdentity != fact.getCanonicalIdentity()
			|| authorization.carrier != carrier
			|| reference.ownerId != authorization.decisionId
			|| reference.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| reference.exactSymbol != "HxRuntime.box_bool") {
			throw 'OCaml target literal ${fact.getCanonicalIdentity()} received conflicting Dynamic Boolean runtime authority';
		}
		return OcamlExpr.ERuntimeIdent(reference);
	}

	static function represent(value:OcamlExpr):OcamlExpr
		return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);

	static function incompatible(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier):OcamlExpr
		throw 'OCaml target literal ${fact.getCanonicalIdentity()} is incompatible with carrier ${carrier}';
}
