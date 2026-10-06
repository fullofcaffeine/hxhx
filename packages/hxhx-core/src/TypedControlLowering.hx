import TypedExpr.TypedExprTag;

/** The statements evaluated before an optional value, with abrupt completion kept explicit. */
private typedef ControlValue = {
	final steps:Array<TypedExpr>;
	final value:Null<TypedExpr>;
	final completes:Bool;
}

/**
	An initializer executes these statements once before reading its final value.
	The statements and value share one local scope. Abrupt completion has no value
	and must not assign the field. This is an executable unit, not a new callable;
	functions authored inside it retain their own return destinations and captures.
 */
typedef LoweredFieldInitializer = {
	final steps:Array<TypedExpr>;
	final value:Null<TypedExpr>;
	final completes:Bool;
}

/**
	Lower source groups after typing has selected exact locals and return targets.

	The source tree stays immutable for macros and revision checks. The derived tree
	uses statement regions and declaration-owned temporaries, so a return in a value
	group still exits its authored function. Unsupported control combinations fail
	here instead of being hidden inside a newly created closure.
 */
class TypedControlLowering {
	static final passIdentity = "source-control-v23";

	final owner:String;
	var nextTemporary:Int = 0;
	var didLower:Bool = false;
	var activeLoop:Null<TyControlTarget> = null;
	var untypedContext:Bool = false;

	final rootTarget:Null<TyControlTarget>;

	function new(owner:String, rootTarget:Null<TyControlTarget>) {
		this.owner = owner;
		this.rootTarget = rootTarget;
	}

	public static function functionBody(fn:TypedFunction):TypedFunction {
		final environment = fn.getEnvironment();
		final lowerer = new TypedControlLowering(fn.getStableIdentity(), environment == null ? null : environment.getRootControlTarget());
		final defaults = [
			for (value in fn.getDefaults()) {
				final expression = value.getExpression();
				final plan = lowerer.value(expression, null);
				if (!plan.completes || plan.value == null) throw "named parameter default must produce a value";
				new TypedFunctionDefault(value.getParameterIndex(),
					plan.steps.length == 0 ? plan.value : TypedExpr.block(plan.steps.concat([plan.value]), expression.getType(), expression.getPosition()));
			}
		];
		final statements = lowerer.statements(fn.getBody().getStatements());
		if (!lowerer.didLower)
			return fn;
		final result = fn.withBody(new TypedFunctionBody(statements, fn.getBody().getSourceFingerprint()), defaults);
		TypedBodyInvariant.assertFunction(result);
		return result;
	}

	/** Lower under the exact field owner without introducing a function return target. */
	public static function fieldInitializer(initializer:TypedFieldInitializer):LoweredFieldInitializer {
		final lowerer = new TypedControlLowering(initializer.getField().getCanonicalKey(), null);
		final plan = lowerer.value(initializer.getExpression(), null);
		return {steps: plan.steps, value: plan.value, completes: plan.completes};
	}

	function statements(inputs:Array<TypedStmt>):Array<TypedStmt> {
		final output = new Array<TypedStmt>();
		for (index in 0...inputs.length) {
			final loweredStatements = statement(inputs[index]);
			for (lowered in loweredStatements)
				output.push(lowered);
			if (loweredStatements.length != 0 && !statementCompletes(loweredStatements[loweredStatements.length - 1])) {
				if (index + 1 < inputs.length)
					didLower = true;
				break;
			}
		}
		return output;
	}

	/** Remove later siblings only after an unconditional exit from this lexical statement list. */
	static function statementCompletes(statement:TypedStmt):Bool {
		final children = statement.getStatements();
		return switch statement.getTag() {
			case Return | ReturnVoid | Throw | Break | Continue: false;
			case Block: children.length == 0 || statementCompletes(children[children.length - 1]);
			case If: children.length != 2 || statementCompletes(children[0]) || statementCompletes(children[1]);
			case _: true;
		};
	}

	/** Lift group evaluation into its enclosing statement list, preserving local visibility. */
	function statement(input:TypedStmt):Array<TypedStmt> {
		final values = new Array<TypedExpr>();
		final prefix = new Array<TypedStmt>();
		for (expression in input.getExpressions()) {
			final plan = input.getTag() == ForIn ? forIterable(expression, rootTarget) : value(expression, rootTarget);
			if ((input.getTag() == While || input.getTag() == DoWhile) && (plan.steps.length != 0 || !plan.completes))
				return repeatedStatement(input, plan);
			if (plan.steps.length != 0) {
				if (values.length != 0)
					throw "multi-operand statement control requires dedicated shared lowering";
				for (step in plan.steps)
					for (lowered in stepStatements(step))
						prefix.push(lowered);
			}
			if (!plan.completes)
				return prefix;
			if (plan.value == null) {
				if (input.getTag() != Expression)
					throw "statement control lowering requires an operand value";
				return prefix;
			}
			values.push(plan.value);
		}
		final previousLoop = activeLoop;
		switch input.getTag() {
			case While | DoWhile | ForIn | ForKeyValue:
				activeLoop = input.getControlTarget();
			case _:
		}
		final children = input.getTag() == Block ? statements(input.getStatements()) : [
			for (child in input.getStatements()) {
				final lowered = statement(child);
				lowered.length == 1 ? lowered[0] : TypedStmt.block(lowered, child.getPosition());
			}
		];
		activeLoop = previousLoop;
		prefix.push(input.withChildren(values, children));
		return prefix;
	}

	/** Evaluate a condition on every loop edge while preserving the original body and jump destination. */
	function repeatedStatement(input:TypedStmt, condition:ControlValue):Array<TypedStmt> {
		final loopTarget = input.getControlTarget();
		if (loopTarget == null || loopTarget.getOwnerIdentity() != owner || input.getStatements().length != 1)
			throw "repeated statement loop requires its exact destination and body";
		final kind:HxWhileKind = input.getTag() == DoWhile ? DoWhile : Normal;
		final plan = repeatedCondition(condition, kind, loopTarget, input.getPosition());
		final previousLoop = activeLoop;
		activeLoop = loopTarget;
		final body = statement(input.getStatements()[0]);
		activeLoop = previousLoop;
		final result = new Array<TypedStmt>();
		for (step in plan.prefix)
			for (item in stepStatements(step))
				result.push(item);
		final region = TypedExpr.controlRegion(plan.head.concat([TypedStatementControl.region(body, rootTarget, input.getPosition())]),
			TyType.fromHintText("Void"), input.getPosition());
		result.push(TypedStmt.expressionStmt(TypedExpr.controlWhile(TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), input.getPosition()), region,
			input.getPosition(), loopTarget, Normal),
			input.getPosition()));
		didLower = true;
		return result;
	}

	function repeatedCondition(condition:ControlValue, kind:HxWhileKind, loopTarget:TyControlTarget,
			position:Null<HxPos>):TypedRepeatedCondition.TypedRepeatedConditionPlan {
		return TypedRepeatedCondition.build({
			steps: condition.steps,
			value: condition.value,
			completes: condition.completes,
			kind: kind,
			target: loopTarget,
			first: kind == DoWhile ? temporary(TyType.fromHintText("Bool")) : null,
			position: position
		});
	}

	/** Convert only scope and declaration instructions into the existing statement view. */
	function stepStatements(step:TypedExpr):Array<TypedStmt> {
		return switch step.getTag() {
			case ControlTry:
				final bodies = [
					for (child in step.getExpressions()) {
						final statements = stepStatements(child);
						if (statements.length != 1) throw "lowered try requires lexical bodies";
						statements[0];
					}
				];
				final catches = step.getSourceCatches();
				[
					TypedStmt.tryStmt(bodies[0], [for (entry in catches) entry.getName()], [for (entry in catches) entry.getTypeHint()], bodies.slice(1),
						step.getPosition(), step.getLocalBindings())
						.withCatchUses(step.getCatchUses())];
			case ControlSwitch:
				final children = step.getExpressions();
				final bodies = [
					for (index in 1...children.length) {
						final statements = stepStatements(children[index]);
						if (statements.length != 1) throw "lowered switch requires lexical arm bodies";
						statements[0];
					}
				];
				[
					TypedStmt.switchStmt(children[0], step.getPatterns(), bodies, step.getPosition(), step.getLocalBindings())
				];
			case ControlFor | ControlWhile:
				// Keep the selected loop destination through backend projection. Rebuilding
				// source-shaped statements here discards the destination used by exits.
				[TypedStmt.expressionStmt(step, step.getPosition())];
			case BreakExpr:
				[
					TypedStmt.breakStmt(step.getPosition()).withControlTarget(step.getControlTarget())
				];
			case ContinueExpr:
				[
					TypedStmt.continueStmt(step.getPosition()).withControlTarget(step.getControlTarget())
				];
			case ControlBranch:
				final children = step.getExpressions();
				final whenTrue = stepStatements(children[1]);
				final whenFalse = children.length == 3 ? stepStatements(children[2]) : [];
				if (whenTrue.length != 1 || (children.length == 3 && whenFalse.length != 1))
					throw "lowered conditional branches must each be one lexical region";
				[
					TypedStmt.ifStmt(children[0], whenTrue[0], whenFalse.length == 0 ? null : whenFalse[0], step.getPosition())
				];
			case ThrowExpr:
				[TypedStmt.throwStmt(step.getExpressions()[0], step.getPosition())];
			case ControlRegion:
				if (step.getControlTarget() != null)
					throw "a function region must remain inside its callable value";
				final body = new Array<TypedStmt>();
				for (entry in step.getExpressions())
					for (statement in stepStatements(entry))
						body.push(statement);
				[TypedStmt.block(body, step.getPosition())];
			case VariableDeclarations:
				[
					for (entry in step.getExpressions()) {
						final bindings = entry.getLocalBindings();
						if (bindings.length != 1 || entry.getVariableIsStatic()) throw "lowered local declaration requires one ordinary binding";
						final initializers = entry.getExpressions();
						TypedStmt.variable(entry.getTexts()[0], entry.getTexts()[1], initializers.length == 0 ? null : initializers[0], entry.getPosition(),
							[], bindings[0]);
					}
				];
			case ReturnExpr:
				if (rootTarget == null || step.getControlTarget() != rootTarget)
					throw "ordinary method return differs from its exact root destination";
				final values = step.getExpressions();
				[
					values.length == 0 ? TypedStmt.returnVoid(step.getPosition()) : TypedStmt.returnValue(values[0], step.getPosition())
				];
			case _:
				[TypedStmt.expressionStmt(step, step.getPosition())];
		};
	}

	function temporary(type:TyType):TyLocalBinding {
		final ordinal = nextTemporary++;
		final name = "result";
		return new TyLocalBinding(TyLocalId.forCompilerTemporary(owner, passIdentity, ordinal, name), name, type, CompilerTemporary);
	}

	function declaration(binding:TyLocalBinding, initial:Null<TypedExpr>, position:Null<HxPos>):TypedExpr {
		return TypedExpr.variableDeclarations([
			TypedExpr.variableDeclaration(binding.getSourceName(), binding.getType().getCanonicalDisplay(), initial, false, false, binding.getType(),
				position, binding)
		], TyType.fromHintText("Void"), position);
	}

	function plain(expression:TypedExpr):ControlValue
		return {steps: [], value: expression, completes: true};

	/** Discard only the value; all observable work and abrupt control remains ordered. */
	function discard(expression:TypedExpr, target:Null<TyControlTarget>):ControlValue {
		if (expression.getTag() == SourceTry)
			return tryValue(expression, target, false);
		if (expression.getTag() == SourceGroup || expression.getTag() == Block)
			return group(expression, target, false);
		if (expression.getTag() == SourceIf)
			return conditional(expression, target, false);
		if (expression.getTag() == SwitchExpr)
			return switchValue(expression, target, false);
		final plan = value(expression, target);
		if (plan.value != null)
			plan.steps.push(plan.value);
		return {steps: plan.steps, value: null, completes: plan.completes};
	}

	/**
		Evaluate the condition once and keep each branch's work inside that branch.
		Only branches that complete assign the selected result temporary. A throwing
		or returning branch never manufactures a value or executes its later effects.
	**/
	function conditional(expression:TypedExpr, target:Null<TyControlTarget>, needsValue:Bool):ControlValue {
		final children = expression.getExpressions();
		final condition = value(children[0], target);
		if (!condition.completes) {
			didLower = true;
			return {steps: condition.steps, value: null, completes: false};
		}
		if (condition.value == null)
			throw "lowered conditional requires a condition value";
		final whenTrue = needsValue ? value(children[1], target) : discard(children[1], target);
		final whenFalse:ControlValue = children.length == 3 ? (needsValue ? value(children[2], target) : discard(children[2], target)) : {
			steps: [],
			value: null,
			completes: true
		};
		// Keep a pure ternary only when both branches already have the selected
		// result type. Otherwise the typed result slot preserves nullable or other
		// widened results without asking each target to infer a common branch type.
		if (expression.getTag() == Ternary
			&& needsValue
			&& condition.steps.length == 0
			&& whenTrue.steps.length == 0
			&& whenFalse.steps.length == 0
			&& whenTrue.completes
			&& whenFalse.completes
			&& whenTrue.value != null
			&& whenFalse.value != null
			&& whenTrue.value.getType().getSemanticKey() == expression.getType().getSemanticKey()
			&& whenFalse.value.getType().getSemanticKey() == expression.getType().getSemanticKey())
			return plain(expression.withExpressions([condition.value, whenTrue.value, whenFalse.value]));
		didLower = true;
		final completes = whenTrue.completes || whenFalse.completes;
		var result:Null<TypedExpr> = null;
		final position = expression.getPosition();
		if (needsValue && completes && !expression.getType().isVoid()) {
			final binding = temporary(expression.getType());
			condition.steps.push(declaration(binding, null, position));
			result = TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
			for (branch in [whenTrue, whenFalse]) {
				if (!branch.completes)
					continue;
				if (branch.value == null)
					throw "a completing value branch must provide its selected result";
				branch.steps.push(TypedExpr.assign(result, branch.value, binding.getType(), position));
			}
		} else {
			for (branch in [whenTrue, whenFalse])
				if (branch.value != null)
					branch.steps.push(branch.value);
		}
		final trueRegion = TypedExpr.controlRegion(whenTrue.steps, whenTrue.completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(),
			children[1].getPosition());
		final falseRegion = children.length == 3 ? TypedExpr.controlRegion(whenFalse.steps,
			whenFalse.completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(), children[2].getPosition()) : null;
		condition.steps.push(TypedExpr.controlBranch(condition.value, trueRegion, falseRegion,
			completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(), position));
		return {steps: condition.steps, value: result, completes: completes};
	}

	/** Keep arm effects conditional and assign a result only on normally completing paths. */
	function switchValue(expression:TypedExpr, target:Null<TyControlTarget>, needsValue:Bool):ControlValue {
		didLower = true;
		final children = expression.getExpressions();
		final scrutinee = value(children[0], target);
		if (!scrutinee.completes)
			return scrutinee;
		if (scrutinee.value == null)
			throw "switch lowering requires a scrutinee value";
		final patterns = expression.getPatterns();
		var coversInput = expression.getSwitchHasExhaustiveCoverage();
		for (pattern in patterns)
			if (pattern.match(PWildcard))
				coversInput = true;
		final branches = [
			for (index in 1...children.length)
				needsValue ? value(children[index], target) : discard(children[index], target)
		];
		var completes = !coversInput;
		for (branch in branches)
			completes = completes || branch.completes;
		var result:Null<TypedExpr> = null;
		if (needsValue && completes && !expression.getType().isVoid()) {
			if (!coversInput)
				throw "value switch lowering requires exact exhaustive coverage before result storage in "
					+ owner
					+ (expression.getPosition() == null ? "" : " at " + expression.getPosition().toString());
			final binding = temporary(expression.getType());
			scrutinee.steps.push(declaration(binding, null, expression.getPosition()));
			result = TypedExpr.localRead(binding.getSourceName(), binding.getType(), expression.getPosition(), binding);
			for (branch in branches)
				if (branch.completes) {
					if (branch.value == null)
						throw "completing switch arm must provide its selected result";
					branch.steps.push(TypedExpr.assign(result, branch.value, binding.getType(), expression.getPosition()));
				}
		} else {
			for (branch in branches)
				if (branch.value != null)
					branch.steps.push(branch.value);
		}
		final completionType = completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion();
		final regions = [
			for (index in 0...branches.length)
				TypedExpr.controlRegion(branches[index].steps, branches[index].completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(),
					children[index + 1].getPosition())
		];
		scrutinee.steps.push(TypedExpr.controlSwitch(scrutinee.value, patterns, regions, completionType, expression.getPosition(),
			expression.getLocalBindings()));
		return {steps: scrutinee.steps, value: result, completes: completes};
	}

	function group(expression:TypedExpr, target:Null<TyControlTarget>, needsValue:Bool):ControlValue {
		didLower = true;
		final entries = expression.getExpressions();
		// Empty source braces keep their authored shape until a value consumer needs
		// the anonymous object selected by shared typing. Discarded bodies allocate nothing.
		if (entries.length == 0 && needsValue && expression.getType().isAnonymous())
			return plain(TypedExpr.anonymous([], [], expression.getType(), expression.getPosition()));
		final steps = new Array<TypedExpr>();
		var result:Null<TypedExpr> = null;
		var completes = true;
		for (index in 0...entries.length) {
			final plan = needsValue && index == entries.length - 1 ? value(entries[index], target) : discard(entries[index], target);
			for (step in plan.steps)
				steps.push(step);
			result = plan.value;
			if (!plan.completes) {
				completes = false;
				break;
			}
		}
		final position = expression.getPosition();
		final outside = new Array<TypedExpr>();
		var projectedValue:Null<TypedExpr> = null;
		if (completes && needsValue && result != null && !result.getType().isVoid()) {
			final binding = temporary(result.getType());
			outside.push(declaration(binding, null, position));
			projectedValue = TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
			steps.push(TypedExpr.assign(projectedValue, result, binding.getType(), position));
		} else if (result != null) {
			steps.push(result);
		}
		outside.push(TypedExpr.controlRegion(steps, completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(), position));
		return {steps: outside, value: projectedValue, completes: completes};
	}

	/** Keep effects inside their handler and assign a result only after normal completion. */
	function tryValue(expression:TypedExpr, target:Null<TyControlTarget>, needsValue:Bool):ControlValue {
		didLower = true;
		final children = expression.getExpressions();
		final branches = [
			for (child in children)
				needsValue ? value(child, target) : discard(child, target)
		];
		var completes = false;
		for (branch in branches)
			completes = completes || branch.completes;
		final outside = new Array<TypedExpr>();
		var result:Null<TypedExpr> = null;
		if (needsValue && completes && !expression.getType().isVoid()) {
			final binding = temporary(expression.getType());
			outside.push(declaration(binding, null, expression.getPosition()));
			result = TypedExpr.localRead(binding.getSourceName(), binding.getType(), expression.getPosition(), binding);
			for (branch in branches)
				if (branch.completes) {
					if (branch.value == null)
						throw "completing try body must provide its selected result";
					branch.steps.push(TypedExpr.assign(result, branch.value, binding.getType(), expression.getPosition()));
				}
		} else {
			for (branch in branches)
				if (branch.value != null)
					branch.steps.push(branch.value);
		}
		final bodies = [
			for (index in 0...branches.length)
				TypedExpr.controlRegion(branches[index].steps, branches[index].completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(),
					children[index].getPosition())
		];
		outside.push(TypedExpr.controlTry(expression.getSourceCatches(), bodies, completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(),
			expression.getPosition(), expression.getLocalBindings())
			.withCatchUses(expression.getCatchUses()));
		return {steps: outside, value: result, completes: completes};
	}

	/** Apply defaults once to parameter storage before body effects, preserving nested return ownership. */
	function sourceFunction(expression:TypedExpr):TypedExpr {
		didLower = true;
		final target = expression.getControlTarget();
		final facts = expression.getSourceFunction();
		if (target == null || facts == null || target.getOwnerIdentity() != owner)
			throw "source function lowering requires its exact typed function target";
		final body = expression.getExpressions()[0];
		final previousLoop = activeLoop;
		activeLoop = null;
		final bindings = expression.getLocalBindings();
		final parameterBindings = facts.getDeclaredName() == null ? bindings : bindings.slice(1);
		final entry = new Array<TypedExpr>();
		final defaults = expression.getExpressions().slice(1);
		final indexes = facts.getDefaultParameterIndexes();
		facts.assertDefaultCount(defaults.length);
		for (index in 0...indexes.length) {
			final binding = parameterBindings[indexes[index]];
			final position = defaults[index].getPosition();
			final destination = TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
			final missing = TypedExpr.binary("==", destination, TypedExpr.nullValue(TyType.fromHintText("Null"), position), TyType.fromHintText("Bool"),
				position);
			final assignment = TypedExpr.assign(destination, defaults[index], binding.getType(), position);
			final guard = TypedExpr.sourceIf(missing, assignment, null, TyType.fromHintText("Void"), position);
			for (step in discard(guard, target).steps)
				entry.push(step);
		}
		final plan = facts.getKind() == Arrow ? value(body, target) : discard(body, target);
		activeLoop = previousLoop;
		if (facts.getKind() == Arrow && plan.completes && plan.value != null)
			plan.steps.push(TypedExpr.returnExpr(plan.value, TyType.noNormalCompletion(), body.getPosition()).withControlTarget(target));
		final region = TypedExpr.controlRegion(entry.concat(plan.steps), body.getType(), body.getPosition(), target);
		return TypedExpr.lambda(facts.getArguments(), region, expression.getType(), expression.getPosition(), parameterBindings, facts.getSignature())
			.withCatchUses(expression.getCatchUses());
	}

	/** Range bounds are evaluated left to right once, before the first loop iteration. */
	function forIterable(expression:TypedExpr, target:Null<TyControlTarget>):ControlValue {
		if (expression.getTag() != Range)
			return value(expression, target);
		didLower = true;
		final steps = new Array<TypedExpr>();
		final bounds = new Array<TypedExpr>();
		for (bound in expression.getExpressions()) {
			final plan = value(bound, target);
			for (step in plan.steps)
				steps.push(step);
			if (!plan.completes)
				return {steps: steps, value: null, completes: false};
			// Dynamic is a declared value type. Preserve it for the target's ordinary
			// comparison/increment behavior instead of inventing an Int conversion.
			if (plan.value == null || plan.value.getType().hasUnknownComponent())
				throw "range iteration requires concrete bound values in "
					+ owner
					+ " at bound "
					+ bounds.length
					+ "; got "
					+ (plan.value == null ? "no value" : plan.value.getType().getSemanticKey());
			final binding = temporary(plan.value.getType());
			steps.push(declaration(binding, plan.value, bound.getPosition()));
			bounds.push(TypedExpr.localRead(binding.getSourceName(), binding.getType(), bound.getPosition(), binding));
		}
		return {
			steps: steps,
			value: TypedExpr.fixedRange(bounds[0], bounds[1], expression.getType(), expression.getPosition()),
			completes: true
		};
	}

	/** One result allocation receives every completing yield through the shared control path. */
	function collectionComprehension(expression:TypedExpr, target:Null<TyControlTarget>):ControlValue {
		final arguments = expression.getType().getTypeArguments();
		final identity = expression.getType().getNominalIdentity();
		final isMap = identity != null && identity.getCanonicalName() == "haxe.ds.Map";
		if (arguments.length != (isMap ? 2 : 1) || expression.getType().hasUnknownComponent())
			throw "collection comprehension lowering requires its selected element types";
		final position = expression.getPosition();
		final binding = temporary(expression.getType());
		final result = TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
		final body = isMap ? TypedMapComprehensionLowering.insertYields(expression.getExpressions()[0],
			result) : TypedArrayComprehensionLowering.appendYields(expression.getExpressions()[0], result, arguments[0]);
		final plan = discard(body, target);
		didLower = true;
		return {
			steps: [
				declaration(binding, TypedExpr.arrayDecl([], expression.getType(), position), position)
			].concat(plan.steps),
			value: plan.completes ? result : null,
			completes: plan.completes
		};
	}

	/**
		Haxe saves array addresses before a control-valued right side, but evaluates
		a field receiver after that side's statements. Preserve this measured order;
		never materialize the stored field/element value as the write destination.
	 */
	function retainDestination(destination:TypedExpr, steps:Array<TypedExpr>):TypedExpr {
		final children = destination.getExpressions();
		switch destination.getTag() {
			case NameRead if (destination.getFieldInfo() != null):
				return destination;
			case FieldRead:
				return destination;
			case ArrayAccess:
				final retained = new Array<TypedExpr>();
				for (operand in children) {
					if (operand.getType().isVoid() || operand.getType().hasUnknownComponent())
						throw "control-valued assignment requires complete address operand types";
					final binding = temporary(operand.getType());
					steps.push(declaration(binding, operand, operand.getPosition()));
					retained.push(TypedExpr.localRead(binding.getSourceName(), binding.getType(), operand.getPosition(), binding));
				}
				return destination.withExpressions(retained);
			case _:
				throw "control-valued assignment requires a supported exact destination";
		}
	}

	/** Preserve address-side statement regions, then the right side; an abrupt exit never writes. */
	function assignment(expression:TypedExpr, target:Null<TyControlTarget>):ControlValue {
		final children = expression.getExpressions();
		final address = value(children[0], target);
		if (!address.completes)
			return address;
		if (address.value == null)
			throw "assignment requires a completing destination";
		final assigned = value(children[1], target);
		final steps = address.steps.copy();
		final destination = assigned.steps.length != 0 || !assigned.completes ? retainDestination(address.value, steps) : address.value;
		for (step in assigned.steps)
			steps.push(step);
		if (!assigned.completes)
			return {steps: steps, value: null, completes: false};
		if (assigned.value == null)
			throw "assignment requires a completing operand value";
		return {steps: steps, value: expression.withExpressions([destination, assigned.value]), completes: true};
	}

	/**
		Parent constructors and extension calls carry invocation syntax rather
		than a callable read. Retain the parent marker or evaluated extension
		receiver before argument statements. The existing unresolved untyped
		abstract boundary also keeps its receiver without inventing a callable type.
		Ordinary methods and function-valued fields keep callable capture.
	 */
	function retainInvocationCallee(call:TypedExpr, callee:TypedExpr, admitted:Bool, steps:Array<TypedExpr>):Null<TypedExpr> {
		if (callee.getTag() == SuperValue && call.getConstructorApplication() != null)
			return callee;
		final children = callee.getExpressions();
		switch callee.getTag() {
			case Parenthesized | Untyped:
				final inner = retainInvocationCallee(call, children[0], admitted || callee.getTag() == Untyped, steps);
				return inner == null ? null : callee.withExpressions([inner]);
			case FieldRead if (call.getExtensionProvider() != null
				|| (admitted && callee.getType().isUnknown() && callee.hasUnresolvedAbstractReceiver())):
				final receiver = children[0];
				if (receiver.getType().isVoid() || receiver.getType().hasUnknownComponent())
					throw "invocation control requires a complete receiver type";
				if (receiver.getTag() == RuntimeTypeValue)
					return callee;
				final binding = temporary(receiver.getType());
				steps.push(declaration(binding, receiver, receiver.getPosition()));
				return callee.withExpressions([
					TypedExpr.localRead(binding.getSourceName(), binding.getType(), receiver.getPosition(), binding)
				]);
			case _:
				return null;
		}
	}

	function value(expression:TypedExpr, target:Null<TyControlTarget>):ControlValue {
		if (expression.getTag() == FeatureDefinition || expression.getTag() == FeatureSelection)
			throw "feature intrinsics require program-owned selection before control lowering";
		final children = expression.getExpressions();
		switch expression.getTag() {
			case Unary if (expression.getUnaryOperator() == LogicalNot):
				// Negation consumes a value; unlike increment, it never needs an lvalue.
				// Complete the operand's selected statements before reading its result.
				final operand = value(children[0], target);
				if (!operand.completes)
					return operand;
				if (operand.value == null)
					throw "logical negation requires a completing operand value";
				return {steps: operand.steps, value: expression.withExpressions([operand.value]), completes: true};
			case Binary if (expression.getTexts()[0] == "&&" || expression.getTexts()[0] == "||"):
				final and = expression.getTexts()[0] == "&&";
				final constant = TypedExpr.boolLiteral(!and, TyType.fromHintText("Bool"), expression.getPosition());
				final branch = TypedExpr.ternary(children[0], and ? children[1] : constant, and ? constant : children[1], expression.getType(),
					expression.getPosition());
				final plan = conditional(branch, target, true);
				if (plan.steps.length == 0 && plan.value != null && plan.value.getTag() == Ternary) {
					final values = plan.value.getExpressions();
					return plain(expression.withExpressions([values[0], values[and ? 1 : 2]]));
				}
				return plan;
			case Block:
				// Operator lowering sequences share the caller's scope and control
				// destinations. Do not project their temporaries as binder lambdas.
				return group(expression, target, true);
			case Temporary:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1
					|| bindings[0].getKind() != CompilerTemporary
					|| !bindings[0].getIdentity().isCompilerTemporary()
					|| bindings[0].getIdentity().getOwnerIdentity() != owner
					|| children.length != 1
					|| bindings[0].getType().getSemanticKey() != children[0].getType().getSemanticKey())
					throw "control lowering temporary requires its exact compiler binding and initializer type";
				didLower = true;
				final initial = value(children[0], target);
				if (!initial.completes)
					return initial;
				if (initial.value == null)
					throw "compiler temporary initializer must provide a value";
				initial.steps.push(declaration(bindings[0], initial.value, expression.getPosition()));
				return {steps: initial.steps, value: null, completes: true};
			case ArrayDecl if (children.length == 1 && children[0].getTag() == SourceFor):
				return collectionComprehension(expression, target);
			case Untyped:
				// Untyped changes checking, not whether its child completes with a value.
				// Statement-only children remain statements; value consumers reject them.
				final previousUntyped = untypedContext;
				untypedContext = true;
				final inner = value(children[0], target);
				untypedContext = previousUntyped;
				return inner.value == null ? inner : {
					steps: inner.steps,
					value: expression.withExpressions([inner.value]),
					completes: inner.completes
				};
			case Assign if (children.length == 2 && children[0].getTag() == LocalRead):
				// A local destination has no receiver or index to evaluate. Its exact
				// binding stays selected while the RHS runs; abrupt exits never write it.
				final assigned = value(children[1], target);
				if ((assigned.steps.length != 0 || !assigned.completes) && children[0].getLocalBindings().length != 1)
					throw "control-valued local assignment requires its exact binding";
				if (!assigned.completes)
					return assigned;
				if (assigned.value == null)
					throw "local assignment requires a completing operand value";
				return {steps: assigned.steps, value: expression.withExpressions([children[0], assigned.value]), completes: true};
			case Assign if (children.length == 2):
				return assignment(expression, target);
			case SourceTry:
				return tryValue(expression, target, true);
			case SwitchExpr:
				return switchValue(expression, target, true);
			case SourceFor:
				final loopTarget = expression.getControlTarget();
				if (loopTarget == null || loopTarget.getOwnerIdentity() != owner)
					throw "for lowering requires its exact typed loop destination";
				final iterable = forIterable(children[0], target);
				if (!iterable.completes)
					return iterable;
				if (iterable.value == null)
					throw "for lowering requires an iterable value";
				final previousLoop = activeLoop;
				activeLoop = loopTarget;
				final body = discard(children[1], target);
				activeLoop = previousLoop;
				didLower = true;
				final region = TypedExpr.controlRegion(body.steps, body.completes ? TyType.fromHintText("Void") : TyType.noNormalCompletion(),
					children[1].getPosition());
				iterable.steps.push(TypedExpr.controlFor(HxForBinding.fromNames(expression.getTexts()), iterable.value, region, expression.getPosition(),
					expression.getLocalBindings(), loopTarget));
				return {steps: iterable.steps, value: null, completes: true};
			case BreakExpr | ContinueExpr:
				if (activeLoop == null || expression.getControlTarget() != activeLoop)
					throw "loop control lowering cannot change its typed loop destination";
				didLower = true;
				return {steps: [expression], value: null, completes: false};
			case MacroExpr | MacroType | ControlRegion | ControlBranch | ControlWhile | ControlFor | ControlSwitch | ControlTry:
				return plain(expression);
			case WhileExpr:
				final loopTarget = expression.getControlTarget();
				if (loopTarget == null || loopTarget.getOwnerIdentity() != owner)
					throw "while lowering requires its exact typed loop destination";
				final condition = value(children[0], target);
				final previousLoop = activeLoop;
				activeLoop = loopTarget;
				final body = new Array<TypedExpr>();
				for (index in 1...children.length) {
					final entry = discard(children[index], target);
					for (step in entry.steps)
						body.push(step);
					if (!entry.completes)
						break;
				}
				activeLoop = previousLoop;
				didLower = true;
				if (condition.steps.length != 0 || !condition.completes) {
					final plan = repeatedCondition(condition, expression.getWhileKind(), loopTarget, expression.getPosition());
					final repeatedBody = TypedExpr.controlRegion(plan.head.concat(body), TyType.fromHintText("Void"), expression.getPosition());
					plan.prefix.push(TypedExpr.controlWhile(TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), expression.getPosition()), repeatedBody,
						expression.getPosition(), loopTarget, Normal));
					return {steps: plan.prefix, value: null, completes: true};
				}
				if (condition.value == null)
					throw "while condition requires a value";
				final region = TypedExpr.controlRegion(body, TyType.fromHintText("Void"), expression.getPosition());
				return {
					steps: [
						TypedExpr.controlWhile(condition.value, region, expression.getPosition(), loopTarget, expression.getWhileKind())
					],
					value: null,
					completes: true
				};
			case SourceFunction:
				final callable = sourceFunction(expression);
				if (expression.getSourceFunction().getDeclaredName() == null)
					return plain(callable);
				final binding = expression.getLocalBindings()[0];
				return {
					steps: [declaration(binding, callable, expression.getPosition())],
					value: TypedExpr.localRead(binding.getSourceName(), binding.getType(), expression.getPosition(), binding),
					completes: true
				};
			case SourceGroup:
				return group(expression, target, true);
			case SourceIf | Ternary:
				return conditional(expression, target, true);
			case ThrowExpr:
				didLower = true;
				final thrown = value(children[0], target);
				if (thrown.completes) {
					if (thrown.value == null)
						throw "throw lowering requires an operand value";
					thrown.steps.push(expression.withExpressions([thrown.value]));
				}
				return {steps: thrown.steps, value: null, completes: false};
			case ReturnExpr:
				if (target == null || expression.getControlTarget() != target)
					throw "return lowering cannot change its typed function destination";
				final returned:ControlValue = children.length == 0 ? {steps: [], value: null, completes: true} : value(children[0], target);
				if (returned.completes)
					returned.steps.push(expression.withExpressions(returned.value == null ? [] : [returned.value]));
				return {steps: returned.steps, value: null, completes: false};
			case VariableDeclarations:
				final steps = new Array<TypedExpr>();
				for (entry in children) {
					final initializers = entry.getExpressions();
					final plan:ControlValue = initializers.length == 0 ? {steps: [], value: null, completes: true} : value(initializers[0], target);
					for (step in plan.steps)
						steps.push(step);
					if (!plan.completes)
						return {steps: steps, value: null, completes: false};
					steps.push(expression.withExpressions([entry.withExpressions(plan.value == null ? [] : [plan.value])]));
				}
				return {steps: steps, value: null, completes: true};
			case Lambda:
				final previousLoop = activeLoop;
				activeLoop = null;
				final plan = value(children[0], null);
				activeLoop = previousLoop;
				if (plan.steps.length != 0 || !plan.completes || plan.value == null)
					throw "legacy expression lambda requires explicit source control migration";
				return plain(expression.withExpressions([plan.value]));
			case _:
		}
		final values = new Array<TypedExpr>();
		final steps = new Array<TypedExpr>();
		var capturedCallee = false;
		for (child in children) {
			final plan = value(child, target);
			if (plan.steps.length != 0) {
				switch expression.getTag() {
					case Ternary | Assign | CompoundAssign | Unary | NullSafeFieldRead | SwitchExpr | ArrayComprehension:
						throw "conditional or lvalue control requires dedicated shared lowering in "
							+ owner
							+ " ("
							+ Std.string(expression.getTag())
							+ ")";
					case Binary if (expression.getTexts()[0] == "&&" || expression.getTexts()[0] == "||"):
						throw "short-circuit control requires dedicated shared lowering";
					case _:
				}
				// Earlier operands must finish before a later operand starts its statement region.
				for (index in 0...values.length) {
					final prior = values[index];
					final method = expression.getTag() == Call
						&& index == 0 ? retainInvocationCallee(expression, prior, untypedContext, steps) : null;
					if (method != null) {
						values[index] = method;
						continue;
					}
					if (prior.getType().isVoid() || prior.getType().hasUnknownComponent())
						throw "control lowering cannot materialize an unresolved operand in " + owner + " (" + Std.string(expression.getTag()) + ")";
					final binding = temporary(prior.getType());
					steps.push(declaration(binding, prior, prior.getPosition()));
					values[index] = TypedExpr.localRead(binding.getSourceName(), binding.getType(), prior.getPosition(), binding);
					if (expression.getTag() == Call && index == 0)
						capturedCallee = true;
				}
				for (step in plan.steps)
					steps.push(step);
			}
			if (!plan.completes)
				return {steps: steps, value: null, completes: false};
			if (plan.value == null)
				throw "control lowering requires a value for an expression operand in " + owner + " (" + Std.string(expression.getTag()) + ")";
			values.push(plan.value);
		}
		// Capturing a method performs receiver binding and lookup before argument
		// effects. Its invocation now consumes that value, not a newly selected
		// member named after the temporary. The captured read retains its exact
		// declaration; shared function-call checking retains the argument contract.
		final lowered = capturedCallee ? TypedExpr.functionValueCall(values[0], values.slice(1), expression.getType(), expression.getPosition(),
			expression.getArgumentBinding()) : expression.withExpressions(values);
		return {steps: steps, value: lowered, completes: true};
	}
}
