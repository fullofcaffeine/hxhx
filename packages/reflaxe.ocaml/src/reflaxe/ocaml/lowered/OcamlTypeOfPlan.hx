package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
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

/** How one `Type.typeof` argument enters the generated runtime classifier. */
enum abstract OcamlTypeOfInputStrategy(String) from String to String {
	/** The value already uses the target's general-purpose `Obj.t` carrier. */
	final DirectObject = "direct-object";

	/** Target syntax converts the value with the OCaml `Obj.repr` primitive. */
	final Repr = "repr";

	/** The source Boolean needs the private boxed-Boolean carrier. */
	final BoxBool = "box-bool";

	/** The source enum needs its runtime name and private enum box. */
	final BoxEnum = "box-enum";
}

/** One immutable runtime-classification decision for one resolved `Type.typeof` call. */
typedef OcamlTypeOfDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final inputStrategy:OcamlTypeOfInputStrategy;
	final inputSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final ?enumRuntimeName:String;
	final evaluationPolicy:String;
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
	Stores every private helper selected by a standard `Type.typeof` call.

	The generated classifier always tests null, boxed Boolean, enum, class, and
	String cases. Its input strategy can add one Boolean or enum boxing helper.
	This plan fixes that complete ordered helper list from the final typed call so
	target syntax cannot introduce an unplanned runtime dependency.
**/
class OcamlTypeOfPlan {
	public static inline final MODEL_REVISION = "typed-ocaml-typeof-v1";
	public static inline final PROOF_ID = "type-of-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed call resolves to root Type.typeof. Its source value type selects one complete direct, repr, Boolean-box, or enum-box input strategy before target syntax. The decision owns every private classifier helper in final AST traversal order while the source argument is evaluated exactly once.";
	public static inline final RUNTIME_CAPABILITY = "haxe-typeof-runtime-classification";
	public static inline final EVALUATION_POLICY = "argument-once-before-classification";

	final ordered:Array<OcamlTypeOfDecision>;
	final byId:Map<String, OcamlTypeOfDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlTypeOfDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-typeof:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision for this exact request-local typed call. */
	public function requireFor(expression:TypedExpr):OcamlTypeOfDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-typeof:missing-decision]: Type.typeof syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-typeof:missing-decision]: the typed call names no sealed runtime-classification decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe copies in source order. */
	public function decisions():Array<OcamlTypeOfDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions copied from another function or compiler pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-typeof:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed input strategy, type, requirement, or helper facts. */
	public static function requireDecision(decision:OcamlTypeOfDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.inputSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.evaluationPolicy != EVALUATION_POLICY
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-typeof:invalid-plan]: Type.typeof decision has incomplete facts";

		final enumRuntimeName = decision.enumRuntimeName;
		if ((decision.inputStrategy == OcamlTypeOfInputStrategy.BoxEnum && (enumRuntimeName == null || enumRuntimeName.length == 0))
			|| (decision.inputStrategy != OcamlTypeOfInputStrategy.BoxEnum && enumRuntimeName != null))
			throw "reflaxe.ocaml [ocaml-typeof:invalid-plan]: Type.typeof input strategy has incompatible enum facts";

		final symbols = exactSymbolsFor(decision.inputStrategy);
		final roles = rolesFor(decision.inputStrategy);
		final requirementId = decision.id + ":runtime:" + RUNTIME_CAPABILITY;
		final expectedRevision = sealRevision(decision.id, decision.source, decision.inputStrategy, decision.inputSemanticTypeId,
			decision.resultSemanticTypeId, enumRuntimeName, decision.evaluationPolicy, decision.order, bindingFor(decision), requirementId, symbols, roles);
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds[0] != requirementId
			|| decision.runtimeUseOccurrences.length != symbols.length)
			throw 'reflaxe.ocaml [ocaml-typeof:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';

		for (index in 0...symbols.length) {
			final occurrence = decision.runtimeUseOccurrences[index];
			if (occurrence.id != decision.id + ":runtime-use:" + roles[index]
				|| occurrence.planRevision != decision.revision
				|| occurrence.ownerId != decision.id
				|| occurrence.requirementId != requirementId
				|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
				|| occurrence.exactSymbol != symbols[index]
				|| occurrence.role != roles[index]
				|| occurrence.order != index
				|| occurrence.source.file != decision.source.file
				|| occurrence.source.min != decision.source.min
				|| occurrence.source.max != decision.source.max
				|| occurrence.profileEligibility.join(",") != "metal,portable"
				|| occurrence.cardinality != 1)
				throw 'reflaxe.ocaml [ocaml-typeof:invalid-runtime-use]: decision "${decision.id}" has a conflicting helper at order $index';
		}
	}

	/** Returns private helper names in final AST traversal order. */
	public static function exactSymbolsFor(strategy:OcamlTypeOfInputStrategy):Array<String> {
		final symbols = switch (strategy) {
			case DirectObject, Repr: [];
			case BoxBool: ["HxRuntime.box_bool"];
			case BoxEnum: ["HxEnum.box_if_needed"];
		};
		return symbols.concat([
			"HxRuntime.is_null",
			"HxRuntime.is_boxed_bool",
			"HxType.class_",
			"HxEnum.name_opt",
			"HxType.enum_",
			"HxType.getClass",
			"HxRuntime.is_null"
		]);
	}

	/** Returns stable roles for each selected helper occurrence. */
	public static function rolesFor(strategy:OcamlTypeOfInputStrategy):Array<String> {
		final roles = switch (strategy) {
			case DirectObject, Repr: [];
			case BoxBool: ["input-box-bool"];
			case BoxEnum: ["input-box-enum"];
		};
		return roles.concat([
			"value-null-test",
			"boxed-bool-test",
			"string-class-meta-value",
			"enum-name-read",
			"enum-meta-value",
			"class-read",
			"class-null-test"
		]);
	}

	/** Returns the direct runtime roots selected by one validated decision. */
	public static function rootModules(decision:OcamlTypeOfDecision):Array<String> {
		requireDecision(decision);
		final roots:Map<String, Bool> = [];
		for (occurrence in decision.runtimeUseOccurrences) {
			final separator = occurrence.exactSymbol.indexOf(".");
			roots.set(separator < 0 ? occurrence.exactSymbol : occurrence.exactSymbol.substr(0, separator), true);
		}
		final out = [for (root in roots.keys()) root];
		out.sort(Reflect.compare);
		return out;
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, inputStrategy:OcamlTypeOfInputStrategy, inputSemanticTypeId:String,
			resultSemanticTypeId:String, enumRuntimeName:Null<String>, evaluationPolicy:String, order:Int, binding:OcamlFunctionPlanBinding,
			requirementId:String, symbols:Array<String>, roles:Array<String>):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(inputStrategy : String),
			inputSemanticTypeId,
			resultSemanticTypeId,
			enumRuntimeName ?? "",
			evaluationPolicy,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			symbols.join("\u001e"),
			roles.join("\u001e")
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-typeof:duplicate-lookup]: decision "$decisionId" is bound to more than one typed call';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-typeof:missing-decision]: typed call "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-typeof:unreachable-decision]: decision "${decision.id}" has no request-local typed call';
	}

	static function bindingFor(decision:OcamlTypeOfDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlTypeOfDecision):OcamlTypeOfDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			inputStrategy: decision.inputStrategy,
			inputSemanticTypeId: decision.inputSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			enumRuntimeName: decision.enumRuntimeName,
			evaluationPolicy: decision.evaluationPolicy,
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
/** Finds resolved root `Type.typeof()` calls before target syntax. */
class OcamlTypeOfPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlTypeOfPlan {
		final decisions:Array<OcamlTypeOfDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, arguments) if (isStandardTypeOf(callee, arguments)):
					final input = arguments[0];
					final inputStrategy = selectInputStrategy(input.t);
					final enumRuntimeName = inputStrategy == OcamlTypeOfInputStrategy.BoxEnum ? enumName(input.t) : null;
					if (inputStrategy == OcamlTypeOfInputStrategy.BoxEnum && enumRuntimeName == null)
						throw "reflaxe.ocaml [ocaml-typeof:invalid-input]: enum boxing has no runtime name";
					final order = decisions.length;
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final inputSemanticTypeId = TypeTools.toString(input.t);
					final resultSemanticTypeId = TypeTools.toString(expression.t);
					final id = "type-of:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						Std.string(order),
						source.file,
						Std.string(source.min),
						Std.string(source.max),
						(inputStrategy : String),
						inputSemanticTypeId,
						resultSemanticTypeId,
						enumRuntimeName ?? ""
					].join("\u001f")).substr(0, 24);
					final symbols = OcamlTypeOfPlan.exactSymbolsFor(inputStrategy);
					final roles = OcamlTypeOfPlan.rolesFor(inputStrategy);
					final requirementId = id + ":runtime:" + OcamlTypeOfPlan.RUNTIME_CAPABILITY;
					final revision = OcamlTypeOfPlan.sealRevision(id, source, inputStrategy, inputSemanticTypeId, resultSemanticTypeId, enumRuntimeName,
						OcamlTypeOfPlan.EVALUATION_POLICY, order, binding, requirementId, symbols, roles);
					final uses:Array<OcamlRuntimeUseOccurrence> = [];
					for (index in 0...symbols.length)
						uses.push({
							id: id + ":runtime-use:" + roles[index],
							planRevision: revision,
							ownerId: id,
							requirementId: requirementId,
							domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
							exactSymbol: symbols[index],
							role: roles[index],
							order: index,
							source: copySource(source),
							profileEligibility: ["metal", "portable"],
							cardinality: 1
						});
					final decision:OcamlTypeOfDecision = {
						id: id,
						revision: revision,
						source: copySource(source),
						inputStrategy: inputStrategy,
						inputSemanticTypeId: inputSemanticTypeId,
						resultSemanticTypeId: resultSemanticTypeId,
						enumRuntimeName: enumRuntimeName,
						evaluationPolicy: OcamlTypeOfPlan.EVALUATION_POLICY,
						order: order,
						profileEligibility: ["metal", "portable"],
						runtimeRequirementIds: [requirementId],
						runtimeUseOccurrences: uses,
						proofId: OcamlTypeOfPlan.PROOF_ID,
						proofClaim: OcamlTypeOfPlan.PROOF_CLAIM,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
					decisions.push(decision);
					lookup.set(expression, decision.id);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlTypeOfPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function isStandardTypeOf(callee:TypedExpr, arguments:Array<TypedExpr>):Bool {
		if (arguments.length != 1)
			return false;
		return switch (unwrap(callee).expr) {
			case TField({expr: TTypeExpr(TClassDecl(ownerRef))}, FStatic(classRef, fieldRef)):
				final owner = ownerRef.get();
				final fieldOwner = classRef.get();
				final field = fieldRef.get();
				owner.pack.length == 0
				&& owner.name == "Type"
				&& owner.module == "Type"
				&& fieldOwner.module == owner.module
				&& fieldOwner.name == owner.name
				&& field.name == "typeof";
			case _:
				false;
		};
	}

	static function selectInputStrategy(type:Type):OcamlTypeOfInputStrategy {
		if (OcamlDynamicCarrierModel.usesDynamicCarrier(type) || nullablePrimitiveKind(type) != null)
			return OcamlTypeOfInputStrategy.DirectObject;
		if (isBoolType(type))
			return OcamlTypeOfInputStrategy.BoxBool;
		if (enumName(type) != null)
			return OcamlTypeOfInputStrategy.BoxEnum;
		return OcamlTypeOfInputStrategy.Repr;
	}

	static function enumName(type:Type):Null<String> {
		return switch (followNoAbstracts(unwrapNullType(type))) {
			case TEnum(reference, _):
				final definition = reference.get();
				(definition.pack ?? []).concat([definition.name]).join(".");
			case _:
				null;
		};
	}

	static function nullablePrimitiveKind(type:Type):Null<String> {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, [inner]):
				final definition = reference.get();
				if (definition.pack.length == 0 && definition.name == "Null") {
					if (isIntType(inner))
						return "int";
					if (isRootAbstract(inner, "Float"))
						return "float";
					if (isRootAbstract(inner, "Bool"))
						return "bool";
				}
				null;
			case _:
				null;
		};
	}

	static function isIntType(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, _): final definition = reference.get(); (definition.pack.length == 0 && definition.name == "Int") || (definition.pack.length == 1
					&& definition.pack[0] == "haxe" && definition.name == "Int32");
			case _:
				false;
		};
	}

	static function isBoolType(type:Type):Bool
		return isRootAbstract(type, "Bool");

	static function isRootAbstract(type:Type, name:String):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, _): final definition = reference.get(); definition.pack.length == 0 && definition.name == name;
			case _: false;
		};
	}

	static function unwrapNullType(type:Type):Type {
		return switch (type) {
			case TAbstract(reference, [inner]): final definition = reference.get(); definition.pack.length == 0 && definition.name == "Null" ? inner : type;
			case _: type;
		};
	}

	static function followNoAbstracts(type:Type):Type {
		var current = type;
		while (true) {
			final next = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final inner = reference.get();
					inner == null ? current : inner;
				case TType(reference, parameters):
					final definition = reference.get();
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
