package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TFunc;
import haxe.macro.TypeTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;

/** Identifies where one Haxe-typed function result was observed. */
enum abstract OcamlTypedFunctionResultBoundarySource(String) from String to String {
	final Declaration = "declaration";
	final NestedFunction = "nested-function";
}

/**
	The Haxe-typed result that owns a conservative private return crossing.

	This boundary does not select a public OCaml call carrier. It records the
	result that Haxe already checked for one exact function body. When a more
	precise representation is unavailable, the control planner can carry a value
	through `Obj.t` and let the enclosing OCaml function infer its recovered type.
	The value cannot leave this function through that private representation.
**/
typedef OcamlTypedFunctionResultBoundaryPlan = {
	final id:String;
	final source:OcamlTypedFunctionResultBoundarySource;
	final semanticTypeId:String;
	final resultKind:OcamlCallResultKind;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Builds the typed fallback boundary without retaining Haxe compiler objects. */
class OcamlTypedFunctionResultBoundary {
	public static inline final MODEL = OcamlTypedFunctionResultModel.MODEL;
	public static inline final PROOF_ID = OcamlTypedFunctionResultModel.PROOF_ID;
	public static inline final INFERRED_CARRIER_TYPE_ID = OcamlTypedFunctionResultModel.INFERRED_CARRIER_TYPE_ID;

	/** Records the declared result of one ordinary Haxe function. */
	public static function fromDeclaration(data:ClassFuncData, binding:OcamlFunctionPlanBinding):OcamlTypedFunctionResultBoundaryPlan {
		final resultType = switch (TypeTools.follow(data.field.type)) {
			case TFun(_, result): result;
			case _: throw 'reflaxe.ocaml [typed-function-result:not-a-function]: declaration "${binding.functionId}" has no function result';
		};
		return create(resultType, OcamlTypedFunctionResultBoundarySource.Declaration, binding);
	}

	/** Records the independently typed result of one nested function literal. */
	public static function fromNestedFunction(tfunc:TFunc, binding:OcamlFunctionPlanBinding):OcamlTypedFunctionResultBoundaryPlan {
		final resultType:Type = switch (TypeTools.follow(tfunc.t)) {
			case TFun(_, result): result;
			case _: tfunc.t;
		};
		return create(resultType, OcamlTypedFunctionResultBoundarySource.NestedFunction, binding);
	}

	/** Returns the owner-bound identity used by one inferred input or output. */
	public static function representationId(functionId:String, role:String, semanticTypeId:String):String {
		return OcamlTypedFunctionResultModel.representationId(functionId, role, semanticTypeId);
	}

	/** Rejects a stale or self-contradictory typed result boundary. */
	public static function require(boundary:OcamlTypedFunctionResultBoundaryPlan, binding:OcamlFunctionPlanBinding):Void {
		if (boundary.id != "typed-function-result-boundary:" + haxe.crypto.Sha256.encode(boundary.functionId).substr(0, 24)
			|| boundary.functionId != binding.functionId
			|| boundary.programRevision != binding.programRevision
			|| boundary.bodyRevision != binding.bodyRevision
			|| boundary.pipelineRevision != binding.pipelineRevision
			|| boundary.semanticTypeId.length == 0
			|| boundary.proofId != PROOF_ID
			|| boundary.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [typed-function-result:invalid-boundary]: function "${binding.functionId}" has an incomplete or stale typed result boundary';
		}
		final isVoid = boundary.semanticTypeId == "Void";
		if ((isVoid && boundary.resultKind != OcamlCallResultKind.EffectOnlyVoid)
			|| (!isVoid && boundary.resultKind != OcamlCallResultKind.Value)) {
			throw 'reflaxe.ocaml [typed-function-result:invalid-kind]: function "${binding.functionId}" disagrees about its typed result kind';
		}
	}

	static function create(resultType:Type, source:OcamlTypedFunctionResultBoundarySource,
			binding:OcamlFunctionPlanBinding):OcamlTypedFunctionResultBoundaryPlan {
		final isVoid = OcamlCallPlanner.isExactVoid(resultType);
		final semanticTypeId = isVoid ? "Void" : TypeTools.toString(resultType);
		final boundary:OcamlTypedFunctionResultBoundaryPlan = {
			id: "typed-function-result-boundary:" + haxe.crypto.Sha256.encode(binding.functionId).substr(0, 24),
			source: source,
			semanticTypeId: semanticTypeId,
			resultKind: isVoid ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value,
			proofId: PROOF_ID,
			proofClaim: "Haxe assigned every return expression in this exact typed body to the function result. The private OCaml signal may erase that value only until the matching function handler recovers it. This boundary does not authorize a callable ABI or another function.",
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		require(boundary, binding);
		return boundary;
	}
}
#end
