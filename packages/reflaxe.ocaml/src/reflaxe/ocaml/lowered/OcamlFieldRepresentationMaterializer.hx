package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlNullablePrimitiveFieldDefaultPlan.OcamlNullablePrimitiveFieldDefaultDecision;
import reflaxe.ocaml.lowered.OcamlStringDefaultPlan.OcamlStringDefaultDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

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

	/** Returns the exact nullable primitive field carrier without claiming a value. */
	public static function carrierForExactNullablePrimitive(decision:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain):OcamlTypeExpr {
		OcamlNullablePrimitiveFieldDefaultPlan.requireRepresentation(decision, expectedDomain);
		return OcamlTypeExpr.TIdent("Obj.t");
	}

	/**
		Returns one owner-bound nullable primitive field carrier and implicit null.

		`Null<Int>` and `Null<Bool>` deliberately remain separate semantic
		decisions even though both mechanically use `Obj.t`. The shared carrier
		decision is not permission to print a null sentinel: the concrete field
		default plan and request-local authority grant that one occurrence.
	**/
	public static function materializeExactNullablePrimitive(decision:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain,
			defaultPlan:OcamlNullablePrimitiveFieldDefaultDecision, authority:OcamlRuntimeUseAuthority):OcamlFieldRepresentationMaterialization {
		final carrierType = carrierForExactNullablePrimitive(decision, expectedDomain);
		OcamlNullablePrimitiveFieldDefaultPlan.requireDecision(defaultPlan, decision);
		if (authority == null)
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:missing-runtime-authority]: default plan "${defaultPlan.id}" cannot construct the private runtime null sentinel';
		final reference = authority.expressionIdentifier(defaultPlan.runtimeUse.id, defaultPlan.revision, OcamlNullablePrimitiveFieldDefaultPlan.EXACT_SYMBOL);
		return {
			carrierType: carrierType,
			implicitDefault: OcamlExpr.ERuntimeIdent(reference)
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
		Returns an admitted field carrier without constructing its implicit value.

		Planning and type declaration code uses this path so it cannot accidentally
		claim a runtime sentinel that will never appear in generated OCaml.
	**/
	public static function carrierForRepresentedField(decision:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain):OcamlTypeExpr {
		return switch (decision.semanticTypeId) {
			case "Int": materializeExactInt(decision, expectedDomain).carrierType;
			case "Bool": materializeExactBool(decision, expectedDomain).carrierType;
			case "Null<Int>", "Null<Bool>": carrierForExactNullablePrimitive(decision, expectedDomain);
			case "String": OcamlStringRepresentationMaterializer.carrierType(decision, expectedDomain);
			case other:
				throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-family]: no represented field carrier exists for $other';
		}
	}

	/**
		Materializes any field family explicitly admitted by the representation registry.

		Unknown families fail rather than falling through to a legacy mapper.
	**/
	public static function materializeRepresentedField(decision:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain,
			?stringDefaultPlan:OcamlStringDefaultDecision, ?stringRuntimeAuthority:OcamlRuntimeUseAuthority):OcamlFieldRepresentationMaterialization {
		return switch (decision.semanticTypeId) {
			case "Int", "Bool": materializeDirectPrimitive(decision, expectedDomain);
			case "Null<Int>", "Null<Bool>":
				throw 'reflaxe.ocaml [ocaml-field-representation:owner-required]: ${decision.semanticTypeId} defaults require materializeExactNullablePrimitive with a concrete field owner';
			case "String":
				final materialized = OcamlStringRepresentationMaterializer.materializeDefault(decision, expectedDomain, stringDefaultPlan,
					stringRuntimeAuthority);
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
