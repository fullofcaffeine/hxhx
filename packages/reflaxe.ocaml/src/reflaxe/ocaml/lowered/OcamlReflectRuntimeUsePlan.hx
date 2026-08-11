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
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One supported operation from the standard Haxe `Reflect` class. */
enum abstract OcamlReflectRuntimeUseKind(String) from String to String {
	final CallMethod = "call-method";
	final IsFunction = "is-function";
	final MakeVarArgs = "make-var-args";
	final MakeVarArgsVoid = "make-var-args-void";
	final IsObject = "is-object";
	final IsEnumValue = "is-enum-value";
	final CompareMethods = "compare-methods";
}

/** One immutable target-runtime decision for one resolved standard Reflect call. */
typedef OcamlReflectRuntimeUseDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlReflectRuntimeUseKind;
	final sourceMethod:String;
	final exactSymbol:String;
	final argumentSemanticTypeIds:Array<String>;
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
	Plans how standard Haxe `Reflect` calls use the OCaml target runtime.

	`HxReflect` is an OCaml support module, not the public Haxe class. The planner
	resolves each typed Haxe call before syntax generation and selects one exact
	`HxReflect` function. The syntax builder can then use only that selected
	function for that call. A copied decision stores no compiler object and must
	not be reused in another compilation request.
**/
class OcamlReflectRuntimeUsePlan {
	public static inline final PROOF_ID = "direct-standard-reflect-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed call resolves to one admitted method on the root standard Reflect class. Its method, argument types, result type, and callback result select exactly one private HxReflect helper. Reflect.compare remains owned by the typed comparator plan, and dynamic function invocation remains a separate call-boundary decision.";
	public static inline final RUNTIME_CAPABILITY = "haxe-reflect-runtime-call";

	final ordered:Array<OcamlReflectRuntimeUseDecision>;
	final byId:Map<String, OcamlReflectRuntimeUseDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlReflectRuntimeUseDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision bound to this exact request-local typed call. */
	public function requireFor(expression:TypedExpr):OcamlReflectRuntimeUseDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-reflect-runtime-use:missing-decision]: direct standard Reflect syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-reflect-runtime-use:missing-decision]: the typed call names no sealed Reflect decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe copies in source order. */
	public function decisions():Array<OcamlReflectRuntimeUseDecision>
		return ordered.map(copyDecision);

	/** Rejects a plan copied from another function, body, program, or pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed identity, method, helper, type, or runtime-use facts. */
	public static function requireDecision(decision:OcamlReflectRuntimeUseDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.sourceMethod.length == 0
			|| decision.exactSymbol.length == 0
			|| decision.resultSemanticTypeId.length == 0
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
			throw "reflaxe.ocaml [ocaml-reflect-runtime-use:invalid-plan]: Reflect decision has incomplete facts";

		final expectedMethod = sourceMethodFor(decision.kind);
		final expectedSymbol = exactSymbolFor(decision.kind);
		final role = roleFor(decision.kind);
		final expectedRequirementId = decision.id + ":runtime:" + RUNTIME_CAPABILITY;
		final expectedRevision = sealRevision(decision.id, decision.source, decision.kind, expectedMethod, expectedSymbol, decision.argumentSemanticTypeIds,
			decision.resultSemanticTypeId, decision.order, bindingFor(decision), expectedRequirementId);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.sourceMethod != expectedMethod
			|| decision.exactSymbol != expectedSymbol
			|| decision.runtimeRequirementIds[0] != expectedRequirementId
			|| decision.revision != expectedRevision
			|| occurrence.id != decision.id + ":runtime-use:" + role
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != decision.runtimeRequirementIds[0]
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != expectedSymbol
			|| occurrence.role != role
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';
	}

	public static function sourceMethodFor(kind:OcamlReflectRuntimeUseKind):String {
		return switch (kind) {
			case CallMethod: "callMethod";
			case IsFunction: "isFunction";
			case MakeVarArgs, MakeVarArgsVoid: "makeVarArgs";
			case IsObject: "isObject";
			case IsEnumValue: "isEnumValue";
			case CompareMethods: "compareMethods";
		};
	}

	public static function exactSymbolFor(kind:OcamlReflectRuntimeUseKind):String {
		return switch (kind) {
			case CallMethod: "HxReflect.callMethod";
			case IsFunction: "HxReflect.isFunction";
			case MakeVarArgs: "HxReflect.makeVarArgs";
			case MakeVarArgsVoid: "HxReflect.makeVarArgsVoid";
			case IsObject: "HxReflect.isObject";
			case IsEnumValue: "HxReflect.isEnumValue";
			case CompareMethods: "HxReflect.same_closure";
		};
	}

	public static function roleFor(kind:OcamlReflectRuntimeUseKind):String
		return "direct-" + (kind : String);

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, kind:OcamlReflectRuntimeUseKind, sourceMethod:String, exactSymbol:String,
			argumentSemanticTypeIds:Array<String>, resultSemanticTypeId:String, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String):String {
		return "sha256:" + Sha256.encode([
			"direct-standard-reflect-runtime-use-v1",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(kind : String),
			sourceMethod,
			exactSymbol,
			argumentSemanticTypeIds.join("\u001e"),
			resultSemanticTypeId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (expression => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:duplicate-lookup]: decision "$decisionId" is bound to more than one typed call';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:missing-decision]: typed call "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-reflect-runtime-use:unreachable-decision]: decision "${decision.id}" has no request-local typed call';
	}

	static function bindingFor(decision:OcamlReflectRuntimeUseDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlReflectRuntimeUseDecision):OcamlReflectRuntimeUseDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			kind: decision.kind,
			sourceMethod: decision.sourceMethod,
			exactSymbol: decision.exactSymbol,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
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

/** Finds all supported direct `Reflect` calls before the target builds syntax. */
#if macro
class OcamlReflectRuntimeUsePlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlReflectRuntimeUsePlan {
		final decisions:Array<OcamlReflectRuntimeUseDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, arguments):
					final kind = admittedKind(callee, arguments);
					if (kind != null) {
						final order = decisions.length;
						final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
						final sourceMethod = OcamlReflectRuntimeUsePlan.sourceMethodFor(kind);
						final exactSymbol = OcamlReflectRuntimeUsePlan.exactSymbolFor(kind);
						final argumentSemanticTypeIds = arguments.map(argument -> TypeTools.toString(argument.t));
						final resultSemanticTypeId = TypeTools.toString(expression.t);
						final id = "reflect-runtime-use:" + Sha256.encode([
							binding.functionId,
							binding.programRevision,
							binding.bodyRevision,
							binding.pipelineRevision,
							Std.string(order),
							source.file,
							Std.string(source.min),
							Std.string(source.max),
							(kind : String),
							argumentSemanticTypeIds.join("\u001e"),
							resultSemanticTypeId
						].join("\u001f")).substr(0, 24);
						final requirementId = id + ":runtime:" + OcamlReflectRuntimeUsePlan.RUNTIME_CAPABILITY;
						final revision = OcamlReflectRuntimeUsePlan.sealRevision(id, source, kind, sourceMethod, exactSymbol, argumentSemanticTypeIds,
							resultSemanticTypeId, order, binding, requirementId);
						final role = OcamlReflectRuntimeUsePlan.roleFor(kind);
						final decision:OcamlReflectRuntimeUseDecision = {
							id: id,
							revision: revision,
							source: copySource(source),
							kind: kind,
							sourceMethod: sourceMethod,
							exactSymbol: exactSymbol,
							argumentSemanticTypeIds: argumentSemanticTypeIds,
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
									exactSymbol: exactSymbol,
									role: role,
									order: 0,
									source: copySource(source),
									profileEligibility: ["metal", "portable"],
									cardinality: 1
								}
							],
							proofId: OcamlReflectRuntimeUsePlan.PROOF_ID,
							proofClaim: OcamlReflectRuntimeUsePlan.PROOF_CLAIM,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						};
						decisions.push(decision);
						lookup.set(expression, id);
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlReflectRuntimeUsePlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function admittedKind(callee:TypedExpr, arguments:Array<TypedExpr>):Null<OcamlReflectRuntimeUseKind> {
		return switch (unwrap(callee).expr) {
			case TField({expr: TTypeExpr(TClassDecl(ownerRef))}, FStatic(classRef, fieldRef)):
				final owner = ownerRef.get();
				final fieldOwner = classRef.get();
				final field = fieldRef.get();
				if (owner.pack.length != 0 || owner.name != "Reflect" || owner.module != "Reflect" || fieldOwner.module != owner.module
					|| fieldOwner.name != owner.name) null; else switch (field.name) {
					case "callMethod" if (arguments.length == 3): OcamlReflectRuntimeUseKind.CallMethod;
					case "isFunction" if (arguments.length == 1): OcamlReflectRuntimeUseKind.IsFunction;
					case "makeVarArgs" if (arguments.length == 1): callbackReturnsVoid(arguments[0].t) ? OcamlReflectRuntimeUseKind.MakeVarArgsVoid : OcamlReflectRuntimeUseKind.MakeVarArgs;
					case "isObject" if (arguments.length == 1): OcamlReflectRuntimeUseKind.IsObject;
					case "isEnumValue" if (arguments.length == 1): OcamlReflectRuntimeUseKind.IsEnumValue;
					case "compareMethods" if (arguments.length == 2): OcamlReflectRuntimeUseKind.CompareMethods;
					case _: null;
				};
			case _:
				null;
		};
	}

	static function callbackReturnsVoid(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TFun(_, result): isVoid(result);
			case _: false;
		};
	}

	static function isVoid(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TAbstract(reference, _): final definition = reference.get(); definition.pack.length == 0 && definition.name == "Void";
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

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end
#end
