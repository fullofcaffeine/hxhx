package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.Context;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Direct String methods implemented by the checked OCaml String runtime. */
enum abstract OcamlStringMethodOperation(String) from String to String {
	final ToUpperCase = "toUpperCase";
	final ToLowerCase = "toLowerCase";
	final CharAt = "charAt";
	final CharCodeAt = "charCodeAt";
	final IndexOf = "indexOf";
	final LastIndexOf = "lastIndexOf";
	final Split = "split";
	final Substr = "substr";
	final Substring = "substring";
	final ToString = "toString";
}

/** How an optional integer argument reaches one String runtime method. */
enum abstract OcamlStringMethodOptionalCarrier(String) from String to String {
	final NotApplicable = "not-applicable";
	final Omitted = "omitted";
	final ExplicitNull = "explicit-null";
	final ExactInt = "exact-int";
	final NullableInt = "nullable-int";
}

/** The value substituted when an optional String method index is null. */
enum abstract OcamlStringMethodOptionalDefault(String) from String to String {
	final NotApplicable = "not-applicable";
	final Zero = "zero";
	final ReceiverLength = "receiver-length";
	final MinusOne = "minus-one";
}

/** One source-bound direct call on the standard Haxe String type. */
typedef OcamlStringMethodDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final operation:OcamlStringMethodOperation;
	final receiverSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final optionalCarrier:OcamlStringMethodOptionalCarrier;
	final optionalDefault:OcamlStringMethodOptionalDefault;
	final resultSemanticTypeId:String;
	final evaluationOrder:Array<String>;
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
	Owns direct calls to the standard Haxe String instance methods.

	A decision records the final typed call before target code generation. It
	selects the method helper, optional-index default, nullable conversion, and
	result conversion. Target syntax can then evaluate the receiver once and use
	only the private identifiers authorized by that exact source call.
**/
class OcamlStringMethodPlan {
	public static inline final MODEL_REVISION = "typed-ocaml-string-method-v1";
	public static inline final PROOF_ID = "string-method-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed expression is a direct call on the standard Haxe String type. Its method, argument carriers, result type, and receiver-first schedule select every private runtime identifier before target syntax.";
	public static inline final RUNTIME_CAPABILITY = "haxe-string-method";

	final ordered:Array<OcamlStringMethodDecision>;
	final byId:Map<String, OcamlStringMethodDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStringMethodDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-method:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Returns the decision for this exact request-local call expression. */
	public function requireFor(expression:TypedExpr):OcamlStringMethodDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-string-method:missing-decision]: direct String method syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-method:missing-decision]: the typed expression names no sealed decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe decisions in source order. */
	public function decisions():Array<OcamlStringMethodDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-string-method:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed method, carrier, order, identity, or runtime-use facts. */
	public static function requireDecision(decision:OcamlStringMethodDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.receiverSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.evaluationOrder.length == 0
			|| decision.evaluationOrder[0] != "receiver"
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length == 0
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-string-method:invalid-plan]: decision has incomplete facts";

		if (!hasValidShape(decision))
			throw 'reflaxe.ocaml [ocaml-string-method:invalid-shape]: decision "${decision.id}" has incompatible method, argument, optional-index, or result facts';

		final symbols = exactSymbolsFor(decision.operation, decision.optionalCarrier, decision.optionalDefault, decision.resultSemanticTypeId);
		final roles = rolesFor(decision.operation, decision.optionalCarrier, decision.optionalDefault, decision.resultSemanticTypeId);
		final requirementId = decision.id + ":runtime:" + RUNTIME_CAPABILITY;
		final expectedRevision = sealRevision(decision.id, decision.source, decision.operation, decision.receiverSemanticTypeId,
			decision.argumentSemanticTypeIds, decision.optionalCarrier, decision.optionalDefault, decision.resultSemanticTypeId, decision.evaluationOrder,
			decision.order, bindingFor(decision), requirementId, symbols, roles);
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds[0] != requirementId
			|| decision.runtimeUseOccurrences.length != symbols.length)
			throw 'reflaxe.ocaml [ocaml-string-method:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';

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
				throw 'reflaxe.ocaml [ocaml-string-method:invalid-runtime-use]: decision "${decision.id}" has a conflicting helper at order $index';
		}
	}

	/** Returns private identifiers in their completed target-tree order. */
	public static function exactSymbolsFor(operation:OcamlStringMethodOperation, optionalCarrier:OcamlStringMethodOptionalCarrier,
			optionalDefault:OcamlStringMethodOptionalDefault, resultSemanticTypeId:String):Array<String> {
		final method = "HxString." + (operation : String);
		if (operation == OcamlStringMethodOperation.CharCodeAt && resultSemanticTypeId == "Int")
			return ["HxRuntime.nullable_int_unwrap", method];
		final symbols = [method];
		if (optionalCarrier == OcamlStringMethodOptionalCarrier.NullableInt)
			symbols.push("HxRuntime.hx_null");
		if (optionalDefault == OcamlStringMethodOptionalDefault.ReceiverLength
			&& (optionalCarrier == OcamlStringMethodOptionalCarrier.Omitted
				|| optionalCarrier == OcamlStringMethodOptionalCarrier.ExplicitNull
				|| optionalCarrier == OcamlStringMethodOptionalCarrier.NullableInt))
			symbols.push("HxString.length");
		return symbols;
	}

	/** Returns stable roles for the selected private identifiers. */
	public static function rolesFor(operation:OcamlStringMethodOperation, optionalCarrier:OcamlStringMethodOptionalCarrier,
			optionalDefault:OcamlStringMethodOptionalDefault, resultSemanticTypeId:String):Array<String> {
		final methodRole = "invoke-" + (operation : String);
		if (operation == OcamlStringMethodOperation.CharCodeAt && resultSemanticTypeId == "Int")
			return ["unwrap-char-code-result", methodRole];
		final roles = [methodRole];
		if (optionalCarrier == OcamlStringMethodOptionalCarrier.NullableInt)
			roles.push("optional-null-sentinel");
		if (optionalDefault == OcamlStringMethodOptionalDefault.ReceiverLength
			&& (optionalCarrier == OcamlStringMethodOptionalCarrier.Omitted
				|| optionalCarrier == OcamlStringMethodOptionalCarrier.ExplicitNull
				|| optionalCarrier == OcamlStringMethodOptionalCarrier.NullableInt))
			roles.push("default-receiver-length");
		return roles;
	}

	/**
		Returns every String-method role that final function assembly can copy.

		One planned call can appear at more than one final output position after
		control and result wrapping. This closed list lets that output boundary give
		each copy a distinct identity. It does not change the source call's helper
		inventory or permit an unknown runtime role.
	**/
	public static function outputCopyRoles():Array<String> {
		final roles = [
			for (operation in [
				OcamlStringMethodOperation.ToUpperCase,
				OcamlStringMethodOperation.ToLowerCase,
				OcamlStringMethodOperation.CharAt,
				OcamlStringMethodOperation.CharCodeAt,
				OcamlStringMethodOperation.IndexOf,
				OcamlStringMethodOperation.LastIndexOf,
				OcamlStringMethodOperation.Split,
				OcamlStringMethodOperation.Substr,
				OcamlStringMethodOperation.Substring,
				OcamlStringMethodOperation.ToString
			])
				"invoke-" + (operation : String)
		];
		roles.push("optional-null-sentinel");
		roles.push("default-receiver-length");
		roles.push("unwrap-char-code-result");
		return roles;
	}

	/** Returns all directly required runtime modules without duplicates. */
	public static function rootModules(decision:OcamlStringMethodDecision):Array<String> {
		requireDecision(decision);
		final roots:Map<String, Bool> = [];
		for (occurrence in decision.runtimeUseOccurrences) {
			final separator = occurrence.exactSymbol.indexOf(".");
			roots.set(separator < 0 ? occurrence.exactSymbol : occurrence.exactSymbol.substr(0, separator), true);
		}
		final result = [for (root in roots.keys()) root];
		result.sort(Reflect.compare);
		return result;
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, operation:OcamlStringMethodOperation, receiverSemanticTypeId:String,
			argumentSemanticTypeIds:Array<String>, optionalCarrier:OcamlStringMethodOptionalCarrier, optionalDefault:OcamlStringMethodOptionalDefault,
			resultSemanticTypeId:String, evaluationOrder:Array<String>, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String,
			symbols:Array<String>, roles:Array<String>):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(operation : String),
			receiverSemanticTypeId,
			argumentSemanticTypeIds.join("\u001e"),
			(optionalCarrier : String),
			(optionalDefault : String),
			resultSemanticTypeId,
			evaluationOrder.join(","),
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

	static function hasValidShape(decision:OcamlStringMethodDecision):Bool {
		final maximumArguments = switch (decision.operation) {
			case ToUpperCase, ToLowerCase, ToString: 0;
			case CharAt, CharCodeAt, Split: 1;
			case IndexOf, LastIndexOf, Substr, Substring: 2;
		};
		final expectedArguments = decision.optionalCarrier == OcamlStringMethodOptionalCarrier.Omitted ? maximumArguments - 1 : maximumArguments;
		final expectedDefault = switch (decision.operation) {
			case IndexOf: OcamlStringMethodOptionalDefault.Zero;
			case LastIndexOf, Substring: OcamlStringMethodOptionalDefault.ReceiverLength;
			case Substr: OcamlStringMethodOptionalDefault.MinusOne;
			case _: OcamlStringMethodOptionalDefault.NotApplicable;
		};
		final optionalShapeValid = expectedDefault == OcamlStringMethodOptionalDefault.NotApplicable ? decision.optionalCarrier == OcamlStringMethodOptionalCarrier.NotApplicable : decision.optionalCarrier != OcamlStringMethodOptionalCarrier.NotApplicable;
		if (decision.argumentSemanticTypeIds.length != expectedArguments
			|| decision.optionalDefault != expectedDefault
			|| !optionalShapeValid)
			return false;
		final expectedOrder = ["receiver"];
		for (index in 0...decision.argumentSemanticTypeIds.length)
			// An explicit `null` contains no computation. The decision still records
			// its typed argument, but target syntax can materialize the selected
			// default without manufacturing a nullable runtime value.
			if (decision.optionalCarrier != OcamlStringMethodOptionalCarrier.ExplicitNull
				|| index < decision.argumentSemanticTypeIds.length - 1)
				expectedOrder.push('argument:$index');
		if (decision.evaluationOrder.join(",") != expectedOrder.join(","))
			return false;
		return switch (decision.operation) {
			case CharCodeAt: decision.resultSemanticTypeId == "Int" || decision.resultSemanticTypeId == "Null<Int>";
			case IndexOf, LastIndexOf: decision.resultSemanticTypeId == "Int";
			case Split: decision.resultSemanticTypeId == "Array<String>";
			case _: decision.resultSemanticTypeId == "String";
		};
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-method:duplicate-lookup]: decision "$decisionId" is bound more than once';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-method:missing-decision]: typed expression "$decisionId" has no decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-method:unreachable-decision]: decision "${decision.id}" has no typed expression';
	}

	static function bindingFor(decision:OcamlStringMethodDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStringMethodDecision):OcamlStringMethodDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			operation: decision.operation,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			optionalCarrier: decision.optionalCarrier,
			optionalDefault: decision.optionalDefault,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			evaluationOrder: decision.evaluationOrder.copy(),
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

	static function copyOccurrence(occurrence:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: occurrence.id,
			planRevision: occurrence.planRevision,
			ownerId: occurrence.ownerId,
			requirementId: occurrence.requirementId,
			domain: occurrence.domain,
			exactSymbol: occurrence.exactSymbol,
			role: occurrence.role,
			order: occurrence.order,
			source: copySource(occurrence.source),
			profileEligibility: occurrence.profileEligibility.copy(),
			cardinality: occurrence.cardinality
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}

#if macro
/** Selects direct standard String calls before target syntax starts. */
class OcamlStringMethodPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStringMethodPlan {
		final decisions:Array<OcamlStringMethodDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, receiver:TypedExpr, fieldName:String, arguments:Array<TypedExpr>):Void {
			final operation = operationFor(fieldName);
			if (operation == null)
				return;
			final normalizedArguments = normalizeArguments(operation, arguments, expression.pos);
			final optionalCarrier = optionalCarrierFor(operation, normalizedArguments);
			final optionalDefault = optionalDefaultFor(operation);
			final argumentSemanticTypeIds = normalizedArguments.map(argument -> TypeTools.toString(argument.t));
			final evaluationOrder = ["receiver"];
			for (index in 0...normalizedArguments.length)
				if (optionalCarrier != OcamlStringMethodOptionalCarrier.ExplicitNull || index < normalizedArguments.length - 1)
					evaluationOrder.push('argument:$index');
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final receiverSemanticTypeId = TypeTools.toString(receiver.t);
			final resultSemanticTypeId = TypeTools.toString(expression.t);
			final id = "string-method:" + Sha256.encode([
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				Std.string(order),
				source.file,
				Std.string(source.min),
				Std.string(source.max),
				(operation : String),
				receiverSemanticTypeId,
				argumentSemanticTypeIds.join("\u001e"),
				(optionalCarrier : String),
				resultSemanticTypeId
			].join("\u001f")).substr(0, 24);
			final requirementId = id + ":runtime:" + OcamlStringMethodPlan.RUNTIME_CAPABILITY;
			final symbols = OcamlStringMethodPlan.exactSymbolsFor(operation, optionalCarrier, optionalDefault, resultSemanticTypeId);
			final roles = OcamlStringMethodPlan.rolesFor(operation, optionalCarrier, optionalDefault, resultSemanticTypeId);
			final revision = OcamlStringMethodPlan.sealRevision(id, source, operation, receiverSemanticTypeId, argumentSemanticTypeIds, optionalCarrier,
				optionalDefault, resultSemanticTypeId, evaluationOrder, order, binding, requirementId, symbols, roles);
			final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
			for (index in 0...symbols.length)
				occurrences.push({
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
			final decision:OcamlStringMethodDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				operation: operation,
				receiverSemanticTypeId: receiverSemanticTypeId,
				argumentSemanticTypeIds: argumentSemanticTypeIds,
				optionalCarrier: optionalCarrier,
				optionalDefault: optionalDefault,
				resultSemanticTypeId: resultSemanticTypeId,
				evaluationOrder: evaluationOrder,
				order: order,
				profileEligibility: ["metal", "portable"],
				runtimeRequirementIds: [requirementId],
				runtimeUseOccurrences: occurrences,
				proofId: OcamlStringMethodPlan.PROOF_ID,
				proofClaim: OcamlStringMethodPlan.PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			OcamlStringMethodPlan.requireDecision(decision);
			decisions.push(decision);
			lookup.set(expression, decision.id);
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, arguments):
					switch (callee.expr) {
						case TField(receiver, FInstance(classRef, _, fieldRef)) if (isStdStringClass(classRef.get())):
							final field = fieldRef.get();
							if (field.kind.match(FMethod(_)) && operationFor(field.name) != null) {
								add(expression, receiver, field.name, arguments);
								visit(receiver);
								for (argument in arguments)
									visit(argument);
								return;
							}
						case _:
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlStringMethodPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	/** Returns whether the expression is one of the admitted direct calls. */
	public static function isDirectStringMethodCall(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TCall(callee, _):
				switch (callee.expr) {
					case TField(_, FInstance(classRef, _, fieldRef)): final field = fieldRef.get(); isStdStringClass(classRef.get()) && field.kind.match(FMethod(_)) && operationFor(field.name) != null;
					case _:
						false;
				}
			case _:
				false;
		};
	}

	public static function operationFor(fieldName:String):Null<OcamlStringMethodOperation> {
		return switch (fieldName) {
			case "toUpperCase": OcamlStringMethodOperation.ToUpperCase;
			case "toLowerCase": OcamlStringMethodOperation.ToLowerCase;
			case "charAt": OcamlStringMethodOperation.CharAt;
			case "charCodeAt": OcamlStringMethodOperation.CharCodeAt;
			case "indexOf": OcamlStringMethodOperation.IndexOf;
			case "lastIndexOf": OcamlStringMethodOperation.LastIndexOf;
			case "split": OcamlStringMethodOperation.Split;
			case "substr": OcamlStringMethodOperation.Substr;
			case "substring": OcamlStringMethodOperation.Substring;
			case "toString": OcamlStringMethodOperation.ToString;
			case _: null;
		};
	}

	static function normalizeArguments(operation:OcamlStringMethodOperation, arguments:Array<TypedExpr>, position:haxe.macro.Expr.Position):Array<TypedExpr> {
		final maximum = switch (operation) {
			case ToUpperCase, ToLowerCase, ToString: 0;
			case CharAt, CharCodeAt, Split: 1;
			case IndexOf, LastIndexOf, Substr, Substring: 2;
		};
		final minimum = switch (operation) {
			case IndexOf, LastIndexOf, Substr, Substring: maximum - 1;
			case _: maximum;
		};
		if (arguments.length < minimum || arguments.length > maximum)
			Context.error('reflaxe.ocaml [ocaml-string-method:unsupported-arity]: ${(operation : String)} expected $minimum..$maximum typed arguments, received ${arguments.length}',
				position);
		return arguments;
	}

	static function optionalCarrierFor(operation:OcamlStringMethodOperation, arguments:Array<TypedExpr>):OcamlStringMethodOptionalCarrier {
		return switch (operation) {
			case IndexOf, LastIndexOf, Substr, Substring:
				if (arguments.length == 1) {
					OcamlStringMethodOptionalCarrier.Omitted;
				} else {
					final optional = unwrap(arguments[1]);
					switch (optional.expr) {
						case TConst(TNull): OcamlStringMethodOptionalCarrier.ExplicitNull;
						case _ if (OcamlRepresentationRegistry.isExactInt(optional.t)): OcamlStringMethodOptionalCarrier.ExactInt;
						case _ if (OcamlRepresentationRegistry.isExactNullInt(optional.t)): OcamlStringMethodOptionalCarrier.NullableInt;
						case _:
							Context.error('reflaxe.ocaml [ocaml-string-method:unsupported-optional-index]: ${(operation : String)} received ${TypeTools.toString(optional.t)}',
								optional.pos);
							OcamlStringMethodOptionalCarrier.ExplicitNull;
					}
				}
			case _:
				OcamlStringMethodOptionalCarrier.NotApplicable;
		};
	}

	static function optionalDefaultFor(operation:OcamlStringMethodOperation):OcamlStringMethodOptionalDefault {
		return switch (operation) {
			case IndexOf: OcamlStringMethodOptionalDefault.Zero;
			case LastIndexOf, Substring: OcamlStringMethodOptionalDefault.ReceiverLength;
			case Substr: OcamlStringMethodOptionalDefault.MinusOne;
			case _: OcamlStringMethodOptionalDefault.NotApplicable;
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
		return classType.pack.length == 0 && classType.name == "String" && classType.module == "String";

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end

#end
