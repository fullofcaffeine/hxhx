package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The two Haxe operators that use the null-safe String equality helper. */
enum abstract OcamlStringEqualityKind(String) from String to String {
	final Equal = "equal";
	final NotEqual = "not-equal";
}

/** One source-bound call to `HxString.equals`. */
typedef OcamlStringEqualityDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlStringEqualityKind;
	final leftSemanticTypeId:String;
	final rightSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final order:Int;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Owns the null-safe runtime comparison selected by Haxe String equality.

	For example, `left != right` owns one `HxString.equals` identifier. The
	target applies ordinary OCaml `not` after that checked call. Null-literal and
	Dynamic comparisons use their earlier, separate compiler paths.
**/
class OcamlStringEqualityPlan {
	public static inline final MODEL_REVISION = "typed-ocaml-string-equality-v1";
	public static inline final PROOF_ID = "string-equality-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed expression is a non-null String equality or inequality that does not use the Dynamic carrier. It authorizes exactly one HxString.equals identifier before target syntax.";
	public static inline final RUNTIME_CAPABILITY = "haxe-string-equality";

	final ordered:Array<OcamlStringEqualityDecision>;
	final byId:Map<String, OcamlStringEqualityDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStringEqualityDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-equality:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Returns the decision for this exact request-local binary expression. */
	public function requireFor(expression:TypedExpr):OcamlStringEqualityDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-string-equality:missing-decision]: String equality syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-equality:missing-decision]: the typed expression names no sealed decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe decisions in source order. */
	public function decisions():Array<OcamlStringEqualityDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-string-equality:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed operator, type, identity, requirement, or helper facts. */
	public static function requireDecision(decision:OcamlStringEqualityDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.leftSemanticTypeId.length == 0
			|| decision.rightSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId != "Bool"
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-string-equality:invalid-plan]: decision has incomplete facts";

		final requirementId = decision.id + ":runtime:" + RUNTIME_CAPABILITY;
		final role = roleFor(decision.kind);
		final expectedRevision = sealRevision(decision.id, decision.source, decision.kind, decision.leftSemanticTypeId, decision.rightSemanticTypeId,
			decision.resultSemanticTypeId, decision.order, bindingFor(decision), requirementId, role);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds[0] != requirementId
			|| occurrence.id != decision.id + ":runtime-use:" + role
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != requirementId
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != "HxString.equals"
			|| occurrence.role != role
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-string-equality:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';
	}

	/** Returns the stable occurrence role for one source operator. */
	public static function roleFor(kind:OcamlStringEqualityKind):String {
		return switch (kind) {
			case Equal: "compare-equal";
			case NotEqual: "compare-not-equal";
		};
	}

	/** Returns the only direct runtime module required by String equality. */
	public static function rootModules(decision:OcamlStringEqualityDecision):Array<String> {
		requireDecision(decision);
		return ["HxString"];
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, kind:OcamlStringEqualityKind, leftSemanticTypeId:String,
			rightSemanticTypeId:String, resultSemanticTypeId:String, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String, role:String):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(kind : String),
			leftSemanticTypeId,
			rightSemanticTypeId,
			resultSemanticTypeId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			role,
			"HxString.equals"
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-equality:duplicate-lookup]: decision "$decisionId" is bound more than once';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-equality:missing-decision]: typed expression "$decisionId" has no decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-equality:unreachable-decision]: decision "${decision.id}" has no typed expression';
	}

	static function bindingFor(decision:OcamlStringEqualityDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStringEqualityDecision):OcamlStringEqualityDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			kind: decision.kind,
			leftSemanticTypeId: decision.leftSemanticTypeId,
			rightSemanticTypeId: decision.rightSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			order: decision.order,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(copyOccurrence),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: copySource(source.source),
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}

#if macro
/** Selects String equality expressions before target syntax. */
class OcamlStringEqualityPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStringEqualityPlan {
		final decisions:Array<OcamlStringEqualityDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, kind:OcamlStringEqualityKind, left:TypedExpr, right:TypedExpr):Void {
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final leftSemanticTypeId = TypeTools.toString(left.t);
			final rightSemanticTypeId = TypeTools.toString(right.t);
			final resultSemanticTypeId = TypeTools.toString(expression.t);
			if (resultSemanticTypeId != "Bool")
				throw 'reflaxe.ocaml [ocaml-string-equality:invalid-result]: String equality must produce Bool, received "$resultSemanticTypeId"';
			final id = "string-equality:" + Sha256.encode([
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				Std.string(order),
				source.file,
				Std.string(source.min),
				Std.string(source.max),
				(kind : String),
				leftSemanticTypeId,
				rightSemanticTypeId
			].join("\u001f")).substr(0, 24);
			final requirementId = id + ":runtime:" + OcamlStringEqualityPlan.RUNTIME_CAPABILITY;
			final role = OcamlStringEqualityPlan.roleFor(kind);
			final revision = OcamlStringEqualityPlan.sealRevision(id, source, kind, leftSemanticTypeId, rightSemanticTypeId, resultSemanticTypeId, order,
				binding, requirementId, role);
			final decision:OcamlStringEqualityDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				kind: kind,
				leftSemanticTypeId: leftSemanticTypeId,
				rightSemanticTypeId: rightSemanticTypeId,
				resultSemanticTypeId: resultSemanticTypeId,
				order: order,
				profileEligibility: ["metal", "portable"],
				runtimeRequirementIds: [requirementId],
				runtimeUseOccurrences: [
					{
						id: id + ":runtime-use:" + role,
						planRevision: revision,
						ownerId: id,
						requirementId: requirementId,
						domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
						exactSymbol: "HxString.equals",
						role: role,
						order: 0,
						source: copySource(source),
						profileEligibility: ["metal", "portable"],
						cardinality: 1
					}
				],
				proofId: OcamlStringEqualityPlan.PROOF_ID,
				proofClaim: OcamlStringEqualityPlan.PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			decisions.push(decision);
			lookup.set(expression, decision.id);
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TBinop(OpEq, left, right) if (selectsStringHelper(left, right)):
					add(expression, OcamlStringEqualityKind.Equal, left, right);
				case TBinop(OpNotEq, left, right) if (selectsStringHelper(left, right)):
					add(expression, OcamlStringEqualityKind.NotEqual, left, right);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlStringEqualityPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	/**
		Returns whether a type reaches the existing String syntax branch.

		This function follows typedefs but preserves abstracts. It recognizes the
		built-in String carrier and String-backed abstracts such as `haxe.Ucs2`.
	**/
	public static function isStringType(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(abstractRef, [inner]):
				final definition = abstractRef.get();
				if (definition.pack.length == 0 && definition.name == "Null") {
					isStringType(inner);
				} else if (definition.pack.length == 1 && definition.pack[0] == "haxe" && definition.name == "Ucs2") {
					true;
				} else {
					switch (TypeTools.follow(definition.type)) {
						case TInst(classRef, _): isStdStringClass(classRef.get());
						case _: false;
					};
				}
			case TAbstract(abstractRef, _):
				final definition = abstractRef.get();
				if (definition.pack.length == 1 && definition.pack[0] == "haxe" && definition.name == "Ucs2") {
					true;
				} else {
					switch (TypeTools.follow(definition.type)) {
						case TInst(classRef, _): isStdStringClass(classRef.get());
						case _: false;
					};
				}
			case TInst(classRef, _):
				isStdStringClass(classRef.get());
			case _:
				false;
		};
	}

	/**
		Returns whether the target must use its null-safe String helper.

		The target builder calls this same predicate after the null and Dynamic
		branches. This shared check prevents planning and syntax from selecting
		different behavior for typedefs, nullable Strings, or String abstracts.
	**/
	public static function selectsStringHelper(left:TypedExpr, right:TypedExpr):Bool {
		return !isNull(left)
			&& !isNull(right)
			&& !OcamlDynamicCarrierModel.usesDynamicCarrier(left.t)
			&& !OcamlDynamicCarrierModel.usesDynamicCarrier(right.t)
			&& (isStringType(left.t) || isStringType(right.t));
	}

	static function isNull(expression:TypedExpr):Bool {
		return switch (unwrap(expression).expr) {
			case TConst(TNull): true;
			case _: false;
		};
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		var current = expression;
		while (true) {
			switch (current.expr) {
				case TParenthesis(inner) | TMeta(_, inner):
					current = inner;
				case _:
					return current;
			}
		}
		return current;
	}

	static function isStdStringClass(classType:ClassType):Bool
		return classType.pack.length == 0 && classType.name == "String";

	static function followNoAbstracts(type:Type):Type {
		var current = type;
		while (true) {
			final next = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final inner = reference.get();
					inner == null ? current : inner;
				case TType(typeRef, parameters):
					final definition = typeRef.get();
					TypeTools.applyTypeParameters(definition.type, definition.params, parameters);
				case _:
					return current;
			};
			if (next == current)
				return current;
			current = next;
		}
		return current;
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end

#end
