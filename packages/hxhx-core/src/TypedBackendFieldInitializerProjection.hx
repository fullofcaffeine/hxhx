/**
	A source-shaped field initializer paired with its exact typed catalogs.

	Field initializers execute outside ordinary methods, but a lambda or block
	inside one can still declare locals and read current-class fields. Keeping
	the projected declaration, stable initializer revision, exact local
	bindings, and exact field reads together lets a backend render that
	executable unit without borrowing mutable state from an unrelated function.
**/
class TypedBackendFieldInitializerProjection {
	final stableIdentity:String;
	final bodyRevision:String;
	final field:TyFieldInfo;
	final declaration:HxFieldDecl;
	final localCatalog:TypedBackendLocalCatalog;
	final fieldReadCatalog:TypedBackendFieldReadCatalog;
	final runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog;
	final constructorCatalog:TypedBackendConstructorCatalog;
	final fields:Array<TypedBackendFieldOccurrence>;
	final methods:Array<TypedBackendMethodOccurrence>;
	final instanceCalls:Array<TypedBackendInstanceCallOccurrence>;
	final aggregates:Array<TypedBackendAggregateOccurrence>;
	final casts:Array<TypedBackendCastOccurrence>;
	final objectAccesses:Array<TypedBackendObjectAccess>;
	final localWrites:Array<TypedBackendLocalWrite>;
	final callArguments:Array<TypedBackendCallArgument>;
	final lambdas:Array<TypedBackendLambdaOccurrence>;
	final fingerprint:String;
	final source:TypedFieldInitializer;
	final lowered:TypedControlLowering.LoweredFieldInitializer;
	var captureCatalog:Null<TypedBackendCaptureCatalog> = null;

	public function new(source:TypedFieldInitializer, lowered:TypedControlLowering.LoweredFieldInitializer, stableIdentity:String, bodyRevision:String,
			field:TyFieldInfo, declaration:HxFieldDecl, localCatalog:TypedBackendLocalCatalog, ?fieldReadCatalog:TypedBackendFieldReadCatalog,
			?runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog, ?constructorCatalog:TypedBackendConstructorCatalog,
			?fields:Array<TypedBackendFieldOccurrence>, ?aggregates:Array<TypedBackendAggregateOccurrence>, ?casts:Array<TypedBackendCastOccurrence>,
			?objectAccesses:Array<TypedBackendObjectAccess>, ?localWrites:Array<TypedBackendLocalWrite>, ?callArguments:Array<TypedBackendCallArgument>,
			?methods:Array<TypedBackendMethodOccurrence>, ?lambdas:Array<TypedBackendLambdaOccurrence>,
			?instanceCalls:Array<TypedBackendInstanceCallOccurrence>) {
		if (stableIdentity == null || stableIdentity.length == 0)
			throw "typed backend field initializer projection requires a stable identity";
		if (bodyRevision == null || bodyRevision.length == 0)
			throw "typed backend field initializer projection requires an exact body revision";
		if (field == null || declaration == null || localCatalog == null)
			throw "typed backend field initializer projection requires complete typed facts";
		if (field.getName() != HxFieldDecl.getName(declaration))
			throw "typed backend field initializer projection received a declaration for a different field";
		if (HxFieldDecl.getInit(declaration) == null)
			throw "typed backend field initializer projection requires a projected initializer";
		switch HxFieldDecl.getInit(declaration) {
			case ELoweredControl(Initializer(hasValue), owner, entries, _):
				if (owner != stableIdentity || (hasValue && entries.length == 0))
					throw "typed backend initializer body has an invalid owner or final value";
			case _:
		}
		this.source = source;
		this.lowered = lowered;
		this.stableIdentity = stableIdentity;
		this.bodyRevision = bodyRevision;
		this.field = field;
		this.fields = fields == null ? [] : fields.copy();
		this.methods = methods == null ? [] : methods.copy();
		this.instanceCalls = instanceCalls == null ? [] : instanceCalls.copy();
		for (entry in this.instanceCalls)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.methods)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.fields)
			entry.assertCurrent(stableIdentity, bodyRevision);
		this.declaration = declaration;
		this.aggregates = aggregates == null ? [] : aggregates.copy();
		this.casts = casts == null ? [] : casts.copy();
		this.objectAccesses = objectAccesses == null ? [] : objectAccesses.copy();
		this.localWrites = localWrites == null ? [] : localWrites.copy();
		this.callArguments = callArguments == null ? [] : callArguments.copy();
		this.lambdas = lambdas == null ? [] : lambdas.copy();
		for (entry in this.lambdas)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.callArguments)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.localWrites)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.objectAccesses)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.casts)
			entry.assertCurrent(stableIdentity, bodyRevision);
		for (entry in this.aggregates)
			entry.assertCurrent(stableIdentity, bodyRevision);
		fingerprint = TypedBodyFingerprint.exactExpression(HxFieldDecl.getInit(declaration));
		this.localCatalog = localCatalog;
		this.fieldReadCatalog = fieldReadCatalog == null ? new TypedBackendFieldReadCatalog([]) : fieldReadCatalog;
		this.runtimeTypeCatalog = runtimeTypeCatalog == null ? new TypedBackendRuntimeTypeCatalog(stableIdentity, bodyRevision, []) : runtimeTypeCatalog;
		this.runtimeTypeCatalog.assertOwner(stableIdentity, bodyRevision);
		this.runtimeTypeCatalog.assertMarkers(TypedRuntimeTypeSource.inExpression(HxFieldDecl.getInit(declaration)));
		this.constructorCatalog = constructorCatalog == null ? new TypedBackendConstructorCatalog(stableIdentity, bodyRevision, []) : constructorCatalog;
		this.constructorCatalog.assertOwner(stableIdentity, bodyRevision);
		this.constructorCatalog.assertExpressions(TypedConstructorSource.inExpression(HxFieldDecl.getInit(declaration)));
	}

	/** Capture facts belong to this exact field body and its lowered closure occurrences. */
	public function requireCaptureCatalog():TypedBackendCaptureCatalog {
		if (captureCatalog == null)
			captureCatalog = new TypedBackendCaptureCatalog(FieldInitializer(source, lowered, declaration), localCatalog);
		captureCatalog.assertOwner(stableIdentity, bodyRevision);
		captureCatalog.assertCurrent();
		return captureCatalog;
	}

	public function getStableIdentity():String
		return stableIdentity;

	/** Authorize an unassigned local only when its original declaration has no initializer. */
	public function assertUninitializedLocal(binding:TyLocalBinding):Void {
		assertCurrent();
		if (binding == null || binding.getKind() != Variable)
			throw "uninitialized initializer local requires an ordinary source binding";
		final name = localCatalog.projectedName(binding);
		var matches = 0;
		var uninitialized = false;
		TypedBackendSourceWalk.expression(getExpression(), expression -> {
			switch expression {
				case EVariableDeclaration(target, _, value, _, _, isStatic) if (target == name):
					matches++;
					uninitialized = value == null && !isStatic;
				case _:
			}
		});
		if (matches != 1 || !uninitialized)
			throw "explicit initializer local initialization cannot be omitted";
	}

	/** Initializer lambdas cannot borrow a method's return conversion facts. */
	public function findLambda(expression:HxExpr):Null<TypedBackendLambdaOccurrence> {
		for (entry in lambdas)
			if (entry.expression == expression) {
				requireExpression(expression);
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** Field initializers retain their own method-value selections, including receiver effects. */
	public function findMethodUse(expression:HxExpr):Null<TypedBackendMethodOccurrence> {
		for (entry in methods)
			if (entry.getExpression() == expression) {
				requireExpression(expression);
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** Only the original live call object can supply a selected native binding. */
	public function findInstanceCall(expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		for (entry in instanceCalls)
			if (entry.getExpression() == expression) {
				requireExpression(expression);
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	public function getRuntimeTypeCatalog():TypedBackendRuntimeTypeCatalog
		return runtimeTypeCatalog;

	public function getConstructorCatalog():TypedBackendConstructorCatalog
		return constructorCatalog;

	/** Static and instance initializers own their call conversions independently of methods. */
	public function findCallArgumentType(expression:HxExpr):Null<TyType> {
		final argument = findCallArgument(expression);
		return argument == null ? null : argument.type;
	}

	/** Initializer-owned callable adaptation uses the same occurrence checks as scalar conversion. */
	public function findCallArgument(expression:HxExpr):Null<TypedBackendCallArgument> {
		for (entry in callArguments)
			if (entry.expression == expression) {
				requireExpression(expression);
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** An initializer remains its own executable; it never borrows a method's local or aggregate facts. */
	public function assertCurrent():Void {
		if (fingerprint != TypedBodyFingerprint.exactExpression(getExpression()))
			throw "field initializer projection was mutated";
	}

	public function requireExpression(expression:HxExpr):Void {
		assertCurrent();
		var found = false;
		TypedBackendSourceWalk.expression(getExpression(), value -> {
			if (value == expression)
				found = true;
		});
		if (!found)
			throw "expression is absent from the current initializer projection";
	}

	/** Initializer locals use their own storage facts and exact destination occurrences. */
	public function requireLocalWrite(name:String, expression:HxExpr):TypedBackendLocalWrite {
		assertCurrent();
		var present = false;
		TypedBackendSourceWalk.expression(getExpression(), node -> {
			if (TypedBackendLocalWrite.matchesExpression(node, name, expression))
				present = true;
		});
		if (present)
			for (entry in localWrites)
				if (entry.projectedName == name && entry.expression == expression) {
					entry.assertCurrent(stableIdentity, bodyRevision);
					if (localCatalog.projectedName(entry.binding) != name)
						throw "initializer local write destination changed after projection";
					return entry;
				}
		throw "local write is absent from this exact initializer projection";
	}

	public function requireAggregate(expression:HxExpr):TypedBackendAggregateOccurrence {
		requireExpression(expression);
		for (entry in aggregates)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		throw "aggregate is not an exact occurrence in this initializer projection";
	}

	/** Structural accesses retain initializer ownership instead of borrowing a method's facts. */
	public function findObjectAccess(expression:HxExpr):Null<TypedBackendObjectAccess> {
		for (entry in objectAccesses)
			if (entry.expression == expression) {
				requireExpression(expression);
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** Retained casts carry exact types only while their original expression belongs to this initializer. */
	public function findCast(expression:HxExpr):Null<TypedBackendCastOccurrence> {
		requireExpression(expression);
		for (entry in casts)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				return entry;
			}
		return null;
	}

	/** Initializer dependencies use resolved fields, never a qualifier's source spelling. */
	public function findField(expression:HxExpr):Null<TypedBackendFieldOccurrence> {
		for (entry in fields)
			if (entry.getExpression() == expression) {
				entry.assertCurrent(stableIdentity, bodyRevision);
				var found = false;
				TypedBackendSourceWalk.expression(getExpression(), value -> {
					if (value == expression)
						found = true;
				});
				if (!found)
					throw "field occurrence is absent from the current initializer projection";
				return entry;
			}
		return null;
	}

	/** Initializers own their constructor facts even when their body contains lowered statements. */
	public function requireConstructor(expression:HxExpr):TypedBackendConstructorOccurrence {
		if (TypedConstructorSource.inExpression(getExpression()).indexOf(expression) < 0)
			throw "constructor is absent from the current initializer projection";
		return constructorCatalog.require(expression, stableIdentity, bodyRevision);
	}

	/** Select an operand only from this exact initializer projection and revision. */
	public function requireRuntimeType(expression:HxExpr):TypedBackendRuntimeTypeOccurrence {
		if (TypedRuntimeTypeSource.inExpression(getExpression()).indexOf(expression) < 0)
			throw "runtime type operand is absent from the current initializer projection";
		return runtimeTypeCatalog.require(expression, stableIdentity, bodyRevision);
	}

	public function getBodyRevision():String
		return bodyRevision;

	public function getField():TyFieldInfo
		return field;

	public function getDeclaration():HxFieldDecl
		return declaration;

	public function getExpression():HxExpr
		return HxFieldDecl.getInit(declaration);

	public function getLocalCatalog():TypedBackendLocalCatalog
		return localCatalog;

	public function getFieldReadCatalog():TypedBackendFieldReadCatalog
		return fieldReadCatalog;
}
