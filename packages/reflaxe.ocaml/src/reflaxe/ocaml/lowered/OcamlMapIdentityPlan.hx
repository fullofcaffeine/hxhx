package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierKind;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
#end

/** An exact standard-map comparison, independent of nullable target storage. */
typedef OcamlMapIdentityDecision = {
	final revision:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final leftType:String;
	final rightType:String;
	final leftKind:OcamlStandardMapCarrierKind;
	final rightKind:OcamlStandardMapCarrierKind;
	final negate:Bool;
	final order:Int;
};

/** Request-local association; typed expression objects never enter durable reports. */
typedef OcamlMapIdentityEntry = {
	final expression:TypedExpr;
	final decision:OcamlMapIdentityDecision;
};

/**
	Retains map identity decisions before OCaml syntax construction.

	A map is a reference even when Haxe exposes it through the Map abstract or
	a nullable typedef. Syntax must view both operands as Obj.t, evaluate each
	once from left to right, and compare physical identity. Obj.repr is a
	representation view; it neither allocates a replacement map nor unboxes null.
**/
class OcamlMapIdentityPlan {
	final byExpression:ObjectMap<TypedExpr, OcamlMapIdentityDecision> = new ObjectMap();

	public function new(entries:Array<OcamlMapIdentityEntry>) {
		for (entry in entries) {
			requireDecision(entry.decision);
			if (byExpression.exists(entry.expression))
				throw "reflaxe.ocaml [map-equality:duplicate]: comparison occurs twice";
			byExpression.set(entry.expression, copy(entry.decision));
		}
	}

	/** Returns a copy so inspection cannot mutate the active request's decision. */
	public function requireFor(expression:TypedExpr):OcamlMapIdentityDecision {
		final decision = byExpression.get(expression);
		if (decision == null)
			throw "reflaxe.ocaml [map-equality:missing]: comparison has no exact typed occurrence";
		requireDecision(decision);
		return copy(decision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in byExpression)
			if (!sameBinding(decision.binding, binding))
				throw "reflaxe.ocaml [map-equality:stale]: comparison belongs to another function revision";
	}

	public static function sameBinding(left:OcamlFunctionPlanBinding, right:OcamlFunctionPlanBinding):Bool {
		return left.functionId == right.functionId
			&& left.programRevision == right.programRevision
			&& left.bodyRevision == right.bodyRevision
			&& left.pipelineRevision == right.pipelineRevision;
	}

	public static function requireDecision(decision:OcamlMapIdentityDecision):Void {
		if (decision.binding.functionId.length == 0
			|| decision.binding.programRevision.length == 0
			|| decision.binding.bodyRevision.length == 0
			|| decision.binding.pipelineRevision.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.leftType.length == 0
			|| decision.rightType.length == 0
			|| decision.leftKind == null
			|| decision.rightKind == null
			|| decision.order < 0
			|| decision.revision != revisionFor(decision))
			throw "reflaxe.ocaml [map-equality:invalid]: comparison facts changed after planning";
	}

	public static function revisionFor(decision:OcamlMapIdentityDecision):String {
		return Sha256.encode([
			"standard-map-reference-identity-v1",
			decision.binding.functionId,
			decision.binding.programRevision,
			decision.binding.bodyRevision,
			decision.binding.pipelineRevision,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			decision.leftType,
			decision.rightType,
			Std.string(decision.leftKind),
			Std.string(decision.rightKind),
			Std.string(decision.negate),
			Std.string(decision.order)
		].join("\u001f"));
	}

	/** Binds the immutable comparison facts to their revision before registry insertion. */
	public static function seal(decision:OcamlMapIdentityDecision):OcamlMapIdentityDecision {
		return copy(decision, revisionFor(decision));
	}

	static function copy(decision:OcamlMapIdentityDecision, ?revision:String):OcamlMapIdentityDecision {
		return {
			revision: revision ?? decision.revision,
			binding: {
				functionId: decision.binding.functionId,
				programRevision: decision.binding.programRevision,
				bodyRevision: decision.binding.bodyRevision,
				pipelineRevision: decision.binding.pipelineRevision
			},
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			leftType: decision.leftType,
			rightType: decision.rightType,
			leftKind: decision.leftKind,
			rightKind: decision.rightKind,
			negate: decision.negate,
			order: decision.order
		};
	}
}

#if macro
/** Selects only exact standard-map pairs; Dynamic and unrelated abstracts retain their existing owners. */
class OcamlMapIdentityPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlMapIdentityPlan {
		final entries:Array<OcamlMapIdentityEntry> = [];
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TBinop(op = (OpEq | OpNotEq), left, right):
					final selected = selection(left.t, right.t);
					if (selected != null) {
						final facts:OcamlMapIdentityDecision = {
							revision: "",
							binding: binding,
							source: OcamlLoweredOrigin.sourceSpan(expression.pos),
							leftType: TypeTools.toString(left.t),
							rightType: TypeTools.toString(right.t),
							leftKind: selected.left,
							rightKind: selected.right,
							negate: op == OpNotEq,
							order: entries.length
						};
						entries.push({expression: expression, decision: OcamlMapIdentityPlan.seal(facts)});
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(root);
		return new OcamlMapIdentityPlan(entries);
	}

	public static function selection(left:Type, right:Type):Null<{left:OcamlStandardMapCarrierKind, right:OcamlStandardMapCarrierKind}> {
		final leftKind = kind(left);
		final rightKind = kind(right);
		return leftKind == null || rightKind == null ? null : {left: leftKind, right: rightKind};
	}

	/** Follow host indirections and nullable wrappers, without expanding arbitrary abstracts. */
	static function kind(type:Type):Null<OcamlStandardMapCarrierKind> {
		return switch (type) {
			case TType(reference, parameters):
				final definition = reference.get();
				kind(TypeTools.applyTypeParameters(definition.type, definition.params, parameters));
			case TMono(reference): final resolved = reference.get(); resolved == null || resolved == type ? null : kind(resolved);
			case TLazy(resolve): kind(resolve());
			case TAbstract(reference, [inner]) if (reference.get().pack.length == 0 && reference.get().name == "Null"): kind(inner);
			case _: OcamlStandardMapCarrierContract.kindForType(type);
		};
	}
}
#end

#end
