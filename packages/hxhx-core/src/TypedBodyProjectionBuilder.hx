/**
	Collect expression facts while rebuilding one typed executable body.

	Functions and field initializers use the same builder. Runtime type operations
	keep their existing owner, while constructions retain applied constructor facts.
	Sealing admits only exact objects that survive in the final projected body.
 */
class TypedBodyProjectionBuilder {
	final ownerIdentity:String;
	final bodyRevision:String;
	final runtimeTypes:TypedRuntimeTypeProjectionBuilder;
	final constructors:Array<TypedBackendConstructorOccurrence> = [];
	final callableAscriptions:Array<HxExpr> = [];
	final callableExpressions:Array<TypedBackendCallableExpression> = [];
	final aggregates:Array<TypedBackendAggregateOccurrence> = [];
	final fields:Array<TypedBackendFieldOccurrence> = [];
	final methods:Array<TypedBackendMethodOccurrence> = [];
	final instanceCalls:Array<TypedBackendInstanceCallOccurrence> = [];
	final casts:Array<TypedBackendCastOccurrence> = [];
	final thrownValues:Array<TypedBackendThrownValue> = [];
	final localWrites:Array<TypedBackendLocalWrite> = [];
	final objectAccesses:Array<TypedBackendObjectAccess> = [];
	final arrayAccesses:Array<TypedBackendArrayAccess> = [];
	final collectionControls:Array<TypedBackendCollectionControl> = [];
	final equalities:Array<TypedBackendEqualityOccurrence> = [];
	final bitwiseOperations:Array<TypedBackendBitwiseOccurrence> = [];
	final conditions:Array<TypedBackendCondition> = [];
	final callArguments:Array<TypedBackendCallArgument> = [];
	final lambdas:Array<TypedBackendLambdaOccurrence> = [];
	final returns:Array<TypedBackendReturnOccurrence> = [];
	final statementControls:Array<TypedBackendStatementControl> = [];
	final namedPatterns:Array<TypedBackendNamedPattern> = [];
	var sealed:Bool = false;

	/** Local renaming preserves pattern order, so each selected case keeps its exact projected object. */
	public function projectNamedPatterns(facts:Null<TypedSwitchPatterns>, patterns:Array<HxSwitchPattern>):Void {
		if (sealed)
			throw "cannot add named patterns to a sealed projection";
		if (facts == null)
			return;
		final names = TypedSwitchPatterns.named(patterns);
		final selections = facts.getSelections();
		if (names.length != selections.length)
			throw "projected named pattern count differs from typing";
		for (index in 0...names.length)
			if (selections[index] != null)
				namedPatterns.push(new TypedBackendNamedPattern({
					owner: ownerIdentity,
					revision: bodyRevision,
					pattern: names[index],
					selection: selections[index]
				}));
	}

	public function getNamedPatterns():Array<TypedBackendNamedPattern> {
		if (!sealed)
			throw "named patterns require a sealed projection";
		return namedPatterns.copy();
	}

	public function new(ownerIdentity:String, bodyRevision:String) {
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
		runtimeTypes = new TypedRuntimeTypeProjectionBuilder(ownerIdentity, bodyRevision);
	}

	/** Preserve selected collection operand types before projecting them as control syntax. */
	public function projectCollectionControl(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add collection controls to a sealed projection";
		if (source.getTag() == ControlFor || source.getTag() == ArrayAppend)
			collectionControls.push(new TypedBackendCollectionControl({
				owner: ownerIdentity,
				revision: bodyRevision,
				source: source,
				expression: expression
			}));
		return expression;
	}

	public function getCollectionControls():Array<TypedBackendCollectionControl> {
		if (!sealed)
			throw "collection controls require a sealed projection";
		return collectionControls.copy();
	}

	/** Ordinary statement loops keep the same exact destinations as lowered expression loops. */
	public function projectStatementControl(source:TypedStmt, statement:HxStmt):HxStmt {
		if (sealed)
			throw "cannot add statement controls to a sealed projection";
		switch source.getTag() {
			case ForIn | ForKeyValue | While | DoWhile | Break | Continue:
				statementControls.push(new TypedBackendStatementControl(ownerIdentity, bodyRevision, source, statement));
			case _:
		}
		return statement;
	}

	public function getStatementControls():Array<TypedBackendStatementControl> {
		if (!sealed)
			throw "statement controls require a sealed projection";
		return statementControls.copy();
	}

	public function projectRuntimeType(target:TypedRuntimeTypeTarget, ?value:HxExpr, ?valueType:TyType):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		return runtimeTypes.project(target, value, valueType);
	}

	/** Record compiler-added type transport separately from authored cast operations. */
	public function ascribeCallable(value:HxExpr, hint:String):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		final expression:HxExpr = ECast(value, hint);
		callableAscriptions.push(expression);
		return expression;
	}

	public function getCallableAscriptions():Array<HxExpr>
		return callableAscriptions.copy();

	/** Keep condition types for calls, fields, locals, and lowered control equally. */
	public function projectCondition(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add conditions to a sealed projection";
		conditions.push(new TypedBackendCondition({
			owner: ownerIdentity,
			revision: bodyRevision,
			source: source,
			expression: expression
		}));
		return expression;
	}

	public function getConditions():Array<TypedBackendCondition> {
		if (!sealed)
			throw "conditions require a sealed projection";
		return conditions.copy();
	}

	/** Preserve operand types before binary syntax loses them. */
	public function projectBinary(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add binary facts to a sealed projection";
		if (TypedBackendBitwiseOccurrence.supports(source.getTexts()[0]))
			bitwiseOperations.push(new TypedBackendBitwiseOccurrence({
				owner: ownerIdentity,
				revision: bodyRevision,
				source: source,
				expression: expression
			}));
		if (source.getTexts()[0] == "==" || source.getTexts()[0] == "!=")
			equalities.push(new TypedBackendEqualityOccurrence({
				owner: ownerIdentity,
				revision: bodyRevision,
				source: source,
				expression: expression
			}));
		return expression;
	}

	public function getEqualities():Array<TypedBackendEqualityOccurrence> {
		if (!sealed)
			throw "equality facts require a sealed projection";
		return equalities.copy();
	}

	public function getBitwiseOperations():Array<TypedBackendBitwiseOccurrence> {
		if (!sealed)
			throw "bitwise facts require a sealed projection";
		return bitwiseOperations.copy();
	}

	/** Retain typed callback producers, uses and comparisons before source projection loses their meaning. */
	public function projectCallableExpression(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add callable expressions to a sealed body projection";
		final relevant = source.getType().isFunction() || switch source.getTag() {
			case Call: final children = source.getExpressions(); children.length > 0 && children[0].getType().isFunction();
			case Binary: final children = source.getExpressions(); children.length == 2 && (children[0].getType().isFunction()
					|| children[1].getType().isFunction()) && ["==", "!="].indexOf(source.getTexts()[0]) >= 0;
			case _: false;
		};
		if (relevant) {
			// Projection visits children first. A transparent block returns its child's
			// object, so the last entry already owns that value. Keep its typed producer;
			// an effectful sequence creates a distinct object and retains a new entry.
			final previous = callableExpressions.length == 0 ? null : callableExpressions[callableExpressions.length - 1];
			if (previous == null || previous.expression != expression)
				callableExpressions.push({expression: expression, source: source});
		}
		return expression;
	}

	/** The capture catalog binds only entries retained in the complete checked projection. */
	public function getCallableExpressions():Array<TypedBackendCallableExpression>
		return callableExpressions.copy();

	/** Preserve the callable result contract without changing the body's own type. */
	public function projectLambda(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add lambda facts to a sealed body projection";
		lambdas.push(new TypedBackendLambdaOccurrence({
			owner: ownerIdentity,
			revision: bodyRevision,
			source: source,
			expression: expression,
			returns: returns
		}));
		return expression;
	}

	/** Save exact return facts before the enclosing lambda collects its own exits. */
	public function projectReturn(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add return facts to a sealed body projection";
		returns.push(new TypedBackendReturnOccurrence(ownerIdentity, bodyRevision, source, expression));
		return expression;
	}

	public function getLambdas():Array<TypedBackendLambdaOccurrence> {
		if (!sealed)
			throw "lambda facts require a sealed body projection";
		return lambdas.copy();
	}

	/** Retain cast, annotation, and untyped operand types apart from compiler-only callable annotations. */
	public function projectCast(source:TypedExpr, operand:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		final entry = new TypedBackendCastOccurrence({
			ownerIdentity: ownerIdentity,
			bodyRevision: bodyRevision,
			source: source,
			operand: operand
		});
		casts.push(entry);
		return entry.getExpression();
	}

	public function getCasts():Array<TypedBackendCastOccurrence> {
		if (!sealed)
			throw "cast facts require a sealed body projection";
		return casts.copy();
	}

	/** Preserve the operand type without adding an authored cast or changing evaluation. */
	public function projectThrownValue(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add thrown values to a sealed body projection";
		thrownValues.push(new TypedBackendThrownValue(ownerIdentity, bodyRevision, source, expression));
		return expression;
	}

	public function getThrownValues():Array<TypedBackendThrownValue> {
		if (!sealed)
			throw "thrown values require a sealed body projection";
		return thrownValues.copy();
	}

	/** Keep conversion facts for initializers and assignments without changing source syntax. */
	public function projectLocalWrite(name:String, binding:TyLocalBinding, source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add local writes to a sealed body projection";
		localWrites.push(new TypedBackendLocalWrite({
			owner: ownerIdentity,
			revision: bodyRevision,
			projectedName: name,
			binding: binding,
			source: source,
			expression: expression
		}));
		return expression;
	}

	public function getLocalWrites():Array<TypedBackendLocalWrite> {
		if (!sealed)
			throw "local writes require a sealed body projection";
		return localWrites.copy();
	}

	/** Preserve structural read/write types without assigning a nominal field declaration. */
	public function projectObjectAccess(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add object accesses to a sealed body projection";
		if (TypedBackendObjectAccess.supports(source))
			objectAccesses.push(new TypedBackendObjectAccess({
				owner: ownerIdentity,
				revision: bodyRevision,
				source: source,
				expression: expression
			}));
		return expression;
	}

	public function getObjectAccesses():Array<TypedBackendObjectAccess> {
		if (!sealed)
			throw "object accesses require a sealed projection";
		return objectAccesses.copy();
	}

	/** Preserve indexed operand types before target-specific storage conversions. */
	public function projectArrayAccess(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add array accesses to a sealed body projection";
		if (TypedBackendArrayAccess.supports(source))
			arrayAccesses.push(new TypedBackendArrayAccess({
				owner: ownerIdentity,
				revision: bodyRevision,
				source: source,
				expression: expression
			}));
		return expression;
	}

	public function getArrayAccesses():Array<TypedBackendArrayAccess> {
		if (!sealed)
			throw "array accesses require a sealed projection";
		return arrayAccesses.copy();
	}

	/** Record written operands before target adapters add receiver or control arguments. */
	public function projectCallArguments(source:TypedExpr, arguments:Array<HxExpr>):Void {
		if (sealed || source.getTag() != Call)
			throw "call arguments require an unsealed projection of a typed call";
		final children = source.getExpressions();
		if (children.length != arguments.length + 1)
			throw "call argument projection changed source arity";
		final expected = TypedCallExpectedArguments.resolveParameters(source);
		for (index in 0...arguments.length) {
			final parameter = expected[index];
			callArguments.push(new TypedBackendCallArgument(ownerIdentity, bodyRevision, children[index + 1], arguments[index],
				parameter == null ? null : parameter.type, parameter != null && parameter.isOptional));
		}
	}

	public function getCallArguments():Array<TypedBackendCallArgument> {
		if (!sealed)
			throw "call arguments require a sealed projection";
		return callArguments.copy();
	}

	/** Preserve resolved field ownership without changing the source-shaped access. */
	public function projectField(source:TypedExpr, expression:HxExpr, receiver:TypedBackendFieldOccurrence.TypedBackendFieldReceiver):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		fields.push(new TypedBackendFieldOccurrence({
			ownerIdentity: ownerIdentity,
			bodyRevision: bodyRevision,
			source: source,
			expression: expression,
			receiver: receiver
		}));
		return expression;
	}

	public function getFields():Array<TypedBackendFieldOccurrence> {
		if (!sealed)
			throw "field facts require a sealed body projection";
		return fields.copy();
	}

	/** Record how an exact method selection is consumed before source-shaped projection loses that distinction. */
	public function projectMethod(source:TypedExpr, expression:HxExpr, use:TypedBackendMethodOccurrence.TypedMethodUse):HxExpr {
		if (sealed)
			throw "cannot add method facts to a sealed body projection";
		methods.push(new TypedBackendMethodOccurrence({
			owner: ownerIdentity,
			revision: bodyRevision,
			source: source,
			expression: expression,
			use: use
		}));
		return expression;
	}

	public function getMethods():Array<TypedBackendMethodOccurrence> {
		if (!sealed)
			throw "method facts require a sealed body projection";
		return methods.copy();
	}

	/** Keep selected-call facts beside the exact marker produced by this builder. */
	public function projectInstanceCall(source:TypedExpr, expression:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add call facts to a sealed body projection";
		instanceCalls.push(new TypedBackendInstanceCallOccurrence({
			owner: ownerIdentity,
			revision: bodyRevision,
			source: source,
			expression: expression
		}));
		return expression;
	}

	public function getInstanceCalls():Array<TypedBackendInstanceCallOccurrence> {
		if (!sealed)
			throw "instance calls require a sealed projection";
		return instanceCalls.copy();
	}

	/** Preserve semantic aggregate types before source-shaped projection discards them. */
	public function projectAggregate(source:TypedExpr, children:Array<HxExpr>):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		final entry = new TypedBackendAggregateOccurrence({
			ownerIdentity: ownerIdentity,
			bodyRevision: bodyRevision,
			source: source,
			children: children
		});
		aggregates.push(entry);
		return entry.getExpression();
	}

	public function getAggregates():Array<TypedBackendAggregateOccurrence> {
		if (!sealed)
			throw "aggregate facts require a sealed body projection";
		return aggregates.copy();
	}

	public function projectConstructor(source:TypedExpr, path:String, arguments:Array<HxExpr>):HxExpr {
		if (sealed)
			throw "cannot add expression facts to a sealed body projection";
		final entry = new TypedBackendConstructorOccurrence({
			ownerIdentity: ownerIdentity,
			bodyRevision: bodyRevision,
			source: source,
			typePath: path,
			arguments: arguments
		});
		constructors.push(entry);
		return entry.getExpression();
	}

	public function seal(runtimeMarkers:Array<HxExpr>, constructions:Array<HxExpr>):{
		runtimeTypes:TypedBackendRuntimeTypeCatalog,
		constructors:TypedBackendConstructorCatalog
	} {
		if (sealed)
			throw "body projection was sealed twice";
		sealed = true;
		final retained = new Array<TypedBackendConstructorOccurrence>();
		for (expression in constructions) {
			var selected:Null<TypedBackendConstructorOccurrence> = null;
			for (entry in constructors)
				if (entry.getExpression() == expression) {
					selected = entry;
					break;
				}
			if (selected == null)
				throw "projected body contains a construction from another builder";
			retained.push(selected);
		}
		final catalog = new TypedBackendConstructorCatalog(ownerIdentity, bodyRevision, retained);
		catalog.assertExpressions(constructions);
		return {runtimeTypes: runtimeTypes.seal(runtimeMarkers), constructors: catalog};
	}
}
