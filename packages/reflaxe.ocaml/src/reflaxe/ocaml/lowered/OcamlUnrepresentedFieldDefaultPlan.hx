package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The existing target value selected for a field without an explicit carrier decision. */
enum abstract OcamlUnrepresentedFieldDefaultKind(String) from String to String {
	final IntZero = "int-zero";
	final FloatZero = "float-zero";
	final BoolFalse = "bool-false";
	final RuntimeNull = "runtime-null";
	final CastRuntimeNull = "cast-runtime-null";
}

/**
	One concrete field default for a type without an explicit carrier decision.

	The value is plain data and contains no Haxe compiler object. It names the
	field or static cell that owns the value. It grants one private null-sentinel
	reference only when that exact default needs it.
**/
typedef OcamlUnrepresentedFieldDefaultDecision = {
	final id:String;
	final revision:String;
	final ownerId:String;
	final ownerRevision:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final kind:OcamlUnrepresentedFieldDefaultKind;
	final profileEligibility:Array<String>;
	final runtimeRequirements:Array<OcamlRuntimeRequirement>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/** Creates immutable default decisions and checks them again before target syntax exists. */
class OcamlUnrepresentedFieldDefaultPlan {
	public static inline final MODEL_REVISION = "ocaml-unrepresented-field-default-v1";
	public static inline final EXACT_SYMBOL = "HxRuntime.hx_null";
	public static inline final RUNTIME_ROLE = "unrepresented-field-null-default";

	/** Creates one immutable default decision from the current typed field. */
	public static function seal(type:Type, ownerId:String, ownerRevision:String, source:OcamlLoweredSourceSpan):OcamlUnrepresentedFieldDefaultDecision {
		requireOwner(ownerId, ownerRevision, source);
		if (type == null)
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:missing-type]: owner "$ownerId" has no typed field';
		if (OcamlRepresentationRegistry.isExactString(type)) {
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:represented-string]: exact String defaults require their sealed field representation';
		}
		final semanticTypeId = TypeTools.toString(type);
		final kind = classify(type);
		final id = "unrepresented-field-default:" + ownerId;
		final profiles = ["metal", "portable"];
		final requirement = usesRuntimeNull(kind) ? OcamlRuntimeRequirementLedger.requirementForCompilerInfrastructure(OcamlRuntimeRequirementLedger.CORE_RUNTIME) : null;
		final revision = revisionFor(id, ownerId, ownerRevision, source, semanticTypeId, kind, profiles, requirement);
		final runtimeRequirements = requirement == null ? [] : [requirement];
		final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence> = requirement == null ? [] : [
			{
				id: id + ":runtime-use:" + RUNTIME_ROLE,
				planRevision: revision,
				ownerId: id,
				requirementId: requirement.id,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: EXACT_SYMBOL,
				role: RUNTIME_ROLE,
				order: 0,
				source: copySource(source),
				profileEligibility: profiles.copy(),
				cardinality: 1
			}
		];
		return {
			id: id,
			revision: revision,
			ownerId: ownerId,
			ownerRevision: ownerRevision,
			source: copySource(source),
			semanticTypeId: semanticTypeId,
			kind: kind,
			profileEligibility: profiles,
			runtimeRequirements: runtimeRequirements,
			runtimeUseOccurrences: runtimeUseOccurrences
		};
	}

	/** Rejects a saved decision when its field, owner, or selected default changed. */
	public static function requireDecision(decision:OcamlUnrepresentedFieldDefaultDecision, type:Type):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-unrepresented-field-default:missing-plan]: field default requires an owner-bound plan";
		final expected = seal(type, decision.ownerId, decision.ownerRevision, decision.source);
		if (Json.stringify(decision) != Json.stringify(expected)) {
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:stale-plan]: default plan "${decision.id}" no longer matches its typed field or owner';
		}
	}

	/**
		Builds the selected target expression after validating its complete plan.

		Primitive constants need no runtime authority. A null default receives one
		request-local authority, so another field cannot reuse its permission.
	**/
	public static function materialize(decision:OcamlUnrepresentedFieldDefaultDecision, type:Type, authority:Null<OcamlRuntimeUseAuthority>):OcamlExpr {
		requireDecision(decision, type);
		return switch (decision.kind) {
			case IntZero:
				OcamlExpr.EConst(OcamlConst.CInt(0));
			case FloatZero:
				OcamlExpr.EConst(OcamlConst.CFloat("0."));
			case BoolFalse:
				OcamlExpr.EConst(OcamlConst.CBool(false));
			case RuntimeNull:
				runtimeNull(decision, authority);
			case CastRuntimeNull:
				OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [runtimeNull(decision, authority)]);
		}
	}

	static function runtimeNull(decision:OcamlUnrepresentedFieldDefaultDecision, authority:Null<OcamlRuntimeUseAuthority>):OcamlExpr {
		if (authority == null) {
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:missing-runtime-authority]: default plan "${decision.id}" cannot construct the private runtime null sentinel';
		}
		if (decision.runtimeUseOccurrences.length != 1) {
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:missing-runtime-use]: default plan "${decision.id}" has no unique null-sentinel occurrence';
		}
		final occurrence = decision.runtimeUseOccurrences[0];
		final reference = authority.expressionIdentifier(occurrence.id, decision.revision, EXACT_SYMBOL);
		return OcamlExpr.ERuntimeIdent(reference);
	}

	/** Preserves the zero, false, and null classification used by the prior compiler helper. */
	static function classify(type:Type):OcamlUnrepresentedFieldDefaultKind {
		return switch (type) {
			case TAbstract(abstractRef, parameters):
				final abstractType = abstractRef.get();
				switch (abstractType.name) {
					case "Int": IntZero;
					case "Float": FloatZero;
					case "Bool": BoolFalse;
					case "Null" if (parameters.length == 1):
						switch (parameters[0]) {
							case TAbstract(parameterRef, _):
								switch (parameterRef.get().name) {
									case "Int", "Float", "Bool": RuntimeNull;
									case _: CastRuntimeNull;
								}
							case _: CastRuntimeNull;
						}
					case _: CastRuntimeNull;
				}
			case _: CastRuntimeNull;
		}
	}

	static function usesRuntimeNull(kind:OcamlUnrepresentedFieldDefaultKind):Bool {
		return switch (kind) {
			case RuntimeNull, CastRuntimeNull: true;
			case IntZero, FloatZero, BoolFalse: false;
		}
	}

	static function revisionFor(id:String, ownerId:String, ownerRevision:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			kind:OcamlUnrepresentedFieldDefaultKind, profiles:Array<String>, requirement:Null<OcamlRuntimeRequirement>):String {
		final fields = [
			MODEL_REVISION,
			id,
			ownerId,
			ownerRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			semanticTypeId,
			(kind : String),
			profiles.join(","),
			requirement == null ? "no-runtime" : Json.stringify(requirement),
			EXACT_SYMBOL,
			RUNTIME_ROLE
		];
		return "sha256:" + Sha256.encode(fields.map(value -> value.length + ":" + value).join("|"));
	}

	static function requireOwner(ownerId:String, ownerRevision:String, source:OcamlLoweredSourceSpan):Void {
		if (ownerId == null || ownerId.length == 0)
			throw "reflaxe.ocaml [ocaml-unrepresented-field-default:missing-owner]: field default requires a concrete owner identity";
		if (ownerRevision == null || ownerRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:missing-owner-revision]: owner "$ownerId" has no revision';
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-unrepresented-field-default:invalid-source]: owner "$ownerId" has no valid source span';
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}
#end
