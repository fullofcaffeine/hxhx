package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Expr.Binop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The typed source form that selects one `HxRuntime.dynamic_equals` call. */
enum abstract OcamlDynamicEqualityKind(String) from String to String {
	final Equal = "equal";
	final NotEqual = "not-equal";
	final SwitchCase = "switch-case";
}

/** One immutable decision for one generated Dynamic equality helper call. */
typedef OcamlDynamicEqualityDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final ownerSource:OcamlLoweredSourceSpan;
	final kind:OcamlDynamicEqualityKind;
	final leftSemanticTypeId:String;
	final rightSemanticTypeId:String;
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
	Classifies Haxe values stored in the target's general-purpose OCaml container.

	OCaml calls this container `Obj.t`. In this module, "Dynamic carrier" means
	that container. Planning and code generation share this model. Thus, both
	phases make the same choice for `Dynamic`, `Any`, and `HxAnon` values.
**/
#if macro
class OcamlDynamicCarrierModel {
	/** Returns whether this exact type uses the general-purpose Dynamic container. */
	public static function usesDynamicCarrier(type:Type):Bool {
		final followed = followNoAbstracts(unwrapNullType(type));
		return switch (followed) {
			case TDynamic(_):
				true;
			case TAbstract(_, _) if (isStdAnyAbstract(type)):
				true;
			case TAnonymous(_) if (anonymousUsesHxAnon(type)):
				true;
			case _:
				false;
		}
	}

	/** Returns whether an anonymous structure uses the runtime's `HxAnon` name-to-value table. */
	public static function anonymousUsesHxAnon(type:Type):Bool {
		if (isSysFileStatTypedef(type) || isSysFileStatAnonymous(type))
			return false;
		if (isIteratorAnonymous(type) || isKeyValueAnonymous(type))
			return false;
		return true;
	}

	static function isStdAnyAbstract(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Any";
			case _:
				false;
		}
	}

	static function isIteratorAnonymous(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAnonymous(anonymousRef): final fields = anonymousRef.get()
					.fields; Lambda.exists(fields, field -> field.name == "hasNext") && Lambda.exists(fields, field -> field.name == "next");
			case _:
				false;
		}
	}

	static function isKeyValueAnonymous(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAnonymous(anonymousRef): final fields = anonymousRef.get()
					.fields; Lambda.exists(fields, field -> field.name == "key") && Lambda.exists(fields, field -> field.name == "value");
			case _:
				false;
		}
	}

	static function isSysFileStatTypedef(type:Type):Bool {
		return switch (unwrapNoTypedef(type)) {
			case TType(typeRef, _):
				final definition = typeRef.get();
				definition.pack.length == 1
				&& definition.pack[0] == "sys"
				&& definition.module == "sys.FileSystem"
				&& definition.name == "FileStat";
			case _:
				false;
		}
	}

	static function isSysFileStatAnonymous(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAnonymous(anonymousRef):
				final names:Map<String, Bool> = [];
				for (field in anonymousRef.get().fields)
					names.set(field.name, true);
				Lambda.foreach([
					"gid", "uid", "atime", "mtime", "ctime", "size", "dev", "ino", "nlink", "rdev", "mode"
				], name -> names.exists(name));
			case _:
				false;
		}
	}

	static function unwrapNullType(type:Type):Type {
		return switch (type) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" ? inner : type;
			case _:
				type;
		}
	}

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
			}
			if (next == current)
				return current;
			current = next;
		}
		return current;
	}

	static function unwrapNoTypedef(type:Type):Type {
		var current = type;
		while (true) {
			final next = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final inner = reference.get();
					inner == null ? current : inner;
				case _:
					return current;
			}
			if (next == current)
				return current;
			current = next;
		}
		return current;
	}
}
#end

/** Validates and stores the exact helper uses for one typed root. */
class OcamlDynamicEqualityPlan {
	public static inline final PROOF_ID = "dynamic-equality-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed occurrence is a non-null equality with a Dynamic operand. It can also be one non-null switch value that needs runtime comparison. The occurrence authorizes exactly one HxRuntime.dynamic_equals identifier. Plain names, null checks, static OCaml patterns, and nested function bodies do not authorize this helper.";
	public static inline final RUNTIME_CAPABILITY = "haxe-dynamic-equality";

	final ordered:Array<OcamlDynamicEqualityDecision>;
	final byId:Map<String, OcamlDynamicEqualityDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlDynamicEqualityDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-dynamic-equality:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision bound to this exact request-local typed node. */
	public function requireFor(expression:TypedExpr):OcamlDynamicEqualityDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-dynamic-equality:missing-decision]: Dynamic equality syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-dynamic-equality:missing-decision]: the typed occurrence names no sealed Dynamic equality decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	public function decisions():Array<OcamlDynamicEqualityDecision> {
		return ordered.map(copyDecision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-dynamic-equality:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
			}
	}

	/** Rejects changed source, type, identity, requirement, or runtime-use facts. */
	public static function requireDecision(decision:OcamlDynamicEqualityDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.ownerSource.file.length == 0
			|| decision.ownerSource.min < 0
			|| decision.ownerSource.max < decision.ownerSource.min
			|| decision.leftSemanticTypeId.length == 0
			|| decision.rightSemanticTypeId.length == 0
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw "reflaxe.ocaml [ocaml-dynamic-equality:invalid-plan]: Dynamic equality decision has incomplete facts";
		}
		final role = roleFor(decision.kind);
		final expectedRevision = sealRevision(decision.id, decision.source, decision.ownerSource, decision.kind, decision.leftSemanticTypeId,
			decision.rightSemanticTypeId, decision.order, bindingFor(decision), decision.runtimeRequirementIds[0], role);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.revision != expectedRevision
			|| occurrence.id != decision.id + ":runtime-use:" + role
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != decision.runtimeRequirementIds[0]
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != "HxRuntime.dynamic_equals"
			|| occurrence.role != role
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1) {
			throw 'reflaxe.ocaml [ocaml-dynamic-equality:stale-plan]: decision "${decision.id}" no longer matches its sealed runtime use';
		}
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-dynamic-equality:duplicate-lookup]: decision "$decisionId" is bound to more than one typed occurrence';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-dynamic-equality:missing-decision]: typed occurrence "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-dynamic-equality:unreachable-decision]: decision "${decision.id}" has no request-local typed occurrence';
	}

	public static function copyDecision(decision:OcamlDynamicEqualityDecision):OcamlDynamicEqualityDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			ownerSource: copySource(decision.ownerSource),
			kind: decision.kind,
			leftSemanticTypeId: decision.leftSemanticTypeId,
			rightSemanticTypeId: decision.rightSemanticTypeId,
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

	static function bindingFor(decision:OcamlDynamicEqualityDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	public static function roleFor(kind:OcamlDynamicEqualityKind):String {
		return switch (kind) {
			case Equal: "equal";
			case NotEqual: "not-equal";
			case SwitchCase: "switch-case";
		}
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, ownerSource:OcamlLoweredSourceSpan, kind:OcamlDynamicEqualityKind,
			leftType:String, rightType:String, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String, role:String):String {
		return "sha256:" + Sha256.encode([
			"ocaml-dynamic-equality-runtime-use-v1",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			ownerSource.file,
			Std.string(ownerSource.min),
			Std.string(ownerSource.max),
			(kind : String),
			leftType,
			rightType,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			role,
			"HxRuntime.dynamic_equals"
		].map(value -> value.length + ":" + value).join("|"));
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/** Builds the complete Dynamic equality inventory before target syntax. */
#if macro
class OcamlDynamicEqualityPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlDynamicEqualityPlan {
		final decisions:Array<OcamlDynamicEqualityDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, owner:TypedExpr, kind:OcamlDynamicEqualityKind, leftType:Type, rightType:Type):Void {
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final ownerSource = OcamlLoweredOrigin.sourceSpan(owner.pos);
			final leftSemanticTypeId = TypeTools.toString(leftType);
			final rightSemanticTypeId = TypeTools.toString(rightType);
			final id = "dynamic-equality:" + Sha256.encode([
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				Std.string(order),
				source.file,
				Std.string(source.min),
				Std.string(source.max),
				ownerSource.file,
				Std.string(ownerSource.min),
				Std.string(ownerSource.max),
				(kind : String),
				leftSemanticTypeId,
				rightSemanticTypeId
			].join("\u001f")).substr(0, 24);
			final requirementId = id + ":runtime:" + OcamlDynamicEqualityPlan.RUNTIME_CAPABILITY;
			final role = OcamlDynamicEqualityPlan.roleFor(kind);
			final revision = OcamlDynamicEqualityPlan.sealRevision(id, source, ownerSource, kind, leftSemanticTypeId, rightSemanticTypeId, order, binding,
				requirementId, role);
			final decision:OcamlDynamicEqualityDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				ownerSource: copySource(ownerSource),
				kind: kind,
				leftSemanticTypeId: leftSemanticTypeId,
				rightSemanticTypeId: rightSemanticTypeId,
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
						exactSymbol: "HxRuntime.dynamic_equals",
						role: role,
						order: 0,
						source: copySource(source),
						profileEligibility: ["metal", "portable"],
						cardinality: 1
					}
				],
				proofId: OcamlDynamicEqualityPlan.PROOF_ID,
				proofClaim: OcamlDynamicEqualityPlan.PROOF_CLAIM,
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
				case TBinop(OpEq, left, right)
					if (!isNull(left)
						&& !isNull(right)
						&& (OcamlDynamicCarrierModel.usesDynamicCarrier(left.t) || OcamlDynamicCarrierModel.usesDynamicCarrier(right.t))):
					add(expression, expression, OcamlDynamicEqualityKind.Equal, left.t, right.t);
				case TBinop(OpNotEq, left, right)
					if (!isNull(left)
						&& !isNull(right)
						&& (OcamlDynamicCarrierModel.usesDynamicCarrier(left.t) || OcamlDynamicCarrierModel.usesDynamicCarrier(right.t))):
					add(expression, expression, OcamlDynamicEqualityKind.NotEqual, left.t, right.t);
				case TSwitch(scrutinee, cases, _) if (switchNeedsRuntimeEquality(scrutinee, cases)):
					for (entry in cases)
						for (value in entry.values)
							if (!isNull(value))
								add(value, expression, OcamlDynamicEqualityKind.SwitchCase, scrutinee.t, value.t);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlDynamicEqualityPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function switchNeedsRuntimeEquality(scrutinee:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>):Bool {
		if (switch (unwrap(scrutinee).expr) {
				case TEnumIndex(_): true;
				case _: false;
			})
			return false;
		for (entry in cases)
			for (value in entry.values)
				if (!isStaticPatternValue(value))
					return true;
		return false;
	}

	static function isStaticPatternValue(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TConst(_) | TField(_, FEnum(_, _)): true;
			case _: false;
		}
	}

	static function isNull(expression:TypedExpr):Bool {
		return switch (unwrap(expression).expr) {
			case TConst(TNull): true;
			case _: false;
		}
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

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}
#end
#end
