package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;

/** One comparison of values from the same ordinary Haxe enum. */
typedef OcamlEnumEqualityDecision = {
	final id:String;
	final revision:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final enumName:String;
	final leftType:String;
	final rightType:String;
	final negate:Bool;
	final order:Int;
}

/** One payload construction that must allocate a distinct Haxe enum value. */
typedef OcamlEnumAllocationDecision = {
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final enumName:String;
	final constructorName:String;
	final arity:Int;
	final revision:String;
}

/**
	Preserves enum identity across native variants and nullable runtime boxes.

	The target first evaluates both operands in source order. It then removes
	any named enum box and compares the underlying values by physical identity.
	The existing recovery helper preserves the null sentinel and payload identity.
	This plan does not authorize structural equality, new boxes, or a call ABI.
	Payload construction records preserve argument order and require a fresh
	variant, including when OCaml could otherwise share constant payloads.
**/
class OcamlEnumIdentityPlan {
	public static inline final MODEL = "typed-enum-identity-comparison-v1";
	public static inline final CAPABILITY = "haxe-enum-identity-comparison";
	public static inline final HELPER = "HxEnum.unbox_or_obj";

	final ordered:Array<OcamlEnumEqualityDecision>;
	final byExpression:ObjectMap<TypedExpr, String>;
	final byId:Map<String, OcamlEnumEqualityDecision> = [];
	final allocations:ObjectMap<TypedExpr, OcamlEnumAllocationDecision>;

	public function new(decisions:Array<OcamlEnumEqualityDecision>, ?lookup:ObjectMap<TypedExpr, String>,
			?allocationLookup:ObjectMap<TypedExpr, OcamlEnumAllocationDecision>) {
		ordered = decisions.map(copy);
		byExpression = new ObjectMap();
		if (lookup != null)
			for (expression => id in lookup)
				byExpression.set(expression, id);
		allocations = new ObjectMap();
		if (allocationLookup != null)
			for (expression => decision in allocationLookup) {
				requireAllocationDecision(decision);
				allocations.set(expression, copyAllocation(decision));
			}
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw "reflaxe.ocaml [enum-equality:duplicate]: comparison occurs twice";
			byId.set(decision.id, decision);
		}
		if (lookup != null) {
			final seen:Map<String, Bool> = [];
			for (id in lookup) {
				if (!byId.exists(id) || seen.exists(id))
					throw "reflaxe.ocaml [enum-equality:lookup]: comparison lookup is not one-to-one";
				seen.set(id, true);
			}
			if (Lambda.count(seen) != ordered.length)
				throw "reflaxe.ocaml [enum-equality:lookup]: comparison has no typed occurrence";
		}
	}

	/** Returns copies so inspection cannot alter the request-owned decisions. */
	public function decisions():Array<OcamlEnumEqualityDecision> {
		return ordered.map(copy);
	}

	public function requireFor(expression:TypedExpr):OcamlEnumEqualityDecision {
		final id = byExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [enum-equality:missing]: comparison has no exact typed occurrence";
		requireDecision(decision);
		return copy(decision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (!sameBinding(binding, decision.binding))
				throw "reflaxe.ocaml [enum-equality:stale]: comparison belongs to another function revision";
		for (decision in allocations)
			if (!sameBinding(binding, decision.binding))
				throw "reflaxe.ocaml [enum-allocation:stale]: constructor belongs to another function revision";
	}

	/** Compares one occurrence with its active function without rescanning every decision in the body. */
	public static function sameBinding(left:OcamlFunctionPlanBinding, right:OcamlFunctionPlanBinding):Bool {
		return left.functionId == right.functionId
			&& left.programRevision == right.programRevision
			&& left.bodyRevision == right.bodyRevision
			&& left.pipelineRevision == right.pipelineRevision;
	}

	/** Requires the constructor occurrence selected before syntax generation. */
	public function requireAllocation(expression:TypedExpr):OcamlEnumAllocationDecision {
		final decision = allocations.get(expression);
		if (decision == null)
			throw "reflaxe.ocaml [enum-allocation:missing]: constructor has no exact typed occurrence";
		requireAllocationDecision(decision);
		return copyAllocation(decision);
	}

	public static function requireAllocationDecision(decision:OcamlEnumAllocationDecision):Void {
		if (decision.arity < 1
			|| decision.enumName.length == 0
			|| decision.constructorName.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.binding.functionId.length == 0
			|| decision.binding.programRevision.length == 0
			|| decision.binding.bodyRevision.length == 0
			|| decision.binding.pipelineRevision.length == 0
			|| decision.revision != allocationRevision(decision))
			throw "reflaxe.ocaml [enum-allocation:invalid]: constructor identity or arity changed";
	}

	public static function allocationRevision(decision:OcamlEnumAllocationDecision):String {
		return Sha256.encode([
			"fresh-enum-payload-v1",
			bindingKey(decision.binding),
			decision.enumName,
			decision.constructorName,
			Std.string(decision.arity),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			"evaluate-arguments-left-to-right",
			"opaque-first-payload"
		].join("\u001f"));
	}

	static function copyAllocation(decision:OcamlEnumAllocationDecision):OcamlEnumAllocationDecision {
		return {
			binding: {
				functionId: decision.binding.functionId,
				programRevision: decision.binding.programRevision,
				bodyRevision: decision.binding.bodyRevision,
				pipelineRevision: decision.binding.pipelineRevision
			},
			source: copySpan(decision.source),
			enumName: decision.enumName,
			constructorName: decision.constructorName,
			arity: decision.arity,
			revision: decision.revision
		};
	}

	/** Rejects altered identities, source spans, operand types, or operators. */
	public static function requireDecision(decision:OcamlEnumEqualityDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.enumName.length == 0
			|| decision.leftType.length == 0
			|| decision.rightType.length == 0
			|| decision.order < 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.binding.functionId.length == 0
			|| decision.binding.programRevision.length == 0
			|| decision.binding.bodyRevision.length == 0
			|| decision.binding.pipelineRevision.length == 0
			|| decision.revision != revisionFor(decision))
			throw "reflaxe.ocaml [enum-equality:invalid]: comparison facts changed or are incomplete";
	}

	/** Authorizes exactly one recovery operation for each already evaluated operand. */
	public static function runtimeUses(decision:OcamlEnumEqualityDecision):Array<OcamlRuntimeUseOccurrence> {
		requireDecision(decision);
		return [
			for (index in 0...2)
				{
					id: decision.id + ":use:" + index,
					planRevision: decision.revision,
					ownerId: decision.id,
					requirementId: requirementId(decision),
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: HELPER,
					role: index == 0 ? "left-enum-value" : "right-enum-value",
					order: index,
					source: copySpan(decision.source),
					profileEligibility: ["metal", "portable"],
					cardinality: 1
				}
		];
	}

	public static function requirementId(decision:OcamlEnumEqualityDecision):String {
		return decision.id + ":runtime:" + CAPABILITY;
	}

	/** Records why packaging must retain the existing enum recovery helper. */
	public function recordRequirements(ledger:OcamlRuntimeRequirementLedger):Void {
		for (decision in ordered) {
			requireDecision(decision);
			ledger.record({
				id: requirementId(decision),
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: copySpan(decision.source),
				semanticCapability: CAPABILITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.enumName
				},
				implementationFeature: MODEL,
				rootModules: ["HxEnum"],
				profileEligibility: ["metal", "portable"],
				explanation: "Enum equality recovers both underlying values before physical comparison. Recovery preserves null and payload identity."
			});
		}
	}

	static function bindingKey(binding:OcamlFunctionPlanBinding):String {
		return [
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision
		].join("\u001f");
	}

	public static function revisionFor(decision:OcamlEnumEqualityDecision):String {
		return Sha256.encode([
			MODEL,
			decision.id,
			bindingKey(decision.binding),
			decision.enumName,
			decision.leftType,
			decision.rightType,
			Std.string(decision.negate),
			Std.string(decision.order),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			"left,right",
			HELPER
		].join("\u001f"));
	}

	static function copySpan(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}

	static function copy(decision:OcamlEnumEqualityDecision):OcamlEnumEqualityDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySpan(decision.source),
			enumName: decision.enumName,
			leftType: decision.leftType,
			rightType: decision.rightType,
			negate: decision.negate,
			order: decision.order,
			binding: {
				functionId: decision.binding.functionId,
				programRevision: decision.binding.programRevision,
				bodyRevision: decision.binding.bodyRevision,
				pipelineRevision: decision.binding.pipelineRevision
			}
		};
	}
}

#if macro
/** Selects ordinary enum comparisons and payload constructions before syntax generation. */
class OcamlEnumIdentityPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlEnumIdentityPlan {
		final decisions:Array<OcamlEnumEqualityDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();
		final allocations:ObjectMap<TypedExpr, OcamlEnumAllocationDecision> = new ObjectMap();
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, _):
					switch (unwrap(callee).expr) {
						case TField(_, FEnum(reference, field)):
							final name = enumName(expression.t);
							final arity = switch (TypeTools.follow(field.type)) {
								case TFun(args, _): args.length;
								case _: 0;
							};
							if (name != null && arity > 0) {
								final facts:OcamlEnumAllocationDecision = {
									binding: binding,
									source: OcamlLoweredOrigin.sourceSpan(expression.pos),
									enumName: name,
									constructorName: field.name,
									arity: arity,
									revision: ""
								};
								allocations.set(expression, {
									binding: binding,
									source: facts.source,
									enumName: name,
									constructorName: field.name,
									arity: arity,
									revision: OcamlEnumIdentityPlan.allocationRevision(facts)
								});
							}
						case _:
					}
				case TBinop(op, left, right) if (op == OpEq || op == OpNotEq):
					final name = selection(left, right);
					if (name != null) {
						final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
						final order = decisions.length;
						final id = "enum-equality:" + Sha256.encode([
							binding.functionId,
							binding.programRevision,
							binding.bodyRevision,
							binding.pipelineRevision,
							Std.string(order)
						].join("\u001f"));
						final facts:OcamlEnumEqualityDecision = {
							id: id,
							revision: "",
							binding: binding,
							source: source,
							enumName: name,
							leftType: TypeTools.toString(left.t),
							rightType: TypeTools.toString(right.t),
							negate: op == OpNotEq,
							order: order
						};
						final decision:OcamlEnumEqualityDecision = {
							id: id,
							revision: OcamlEnumIdentityPlan.revisionFor(facts),
							binding: binding,
							source: source,
							enumName: name,
							leftType: facts.leftType,
							rightType: facts.rightType,
							negate: facts.negate,
							order: order
						};
						decisions.push(decision);
						lookup.set(expression, id);
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(root);
		return new OcamlEnumIdentityPlan(decisions, lookup, allocations);
	}

	/** Null literals keep the existing null check. Abstracts and native enums retain their own semantics. */
	public static function selection(left:TypedExpr, right:TypedExpr):Null<String> {
		if (isNull(left) || isNull(right))
			return null;
		final leftName = enumName(left.t);
		return leftName != null && leftName == enumName(right.t) ? leftName : null;
	}

	static function enumName(type:Type):Null<String> {
		return switch (type) {
			case TLazy(resolve): enumName(resolve());
			case TMono(reference): reference.get() == null ? null : enumName(reference.get());
			case TType(reference, parameters):
				final definition = reference.get();
				enumName(TypeTools.applyTypeParameters(definition.type, definition.params, parameters));
			case TAbstract(reference, [inner]) if (reference.get().pack.length == 0 && reference.get().name == "Null"):
				enumName(inner);
			case TEnum(reference, _): final definition = reference.get(); definition.pack.length > 0 && definition.pack[0] == "ocaml" ? null : definition.pack.concat([definition.name])
				.join(".");
			case _: null;
		}
	}

	static function isNull(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TMeta(_, inner) | TParenthesis(inner): isNull(inner);
			case TConst(TNull): true;
			case _: false;
		}
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, inner) | TParenthesis(inner): unwrap(inner);
			case _: expression;
		}
	}
}
#end

#end
