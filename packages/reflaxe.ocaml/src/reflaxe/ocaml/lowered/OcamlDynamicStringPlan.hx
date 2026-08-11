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
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** How one value enters `HxDynamic.toStdString`. */
enum abstract OcamlDynamicStringStrategy(String) from String to String {
	/** The expression already uses OCaml's general-purpose `Obj.t` carrier. */
	final DirectCarrier = "direct-carrier";

	/** The expression has a more specific OCaml carrier and needs `Obj.repr`. */
	final BoxWithObjRepr = "box-with-obj-repr";
}

/** The Haxe construct that requests standard string conversion. */
enum abstract OcamlDynamicStringSourceKind(String) from String to String {
	final StdString = "std-string";
	final StringConcat = "string-concat";
	final StringCompoundAssignment = "string-compound-assignment";
	final ReflectFieldName = "reflect-field-name";
}

/** One immutable decision for one generated `HxDynamic.toStdString` call. */
typedef OcamlDynamicStringDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final ownerSource:OcamlLoweredSourceSpan;
	final sourceKind:OcamlDynamicStringSourceKind;
	final strategy:OcamlDynamicStringStrategy;
	final semanticTypeId:String;
	final inputCarrierTypeId:String;
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
	Selects the existing Dynamic string-conversion strategy from typed Haxe input.

	The model is shared by planning and syntax. A `null` result means that the
	value uses a static conversion, such as `string_of_int`, `HxString`, or a
	class's own `toString` method. Thus, the model cannot grant a private runtime
	name merely because a value appears near a string operation.
**/
#if macro
class OcamlDynamicStringModel {
	public static function select(expression:TypedExpr):Null<OcamlDynamicStringStrategy> {
		final unwrapped = unwrap(expression);
		if (OcamlRepresentationRegistry.isExactNullDynamic(unwrapped.t) || OcamlDynamicCarrierModel.usesDynamicCarrier(unwrapped.t))
			return OcamlDynamicStringStrategy.DirectCarrier;

		switch (unwrapped.expr) {
			case TConst(TNull) | TConst(TString(_)):
				return null;
			case TBinop(OpAdd, left, right) if (isStringType(unwrapped.t) || isStringType(left.t) || isStringType(right.t)):
				return null;
			case _:
		}

		return switch (followNoAbstracts(unwrapped.t)) {
			case TAbstract(_, _):
				null;
			case TInst(classRef, _):
				final classType = classRef.get();
				if (isStdStringClass(classType) || hasSourceToString(classType)) {
					null;
				} else {
					switch (classType.kind) {
						case KTypeParameter(_): OcamlDynamicStringStrategy.DirectCarrier;
						case _: OcamlDynamicStringStrategy.BoxWithObjRepr;
					}
				}
			case TDynamic(_) | TAnonymous(_) | TMono(_):
				OcamlDynamicStringStrategy.DirectCarrier;
			case _:
				OcamlDynamicStringStrategy.BoxWithObjRepr;
		};
	}

	public static function inputCarrierTypeId(strategy:OcamlDynamicStringStrategy, semanticTypeId:String):String {
		return switch (strategy) {
			case DirectCarrier: "Obj.t";
			case BoxWithObjRepr: "typed:" + semanticTypeId;
		};
	}

	public static function isStringType(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" && isStringType(inner);
			case TInst(classRef, _): isStdStringClass(classRef.get());
			case _: false;
		};
	}

	static function hasSourceToString(classType:ClassType):Bool {
		try {
			for (field in classType.fields.get())
				if (field.name == "toString")
					return true;
		} catch (_:Dynamic) {}
		return false;
	}

	static function isStdStringClass(classType:ClassType):Bool {
		return classType.pack.length == 0 && classType.name == "String";
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
				case _: return current;
			}
			if (next == current)
				return current;
			current = next;
		}
		return current;
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
}
#end

/** Validates and stores the exact Dynamic string uses for one typed root. */
class OcamlDynamicStringPlan {
	public static inline final PROOF_ID = "dynamic-string-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed occurrence is converted through Haxe standard string behavior. Static primitive, String, nullable, and source toString paths do not authorize the helper. One selected occurrence authorizes exactly one HxDynamic.toStdString identifier, and nested functions keep separate plans.";
	public static inline final RUNTIME_CAPABILITY = "haxe-dynamic-string";

	final ordered:Array<OcamlDynamicStringDecision>;
	final byId:Map<String, OcamlDynamicStringDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlDynamicStringDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-dynamic-string:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision bound to this exact request-local typed node. */
	public function requireFor(expression:TypedExpr):OcamlDynamicStringDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-dynamic-string:missing-decision]: Dynamic string syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-dynamic-string:missing-decision]: the typed occurrence names no sealed Dynamic string decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	public function decisions():Array<OcamlDynamicStringDecision> {
		return ordered.map(copyDecision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-dynamic-string:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed identity, carrier, requirement, or runtime-use facts. */
	public static function requireDecision(decision:OcamlDynamicStringDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.ownerSource.file.length == 0
			|| decision.ownerSource.min < 0
			|| decision.ownerSource.max < decision.ownerSource.min
			|| decision.semanticTypeId.length == 0
			|| decision.inputCarrierTypeId.length == 0
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
			throw "reflaxe.ocaml [ocaml-dynamic-string:invalid-plan]: Dynamic string decision has incomplete facts";

		final expectedCarrier = switch (decision.strategy) {
			case DirectCarrier: "Obj.t";
			case BoxWithObjRepr: "typed:" + decision.semanticTypeId;
		};
		final role = roleFor(decision.sourceKind);
		final expectedRevision = sealRevision(decision.id, decision.source, decision.ownerSource, decision.sourceKind, decision.strategy,
			decision.semanticTypeId, expectedCarrier, decision.order, bindingFor(decision), decision.runtimeRequirementIds[0], role);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.inputCarrierTypeId != expectedCarrier
			|| decision.revision != expectedRevision
			|| occurrence.id != decision.id + ":runtime-use:" + role
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != decision.runtimeRequirementIds[0]
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != "HxDynamic.toStdString"
			|| occurrence.role != role
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-dynamic-string:stale-plan]: decision "${decision.id}" no longer matches its sealed runtime use';
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (expression => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-dynamic-string:duplicate-lookup]: decision "$decisionId" is bound to more than one typed occurrence';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-dynamic-string:missing-decision]: typed occurrence "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-dynamic-string:unreachable-decision]: decision "${decision.id}" has no request-local typed occurrence';
	}

	public static function copyDecision(decision:OcamlDynamicStringDecision):OcamlDynamicStringDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			ownerSource: copySource(decision.ownerSource),
			sourceKind: decision.sourceKind,
			strategy: decision.strategy,
			semanticTypeId: decision.semanticTypeId,
			inputCarrierTypeId: decision.inputCarrierTypeId,
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

	static function bindingFor(decision:OcamlDynamicStringDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	public static function roleFor(sourceKind:OcamlDynamicStringSourceKind):String {
		return switch (sourceKind) {
			case StdString: "std-string";
			case StringConcat: "string-concat";
			case StringCompoundAssignment: "string-compound-assignment";
			case ReflectFieldName: "reflect-field-name";
		};
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, ownerSource:OcamlLoweredSourceSpan, sourceKind:OcamlDynamicStringSourceKind,
			strategy:OcamlDynamicStringStrategy, semanticTypeId:String, inputCarrierTypeId:String, order:Int, binding:OcamlFunctionPlanBinding,
			requirementId:String, role:String):String {
		return "sha256:" + Sha256.encode([
			"ocaml-dynamic-string-runtime-use-v1",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			ownerSource.file,
			Std.string(ownerSource.min),
			Std.string(ownerSource.max),
			(sourceKind : String),
			(strategy : String),
			semanticTypeId,
			inputCarrierTypeId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			role,
			"HxDynamic.toStdString"
		].map(value -> value.length + ":" + value).join("|"));
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/** Builds the complete Dynamic string inventory before target syntax. */
#if macro
class OcamlDynamicStringPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlDynamicStringPlan {
		final decisions:Array<OcamlDynamicStringDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, owner:TypedExpr, sourceKind:OcamlDynamicStringSourceKind):Void {
			final strategy = OcamlDynamicStringModel.select(expression);
			if (strategy == null)
				return;
			if (lookup.exists(expression))
				throw "reflaxe.ocaml [ocaml-dynamic-string:duplicate-source]: one typed expression requested Dynamic string conversion more than once";
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final ownerSource = OcamlLoweredOrigin.sourceSpan(owner.pos);
			final semanticTypeId = TypeTools.toString(expression.t);
			final inputCarrierTypeId = OcamlDynamicStringModel.inputCarrierTypeId(strategy, semanticTypeId);
			final id = "dynamic-string:" + Sha256.encode([
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
				(sourceKind : String),
				(strategy : String),
				semanticTypeId,
				inputCarrierTypeId
			].join("\u001f")).substr(0, 24);
			final requirementId = id + ":runtime:" + OcamlDynamicStringPlan.RUNTIME_CAPABILITY;
			final role = OcamlDynamicStringPlan.roleFor(sourceKind);
			final revision = OcamlDynamicStringPlan.sealRevision(id, source, ownerSource, sourceKind, strategy, semanticTypeId, inputCarrierTypeId, order,
				binding, requirementId, role);
			final decision:OcamlDynamicStringDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				ownerSource: copySource(ownerSource),
				sourceKind: sourceKind,
				strategy: strategy,
				semanticTypeId: semanticTypeId,
				inputCarrierTypeId: inputCarrierTypeId,
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
						exactSymbol: "HxDynamic.toStdString",
						role: role,
						order: 0,
						source: copySource(source),
						profileEligibility: ["metal", "portable"],
						cardinality: 1
					}
				],
				proofId: OcamlDynamicStringPlan.PROOF_ID,
				proofClaim: OcamlDynamicStringPlan.PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			decisions.push(decision);
			lookup.set(expression, decision.id);
		}

		function collectConcatParts(expression:TypedExpr, output:Array<TypedExpr>):Void {
			final unwrapped = unwrap(expression);
			switch (unwrapped.expr) {
				case TBinop(OpAdd, left, right)
					if (OcamlDynamicStringModel.isStringType(unwrapped.t)
						|| OcamlDynamicStringModel.isStringType(left.t)
						|| OcamlDynamicStringModel.isStringType(right.t)):
					collectConcatParts(left, output);
					collectConcatParts(right, output);
				case _:
					output.push(expression);
			}
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TBinop(OpAdd, left, right)
					if (OcamlDynamicStringModel.isStringType(expression.t)
						|| OcamlDynamicStringModel.isStringType(left.t)
						|| OcamlDynamicStringModel.isStringType(right.t)):
					final parts:Array<TypedExpr> = [];
					collectConcatParts(left, parts);
					collectConcatParts(right, parts);
					for (part in parts) {
						add(part, expression, OcamlDynamicStringSourceKind.StringConcat);
						visit(part);
					}
					return;
				case TBinop(OpAssignOp(OpAdd), left, right) if (OcamlDynamicStringModel.isStringType(left.t)
					|| OcamlDynamicStringModel.isStringType(right.t)):
					add(right, expression, OcamlDynamicStringSourceKind.StringCompoundAssignment);
					visit(left);
					visit(right);
					return;
				case TCall(functionExpression, arguments):
					switch (unwrap(functionExpression).expr) {
						case TField(_, FStatic(classRef, fieldRef)):
							final classType = classRef.get();
							final field = fieldRef.get();
							if (classType.pack.length == 0 && classType.name == "Std" && field.name == "string" && arguments.length == 1) {
								add(arguments[0], expression, OcamlDynamicStringSourceKind.StdString);
							} else if (classType.pack.length == 0
								&& classType.name == "Reflect"
								&& arguments.length >= 2
								&& Lambda.has(["field", "getProperty", "setField", "hasField", "deleteField"], field.name)) {
								add(arguments[1], expression, OcamlDynamicStringSourceKind.ReflectFieldName);
							}
						case _:
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlDynamicStringPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
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
