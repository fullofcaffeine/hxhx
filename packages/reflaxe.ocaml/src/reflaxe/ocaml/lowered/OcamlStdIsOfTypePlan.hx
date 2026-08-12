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

/** The complete target strategy for one standard Haxe runtime type check. */
enum abstract OcamlStdIsOfTypeStrategy(String) from String to String {
	final StaticTrue = "static-true";
	final StaticFalse = "static-false";
	final DynamicInt = "dynamic-int";
	final DynamicFloat = "dynamic-float";
	final DynamicBool = "dynamic-bool";
	final RuntimeFallback = "runtime-fallback";
}

/** How the source value enters a runtime type check. */
enum abstract OcamlStdIsOfTypeValueCarrier(String) from String to String {
	/** The source value already uses the target's general-purpose `Obj.t` carrier. */
	final DirectObject = "direct-object";

	/** Target syntax must convert the source value with `Obj.repr`. */
	final Repr = "repr";
}

/** One immutable type-test decision for one resolved `Std.isOfType()` call. */
typedef OcamlStdIsOfTypeDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final strategy:OcamlStdIsOfTypeStrategy;
	final valueCarrier:OcamlStdIsOfTypeValueCarrier;
	final valueSemanticTypeId:String;
	final requestedTypeSemanticId:String;
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
	Stores the selected behavior for each standard Haxe runtime type check.

	For example, `Std.isOfType(value, Int)` needs two private helpers when
	`value` is Dynamic. The plan records the null sentinel first and the boxed
	Boolean test second. Target syntax can then print only those two names in
	that order. Static checks record no private helper.

	The lookup uses typed expressions from the current compiler request. Copied
	decisions contain stable values, but the plan must not survive the request.
**/
class OcamlStdIsOfTypePlan {
	public static inline final MODEL_REVISION = "typed-ocaml-std-is-of-type-v1";
	public static inline final PROOF_ID = "std-is-of-type-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed call resolves to root Std.isOfType. Its requested type and source value type select one complete static, dynamic-primitive, or runtime-fallback strategy before target syntax. The strategy owns every private helper in final expression order.";
	public static inline final RUNTIME_CAPABILITY = "haxe-std-is-of-type";

	final ordered:Array<OcamlStdIsOfTypeDecision>;
	final byId:Map<String, OcamlStdIsOfTypeDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStdIsOfTypeDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision for this exact request-local typed call. */
	public function requireFor(expression:TypedExpr):OcamlStdIsOfTypeDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-std-is-of-type:missing-decision]: Std.isOfType syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-std-is-of-type:missing-decision]: the typed call names no sealed type-test decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe copies in source order. */
	public function decisions():Array<OcamlStdIsOfTypeDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or target pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects incomplete or changed type, strategy, requirement, and helper facts. */
	public static function requireDecision(decision:OcamlStdIsOfTypeDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.valueSemanticTypeId.length == 0
			|| decision.requestedTypeSemanticId.length == 0
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-std-is-of-type:invalid-plan]: type-test decision has incomplete facts";

		final symbols = exactSymbolsFor(decision.strategy);
		final roles = rolesFor(decision.strategy);
		final expectedRequirementIds = symbols.length == 0 ? [] : [decision.id + ":runtime:" + RUNTIME_CAPABILITY];
		final expectedRevision = sealRevision(decision.id, decision.source, decision.strategy, decision.valueCarrier, decision.valueSemanticTypeId,
			decision.requestedTypeSemanticId, decision.order, bindingFor(decision), expectedRequirementIds, symbols, roles);
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds.join(",") != expectedRequirementIds.join(",")
			|| decision.runtimeUseOccurrences.length != symbols.length)
			throw 'reflaxe.ocaml [ocaml-std-is-of-type:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';

		for (index in 0...symbols.length) {
			final occurrence = decision.runtimeUseOccurrences[index];
			final requirementId = expectedRequirementIds[0];
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
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:invalid-runtime-use]: decision "${decision.id}" has a conflicting helper at order $index';
		}
	}

	/** Returns private helper names in their final target-expression order. */
	public static function exactSymbolsFor(strategy:OcamlStdIsOfTypeStrategy):Array<String> {
		return switch (strategy) {
			case StaticTrue, StaticFalse: [];
			case DynamicInt, DynamicFloat, DynamicBool: ["HxRuntime.hx_null", "HxRuntime.is_boxed_bool"];
			case RuntimeFallback: ["HxType.isOfType"];
		};
	}

	/** Returns stable roles for the private helpers in one strategy. */
	public static function rolesFor(strategy:OcamlStdIsOfTypeStrategy):Array<String> {
		return switch (strategy) {
			case StaticTrue, StaticFalse: [];
			case DynamicInt, DynamicFloat, DynamicBool: ["null-sentinel", "boxed-bool-test"];
			case RuntimeFallback: ["runtime-type-test"];
		};
	}

	/** Returns the direct runtime roots selected by one validated decision. */
	public static function rootModules(decision:OcamlStdIsOfTypeDecision):Array<String> {
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

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, strategy:OcamlStdIsOfTypeStrategy,
			valueCarrier:OcamlStdIsOfTypeValueCarrier, valueSemanticTypeId:String, requestedTypeSemanticId:String, order:Int,
			binding:OcamlFunctionPlanBinding, requirementIds:Array<String>, symbols:Array<String>, roles:Array<String>):String {
		return "sha256:" + Sha256.encode([
			"std-is-of-type-runtime-use-v1",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(strategy : String),
			(valueCarrier : String),
			valueSemanticTypeId,
			requestedTypeSemanticId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementIds.join("\u001e"),
			symbols.join("\u001e"),
			roles.join("\u001e")
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:duplicate-lookup]: decision "$decisionId" is bound to more than one typed call';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:missing-decision]: typed call "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:unreachable-decision]: decision "${decision.id}" has no request-local typed call';
	}

	static function bindingFor(decision:OcamlStdIsOfTypeDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStdIsOfTypeDecision):OcamlStdIsOfTypeDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			strategy: decision.strategy,
			valueCarrier: decision.valueCarrier,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			requestedTypeSemanticId: decision.requestedTypeSemanticId,
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

/** Finds all resolved root `Std.isOfType()` calls before target syntax. */
#if macro
class OcamlStdIsOfTypePlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStdIsOfTypePlan {
		final decisions:Array<OcamlStdIsOfTypeDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, arguments) if (isStandardIsOfType(callee, arguments)):
					final value = arguments[0];
					final requestedType = arguments[1];
					final strategy = selectStrategy(value.t, requestedType);
					final carrier = selectValueCarrier(value.t);
					final order = decisions.length;
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final valueSemanticTypeId = TypeTools.toString(value.t);
					final requestedTypeSemanticId = TypeTools.toString(requestedType.t);
					final id = "std-is-of-type:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						Std.string(order),
						source.file,
						Std.string(source.min),
						Std.string(source.max),
						(strategy : String),
						(carrier : String),
						valueSemanticTypeId,
						requestedTypeSemanticId
					].join("\u001f")).substr(0, 24);
					final symbols = OcamlStdIsOfTypePlan.exactSymbolsFor(strategy);
					final roles = OcamlStdIsOfTypePlan.rolesFor(strategy);
					final requirementIds = symbols.length == 0 ? [] : [id + ":runtime:" + OcamlStdIsOfTypePlan.RUNTIME_CAPABILITY];
					final revision = OcamlStdIsOfTypePlan.sealRevision(id, source, strategy, carrier, valueSemanticTypeId, requestedTypeSemanticId, order,
						binding, requirementIds, symbols, roles);
					final uses:Array<OcamlRuntimeUseOccurrence> = [];
					for (index in 0...symbols.length)
						uses.push({
							id: id + ":runtime-use:" + roles[index],
							planRevision: revision,
							ownerId: id,
							requirementId: requirementIds[0],
							domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
							exactSymbol: symbols[index],
							role: roles[index],
							order: index,
							source: copySource(source),
							profileEligibility: ["metal", "portable"],
							cardinality: 1
						});
					final decision:OcamlStdIsOfTypeDecision = {
						id: id,
						revision: revision,
						source: copySource(source),
						strategy: strategy,
						valueCarrier: carrier,
						valueSemanticTypeId: valueSemanticTypeId,
						requestedTypeSemanticId: requestedTypeSemanticId,
						order: order,
						profileEligibility: ["metal", "portable"],
						runtimeRequirementIds: requirementIds,
						runtimeUseOccurrences: uses,
						proofId: OcamlStdIsOfTypePlan.PROOF_ID,
						proofClaim: OcamlStdIsOfTypePlan.PROOF_CLAIM,
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
		final plan = new OcamlStdIsOfTypePlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function isStandardIsOfType(callee:TypedExpr, arguments:Array<TypedExpr>):Bool {
		if (arguments.length != 2)
			return false;
		return switch (unwrap(callee).expr) {
			case TField({expr: TTypeExpr(TClassDecl(ownerRef))}, FStatic(classRef, fieldRef)):
				final owner = ownerRef.get();
				final fieldOwner = classRef.get();
				final field = fieldRef.get();
				owner.pack.length == 0
				&& owner.name == "Std"
				&& owner.module == "Std"
				&& fieldOwner.module == owner.module
				&& fieldOwner.name == owner.name
				&& field.name == "isOfType";
			case _:
				false;
		};
	}

	static function selectStrategy(valueType:Type, requestedType:TypedExpr):OcamlStdIsOfTypeStrategy {
		return switch (requestedCoreAbstractName(requestedType)) {
			case "Int":
				if (isIntType(valueType)) StaticTrue; else if (isFloatType(valueType) || isBoolType(valueType) || isStringType(valueType)) StaticFalse; else
					DynamicInt;
			case "Float":
				if (isFloatType(valueType) || isIntType(valueType)) StaticTrue; else if (isBoolType(valueType) || isStringType(valueType)) StaticFalse; else
					DynamicFloat;
			case "Bool":
				if (isBoolType(valueType)) StaticTrue; else if (isIntType(valueType) || isFloatType(valueType) || isStringType(valueType)) StaticFalse; else
					DynamicBool;
			case _:
				RuntimeFallback;
		};
	}

	static function selectValueCarrier(valueType:Type):OcamlStdIsOfTypeValueCarrier {
		final unwrapped = unwrapNullType(valueType);
		return nullablePrimitiveKind(unwrapped) != null || OcamlDynamicCarrierModel.usesDynamicCarrier(unwrapped) ? DirectObject : Repr;
	}

	static function requestedCoreAbstractName(expression:TypedExpr):Null<String> {
		return switch (unwrap(expression).expr) {
			case TTypeExpr(TAbstract(reference)):
				final definition = reference.get();
				definition.pack.length == 0 ? definition.name : null;
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

	static function isFloatType(type:Type):Bool
		return isRootAbstract(type, "Float");

	static function isBoolType(type:Type):Bool
		return isRootAbstract(type, "Bool");

	static function isRootAbstract(type:Type, name:String):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, _): final definition = reference.get(); definition.pack.length == 0 && definition.name == name;
			case _:
				false;
		};
	}

	static function isStringType(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, [inner]): final definition = reference.get(); definition.pack.length == 0 && definition.name == "Null" && isStringType(inner);
			case TAbstract(reference, _):
				final definition = reference.get();
				if (definition.pack.length == 1 && definition.pack[0] == "haxe" && definition.name == "Ucs2") {
					true;
				} else {
					switch (TypeTools.follow(definition.type)) {
						case TInst(classRef, _): isRootStringClass(classRef.get());
						case _: false;
					}
				}
			case TInst(classRef, _):
				isRootStringClass(classRef.get());
			case _:
				false;
		};
	}

	static function isRootStringClass(definition:ClassType):Bool
		return definition.pack.length == 0 && definition.name == "String";

	static function nullablePrimitiveKind(type:Type):Null<String> {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, [inner]):
				final definition = reference.get();
				if (definition.pack.length == 0 && definition.name == "Null") {
					if (isIntType(inner))
						return "int";
					if (isFloatType(inner))
						return "float";
					if (isBoolType(inner))
						return "bool";
				}
				null;
			case _:
				null;
		};
	}

	static function unwrapNullType(type:Type):Type {
		return switch (type) {
			case TAbstract(reference, [inner]): final definition = reference.get(); definition.pack.length == 0 && definition.name == "Null" ? inner : type;
			case _:
				type;
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
