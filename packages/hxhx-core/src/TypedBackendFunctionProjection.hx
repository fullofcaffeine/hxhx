/**
	A source-shaped function body paired with the exact typed-local and bare
	field-read catalogs that gave projected values their transport names. The
	body revision comes from the same sealed typed tree and lets target plans bind
	their decisions without hashing this projected source-shaped view.

	Existing emitters may consume the declaration while they migrate, but a
	backend that makes local-identity or local-type decisions must also consume
	`localCatalog`. A backend that interprets a bare field must consume
	`fieldReadCatalog` rather than rediscovering field ownership from text.
**/
class TypedBackendFunctionProjection {
	final source:TypedFunction;
	final lowered:TypedFunction;
	var captureCatalog:Null<TypedBackendCaptureCatalog> = null;
	final stableIdentity:String;
	final bodyRevision:String;
	final declaration:HxFunctionDecl;
	final localCatalog:TypedBackendLocalCatalog;
	final fieldReadCatalog:TypedBackendFieldReadCatalog;
	final parameterBindingIdentities:Array<String>;
	final returnType:TyType;
	final runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog;
	final constructorCatalog:TypedBackendConstructorCatalog;
	final aggregates:Array<TypedBackendAggregateOccurrence>;
	final fields:Array<TypedBackendFieldOccurrence>;
	final methods:Array<TypedBackendMethodOccurrence>;
	final instanceCalls:Array<TypedBackendInstanceCallOccurrence>;
	final casts:Array<TypedBackendCastOccurrence>;
	final thrownValues:Array<TypedBackendThrownValue>;
	final localWrites:Array<TypedBackendLocalWrite>;
	final objectAccesses:Array<TypedBackendObjectAccess>;
	final callArguments:Array<TypedBackendCallArgument>;
	final lambdas:Array<TypedBackendLambdaOccurrence>;
	final statementControls:Array<TypedBackendStatementControl>;
	final defaults:Array<TypedBackendFunctionDefault>;

	public function new(source:TypedFunction, lowered:TypedFunction, declaration:HxFunctionDecl, localCatalog:TypedBackendLocalCatalog, returnType:TyType,
			?fieldReadCatalog:TypedBackendFieldReadCatalog, ?parameterBindingIdentities:Array<String>, ?runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog,
			?constructorCatalog:TypedBackendConstructorCatalog, ?aggregates:Array<TypedBackendAggregateOccurrence>,
			?fields:Array<TypedBackendFieldOccurrence>, ?casts:Array<TypedBackendCastOccurrence>, ?thrownValues:Array<TypedBackendThrownValue>,
			?localWrites:Array<TypedBackendLocalWrite>, ?objectAccesses:Array<TypedBackendObjectAccess>, ?callArguments:Array<TypedBackendCallArgument>,
			?methods:Array<TypedBackendMethodOccurrence>, ?lambdas:Array<TypedBackendLambdaOccurrence>,
			?instanceCalls:Array<TypedBackendInstanceCallOccurrence>, ?statementControls:Array<TypedBackendStatementControl>) {
		if (source == null || lowered == null)
			throw "typed backend function projection requires authored and lowered owners";
		final stableIdentity = source.getStableIdentity();
		final bodyRevision = CompilerTypedTreeRevision.functionBody(source);
		if (lowered.getStableIdentity() != stableIdentity
			|| lowered.getBody().getSourceFingerprint() != source.getBody().getSourceFingerprint())
			throw "typed backend function projection has another lowered owner";
		if (stableIdentity == null || stableIdentity.length == 0)
			throw "typed backend function projection requires a stable identity";
		if (bodyRevision == null || bodyRevision.length == 0)
			throw "typed backend function projection requires an exact body revision";
		if (declaration == null)
			throw "typed backend function projection requires a declaration";
		if (localCatalog == null)
			throw "typed backend function projection requires a local catalog";
		if (returnType == null)
			throw "typed backend function projection requires an exact return type";
		this.stableIdentity = stableIdentity;
		this.bodyRevision = bodyRevision;
		this.source = source;
		this.lowered = lowered;
		this.declaration = declaration;
		defaults = [
			for (value in lowered.getDefaults()) {
				final slot = value.getParameterIndex();
				final expression = switch HxFunctionArg.getDefaultValue(HxFunctionDecl.getArgs(declaration)[slot]) {
					case Default(expression): expression;
					case NoDefault: throw "projected function lost a typed parameter default";
				};
				{slot: slot, expression: expression, type: value.getExpression().getType()};
			}
		];
		this.localCatalog = localCatalog;
		this.fieldReadCatalog = fieldReadCatalog == null ? new TypedBackendFieldReadCatalog([]) : fieldReadCatalog;
		this.parameterBindingIdentities = parameterBindingIdentities == null ? [] : parameterBindingIdentities.copy();
		this.returnType = returnType;
		this.aggregates = aggregates == null ? [] : aggregates.copy();
		this.fields = fields == null ? [] : fields.copy();
		this.methods = methods == null ? [] : methods.copy();
		this.instanceCalls = instanceCalls == null ? [] : instanceCalls.copy();
		for (entry in this.instanceCalls)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.methods)
			entry.assertCurrent(stableIdentity, bodyRevision);
		this.casts = casts == null ? [] : casts.copy();
		this.thrownValues = thrownValues == null ? [] : thrownValues.copy();
		this.localWrites = localWrites == null ? [] : localWrites.copy();
		this.objectAccesses = objectAccesses == null ? [] : objectAccesses.copy();
		this.callArguments = callArguments == null ? [] : callArguments.copy();
		this.lambdas = lambdas == null ? [] : lambdas.copy();
		this.statementControls = statementControls == null ? [] : statementControls.copy();
		for (entry in this.statementControls)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.lambdas)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.callArguments)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.objectAccesses)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.localWrites)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.thrownValues)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.casts)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.fields)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.aggregates)
			entry.assertCurrent(stableIdentity, bodyRevision);
		this.runtimeTypeCatalog = runtimeTypeCatalog == null ? new TypedBackendRuntimeTypeCatalog(stableIdentity, bodyRevision, []) : runtimeTypeCatalog;
		this.runtimeTypeCatalog.assertOwner(stableIdentity, bodyRevision);
		this.runtimeTypeCatalog.assertMarkers(TypedRuntimeTypeSource.inFunction(declaration));
		this.constructorCatalog = constructorCatalog == null ? new TypedBackendConstructorCatalog(stableIdentity, bodyRevision, []) : constructorCatalog;
		this.constructorCatalog.assertOwner(stableIdentity, bodyRevision);
		this.constructorCatalog.assertExpressions(TypedConstructorSource.inFunction(declaration));
		for (local in localCatalog.getEntries())
			if (local.getBinding().getIdentity().getOwnerIdentity() != stableIdentity)
				throw "typed backend function projection contains a local from another function " + stableIdentity;
		final seenParameters = new haxe.ds.StringMap<Bool>();
		for (identity in this.parameterBindingIdentities) {
			if (identity == null || identity.length == 0)
				throw "typed backend function projection contains an empty parameter binding identity";
			if (seenParameters.exists(identity))
				throw "typed backend function projection contains duplicate parameter binding " + identity;
			final local = localCatalog.findByIdentity(identity);
			if (local == null || !local.getBinding().getKind().match(Parameter))
				throw "typed backend function projection cannot find exact parameter binding " + identity;
			seenParameters.set(identity, true);
		}
	}

	public function getDeclaration():HxFunctionDecl
		return declaration;

	/** Require an original expression after validating this projection against its current typed owner. */
	public function requireExpression(expression:HxExpr):Void {
		requireCaptureCatalog().assertCurrent();
		var present = false;
		TypedBackendSourceWalk.functionDeclaration(declaration, value -> {
			if (value == expression)
				present = true;
		}, _ -> {});
		if (!present)
			throw "expression is absent from this exact function projection";
	}

	/** Return only the original conditional entry operands of this exact projection. */
	public function getDefaults():Array<TypedBackendFunctionDefault> {
		requireCaptureCatalog().assertCurrent();
		for (value in defaults)
			switch HxFunctionArg.getDefaultValue(HxFunctionDecl.getArgs(declaration)[value.slot]) {
				case Default(expression) if (expression == value.expression):
				case _:
					throw "projected parameter default is not its original occurrence";
			}
		return defaults.copy();
	}

	/**
		Authorize checked unassigned storage only for an exact source declaration
		without an initializer. This prevents a backend from silently dropping an
		existing initializer when it requests deferred assignment storage.
	 */
	public function assertUninitializedLocal(binding:TyLocalBinding):Void {
		source.assertParsedBodyCurrent();
		if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
			throw "uninitialized local owner changed after projection";
		if (binding == null || binding.getKind() != Variable)
			throw "uninitialized local requires an ordinary source binding";
		final name = localCatalog.projectedName(binding);
		var matches = 0;
		var uninitialized = false;
		TypedBackendSourceWalk.functionDeclaration(declaration, node -> {
			switch node {
				case EVariableDeclaration(target, _, value, _, _, isStatic) if (target == name):
					matches++;
					uninitialized = value == null && !isStatic;
				case _:
			}
		}, node -> {
			switch node {
				case SVar(target, _, value, _) if (target == name):
					matches++;
					uninitialized = value == null;
				case _:
			}
		});
		if (matches != 1 || !uninitialized)
			throw "explicit source initialization cannot be omitted";
	}

	/** Require the original local destination and operand to remain in this projected body. */
	public function requireLocalWrite(name:String, expression:HxExpr):TypedBackendLocalWrite {
		source.assertParsedBodyCurrent();
		if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
			throw "local write owner changed after projection";
		var present = false;
		TypedBackendSourceWalk.functionDeclaration(declaration, node -> {
			if (TypedBackendLocalWrite.matchesExpression(node, name, expression))
				present = true;
		}, node -> {
			switch node {
				case SVar(target, _, value, _) if (target == name && value == expression): present = true;
				case _:
			}
		});
		if (present)
			for (entry in localWrites)
				if (entry.projectedName == name && entry.expression == expression) {
					entry.assertCurrent(stableIdentity, bodyRevision);
					if (localCatalog.projectedName(entry.binding) != name)
						throw "local write destination changed after projection";
					return entry;
				}
		throw "local write is absent from this exact function projection";
	}

	/** Only an original throw operand can obtain its retained semantic type. */
	public function requireThrownValue(expression:HxExpr):TypedBackendThrownValue {
		source.assertParsedBodyCurrent();
		if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
			throw "thrown value owner changed after projection";
		var present = false;
		TypedBackendSourceWalk.functionDeclaration(declaration, node -> {
			switch node {
				case ELoweredControl(Throw, "", [value], _) if (value == expression): present = true;
				case _:
			}
		}, node -> {
			switch node {
				case SThrow(value, _) if (value == expression): present = true;
				case _:
			}
		});
		if (present)
			for (entry in thrownValues)
				if (entry.expression == expression) {
					entry.assertCurrent(stableIdentity, bodyRevision);
					return entry;
				}
		throw "thrown operand is absent from this exact function projection";
	}

	/** Native bindings select the actual typed declaration, including bodyless extern methods. */
	public function requireSemanticDeclaration():TyDeclarationInfo {
		source.assertParsedBodyCurrent();
		final selected = source.getDeclaration();
		if (selected == null || selected.getIdentity().getCanonicalKey() != stableIdentity)
			throw "backend function lacks its exact semantic declaration";
		return selected;
	}

	/**
		Publish capture facts only for this function's exact projected closure objects.
		Construction is lazy because targets without closure storage do not consume this
		analysis. A consumer must request it before making capture or lifetime decisions.
		Unsupported authored closure forms fail here instead of receiving an empty plan.
	 */
	public function requireCaptureCatalog():TypedBackendCaptureCatalog {
		if (captureCatalog == null)
			captureCatalog = new TypedBackendCaptureCatalog(FunctionBody(source, lowered, declaration), localCatalog);
		captureCatalog.assertOwner(stableIdentity, bodyRevision);
		captureCatalog.assertCurrent();
		return captureCatalog;
	}

	/** Only the original live call object can supply a selected native binding. */
	public function findInstanceCall(expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		for (entry in instanceCalls)
			if (entry.getExpression() == expression) {
				source.assertParsedBodyCurrent();
				if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
					throw "instance call owner changed after projection";
				var present = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, value -> {
					if (value == expression)
						present = true;
				}, _ -> {});
				if (!present)
					throw "instance call is absent from the current projection";
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	public function getRuntimeTypeCatalog():TypedBackendRuntimeTypeCatalog
		return runtimeTypeCatalog;

	public function getConstructorCatalog():TypedBackendConstructorCatalog
		return constructorCatalog;

	/** Only a retained operand in this executable can supply a call-boundary conversion type. */
	public function findCallArgumentType(expression:HxExpr):Null<TyType> {
		final argument = findCallArgument(expression);
		return argument == null ? null : argument.type;
	}

	/** Lambda return conversions require the same live occurrence and semantic owner. */
	public function findLambda(expression:HxExpr):Null<TypedBackendLambdaOccurrence> {
		for (entry in lambdas)
			if (entry.expression == expression) {
				source.assertParsedBodyCurrent();
				if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
					throw "lambda owner changed after projection";
				entry.assertCurrent(stableIdentity, bodyRevision);
				var present = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, value -> {
					if (value == expression)
						present = true;
				}, _ -> {});
				if (!present)
					throw "lambda is absent from its function projection";
				return entry;
			}
		return null;
	}

	/** Both sides of a conversion belong to the same checked executable occurrence. */
	public function findCallArgument(expression:HxExpr):Null<TypedBackendCallArgument> {
		for (entry in callArguments)
			if (entry.expression == expression) {
				source.assertParsedBodyCurrent();
				if (CompilerTypedTreeRevision.functionBody(source) != bodyRevision)
					throw "call argument owner changed after projection";
				entry.assertCurrent(stableIdentity, bodyRevision);
				var present = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, value -> {
					if (value == expression)
						present = true;
				}, _ -> {});
				if (!present)
					throw "call argument is absent from its function projection";
				return entry;
			}
		return null;
	}

	/** Structural storage facts require the original access to remain in this executable. */
	public function findObjectAccess(expression:HxExpr):Null<TypedBackendObjectAccess> {
		for (entry in objectAccesses)
			if (entry.expression == expression) {
				requireCaptureCatalog().assertCurrent();
				entry.assertCurrent(stableIdentity, bodyRevision);
				var present = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, node -> {
					if (node == expression)
						present = true;
				}, _ -> {});
				if (!present)
					throw "object access is absent from its function projection";
				return entry;
			}
		return null;
	}

	/** Return facts only for the original field object still present in this body. */
	public function findField(expression:HxExpr):Null<TypedBackendFieldOccurrence> {
		source.assertParsedBodyCurrent();
		for (entry in fields)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				var found = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, value -> {
					if (value == expression)
						found = true;
				}, _ -> {});
				if (!found)
					throw "field occurrence is absent from the current function projection";
				return entry;
			}
		return null;
	}

	/** Method facts belong to this exact executable object, not an equal-looking copied field read. */
	public function findMethodUse(expression:HxExpr):Null<TypedBackendMethodOccurrence> {
		source.assertParsedBodyCurrent();
		for (entry in methods)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				var present = false;
				TypedBackendSourceWalk.functionDeclaration(declaration, node -> {
					if (node == expression)
						present = true;
				}, _ -> {});
				if (!present)
					throw "method occurrence is absent from the current function projection";
				return entry;
			}
		return null;
	}

	/** Consumers first verify lexical occurrence ownership, then request the retained type. */
	public function findCast(expression:HxExpr):Null<TypedBackendCastOccurrence> {
		for (entry in casts)
			if (entry.getExpression() == expression) {
				requireCaptureCatalog().assertCurrent();
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** Consumers first verify lexical occurrence ownership, then request the retained type. */
	public function requireAggregate(expression:HxExpr):TypedBackendAggregateOccurrence {
		requireCaptureCatalog().assertCurrent();
		for (entry in aggregates)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		throw "aggregate is not an exact occurrence in this function projection";
	}

	/** Select construction facts only for an expression still present in this exact projected body. */
	public function requireConstructor(expression:HxExpr):TypedBackendConstructorOccurrence {
		if (TypedConstructorSource.inFunction(declaration).indexOf(expression) < 0)
			throw "constructor is absent from the current function projection";
		return constructorCatalog.require(expression, stableIdentity, bodyRevision);
	}

	/** Select an operand only from this exact function projection and body revision. */
	public function requireRuntimeType(expression:HxExpr):TypedBackendRuntimeTypeOccurrence {
		if (TypedRuntimeTypeSource.inFunction(declaration).indexOf(expression) < 0)
			throw "runtime type operand is absent from the current function projection";
		return runtimeTypeCatalog.require(expression, stableIdentity, bodyRevision);
	}

	/**
		Return the source-shaped body rebuilt from this projection's sealed typed
		body.

		Migrating backends should use this accessor after selecting a strict
		projection. It makes the typed record—not a parsed declaration—the visible
		owner of the body they render.
	**/
	public function getBody():Array<HxStmt>
		return HxFunctionDecl.getBody(declaration);

	public function getStableIdentity():String
		return stableIdentity;

	/** Return the exact semantic body revision supplied by the sealed typed owner. **/
	public function getBodyRevision():String
		return bodyRevision;

	public function getLocalCatalog():TypedBackendLocalCatalog
		return localCatalog;

	public function getFieldReadCatalog():TypedBackendFieldReadCatalog
		return fieldReadCatalog;

	/** Return the semantic result type sealed with this function body. **/
	public function getReturnType():TyType
		return returnType;

	/** Ordinary statement returns belong to this typed method, never to a generated closure. */
	public function requireRootControlIdentity():String {
		requireCaptureCatalog().assertCurrent();
		final environment = lowered.getEnvironment();
		final target = environment == null ? null : environment.getRootControlTarget();
		if (target == null)
			throw "root function rendering requires an executing typed control owner";
		return target.getCanonicalIdentity();
	}

	/** A target may use only control facts retained for this exact current statement. */
	public function requireStatementControl(statement:HxStmt):TypedBackendStatementControl {
		requireCaptureCatalog().assertCurrent();
		var present = false;
		function visit(candidate:HxStmt):Void {
			if (candidate == statement)
				present = true;
			TypedBackendSourceWalk.statementChildren(candidate, _ -> {}, visit);
		}
		for (candidate in getBody())
			visit(candidate);
		if (present)
			for (entry in statementControls)
				if (entry.statement == statement) {
					entry.assertCurrent(stableIdentity, bodyRevision);
					return entry;
				}
		throw "statement control is absent from this exact function projection";
	}

	/** Return exact parameter bindings in source signature order. **/
	public function getParameterBindingIdentities():Array<String>
		return parameterBindingIdentities.copy();

	/**
		Return exact parameter projections in source signature order.

		A target must use this boundary when parameter order, names, or types affect
		emission. Missing or stale catalog entries are rejected here instead of being
		recovered from source spellings.
	**/
	public function getParameters():Array<TypedBackendLocalProjection> {
		final arguments = HxFunctionDecl.getArgs(declaration);
		if (arguments.length != parameterBindingIdentities.length)
			throw "typed backend function projection parameter count mismatch for " + stableIdentity;
		final parameters = new Array<TypedBackendLocalProjection>();
		for (index in 0...parameterBindingIdentities.length) {
			final identity = parameterBindingIdentities[index];
			final parameter = localCatalog.findByIdentity(identity);
			if (parameter == null)
				throw "typed backend function projection lost exact parameter binding " + identity;
			if (parameter.getProjectedName() != HxFunctionArg.getName(arguments[index]))
				throw "typed backend function projection parameter name mismatch for " + identity;
			parameters.push(parameter);
		}
		return parameters;
	}
}

/** A conditional parameter initializer retains its exact projected operand and semantic type. */
typedef TypedBackendFunctionDefault = {
	final slot:Int;
	final expression:HxExpr;
	final type:TyType;
}
