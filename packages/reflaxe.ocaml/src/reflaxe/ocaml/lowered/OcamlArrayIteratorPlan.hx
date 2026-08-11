package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Expr.Binop;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.Ref;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayCallContract;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The exact source form that selects one standard or structural Array iterator result. */
enum abstract OcamlArrayIteratorUseKind(String) from String to String {
	final DirectCall = "direct-call";
	final BoundMethod = "bound-method";
	final StructuralAdapter = "structural-adapter";
	final StructuralCarrier = "structural-carrier";
}

/** One immutable standard-Array iterator or structural carrier decision. */
typedef OcamlArrayIteratorDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlArrayIteratorUseKind;
	final receiverSemanticTypeId:String;
	final elementSemanticTypeId:String;
	final resultSemanticTypeId:String;
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

/** Selects standard Array iterators and validates structural uses of `HxIterator`. */
class OcamlArrayIteratorContract {
	public static inline final PROOF_ID = "standard-array-iterator-runtime-use-v2";
	public static inline final PROOF_CLAIM = "The final typed occurrence is Array<T>.iterator(), the same method captured as a value, an Array<T> value crossing an exact Iterable<T> boundary, or a structural Iterator<T> object literal. The sealed source kind and element type select exactly one HxIterator expression or carrier type before target syntax. An Array value alone, a field name alone, or an anonymous shape alone does not authorize another private runtime reference.";
	public static inline final RUNTIME_CAPABILITY = "haxe-iterator";

	#if macro
	/** Creates a checked plain-value decision from one admitted typed occurrence. */
	public static function seal(expression:TypedExpr, binding:OcamlFunctionPlanBinding, ordinal:Int):Null<OcamlArrayIteratorDecision> {
		final selected = select(expression);
		if (selected == null)
			return null;
		return sealSelected(expression, selected, binding, ordinal);
	}

	/** Seals an Array value only when it crosses one exact `Iterable<T>` boundary. */
	public static function sealStructuralAdapter(expression:TypedExpr, expectedType:Type, binding:OcamlFunctionPlanBinding,
			ordinal:Int):Null<OcamlArrayIteratorDecision> {
		final arrayElement = arrayElementType(expression.t);
		final iterableElement = iterableElementType(expectedType);
		if (arrayElement == null || iterableElement == null || TypeTools.toString(arrayElement) != TypeTools.toString(iterableElement))
			return null;
		final element = TypeTools.toString(arrayElement);
		return sealSelected(expression, {
			kind: OcamlArrayIteratorUseKind.StructuralAdapter,
			receiverSemanticTypeId: 'Array<$element>',
			elementSemanticTypeId: element,
			resultSemanticTypeId: TypeTools.toString(expectedType)
		}, binding, ordinal);
	}

	static function sealSelected(expression:TypedExpr, selected:{
		kind:OcamlArrayIteratorUseKind,
		receiverSemanticTypeId:String,
		elementSemanticTypeId:String,
		resultSemanticTypeId:String
	}, binding:OcamlFunctionPlanBinding, ordinal:Int):OcamlArrayIteratorDecision {
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final id = "array-iterator:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			Std.string(ordinal),
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(selected.kind : String),
			selected.receiverSemanticTypeId,
			selected.elementSemanticTypeId,
			selected.resultSemanticTypeId
		].join("|"));
		final usesPrivateRuntime = selected.kind == OcamlArrayIteratorUseKind.StructuralCarrier
			|| selected.kind == OcamlArrayIteratorUseKind.StructuralAdapter;
		final requirementId = usesPrivateRuntime ? id + ":runtime:" + RUNTIME_CAPABILITY : "";
		final exactSymbol = selected.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? "HxIterator.t" : usesPrivateRuntime ? "HxIterator.of_array" : "";
		final domain = selected.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? OcamlRuntimeUseDomain.TypeIdentifier : OcamlRuntimeUseDomain.ExpressionIdentifier;
		final role = selected.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? "iterator-carrier" : usesPrivateRuntime ? "iterator-from-array" : "";
		final revision = revisionFor(id, source, selected.kind, selected.receiverSemanticTypeId, selected.elementSemanticTypeId,
			selected.resultSemanticTypeId, binding, exactSymbol, usesPrivateRuntime ? (domain : String) : "", role, requirementId);
		final occurrences:Array<OcamlRuntimeUseOccurrence> = usesPrivateRuntime ? [
			{
				id: id + ":runtime-use:" + role,
				planRevision: revision,
				ownerId: id,
				requirementId: requirementId,
				domain: domain,
				exactSymbol: exactSymbol,
				role: role,
				order: 0,
				source: copySource(source),
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			}
		] : [];
		return {
			id: id,
			revision: revision,
			source: copySource(source),
			kind: selected.kind,
			receiverSemanticTypeId: selected.receiverSemanticTypeId,
			elementSemanticTypeId: selected.elementSemanticTypeId,
			resultSemanticTypeId: selected.resultSemanticTypeId,
			profileEligibility: ["metal", "portable"],
			runtimeRequirementIds: usesPrivateRuntime ? [requirementId] : [],
			runtimeUseOccurrences: occurrences,
			proofId: PROOF_ID,
			proofClaim: PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}
	#end

	/** Rejects any decision whose owner, type, symbol, or revision was changed. */
	public static function requireDecision(decision:OcamlArrayIteratorDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.receiverSemanticTypeId.length == 0
			|| decision.elementSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != (usesPrivateRuntime(decision.kind) ? 1 : 0)
			|| decision.runtimeUseOccurrences.length != (usesPrivateRuntime(decision.kind) ? 1 : 0)
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw "reflaxe.ocaml [ocaml-array-iterator:invalid-plan]: Array iterator decision has incomplete facts";
		}
		final privateRuntime = usesPrivateRuntime(decision.kind);
		final use = privateRuntime ? decision.runtimeUseOccurrences[0] : null;
		final exactSymbol = decision.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? "HxIterator.t" : privateRuntime ? "HxIterator.of_array" : "";
		final domain = decision.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? OcamlRuntimeUseDomain.TypeIdentifier : OcamlRuntimeUseDomain.ExpressionIdentifier;
		final role = decision.kind == OcamlArrayIteratorUseKind.StructuralCarrier ? "iterator-carrier" : privateRuntime ? "iterator-from-array" : "";
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final expectedRevision = revisionFor(decision.id, decision.source, decision.kind, decision.receiverSemanticTypeId, decision.elementSemanticTypeId,
			decision.resultSemanticTypeId, binding, exactSymbol, privateRuntime ? (domain : String) : "", role,
			privateRuntime ? decision.runtimeRequirementIds[0] : "");
		if (decision.revision != expectedRevision
			|| (privateRuntime
				&& (use == null
					|| use.id != decision.id + ":runtime-use:" + role
					|| use.planRevision != decision.revision
					|| use.ownerId != decision.id
					|| use.requirementId != decision.runtimeRequirementIds[0]
					|| use.domain != domain
					|| use.exactSymbol != exactSymbol
					|| use.role != role
					|| use.order != 0
					|| use.source.file != decision.source.file
					|| use.source.min != decision.source.min
					|| use.source.max != decision.source.max
					|| use.profileEligibility.join(",") != "metal,portable"
					|| use.cardinality != 1))) {
			throw 'reflaxe.ocaml [ocaml-array-iterator:stale-plan]: Array iterator decision "${decision.id}" no longer matches its sealed runtime use';
		}
	}

	static function usesPrivateRuntime(kind:OcamlArrayIteratorUseKind):Bool {
		return kind == OcamlArrayIteratorUseKind.StructuralAdapter || kind == OcamlArrayIteratorUseKind.StructuralCarrier;
	}

	#if macro
	static function select(expression:TypedExpr):Null<{
		kind:OcamlArrayIteratorUseKind,
		receiverSemanticTypeId:String,
		elementSemanticTypeId:String,
		resultSemanticTypeId:String
	}> {
		return switch (expression.expr) {
			case TCall({expr: TField(receiver, FInstance(classRef, parameters, fieldRef))}, arguments)
				if (isArrayIterator(classRef.get(), parameters, fieldRef.get(), arguments.length)):
				final element = TypeTools.toString(parameters[0]);
				{
					kind: OcamlArrayIteratorUseKind.DirectCall,
					receiverSemanticTypeId: 'Array<$element>',
					elementSemanticTypeId: element,
					resultSemanticTypeId: TypeTools.toString(expression.t)
				};
			case TField(_, FInstance(classRef, parameters, fieldRef)) if (isArrayIterator(classRef.get(), parameters, fieldRef.get(), -1)):
				final element = TypeTools.toString(parameters[0]);
				{
					kind: OcamlArrayIteratorUseKind.BoundMethod,
					receiverSemanticTypeId: 'Array<$element>',
					elementSemanticTypeId: element,
					resultSemanticTypeId: TypeTools.toString(expression.t)
				};
			case TField(receiver, FClosure(classData, fieldRef)) if (isArrayIteratorClosure(receiver, classData, fieldRef.get())):
				final elementType = arrayElementType(receiver.t);
				if (elementType == null) {
					null;
				} else {
					final element = TypeTools.toString(elementType);
					{
						kind: OcamlArrayIteratorUseKind.BoundMethod,
						receiverSemanticTypeId: 'Array<$element>',
						elementSemanticTypeId: element,
						resultSemanticTypeId: TypeTools.toString(expression.t)
					};
				}
			case TObjectDecl(_) if (iteratorElementType(expression.t) != null):
				final element = TypeTools.toString(iteratorElementType(expression.t));
				{
					kind: OcamlArrayIteratorUseKind.StructuralCarrier,
					receiverSemanticTypeId: TypeTools.toString(expression.t),
					elementSemanticTypeId: element,
					resultSemanticTypeId: TypeTools.toString(expression.t)
				};
			case _:
				null;
		};
	}

	static function isArrayIterator(classType:ClassType, parameters:Array<Type>, field:ClassField, argumentCount:Int):Bool {
		return OcamlStandardArrayCallContract.isArrayClass(classType)
			&& parameters.length == 1
			&& field.name == "iterator"
			&& (argumentCount == -1 || argumentCount == 0);
	}

	static function isArrayIteratorClosure(receiver:TypedExpr, classData:Null<{c:Ref<ClassType>, params:Array<Type>}>, field:ClassField):Bool {
		final elementType = arrayElementType(receiver.t);
		final owner = classData == null ? null : classData.c.get();
		return elementType != null && field.name == "iterator" && (owner == null || OcamlStandardArrayCallContract.isArrayClass(owner));
	}

	static function iteratorElementType(type:Type):Null<Type> {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(anonymousRef):
				final next = Lambda.find(anonymousRef.get().fields, field -> field.name == "next");
				final hasNext = Lambda.find(anonymousRef.get().fields, field -> field.name == "hasNext");
				if (next == null || hasNext == null) null; else switch [TypeTools.follow(next.type), TypeTools.follow(hasNext.type)] {
					case [TFun(nextArgs, result), TFun(hasNextArgs, hasNextResult)]
						if (nextArgs.length == 0 && hasNextArgs.length == 0 && TypeTools.toString(hasNextResult) == "Bool"):
						result;
					case _:
						null;
				};
			case _:
				null;
		};
	}

	static function arrayElementType(type:Type):Null<Type> {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, [elementType]) if (OcamlStandardArrayCallContract.isArrayClass(classRef.get())): elementType;
			case _: null;
		};
	}

	static function iterableElementType(type:Type):Null<Type> {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(anonymousRef):
				final iterator = Lambda.find(anonymousRef.get().fields, field -> field.name == "iterator");
				if (iterator == null) null; else switch (TypeTools.follow(iterator.type)) {
					case TFun(arguments, result) if (arguments.length == 0): iteratorElementType(result);
					case _: null;
				};
			case _: null;
		};
	}
	#end

	static function revisionFor(id:String, source:OcamlLoweredSourceSpan, kind:OcamlArrayIteratorUseKind, receiverType:String, elementType:String,
			resultType:String, binding:OcamlFunctionPlanBinding, exactSymbol:String, domain:String, role:String, requirementId:String):String {
		return "sha256:" + Sha256.encode([
			"ocaml-array-iterator-runtime-use-v2",
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(kind : String),
			receiverType,
			elementType,
			resultType,
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			exactSymbol,
			domain,
			role,
			requirementId
		].map(value -> value.length + ":" + value).join("|"));
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/** Request-local lookup for every iterator runtime-use decision in one root. */
class OcamlArrayIteratorPlan {
	final ordered:Array<OcamlArrayIteratorDecision>;
	final idByExpression:ObjectMap<TypedExpr, String>;
	final byId:Map<String, OcamlArrayIteratorDecision> = [];

	public function new(decisions:Array<OcamlArrayIteratorDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			OcamlArrayIteratorContract.requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-iterator:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the exact decision associated with this request-local typed node. */
	public function requireFor(expression:TypedExpr):OcamlArrayIteratorDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-array-iterator:missing-decision]: an iterator runtime reference reached syntax without a sealed source occurrence";
		final decisionId = idByExpression.get(expression);
		if (decisionId == null)
			throw "reflaxe.ocaml [ocaml-array-iterator:missing-decision]: the typed occurrence has no iterator decision identity";
		final decision = byId.get(decisionId);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-array-iterator:missing-decision]: the typed occurrence names no sealed iterator decision";
		OcamlArrayIteratorContract.requireDecision(decision);
		return copyDecision(decision);
	}

	public function decisions():Array<OcamlArrayIteratorDecision> {
		return ordered.map(copyDecision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-array-iterator:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
			}
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-array-iterator:duplicate-lookup]: iterator decision "$decisionId" is bound to more than one typed occurrence';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-array-iterator:missing-decision]: typed iterator occurrence "$decisionId" has no sealed decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-iterator:unreachable-decision]: iterator decision "${decision.id}" has no request-local typed occurrence';
	}

	public static function copyDecision(decision:OcamlArrayIteratorDecision):OcamlArrayIteratorDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			elementSemanticTypeId: decision.elementSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(use -> {
				id: use.id,
				planRevision: use.planRevision,
				ownerId: use.ownerId,
				requirementId: use.requirementId,
				domain: use.domain,
				exactSymbol: use.exactSymbol,
				role: use.role,
				order: use.order,
				source: {
					file: use.source.file,
					min: use.source.min,
					max: use.source.max
				},
				profileEligibility: use.profileEligibility.copy(),
				cardinality: use.cardinality
			}),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}
}

/** Builds the complete Array-iterator runtime-use inventory before syntax. */
class OcamlArrayIteratorPlanner {
	#if macro
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlArrayIteratorPlan {
		final decisions:Array<OcamlArrayIteratorDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();
		var ordinal = 0;

		function add(expression:TypedExpr):Bool {
			final decision = OcamlArrayIteratorContract.seal(expression, binding, ordinal);
			if (decision == null)
				return false;
			ordinal++;
			decisions.push(decision);
			lookup.set(expression, decision.id);
			return true;
		}

		function addStructuralAdapter(expression:TypedExpr, expectedType:Type):Bool {
			final decision = OcamlArrayIteratorContract.sealStructuralAdapter(expression, expectedType, binding, ordinal);
			if (decision == null)
				return false;
			ordinal++;
			decisions.push(decision);
			lookup.set(expression, decision.id);
			return true;
		}

		function expectedArguments(callee:TypedExpr):Null<Array<{name:String, opt:Bool, t:Type}>> {
			return switch (TypeTools.follow(callee.t)) {
				case TFun(arguments, _): arguments;
				case _: null;
			};
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					// Each nested function has a different body revision. Its own planner
					// seals any iterator decisions when that function becomes active.
				case TCall(callee = {expr: TField(receiver, FInstance(_, _, _))}, arguments) if (add(expression)):
					visit(receiver);
					final expected = expectedArguments(callee);
					for (index in 0...arguments.length) {
						if (expected != null && index < expected.length)
							addStructuralAdapter(arguments[index], expected[index].t);
						visit(arguments[index]);
					}
				case TCall(callee, arguments):
					final expected = expectedArguments(callee);
					visit(callee);
					for (index in 0...arguments.length) {
						if (expected != null && index < expected.length)
							addStructuralAdapter(arguments[index], expected[index].t);
						visit(arguments[index]);
					}
				case TVar(local, initializer) if (initializer != null):
					addStructuralAdapter(initializer, local.t);
					visit(initializer);
				case TBinop(OpAssign, left, right):
					visit(left);
					addStructuralAdapter(right, left.t);
					visit(right);
				case TBinop(OpAssignOp(_), left, right):
					visit(left);
					visit(right);
				case TField(receiver, FInstance(_, _, _)) if (add(expression)):
					visit(receiver);
				case TField(receiver, FClosure(_, _)) if (add(expression)):
					visit(receiver);
				case TObjectDecl(fields) if (add(expression)):
					for (field in fields)
						visit(field.expr);
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(root);
		return new OcamlArrayIteratorPlan(decisions, lookup);
	}
	#end
}
#end
