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
	final aggregates:Array<TypedBackendAggregateOccurrence> = [];
	final fields:Array<TypedBackendFieldOccurrence> = [];
	final methods:Array<TypedBackendMethodOccurrence> = [];
	final instanceCalls:Array<TypedBackendInstanceCallOccurrence> = [];
	final casts:Array<TypedBackendCastOccurrence> = [];
	final thrownValues:Array<TypedBackendThrownValue> = [];
	final localWrites:Array<TypedBackendLocalWrite> = [];
	final objectAccesses:Array<TypedBackendObjectAccess> = [];
	final callArguments:Array<TypedBackendCallArgument> = [];
	final lambdas:Array<TypedBackendLambdaOccurrence> = [];
	final returns:Array<TypedBackendReturnOccurrence> = [];
	final statementControls:Array<TypedBackendStatementControl> = [];
	var sealed:Bool = false;

	public function new(ownerIdentity:String, bodyRevision:String) {
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
		runtimeTypes = new TypedRuntimeTypeProjectionBuilder(ownerIdentity, bodyRevision);
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

	/** Keep typed cast operands distinct from compiler-only callable annotations. */
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

	/** Record written operands before target adapters add receiver or control arguments. */
	public function projectCallArguments(source:TypedExpr, arguments:Array<HxExpr>):Void {
		if (sealed || source.getTag() != Call)
			throw "call arguments require an unsealed projection of a typed call";
		final children = source.getExpressions();
		if (children.length != arguments.length + 1)
			throw "call argument projection changed source arity";
		final expected = TypedCallExpectedArguments.resolve(source);
		for (index in 0...arguments.length)
			callArguments.push(new TypedBackendCallArgument(ownerIdentity, bodyRevision, children[index + 1], arguments[index], expected[index]));
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
