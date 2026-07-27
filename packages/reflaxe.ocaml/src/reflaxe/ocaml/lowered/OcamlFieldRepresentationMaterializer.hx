package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;

/** Mechanical OCaml syntax facts derived from one validated field decision. */
typedef OcamlFieldRepresentationMaterialization = {
	final carrierType:OcamlTypeExpr;
	final implicitDefault:OcamlExpr;
}

/**
	Materializes field syntax from a program-owned representation decision.

	The registry decides the semantic type, carrier, storage domain, and Haxe
	implicit default. This helper checks that complete decision and translates it
	to the small OCaml AST fragments used by record and static-cell declarations.
	It never inspects a Haxe type or selects a fallback representation.
**/
class OcamlFieldRepresentationMaterializer {
	static function requireFieldDomain(decision:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain):Void {
		switch (expectedDomain) {
			case InstanceField, StaticField:
			case InternalValue, MutableLocalStorage, CapturedLocalStorage, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-domain]: field materialization requires instance-field or static-field, not $expectedDomain';
		}
		if (decision.domain != expectedDomain) {
			throw 'reflaxe.ocaml [ocaml-field-representation:wrong-domain]: representation ${decision.id} selects ${decision.domain}, but field materialization requires $expectedDomain';
		}
	}

	/**
		Returns the direct exact-Int field carrier and implicit zero initializer.

		Other semantic families stay rejected until their field representation and
		default policies receive their own bounded proof.
	**/
	public static function materializeExactInt(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		requireFieldDomain(decision, expectedDomain);
		if (decision.semanticTypeId != "Int"
			|| decision.carrierTypeId != "int"
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.ExactIntZero) {
			throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-decision]: representation ${decision.id} must select exact Int -> int with exact-int-zero, but selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} with ${decision.implicitDefaultPolicy}';
		}
		return {
			carrierType: OcamlTypeExpr.TIdent("int"),
			implicitDefault: OcamlExpr.EConst(OcamlConst.CInt(0))
		};
	}

	/** Returns the direct exact-Bool field carrier and implicit false initializer. */
	public static function materializeExactBool(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		requireFieldDomain(decision, expectedDomain);
		if (decision.semanticTypeId != "Bool"
			|| decision.carrierTypeId != "bool"
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.ExactBoolFalse) {
			throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-decision]: representation ${decision.id} must select exact Bool -> bool with exact-bool-false, but selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} with ${decision.implicitDefaultPolicy}';
		}
		return {
			carrierType: OcamlTypeExpr.TIdent("bool"),
			implicitDefault: OcamlExpr.EConst(OcamlConst.CBool(false))
		};
	}

	/**
		Returns one exact nullable primitive field carrier and implicit null.

		`Null<Int>` and `Null<Bool>` deliberately remain separate semantic
		decisions even though both mechanically use `Obj.t`.
	**/
	public static function materializeExactNullablePrimitive(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		requireFieldDomain(decision, expectedDomain);
		final admittedSemanticType = decision.semanticTypeId == "Null<Int>" || decision.semanticTypeId == "Null<Bool>";
		if (!admittedSemanticType
			|| decision.carrierTypeId != "Obj.t"
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel) {
			throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-decision]: representation ${decision.id} must select exact Null<Int> or Null<Bool> -> Obj.t with runtime-sentinel null, nullable-primitive boxing, and runtime-null-sentinel default, but selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} with ${decision.nullPolicy}, ${decision.boxingPolicy}, and ${decision.implicitDefaultPolicy}';
		}
		return {
			carrierType: OcamlTypeExpr.TIdent("Obj.t"),
			implicitDefault: OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
		};
	}

	/**
		Materializes one of the two explicitly admitted direct primitive fields.

		The decision's semantic type selects the already-proven mechanical
		translation. Unknown families fail instead of falling back to a type mapper.
	**/
	public static function materializeDirectPrimitive(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		return switch (decision.semanticTypeId) {
			case "Int": materializeExactInt(decision, expectedDomain);
			case "Bool": materializeExactBool(decision, expectedDomain);
			case other:
				throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-family]: no direct primitive field materializer exists for $other';
		}
	}

	/**
		Materializes any field family explicitly admitted by the representation registry.

		Unknown families fail rather than falling through to a legacy mapper.
	**/
	public static function materializeRepresentedField(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		return switch (decision.semanticTypeId) {
			case "Int", "Bool": materializeDirectPrimitive(decision, expectedDomain);
			case "Null<Int>", "Null<Bool>": materializeExactNullablePrimitive(decision, expectedDomain);
			case "String":
				final materialized = OcamlStringRepresentationMaterializer.materialize(decision, expectedDomain);
				{
					carrierType: materialized.carrierType,
					implicitDefault: materialized.implicitDefault
				};
			case other:
				throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-family]: no represented field materializer exists for $other';
		}
	}
}
#end
