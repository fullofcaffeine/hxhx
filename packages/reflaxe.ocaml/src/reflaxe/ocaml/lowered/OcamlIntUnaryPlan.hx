package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The two exact integer unary operations that require Haxe Int32 helpers. */
enum abstract OcamlIntUnaryOperation(String) from String to String {
	final Negate = "negate";
	final BitwiseNot = "bitwise-not";
}

/** The operand conversion selected before integer unary syntax is built. */
enum abstract OcamlIntUnaryOperandCarrier(String) from String to String {
	final ExactInt = "exact-int";
	final NullableInt = "nullable-int";
}

/** One immutable integer-unary decision for one typed source occurrence. */
typedef OcamlIntUnaryDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final operation:OcamlIntUnaryOperation;
	final operandCarrier:OcamlIntUnaryOperandCarrier;
	final operandSemanticTypeId:String;
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
	Stores the complete target choice for exact integer unary expressions.

	For `-value`, the plan selects `HxInt.neg`. For `~value`, it selects
	`HxInt.lognot`. A nullable integer also records the Haxe null sentinel used by
	the existing null-to-zero operand conversion. The outer Int32 call appears
	first in the structured target tree, followed by its nested sentinel use.
	Target syntax receives only these names and cannot choose another private
	helper after planning.

	The expression lookup belongs to one compiler request and must not be cached.
**/
class OcamlIntUnaryPlan {
	public static inline final MODEL_REVISION = "typed-ocaml-int-unary-v1";
	public static inline final PROOF_ID = "int-unary-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed unary expression has an exact or nullable Int operand and an Int result. Its operator and operand carrier select the complete private-runtime sequence before target syntax.";
	public static inline final RUNTIME_CAPABILITY = "haxe-int32-unary";

	final ordered:Array<OcamlIntUnaryDecision>;
	final byId:Map<String, OcamlIntUnaryDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlIntUnaryDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-int-unary:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision for this exact request-local typed unary expression. */
	public function requireFor(expression:TypedExpr):OcamlIntUnaryDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-int-unary:missing-decision]: integer unary syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-int-unary:missing-decision]: the typed expression names no sealed integer-unary decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe copies in source order. */
	public function decisions():Array<OcamlIntUnaryDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or target pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-int-unary:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects incomplete or changed operation, carrier, requirement, and helper facts. */
	public static function requireDecision(decision:OcamlIntUnaryDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.operandSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-int-unary:invalid-plan]: integer-unary decision has incomplete facts";

		final symbols = exactSymbolsFor(decision.operation, decision.operandCarrier);
		final roles = rolesFor(decision.operation, decision.operandCarrier);
		final expectedRequirementIds = [decision.id + ":runtime:" + RUNTIME_CAPABILITY];
		final expectedRevision = sealRevision(decision.id, decision.source, decision.operation, decision.operandCarrier, decision.operandSemanticTypeId,
			decision.resultSemanticTypeId, decision.order, bindingFor(decision), expectedRequirementIds, symbols, roles);
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds.join(",") != expectedRequirementIds.join(",")
			|| decision.runtimeUseOccurrences.length != symbols.length)
			throw 'reflaxe.ocaml [ocaml-int-unary:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';

		for (index in 0...symbols.length) {
			final occurrence = decision.runtimeUseOccurrences[index];
			if (occurrence.id != decision.id + ":runtime-use:" + roles[index]
				|| occurrence.planRevision != decision.revision
				|| occurrence.ownerId != decision.id
				|| occurrence.requirementId != expectedRequirementIds[0]
				|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
				|| occurrence.exactSymbol != symbols[index]
				|| occurrence.role != roles[index]
				|| occurrence.order != index
				|| occurrence.source.file != decision.source.file
				|| occurrence.source.min != decision.source.min
				|| occurrence.source.max != decision.source.max
				|| occurrence.profileEligibility.join(",") != "metal,portable"
				|| occurrence.cardinality != 1)
				throw 'reflaxe.ocaml [ocaml-int-unary:invalid-runtime-use]: decision "${decision.id}" has a conflicting helper at order $index';
		}
	}

	/** Returns private helper names in their final target-expression order. */
	public static function exactSymbolsFor(operation:OcamlIntUnaryOperation, carrier:OcamlIntUnaryOperandCarrier):Array<String> {
		final finalOperation = operation == OcamlIntUnaryOperation.Negate ? "HxInt.neg" : "HxInt.lognot";
		return carrier == OcamlIntUnaryOperandCarrier.NullableInt ? [finalOperation, "HxRuntime.hx_null"] : [finalOperation];
	}

	/** Returns stable roles for the helpers selected by one decision. */
	public static function rolesFor(operation:OcamlIntUnaryOperation, carrier:OcamlIntUnaryOperandCarrier):Array<String> {
		final finalRole = operation == OcamlIntUnaryOperation.Negate ? "negate-int32" : "complement-int32";
		return carrier == OcamlIntUnaryOperandCarrier.NullableInt ? [finalRole, "nullable-null-sentinel"] : [finalRole];
	}

	/** Returns the direct runtime roots selected by one validated decision. */
	public static function rootModules(decision:OcamlIntUnaryDecision):Array<String> {
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

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, operation:OcamlIntUnaryOperation,
			operandCarrier:OcamlIntUnaryOperandCarrier, operandSemanticTypeId:String, resultSemanticTypeId:String, order:Int,
			binding:OcamlFunctionPlanBinding, requirementIds:Array<String>, symbols:Array<String>, roles:Array<String>):String {
		return "sha256:" + Sha256.encode([
			"int-unary-runtime-use-v1",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(operation : String),
			(operandCarrier : String),
			operandSemanticTypeId,
			resultSemanticTypeId,
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
				throw 'reflaxe.ocaml [ocaml-int-unary:duplicate-lookup]: decision "$decisionId" is bound to more than one typed expression';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-int-unary:missing-decision]: typed expression "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-int-unary:unreachable-decision]: decision "${decision.id}" has no request-local typed expression';
	}

	static function bindingFor(decision:OcamlIntUnaryDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlIntUnaryDecision):OcamlIntUnaryDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			operation: decision.operation,
			operandCarrier: decision.operandCarrier,
			operandSemanticTypeId: decision.operandSemanticTypeId,
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

/** Finds exact and nullable integer unary expressions before target syntax. */
#if macro
class OcamlIntUnaryPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlIntUnaryPlan {
		final decisions:Array<OcamlIntUnaryDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TUnop(unaryOperator, _, operand):
					final operation = selectedOperation(unaryOperator, operand.t, expression.t);
					if (operation != null) {
						final carrier = isNullableInt(operand.t) ? OcamlIntUnaryOperandCarrier.NullableInt : OcamlIntUnaryOperandCarrier.ExactInt;
						final order = decisions.length;
						final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
						final operandSemanticTypeId = TypeTools.toString(operand.t);
						final resultSemanticTypeId = TypeTools.toString(expression.t);
						final id = "int-unary:" + Sha256.encode([
							binding.functionId,
							binding.programRevision,
							binding.bodyRevision,
							binding.pipelineRevision,
							Std.string(order),
							source.file,
							Std.string(source.min),
							Std.string(source.max),
							(operation : String),
							(carrier : String),
							operandSemanticTypeId,
							resultSemanticTypeId
						].join("\u001f")).substr(0, 24);
						final symbols = OcamlIntUnaryPlan.exactSymbolsFor(operation, carrier);
						final roles = OcamlIntUnaryPlan.rolesFor(operation, carrier);
						final requirementIds = [id + ":runtime:" + OcamlIntUnaryPlan.RUNTIME_CAPABILITY];
						final revision = OcamlIntUnaryPlan.sealRevision(id, source, operation, carrier, operandSemanticTypeId, resultSemanticTypeId, order,
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
						final decision:OcamlIntUnaryDecision = {
							id: id,
							revision: revision,
							source: copySource(source),
							operation: operation,
							operandCarrier: carrier,
							operandSemanticTypeId: operandSemanticTypeId,
							resultSemanticTypeId: resultSemanticTypeId,
							order: order,
							profileEligibility: ["metal", "portable"],
							runtimeRequirementIds: requirementIds,
							runtimeUseOccurrences: uses,
							proofId: OcamlIntUnaryPlan.PROOF_ID,
							proofClaim: OcamlIntUnaryPlan.PROOF_CLAIM,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						};
						decisions.push(decision);
						lookup.set(expression, decision.id);
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlIntUnaryPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function selectedOperation(unaryOperator:Unop, operandType:Type, resultType:Type):Null<OcamlIntUnaryOperation> {
		if ((!isExactInt(operandType) && !isNullableInt(operandType)) || !isExactInt(resultType))
			return null;
		return switch (unaryOperator) {
			case OpNeg: OcamlIntUnaryOperation.Negate;
			case OpNegBits: OcamlIntUnaryOperation.BitwiseNot;
			case _: null;
		};
	}

	static function isExactInt(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, _): final definition = reference.get(); (definition.pack.length == 0 && definition.name == "Int") || (definition.pack.length == 1
					&& definition.pack[0] == "haxe" && definition.name == "Int32");
			case _:
				false;
		};
	}

	static function isNullableInt(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(reference, [inner]): final definition = reference.get(); definition.pack.length == 0 && definition.name == "Null" && isExactInt(inner);
			case _:
				false;
		};
	}

	static function followNoAbstracts(type:Type):Type {
		return switch (type) {
			case TLazy(resolve): followNoAbstracts(resolve());
			case TMono(reference):
				final resolved = reference.get();
				resolved == null ? type : followNoAbstracts(resolved);
			case TType(reference, parameters):
				final definition = reference.get();
				followNoAbstracts(TypeTools.applyTypeParameters(definition.type, definition.params, parameters));
			case _:
				type;
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end
#end
