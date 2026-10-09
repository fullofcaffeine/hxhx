import haxe.ds.StringMap;
import TyInferenceTerm;

/** Already aligned source operands retain their inference identities across a member call. */
private typedef MemberInputSources = {
	final expressions:Array<HxExpr>;
	final order:TyMethodArgumentOrder;
}

/** One source occurrence retains its variables through later local constraints. */
private typedef InferredOccurrence = {
	final expression:HxExpr;
	final term:TyInferenceTerm;
	final ?methodSignature:TyFunSig;
	final ?sourceFingerprint:String;
	final ?callDeclarationKey:String;
}

/** A direct call retains its callable parameters as well as the result shared with local uses. */
private typedef InferredDirectCall = {
	final expression:HxExpr;
	final declaration:TyDeclarationInfo;
	final callable:TyInferenceTerm;
}

/** Keep source and term identities until all calls through a stored generic value have constrained it. */
private typedef InferredCapturedCall = {
	final callee:HxExpr;
	final callable:TyInferenceTerm;
	final arguments:Array<HxExpr>;
	final terms:Array<Null<TyInferenceTerm>>;
	final types:Array<TyType>;
	final index:TyperIndex;
	final ?selectedSlots:Array<TyCallAlignment.TyCallArgumentSlot>;
}

/**
	Keep expression constraints in the function's mutable inference phase.
	Exact source objects identify allocations and method captures; lexical identities
	identify aliases. Replay reads solved snapshots from this same owner.
 */
class TyFunctionInference {
	final owner:String;
	var solver:TyInferenceSolver;
	var occurrences:Array<InferredOccurrence> = [];
	var directCalls:Array<InferredDirectCall> = [];
	var receiverCalls:Array<TyReceiverCallContext> = [];
	var capturedCalls:Array<InferredCapturedCall> = [];
	var locals:StringMap<TyInferenceTerm> = new StringMap();
	var speculativeReplay:Bool = false;
	var callbackArguments:Array<{final callee:HxExpr; final binding:TyCallArgumentBinding;}> = [];
	var sourceFunctions:Array<{
		final source:HxExpr;
		final fingerprint:String;
		final type:TyType;
		final arguments:Array<TyInferenceTerm>;
		final result:TyInferenceTerm;
	}> = [];

	/** Preserve invocation-only evidence before later source uses solve the receiver. */
	public function recordReceiverCall(source:HxExpr, declaration:TyDeclarationInfo, parameters:Array<Null<TyType>>):Void {
		for (entry in receiverCalls)
			if (entry.owns(source))
				return;
		if (solver.isSealed())
			throw "receiver call context is absent from sealed inference";
		receiverCalls.push(new TyReceiverCallContext(source, declaration, parameters));
	}

	/** A member result shares the receiver's type variables even when it allocates a different runtime value. */
	public function recordReceiverResult(source:HxExpr, receiver:HxExpr, declaration:TyDeclarationInfo, environment:TyFunctionEnv, index:TyperIndex):Void {
		if (declaration.getIsStatic() || declaration.getTypeParameterIds().length > 0)
			return;
		for (entry in occurrences)
			if (entry.expression == source
				&& entry.callDeclarationKey != null
				&& entry.callDeclarationKey != declaration.getIdentity().getCanonicalKey())
				throw "receiver result changed its selected declaration";
		if (occurrence(source) != null)
			return;
		final original = sourceTerm(receiver, environment);
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		if (original == null || owner == null)
			return;
		final parameters = TyNominalApplication.parameterIds(owner);
		final result = declaration.getSignature().getReturnType();
		if (result.hasUnknownComponent()
			|| TyTypeSubstitution.parameterIdentities(result).filter(parameter -> parameters.filter(owned -> owned.equals(parameter)).length > 0).length == 0)
			return;
		final viewed = TyInferenceNominalContext.view(index, original, TyType.nominal(owner.getIdentity(), []));
		final arguments = switch viewed {
			case Nominal(identity, arguments) if (identity.equals(owner.getIdentity())): arguments;
			case _: return;
		};
		if (parameters.length != arguments.length)
			throw "receiver result lost its owner arguments";
		if (solver.isSealed())
			throw "receiver result is absent from sealed inference";
		final bindings = new StringMap<TyInferenceTerm>();
		for (i in 0...parameters.length)
			bindings.set(parameters[i].getCanonicalKey(), arguments[i]);
		occurrences.push({
			expression: source,
			term: TyInferenceSubstitution.apply(result, bindings),
			sourceFingerprint: TypedBodyFingerprint.exactExpression(source),
			callDeclarationKey: declaration.getIdentity().getCanonicalKey()
		});
	}

	/** A different occurrence receives no permission from an earlier call with the same spelling. */
	public function receiverCallParameters(source:HxExpr, declaration:TyDeclarationInfo, parameters:Array<TyType>):Array<TyType> {
		for (entry in receiverCalls)
			if (entry.owns(source))
				return entry.apply(source, declaration, parameters);
		return parameters;
	}

	/** Sealed replay reads the signature inferred for this exact authored function occurrence. */
	public function sourceFunctionType(source:HxExpr):Null<TyType> {
		if (!solver.isSealed())
			return null;
		for (entry in sourceFunctions)
			if (entry.source == source) {
				if (entry.fingerprint != TypedBodyFingerprint.forExpression(source))
					throw "source function changed after parameter inference";
				// Body parameters contain Rest<T>; the callable accepts individual T
				// operands. Reuse the source-signature owner to preserve that distinction.
				return switch source {
					case ESourceFunction(facts, _, _, _):
						TyCallableSignature.sourceFunctionType(facts.getArguments(), facts.getSignature(), entry.arguments.map(solver.published),
							solver.published(entry.result));
					case _: throw "source function signature requires its authored function occurrence";
				};
			}
		return null;
	}

	/**
		Unresolved returns share the function's result constraints. Keep each
		return's lexical term so a later callback annotation reaches every path.
		Commit together: a conflicting return must not partially bind its peers.
	 */
	public function sourceFunctionResult(returns:Array<TyInferenceTerm>):Null<TyInferenceTerm> {
		if (returns.length == 0)
			return null;
		final candidate = solver.fork();
		final result = returns[0];
		for (index in 1...returns.length)
			if (!candidate.constrain(result, returns[index]))
				throw "source function returns have incompatible inference constraints";
		solver.commit(candidate);
		return result;
	}

	/** Retain parameter and result terms so replay observes constraints supplied after an earlier body call. */
	public function recordSourceFunction(source:HxExpr, type:TyType, parameters:Array<TySymbol>, ?result:TyInferenceTerm):Void {
		if (solver.isSealed())
			throw "source function signature is absent from sealed inference";
		if (!type.isFunction())
			throw "source function inference requires a callable type";
		if (parameters.length != type.getFunctionArguments().length)
			throw "source function inference requires one binding per parameter";
		final fingerprint = TypedBodyFingerprint.forExpression(source);
		final arguments = [
			for (parameter in parameters) {
				final term = locals.get(parameter.getIdentity().getCanonicalKey());
				term == null ? TyInferenceSolver.fromType(parameter.getType()) : term;
			}
		];
		for (index in 0...sourceFunctions.length)
			if (sourceFunctions[index].source == source) {
				sourceFunctions[index] = {
					source: source,
					fingerprint: fingerprint,
					type: type,
					arguments: arguments,
					result: result == null ? TyInferenceSolver.fromType(type.getFunctionReturn()) : result
				};
				return;
			}
		sourceFunctions.push({
			source: source,
			fingerprint: fingerprint,
			type: type,
			arguments: arguments,
			result: result == null ? TyInferenceSolver.fromType(type.getFunctionReturn()) : result
		});
	}

	/** Exact source occurrence ownership keeps optional selection stable during typed-body replay. */
	public function callbackBinding(callee:HxExpr):Null<TyCallArgumentBinding> {
		for (entry in callbackArguments)
			if (entry.callee == callee)
				return entry.binding;
		return null;
	}

	/**
		Retain a selected callback's slots until all local constraints are complete.
		The contextual preview can include deferred Dynamic defaults, so its types
		are not a final binding. Publication reads the original terms after sealing
		and checks the same slots without repeating optional-argument selection.
	 */
	@:allow(TyCallbackArgumentContext)
	function recordCallbackAlignment(callee:HxExpr, signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>,
			slots:Array<TyCallAlignment.TyCallArgumentSlot>, environment:TyFunctionEnv, index:TyperIndex):Void {
		if (solver.isSealed())
			throw "callback alignment is absent from sealed inference";
		// An untyped or hint-free cast callable shares its result variable with later uses.
		// Freezing its current Unknown preview here would discard those constraints.
		final original = sourceTerm(callee, environment);
		final callable = original != null
			&& solver.isInferredCallableResult(original) ? original : TyInferenceSolver.fromType(signature.getFunctionType());
		capturedCalls = capturedCalls.filter(call -> call.callee != callee);
		capturedCalls.push({
			callee: callee,
			callable: callable,
			arguments: arguments.copy(),
			terms: [
				for (argument in arguments)
					sourceTerm(switch argument {
						case ECall(EIdent("__hxhx_spread"), [container]): container;
						case _: argument;
					}, environment)
			],
			types: types.copy(),
			index: index,
			selectedSlots: [
				for (slot in slots)
					switch slot {
						case RestElements(sources):
							RestElements(sources.copy());
						case _:
							slot;
					}
			]
		});
	}

	public function new(owner:String) {
		this.owner = owner;
		solver = new TyInferenceSolver(owner);
	}

	/** Register only source arguments whose annotation was omitted, before aliases can capture them. */
	public function registerOmittedParameter(symbol:TySymbol):Void {
		if ((symbol.getKind() != Parameter && symbol.getKind() != LambdaParameter) || !symbol.getType().unwrapNull().isUnknown())
			throw "omitted parameter registration requires an unknown declaration input";
		final key = symbol.getIdentity().getCanonicalKey();
		if (locals.exists(key))
			throw "omitted parameter was registered twice";
		final inferred = solver.freshOmittedParameter();
		locals.set(key, symbol.getType().isNullable() ? TyInferenceTerm.Nullable(inferred) : inferred);
	}

	/** Speculative replay shares sealed solutions but owns aliases for its temporary declarations. */
	public function fork():TyFunctionInference {
		final candidate = new TyFunctionInference(owner);
		candidate.solver = solver.isSealed() ? solver : solver.fork();
		candidate.speculativeReplay = solver.isSealed();
		candidate.occurrences = occurrences.copy();
		candidate.directCalls = directCalls.copy();
		candidate.receiverCalls = receiverCalls.copy();
		candidate.capturedCalls = capturedCalls.copy();
		candidate.callbackArguments = callbackArguments.copy();
		candidate.sourceFunctions = sourceFunctions.copy();
		for (key => value in locals)
			candidate.locals.set(key, value);
		return candidate;
	}

	function occurrence(expression:HxExpr):Null<TyInferenceTerm> {
		for (entry in occurrences)
			if (entry.expression == expression) {
				if (entry.sourceFingerprint != null && entry.sourceFingerprint != TypedBodyFingerprint.exactExpression(expression))
					throw "inferred result source changed during inference";
				return entry.term;
			}
		return null;
	}

	/** Retain one untyped result across contextual typing, aliases, and sealed body replay. */
	public function untypedResult(expression:HxExpr):TyType {
		var term = occurrence(expression);
		if (term == null) {
			if (solver.isSealed())
				throw "untyped result is absent from sealed inference";
			term = solver.freshUntypedResult();
			occurrences.push({expression: expression, term: term});
		}
		return solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	/** Retain a cast's result through aliases and field requirements without constraining its operand. */
	public function uncheckedCastResult(expression:HxExpr):TyType {
		if (!expression.match(ECast(_, "")))
			throw "unchecked cast inference requires an authored hint-free cast";
		var term = occurrence(expression);
		if (term == null) {
			if (solver.isSealed())
				throw "unchecked cast result is absent from sealed inference";
			term = solver.freshUncheckedCastResult();
			occurrences.push({expression: expression, term: term, sourceFingerprint: TypedBodyFingerprint.exactExpression(expression)});
		}
		return solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	/** Resolve only a cast-owned field; ordinary missing fields gain no call permission. */
	public function isUncheckedCallable(expression:HxExpr, environment:TyFunctionEnv):Bool {
		final term = sourceTerm(expression, environment);
		return term != null && solver.isUncheckedCastResult(term);
	}

	/** Infer an untyped or hint-free cast callable from checked operands without revisiting their expressions. */
	public function constrainInferredCallable(expression:HxExpr, arguments:Array<HxExpr>, actual:Array<TyType>, environment:TyFunctionEnv):Void {
		// An unresolved host name under untyped has no declaration shared by its
		// call occurrences. A stored local or an explicit wrapper does have an
		// inference identity, so its calls must retain one consistent signature.
		function unresolvedHostName(value:HxExpr):Bool {
			return switch value {
				case EIdent(name): environment.resolveSymbol(name) == null;
				case EParenthesized(inner, _) | EPrivateAccess(inner, _): unresolvedHostName(inner);
				case _: false;
			};
		}
		if (unresolvedHostName(expression))
			return;
		final term = sourceTerm(expression, environment);
		if (solver.isSealed() || term == null || !solver.isInferredCallableResult(term) || !solver.preview(term).isUnknown())
			return;
		if (arguments.filter(argument -> argument.match(ECall(EIdent("__hxhx_spread"), [_]))).length > 0)
			return;
		final inputs = [
			for (index in 0...arguments.length) {
				final existing = sourceTerm(arguments[index], environment);
				existing == null ? TyInferenceSolver.fromType(actual[index]) : existing;
			}
		];
		final candidate = solver.fork();
		final result = solver.isUncheckedCastResult(term) ? candidate.freshUncheckedCastResult() : candidate.freshUntypedResult();
		if (!candidate.constrain(term, Function(inputs, result, TyType.functionType(actual, TyType.unknown()))))
			throw "unchecked callable conflicts with its inferred shape";
		solver.commit(candidate);
	}

	/** Query the sealed input origin, including retained aliases, without inventing evidence for an arbitrary Unknown value. */
	public function isUnresolvedInput(expression:HxExpr, environment:TyFunctionEnv):Bool {
		if (!solver.isSealed())
			return false;
		final term = sourceTerm(expression, environment);
		return term != null && solver.isUnresolvedInput(term);
	}

	/** Resolve initializer provenance before its new local becomes visible. */
	public function sourceTerm(expression:HxExpr, environment:TyFunctionEnv):Null<TyInferenceTerm> {
		return switch expression {
			case ESourceFunction(_, _, _, _):
				var term:Null<TyInferenceTerm> = null;
				for (entry in sourceFunctions)
					if (entry.source == expression) {
						if (entry.fingerprint != TypedBodyFingerprint.forExpression(expression))
							throw "source function changed during inference";
						final parameters = entry.type.getFunctionParameters();
						final arguments = [
							for (index in 0...entry.arguments.length) {
								final argument = entry.arguments[index];
								if (!parameters[index].isRest) argument; else switch argument {
									case Nominal(_, [element]):
										element;
									case _:
										throw "source rest parameter lost its inferred container";
								};
							}
						];
						term = Function(arguments, entry.result, entry.type);
						break;
					}
				term;
			case ECall(callee, _):
				final recorded = occurrence(expression);
				final callable = recorded == null ? sourceTerm(callee, environment) : null;
				recorded != null ? recorded : callable == null ? null : solver.inferredCallResult(callable);
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): sourceTerm(inner, environment);
			case EIdent(name):
				final symbol = environment.resolveSymbol(name);
				symbol == null ? occurrence(expression) : locals.get(symbol.getIdentity().getCanonicalKey());
			case EField(receiver, name):
				final parent = sourceTerm(receiver, environment);
				final projected = parent == null ? null : solver.field(parent, name);
				projected == null ? occurrence(expression) : projected;
			case _: occurrence(expression);
		};
	}

	/** Written type arguments remain authoritative; only genuinely omitted arguments allocate variables. */
	public function construct(expression:HxExpr, type:TyType, arity:Int):TyType {
		if (arity == 0 || type.getTypeArguments().length > 0 || type.getNominalIdentity() == null)
			return type;
		var term = occurrence(expression);
		if (term == null) {
			if (solver.isSealed())
				throw "constructor occurrence is absent from sealed inference";
			term = Nominal(type.getNominalIdentity(), [for (_ in 0...arity) solver.fresh()]);
			occurrences.push({expression: expression, term: term});
		}
		return solver.isSealed() ? solver.requireSolved(term) : solver.preview(term);
	}

	/** Empty and null-only arrays retain an element variable shared by later aliases and uses. */
	public function inferredArray(expression:HxExpr, identity:TyNominalTypeId, nullableElement:Bool = false):TyType {
		var term = occurrence(expression);
		if (term == null) {
			if (solver.isSealed())
				throw "empty array occurrence is absent from sealed inference";
			final element = solver.freshEmptyArrayElement();
			term = Nominal(identity, [nullableElement ? Nullable(element) : element]);
			occurrences.push({expression: expression, term: term});
		}
		return solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	/** Each generic method capture owns fresh variables; aliases keep the same function term. */
	public function captureMethod(expression:HxExpr, type:TyType, parameters:Array<TyTypeParameterId>, signature:TyFunSig):TyType {
		if (parameters.length == 0)
			return type;
		var captured = occurrence(expression);
		if (captured == null) {
			if (solver.isSealed())
				throw "method capture is absent from sealed inference in " + owner + " for " + signature.getName();
			captured = instantiateMethod(type, parameters);
			occurrences.push({expression: expression, term: captured, methodSignature: signature});
		}
		return solver.isSealed() ? solver.requireSolved(captured) : solver.preview(captured);
	}

	/** Allocate only binders still present in the applied callable, sharing each binder inside this one occurrence. */
	function instantiateMethod(type:TyType, parameters:Array<TyTypeParameterId>):TyInferenceTerm {
		final bindings = new StringMap<TyInferenceTerm>();
		function term(value:TyType):TyInferenceTerm {
			final identity = value.getTypeParameterIdentity();
			if (identity != null)
				for (parameter in parameters)
					if (parameter.equals(identity)) {
						final key = parameter.getCanonicalKey();
						if (!bindings.exists(key))
							bindings.set(key, solver.freshMethodParameter(parameter));
						return bindings.get(key);
					}
			if (value.isNullable())
				return Nullable(term(value.unwrapNull()));
			if (value.isFunction())
				return Function(value.getFunctionArguments().map(term), term(value.getFunctionReturn()), value);
			if (value.isAnonymous())
				return Structure(value.getAnonymousFieldTypes().map(term), value);
			final owner = value.getNominalIdentity();
			return owner == null ? Known(value) : Nominal(owner, value.getTypeArguments().map(term));
		}
		return term(type);
	}

	/** Register a selected call once; result annotations and later local uses constrain its same result term. */
	public function inferDirectCall(input:{
		expression:HxExpr,
		declaration:TyDeclarationInfo,
		callable:TyType,
		signature:TyFunSig,
		order:TyMethodArgumentOrder,
		arguments:Array<HxExpr>,
		actual:Array<TyType>,
		environment:TyFunctionEnv,
		index:TyperIndex,
		accepts:(TyType, TyType) -> Bool
	}):TyType {
		final expression = input.expression;
		final declaration = input.declaration;
		if (directCallType(expression, declaration) == null) {
			if (solver.isSealed())
				throw "direct generic call is absent from sealed inference";
			final candidate = fork();
			final instantiated = candidate.instantiateMethod(input.callable, declaration.getTypeParameterIds());
			if (input.arguments.length != input.actual.length)
				throw "direct generic call requires one type per source operand";
			final terms = [
				for (offset in 0...input.arguments.length) {
					final argument = input.arguments[offset];
					final term = candidate.sourceTerm(switch argument {
						case ECall(EIdent("__hxhx_spread"), [container]): container;
						case _: argument;
					}, input.environment);
					final actual = input.actual[offset];
					// Ordinary written values need no inference occurrence, but their
					// known types still constrain the selected method's parameters.
					term == null
				&& !actual.hasUnknownComponent() ? TyInferenceSolver.fromType(actual) : term;
				}
			];
			if (!TyDirectGenericCallConstraints.constrain({
				solver: candidate.solver,
				callable: instantiated,
				signature: input.signature,
				order: input.order,
				arguments: input.arguments,
				terms: terms,
				index: input.index,
				accepts: input.accepts
			}))
				throw "selected direct generic call has conflicting operand constraints";
			switch instantiated {
				case Function(_, result, _):
					solver.commit(candidate.solver);
					directCalls.push({expression: expression, declaration: declaration, callable: instantiated});
					occurrences.push({expression: expression, term: result});
				case _:
					throw "direct generic call requires a callable type";
			}
		}
		return directCallType(expression, declaration).getFunctionReturn();
	}

	/** Replay must read the exact selected declaration's solved callable rather than re-infer null arguments. */
	public function directCallType(expression:HxExpr, declaration:TyDeclarationInfo):Null<TyType> {
		for (entry in directCalls)
			if (entry.expression == expression) {
				if (entry.declaration.getIdentity().getCanonicalKey() != declaration.getIdentity().getCanonicalKey())
					throw "direct generic call changed its selected declaration";
				if (!solver.isSealed())
					return solver.preview(entry.callable);
				try {
					return solver.requireSolved(entry.callable);
				} catch (message:String) {
					throw message + " while replaying " + declaration.getIdentity().getCanonicalKey() + " in " + owner;
				}
			}
		return null;
	}

	/** Argument constraints apply to the captured function, so later calls and aliases see the same solution. */
	public function callCaptured(callee:HxExpr, arguments:Array<HxExpr>, actual:Array<TyType>, environment:TyFunctionEnv, index:TyperIndex,
			accepts:(TyType, TyType) -> Bool):Null<TyType> {
		final captured = sourceTerm(callee, environment);
		if (captured == null)
			return null;
		// Aliases retain this exact term, including the selected declaration's
		// omission rules, even after inference has solved its parameter types.
		var signature:Null<TyFunSig> = null;
		for (entry in occurrences)
			if (entry.term == captured && entry.methodSignature != null) {
				signature = entry.methodSignature;
				break;
			}
		final optional = signature == null ? [] : signature.getArgOptional();
		return switch solver.inferredCallable(captured) {
			case Function(parameters, result, shape):
				// Written omission and rest rules belong to callback alignment. Only
				// inferred fixed-arity calls use the deferred positional constraints here.
				if (signature == null
					&& shape.getFunctionParameters().filter(parameter -> parameter.isOptional || parameter.isRest).length > 0)
					return null;
				if (actual.length > parameters.length
					|| (signature == null ? parameters.length != actual.length : !signature.acceptsArity(actual.length)))
					throw "captured callback argument count differs";
				if (!solver.isSealed()) {
					final candidate = solver.fork();
					for (index in 0...actual.length) {
						if (index < optional.length && optional[index] && actual[index].isNullLiteral())
							continue;
						final argument = sourceTerm(arguments[index], environment);
						if (argument == null && (actual[index].isDynamic() || actual[index].hasUnknownComponent()))
							continue;
						// Once inference has fixed a parameter, ordinary call compatibility
						// decides admissible subtypes and conversions without rebinding it.
						final expected = candidate.preview(parameters[index]);
						final supplied = argument == null ? actual[index] : candidate.preview(argument);
						if (!expected.hasUnknownComponent() && !supplied.hasUnknownComponent()) {
							if (!accepts(expected, supplied))
								throw "captured callback argument conflicts with its inferred type";
							continue;
						}
						if (!candidate.constrain(parameters[index], argument == null ? TyInferenceSolver.fromType(actual[index]) : argument))
							throw "captured callback argument conflicts with its inferred type";
					}
					// Invoking an explicitly untyped or cast callable requires runtime
					// carriers for its remaining holes. Defer these defaults until seal
					// so later calls still constrain the same inputs and result.
					if (candidate.isInferredCallableResult(captured))
						candidate.observeDynamicUse(captured);
					solver.commit(candidate);
					// Publishing now would freeze a temporary type: a later alias use can
					// still solve shared variables. Keep the source-owned terms until seal.
					capturedCalls = capturedCalls.filter(call -> call.callee != callee);
					capturedCalls.push({
						callee: callee,
						callable: captured,
						arguments: arguments.copy(),
						terms: [for (argument in arguments) sourceTerm(argument, environment)],
						types: actual.copy(),
						index: index
					});
				}
				solver.isSealed() ? solver.published(result) : solver.preview(result);
			case _: null;
		};
	}

	/**
		Infer an allocation from its already-typed operands before local publication.
		Every explicit constructor gets isolated constraints and ordinary overload
		scoring. Commit only a unique best candidate; argument traversal is never
		repeated during selection. Explicit owner arguments need no inference here.
	 */
	public function constrainConstructor(input:{
		expression:HxExpr,
		provider:TyNominalInfo,
		argumentTypes:Array<TyType>,
		environment:TyFunctionEnv,
		index:TyperIndex,
		score:(TyFunSig, Array<TyTypeParameterId>) -> Int
	}):Bool {
		final term = occurrence(input.expression);
		if (solver.isSealed() || term == null || input.provider == null)
			return true;
		final candidates = input.provider.instanceMethodCandidates("new");
		if (candidates.length == 0)
			return true;
		var best:Null<TyFunctionInference> = null;
		final selectedGroups = new Array<TyDeclarationInfo>();
		var bestScore = -1;
		var tied = false;
		for (signature in candidates) {
			final declaration = input.provider.declarationForSignature(signature);
			if (declaration == null || declaration.getIsStatic() || !declaration.getOwner().equals(input.provider.getIdentity()))
				continue;
			// Omitted constructor annotations can still expose owner binders through
			// checked field assignments. Use those facts before solving the allocation.
			final checkedSignature = input.index.getMethodBodyResults().signature(declaration);
			final candidate = fork();
			if (!candidate.constrainMember(input.expression, input.provider, checkedSignature, input.argumentTypes, input.environment, input.index))
				continue;
			final applied = TyNominalApplication.signature(input.index, input.provider, candidate.solver.preview(term), signature);
			final score = input.score(applied, TyMethodGenericBinding.inferableTypeParameters(declaration));
			if (score < 0)
				continue;
			if (!TyMetadataOverloadOrder.accept(declaration, selectedGroups))
				continue;
			if (score > bestScore) {
				best = candidate;
				bestScore = score;
				tied = false;
			} else if (score == bestScore) {
				tied = true;
			}
		}
		if (best == null || tied)
			return false;
		solver.commit(best.solver);
		return true;
	}

	/** Find an unannotated lexical parameter; explicit Dynamic and unresolved written names are not inference holes. */
	function contextParameter(expression:HxExpr, environment:TyFunctionEnv):Null<TySymbol> {
		return switch expression {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): contextParameter(inner, environment);
			case EIdent(name): final symbol = environment.resolveSymbol(name); symbol != null && symbol.getKind() == LambdaParameter && symbol.getType()
					.isUnknown() ? symbol : null;
			case _: null;
		};
	}

	/** A body use may supply the first concrete evidence for an unannotated parameter. */
	public function canReceiveContext(expression:HxExpr, environment:TyFunctionEnv):Bool {
		return sourceTerm(expression, environment) != null || contextParameter(expression, environment) != null;
	}

	/** Bind only a selected complete context; publish new parameter facts only after the entire transaction succeeds. */
	public function constrain(expressions:Array<HxExpr>, expected:Array<TyType>, environment:TyFunctionEnv, semanticIndex:TyperIndex):Bool {
		if (solver.isSealed())
			return true;
		final candidate = solver.fork();
		final parameters = new StringMap<TyInferenceTerm>();
		var collections:Null<haxe.ds.IntMap<TyInferenceTerm>> = null;
		for (index in 0...expressions.length) {
			if (index >= expected.length || expected[index].hasUnknownComponent())
				continue;
			var term = sourceTerm(expressions[index], environment);
			final collection = TypedCollectionExpectation.select(expressions[index], expected[index]);
			if (collection != null
				&& term != null
				&& candidate.preview(term).hasUnknownComponent()
				&& !TyMethodGenericBinding.sameTypeConstructor(candidate.preview(term), collection)) {
				// Selection may give [] its first Map context after an initial Array
				// preview. Only the literal can change constructor; a local alias cannot.
				final occurrenceIndex = emptyLiteralOccurrence(expressions[index]);
				if (occurrenceIndex >= 0) {
					term = TyInferenceSolver.fromType(collection);
					if (collections == null)
						collections = new haxe.ds.IntMap();
					collections.set(occurrenceIndex, term);
				}
			}
			if (expected[index].isDynamic()) {
				// A Dynamic destination accepts the value without supplying a type
				// for an omitted parameter. Explicitly untyped results still need
				// their deferred carrier when consumed through a Dynamic boundary.
				if (term != null)
					candidate.observeDynamicUse(term, true);
				continue;
			}
			if (term == null) {
				final parameter = contextParameter(expressions[index], environment);
				if (parameter != null) {
					final identity = parameter.getIdentity().getCanonicalKey();
					term = parameters.get(identity);
					if (term == null) {
						parameters.set(identity, TyInferenceSolver.fromType(expected[index]));
						continue;
					}
				}
			}
			if (term != null) {
				final context = expected[index].unwrapNull();
				// Assignment context constrains the value inside a nullable input. Keep
				// its wrapper on the stored term so body publication still admits null.
				final value = switch term {
					case Nullable(inner): inner;
					case _: term;
				};
				final projected = TyInferenceNominalContext.view(semanticIndex, value, context);
				// Callable assignment uses the existing parameter/result compatibility
				// rules, including optional inputs, rather than exact solver equality.
				final direct = context.isAnonymous()
					|| context.isFunction() ? TyStructuralConstraint.constrain(semanticIndex, candidate, value,
						context) : projected != null
						&& TyStructuralConstraint.constrainNominalAssignment(semanticIndex, candidate, projected, context);
				if (!direct
					&& !TyInferenceAbstractDestination.constrain(semanticIndex, candidate, value, context)
					&& TyAbstractMethodConversion.constrain(semanticIndex, candidate, value, context) == null)
					return false;
			}
		}
		solver.commit(candidate);
		if (collections != null)
			for (index => term in collections)
				occurrences[index] = {expression: occurrences[index].expression, term: term};
		for (identity => term in parameters)
			locals.set(identity, term);
		return true;
	}

	/** Context can choose an empty literal's collection kind before it becomes a stored value. */
	function emptyLiteralOccurrence(expression:HxExpr):Int {
		return switch expression {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): emptyLiteralOccurrence(inner);
			case EArrayDecl(values) if (values.length == 0):
				var found = -1;
				for (index in 0...occurrences.length)
					if (occurrences[index].expression == expression)
						found = index;
				found;
			case _: -1;
		};
	}

	/**
		Constrain a generic receiver from one candidate's supplied member arguments.
		The transaction changes nothing on failure. Call ranking uses a fork of this
		owner and repeats the successful constraint only for its selected declaration.
	 */
	public function constrainMember(receiver:HxExpr, provider:TyNominalInfo, signature:TyFunSig, actual:Array<TyType>, environment:TyFunctionEnv,
			index:TyperIndex, ?supplied:MemberInputSources):Bool {
		if (solver.isSealed())
			return true;
		final receiverTerm = sourceTerm(receiver, environment);
		if (receiverTerm == null)
			return true;
		final arguments = switch receiverTerm {
			case Nominal(identity, arguments) if (identity.equals(provider.getIdentity())): arguments;
			case _: return true;
		};
		final parameters = TyNominalApplication.parameterIds(provider);
		if (parameters.length != arguments.length)
			throw "generic receiver inference has inconsistent owner arity";
		final bindings = new StringMap<TyInferenceTerm>();
		for (index in 0...parameters.length)
			bindings.set(parameters[index].getCanonicalKey(), arguments[index]);
		function term(type:TyType):TyInferenceTerm
			return TyInferenceSubstitution.apply(type, bindings);

		// A later receiver annotation must also solve an earlier open operand.
		// Preserve its original term instead of copying an incomplete type preview.
		// Resolve fields before forking because that lookup can add a requirement.
		final sourceTerms:Array<Null<TyInferenceTerm>> = supplied == null ? [] : [
			for (slot in supplied.order.getSlots())
				switch slot {
					case Supplied(source):
						sourceTerm(supplied.expressions[source], environment);
					case _:
						null;
				}
		];
		final candidate = solver.fork();
		final expected = signature.getArgs();
		for (argumentIndex in 0...actual.length) {
			if (argumentIndex >= expected.length || actual[argumentIndex].isNullLiteral() || actual[argumentIndex].isDynamic())
				continue;
			final referenced = TyTypeSubstitution.parameterIdentities(expected[argumentIndex]);
			if (referenced.length == 0 || referenced.filter(parameter -> bindings.exists(parameter.getCanonicalKey())).length == 0)
				continue;
			// A method-local parameter needs the separate method-generic binding pass.
			if (referenced.filter(parameter -> !bindings.exists(parameter.getCanonicalKey())).length > 0)
				continue;
			final expectedTerm = term(expected[argumentIndex].unwrapNull());
			// A complete context is checked by ordinary overload compatibility. It
			// may accept a conversion such as Int to Float without rebinding T.
			if (!candidate.preview(expectedTerm).hasUnknownComponent())
				continue;
			if (actual[argumentIndex].hasUnknownComponent()) {
				final original = argumentIndex < sourceTerms.length ? sourceTerms[argumentIndex] : null;
				if (original == null)
					continue;
				final projected = TyInferenceNominalContext.view(index, original, candidate.preview(expectedTerm));
				if (projected == null || !candidate.constrainNullableInput(expectedTerm, projected))
					return false;
				continue;
			}
			final actualType = actual[argumentIndex].unwrapNull();
			final expectedIdentity = expected[argumentIndex].unwrapNull().getNominalIdentity();
			final ancestor = expectedIdentity == null ? null : TyNominalAncestor.view(index, actualType, expectedIdentity);
			if (!candidate.constrainNullableInput(expectedTerm, TyInferenceSolver.fromType(ancestor == null ? actualType : ancestor))
				&& !TyInferenceAbstractInput.constrain({
					solver: candidate,
					expected: expected[argumentIndex].unwrapNull(),
					actual: actualType,
					term: term,
					index: index
				}))
				return false;
		}
		solver.commit(candidate);
		return true;
	}

	/** An alias points at its initializer's term, not a copy of its current incomplete preview. */
	public function recordLocal(symbol:TySymbol, term:TyInferenceTerm):Void {
		if (solver.isSealed()) {
			// A speculative resolver may allocate temporary declarations in its own
			// environment. Only that fork may add aliases to already sealed terms.
			final recorded = locals.get(symbol.getIdentity().getCanonicalKey());
			if (recorded == null && speculativeReplay) {
				solver.published(term);
				locals.set(symbol.getIdentity().getCanonicalKey(), term);
				return;
			}
			if (recorded == null || solver.published(recorded).getSemanticKey() != solver.published(term).getSemanticKey())
				throw "local initializer differs from sealed function inference in "
					+ owner
					+ " at "
					+ symbol.getIdentity().getCanonicalKey()
					+ "; recorded="
					+ (recorded == null ? "absent" : solver.published(recorded).getSemanticKey())
					+ "; replay="
					+ solver.published(term).getSemanticKey();
			return;
		}
		if (term != null)
			locals.set(symbol.getIdentity().getCanonicalKey(), term);
	}

	/** Re-read solved argument facts without evaluating its inference traversal again. */
	public function expressionType(expression:HxExpr, fallback:TyType, environment:TyFunctionEnv):TyType {
		final term = sourceTerm(expression, environment);
		return term == null ? fallback : solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	/** Candidate checking may observe deferred defaults, but source typing continues to use the unsolved term. */
	@:allow(TyCallbackArgumentContext)
	function callbackContextType(expression:HxExpr, fallback:TyType, environment:TyFunctionEnv, ?expected:TyType):TyType {
		final term = sourceTerm(expression, environment);
		final type = term == null ? fallback : solver.previewDynamicUses(term);
		return expected != null
			&& expected.isDynamic()
			&& type.isUnknown()
			&& term != null
			&& solver.hasOmittedInputOrigin(term) ? expected : type;
	}

	/** Resolve a retained lexical term against this traversal's constraints, including in speculative forks. */
	public function termType(term:TyInferenceTerm):TyType {
		return solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	public function localType(symbol:TySymbol):TyType {
		final term = locals.get(symbol.getIdentity().getCanonicalKey());
		return term == null ? symbol.getType() : solver.isSealed() ? solver.published(term) : solver.preview(term);
	}

	/** No incomplete inferred type may enter local bindings or typed-body revision keys. */
	public function seal(symbols:Array<TySymbol>):Void {
		solver.seal();
		for (call in capturedCalls) {
			final types = [
				for (operand in 0...call.types.length)
					call.terms[operand] == null ? call.types[operand] : solver.published(call.terms[operand])
			];
			final signature = TyCallableSignature.fromFunctionValue(solver.published(call.callable));
			final converted = call.selectedSlots == null ? types : TyCallbackArgumentContext.dynamicInputTypes(signature, call.selectedSlots, types,
				operand -> call.terms[operand] != null && solver.isUnresolvedInput(call.terms[operand]));
			final binding = call.selectedSlots == null ? TyCallbackArgumentContext.publish(signature, call.arguments, types,
				call.index) : TyCallbackArgumentContext.publishSlots(signature, call.arguments, converted, call.index, call.selectedSlots);
			callbackArguments.push({callee: call.callee, binding: binding});
		}
		for (symbol in symbols)
			symbol.setType(localType(symbol));
	}
}
