import haxe.ds.StringMap;
import TypedCaptureBinding.TypedCaptureCreation;

/** Real executable inputs preserve initializer ownership without inventing a function. */
private typedef CaptureAnalysisInput = {
	final owner:String;
	final revision:String;
	final receiver:Null<TyNominalTypeId>;
	final parameters:Array<TyLocalBinding>;
	final locals:Null<Array<TyLocalBinding>>;
	final statements:Array<TypedStmt>;
	final expressions:Array<TypedExpr>;
}

/**
	Finds lexical capture dependencies before or after shared control lowering.
	The pre-control body can already contain abstract-operator temporaries with
	exact compiler bindings. Those declarations do not introduce callable scopes.
	Authored analysis establishes function origins. Lowered analysis checks those
	origins and records executable declarations, including introduced temporaries.
	Each plan binds one exact typed revision and owns no target storage.
	Receiver dependencies use resolved declarations, never emitted names.
 */
class TypedCapturePlan {
	public final ownerIdentity:String;
	public final bodyRevision:String;
	public final sourceBodyRevision:String;
	public final receiverOwner:Null<TyNominalTypeId>;

	/** Exact type of authored this reads; a superclass read does not change this type. */
	public final receiverType:Null<TyType>;

	final functions:Array<TypedCaptureFunction>;
	final bindings:Array<TypedCaptureBinding>;
	final occurrences:Array<CaptureOccurrence>;
	final canonicalIdentity:String;

	function new(input:CaptureAnalysisInput, ?origin:TypedCapturePlan) {
		ownerIdentity = input.owner;
		bodyRevision = input.revision;
		sourceBodyRevision = origin == null ? bodyRevision : origin.bodyRevision;
		final analysis = new CaptureAnalysis(input, origin);
		analysis.run();
		functions = analysis.freezeFunctions();
		bindings = analysis.bindings.copy();
		occurrences = analysis.occurrences.copy();
		receiverOwner = analysis.receiverOwner;
		receiverType = analysis.receiverType;
		final facts:Array<Null<String>> = [
			"typed-capture-plan-v3",
			ownerIdentity,
			bodyRevision,
			origin == null ? null : sourceBodyRevision,
			receiverOwner == null ? null : receiverOwner.getCanonicalName(),
			receiverType == null ? null : receiverType.getSemanticKey(),
			Std.string(bindings.length)
		];
		for (binding in bindings)
			facts.push(binding.getCanonicalIdentity());
		facts.push(Std.string(functions.length));
		for (entry in functions) {
			facts.push(entry.identity);
			facts.push(entry.parentIdentity);
			facts.push(entry.controlTargetIdentity);
			facts.push(entry.namedBinding == null ? null : entry.namedBinding.getCanonicalIdentity());
			facts.push(Std.string(entry.directReceiver));
			facts.push(Std.string(entry.capturesReceiver));
			facts.push(CompilerCacheIdentity.encode([for (binding in entry.getDirectCaptures()) binding.getCanonicalIdentity()]));
			facts.push(CompilerCacheIdentity.encode([for (binding in entry.getCaptures()) binding.getCanonicalIdentity()]));
		}
		canonicalIdentity = CompilerCacheIdentity.encode(facts);
	}

	public static function analyze(fn:TypedFunction):TypedCapturePlan
		return new TypedCapturePlan(functionInput(fn));

	/**
		Recompute captures from the actual lowered body, retaining authored function identities.
		The shared lowerer can remove unreachable code and introduce local temporaries.
		Surviving closures keep their original parameters and lexical parent.
		Their captures must remain within the original dependency set.
		This validates capture transfer, not the general semantic equivalence of arbitrary rewrites.
	 */
	public static function afterLowering(source:TypedFunction, lowered:TypedFunction):TypedCapturePlan {
		final origin = analyze(source);
		if (lowered.getStableIdentity() != origin.ownerIdentity
			|| lowered.getBody().getSourceFingerprint() != source.getBody().getSourceFingerprint())
			throw "capture lowering requires the same authored function";
		return new TypedCapturePlan(functionInput(lowered), origin);
	}

	/** A field is the real root executable; its authored lambdas remain separate functions. */
	public static function analyzeInitializer(initializer:TypedFieldInitializer):TypedCapturePlan
		return new TypedCapturePlan(initializerInput(initializer, null));

	/** Retain authored initializer binding and closure identities through shared lowering. */
	public static function afterInitializerLowering(initializer:TypedFieldInitializer, expressions:Array<TypedExpr>):TypedCapturePlan
		return new TypedCapturePlan(initializerInput(initializer, expressions), analyzeInitializer(initializer));

	/** Check the same owner and exact authored or lowered initializer revision. */
	public function assertInitializerCurrent(initializer:TypedFieldInitializer, ?expressions:Array<TypedExpr>):Void {
		final input = initializerInput(initializer, expressions);
		if (input.owner != ownerIdentity || input.revision != bodyRevision)
			throw "capture plan belongs to another typed initializer revision";
	}

	static function functionInput(fn:TypedFunction):CaptureAnalysisInput {
		fn.assertParsedBodyCurrent();
		final environment = fn.getEnvironment();
		if (environment == null)
			throw "capture analysis requires the frozen function environment";
		final declaration = fn.getDeclaration();
		return {
			owner: fn.getStableIdentity(),
			revision: CompilerTypedTreeRevision.functionBody(fn),
			receiver: declaration == null || declaration.getIsStatic() ? null : declaration.getOwner(),
			parameters: [for (parameter in environment.getParams()) parameter.toBinding()],
			locals: [for (local in environment.getLocals()) local.toBinding()],
			statements: fn.getBody().getStatements(),
			expressions: [for (value in fn.getDefaults()) value.getExpression()]
		};
	}

	static function initializerInput(initializer:TypedFieldInitializer, lowered:Null<Array<TypedExpr>>):CaptureAnalysisInput {
		final field = initializer.getField();
		final owner = field.getCanonicalKey();
		final expressions = lowered == null ? [initializer.getExpression()] : lowered.copy();
		final revision = lowered == null ? CompilerTypedTreeRevision.expression(owner,
			initializer.getExpression()) : CompilerCacheIdentity.encode(["capture-initializer-body-v1", owner].concat([
				for (expression in expressions)
					CompilerTypedTreeRevision.expression(owner, expression)
			]));
		return {
			owner: owner,
			revision: revision,
			receiver: field.getIsStatic() ? null : field.getOwner(),
			parameters: [],
			locals: null,
			statements: [],
			expressions: expressions
		};
	}

	/** Exact immutable nodes distinguish two projections of otherwise identical function bodies. */
	public function getFunctionExpressions():Array<TypedExpr>
		return [for (entry in occurrences) entry.expression];

	public function requireFunction(expression:TypedExpr):TypedCaptureFunction {
		for (entry in occurrences)
			if (entry.expression == expression)
				for (fn in functions)
					if (fn.identity == entry.identity)
						return fn;
		throw "closure is not an exact occurrence in this capture plan";
	}

	/** Requires the exact authored or lowered revision bound when this plan was constructed. */
	public function assertCurrent(fn:TypedFunction):Void {
		fn.assertParsedBodyCurrent();
		if (fn.getStableIdentity() != ownerIdentity || CompilerTypedTreeRevision.functionBody(fn) != bodyRevision)
			throw "capture plan belongs to another typed function revision";
	}

	public function getFunctions():Array<TypedCaptureFunction>
		return functions.copy();

	public function getBindings():Array<TypedCaptureBinding>
		return bindings.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;
}

/** Occurrence identity is local to one immutable typed body, even when source identities agree. */
private typedef CaptureOccurrence = {
	final expression:TypedExpr;
	final identity:String;
}

/** Mutable construction state stays private; callers receive only frozen facts. */
private class CaptureFunctionState {
	public final identity:String;
	public final parent:Null<CaptureFunctionState>;
	public final occurrence:String;
	public final controlTargetIdentity:Null<String>;
	public final namedBinding:Null<TyLocalBinding>;
	public final references:Array<TyLocalBinding> = [];
	public final direct:StringMap<Bool> = new StringMap();
	public final captures:StringMap<Bool> = new StringMap();
	public var directReceiver:Bool = false;
	public var capturesReceiver:Bool = false;

	public function new(identity:String, parent:Null<CaptureFunctionState>, occurrence:String, namedBinding:Null<TyLocalBinding>,
			controlTargetIdentity:Null<String>) {
		this.identity = identity;
		this.parent = parent;
		this.occurrence = occurrence;
		this.controlTargetIdentity = controlTargetIdentity;
		this.namedBinding = namedBinding;
	}
}

/** Registers declarations before resolving references, then forwards captures through lexical parents. */
private class CaptureAnalysis {
	final input:CaptureAnalysisInput;
	final owner:String;
	final origin:Null<TypedCapturePlan>;
	final functions:Array<CaptureFunctionState> = [];
	final sourceFunctions:StringMap<TypedCaptureFunction> = new StringMap();
	final sourceExpressions:StringMap<TypedExpr> = new StringMap();
	final sourceBindings:StringMap<TypedCaptureBinding> = new StringMap();
	final seenFunctions:StringMap<Bool> = new StringMap();
	final seenTargets:StringMap<Bool> = new StringMap();

	public final bindings:Array<TypedCaptureBinding> = [];
	public final occurrences:Array<CaptureOccurrence> = [];
	public var receiverOwner:Null<TyNominalTypeId> = null;
	public var receiverType:Null<TyType> = null;

	final declarations:StringMap<TypedCaptureBinding> = new StringMap();

	public function new(input:CaptureAnalysisInput, origin:Null<TypedCapturePlan>) {
		this.input = input;
		this.origin = origin;
		owner = input.owner;
		if (origin != null) {
			for (binding in origin.getBindings())
				sourceBindings.set(binding.binding.getIdentity().getCanonicalKey(), binding);
			for (facts in origin.getFunctions())
				if (facts.controlTargetIdentity != null)
					sourceFunctions.set(facts.controlTargetIdentity, facts);
			for (expression in origin.getFunctionExpressions())
				sourceExpressions.set(expression.getControlTarget().getCanonicalIdentity(), expression);
		}
	}

	function functionAt(path:String, parent:Null<CaptureFunctionState>, named:Null<TyLocalBinding>, ?controlTargetIdentity:String):CaptureFunctionState {
		// Like TyLocalId, this key is scoped to the plan's checked body revision.
		// Repeating that full revision here would copy it into every local fact.
		var identity = CompilerCacheIdentity.encode(["capture-function-v1", owner, path]);
		if (origin != null) {
			final source = parent == null ? origin.getFunctions()[0] : sourceFunctions.get(controlTargetIdentity);
			if (source == null)
				throw "lowered closure has no authored function origin";
			if (source.parentIdentity != (parent == null ? null : parent.identity))
				throw "lowered closure changed its lexical function parent";
			identity = source.identity;
			path = source.occurrence;
			named = source.namedBinding;
		}
		if (seenFunctions.exists(identity))
			throw "capture analysis found a repeated function origin";
		seenFunctions.set(identity, true);
		if (controlTargetIdentity != null) {
			if (seenTargets.exists(controlTargetIdentity))
				throw "capture analysis found a repeated function control target";
			seenTargets.set(controlTargetIdentity, true);
		}
		final result = new CaptureFunctionState(identity, parent, path, named, controlTargetIdentity);
		functions.push(result);
		return result;
	}

	function declare(binding:TyLocalBinding, scope:CaptureFunctionState, path:String, slot:Int, creation:TypedCaptureCreation):Void {
		if (binding.getIdentity().getOwnerIdentity() != owner)
			throw "capture declaration belongs to another typed function";
		final key = binding.getIdentity().getCanonicalKey();
		if (origin != null) {
			final source = sourceBindings.get(key);
			if (source == null) {
				if (binding.getKind() != CompilerTemporary)
					throw "lowered capture declaration has no authored binding";
			} else if (source.binding.getCanonicalIdentity() != binding.getCanonicalIdentity()
				|| source.functionIdentity != scope.identity
				|| source.creation != creation) {
				throw "lowering changed capture declaration ownership or creation";
			}
		}
		final previous = declarations.get(key);
		if (previous != null) {
			// OR-pattern alternatives deliberately repeat the same declaration.
			if (creation == PatternMatch
				&& previous.creation == PatternMatch
				&& previous.occurrence == path
				&& previous.functionIdentity == scope.identity
				&& previous.binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
				return;
			throw "capture analysis found a repeated declaration identity";
		}
		final fact = new TypedCaptureBinding(binding, scope.identity, path, slot, creation);
		declarations.set(key, fact);
		bindings.push(fact);
	}

	function declareAll(values:Array<TyLocalBinding>, scope:CaptureFunctionState, path:String, creation:TypedCaptureCreation):Void {
		for (index in 0...values.length)
			declare(values[index], scope, path, index, creation);
	}

	/** Every nested use retains the enclosing method receiver, including forwarding-only closures. */
	function useReceiver(scope:CaptureFunctionState):Void {
		if (input.receiver == null)
			throw "capture analysis requires a resolved instance declaration for receiver ownership";
		receiverOwner = input.receiver;
		scope.directReceiver = true;
		var cursor = scope;
		while (cursor.parent != null) {
			cursor.capturesReceiver = true;
			cursor = cursor.parent;
		}
	}

	function expression(node:TypedExpr, scope:CaptureFunctionState, path:String, resolvedCallee:Bool = false):Void {
		final children = node.getExpressions();
		final locals = node.getLocalBindings();
		switch (node.getTag()) {
			case MacroExpr | MacroType:
				return;
			case SourceFunction:
				if (origin != null)
					throw "capture transfer requires fully lowered executable functions";
				final source = node.getSourceFunction();
				final target = node.getControlTarget();
				if (target == null || target.getOwnerIdentity() != owner || target.getKind() != Function)
					throw "capture analysis requires the exact source function control target";
				final named = source != null && source.getDeclaredName() != null;
				if (named) {
					if (locals.length == 0 || locals[0].getKind() != NamedFunction)
						throw "capture analysis requires the exact named-function binding";
					declare(locals[0], scope, path, 0, Declaration);
				}
				final childScope = functionAt(path, scope, named ? locals[0] : null, target == null ? null : target.getCanonicalIdentity());
				occurrences.push({expression: node, identity: childScope.identity});
				declareAll(named ? locals.slice(1) : locals, childScope, path, FunctionEntry);
				for (use in node.getCatchUses())
					childScope.references.push(use.binding);
				for (index in 0...children.length)
					expression(children[index], childScope, path + "/e" + index);
				return;
			case Lambda:
				if (origin == null)
					throw "capture analysis requires explicit provenance for legacy or lowered lambdas";
				final body = children.length == 1 ? children[0] : null;
				final target = body == null ? null : body.getControlTarget();
				if (body == null || body.getTag() != ControlRegion || target == null || target.getKind() != Function)
					throw "lowered closure requires its exact function body origin";
				final targetIdentity = target.getCanonicalIdentity();
				final authored = sourceExpressions.get(targetIdentity);
				if (authored == null)
					throw "lowered closure has no authored function origin";
				final parameters = authored.getSourceFunction().getDeclaredName() == null ? authored.getLocalBindings() : authored.getLocalBindings().slice(1);
				if (parameters.length != locals.length || authored.getType().getSemanticKey() != node.getType().getSemanticKey())
					throw "lowered closure changed its callable signature";
				for (index in 0...parameters.length)
					if (parameters[index].getCanonicalIdentity() != locals[index].getCanonicalIdentity())
						throw "lowered closure changed its parameter bindings";
				final childScope = functionAt(path, scope, null, targetIdentity);
				occurrences.push({expression: node, identity: childScope.identity});
				declareAll(locals, childScope, path, FunctionEntry);
				for (use in node.getCatchUses())
					childScope.references.push(use.binding);
				expression(body, childScope, path + "/e0");
				return;
			case LocalRead:
				if (locals.length != 1)
					throw "capture analysis requires one exact binding for every local reference";
				scope.references.push(locals[0]);
			case VariableDeclaration:
				declareAll(locals, scope, path, Declaration);
			case Temporary:
				// Abstract operators already introduce exact temporaries before
				// control lowering. They are declarations, not lowered control flow.
				if (locals.length != 1
					|| locals[0].getKind() != CompilerTemporary
					|| !locals[0].getIdentity().isCompilerTemporary()
					|| children.length != 1
					|| locals[0].getType().getSemanticKey() != children[0].getType().getSemanticKey())
					throw "capture temporary requires one exact compiler binding and matching initializer type";
				declare(locals[0], scope, path, 0, Declaration);
			case SourceTry | ControlTry:
				if (node.getTag() == ControlTry && origin == null)
					throw "capture analysis requires authored catch declarations before lowering";
				declareAll(locals, scope, path, CatchEntry);
			case SourceFor | ArrayComprehension | ControlFor:
				if (node.getTag() == ControlFor && origin == null)
					throw "capture analysis requires the authored typed body before control lowering";
				declareAll(locals, scope, path, LoopIteration);
			case SwitchExpr | ControlSwitch:
				if (node.getTag() == ControlSwitch && origin == null)
					throw "capture analysis requires the authored typed body before control lowering";
				declareAll(locals, scope, path, PatternMatch);
			case ThisValue:
				if (receiverType != null && receiverType.getSemanticKey() != node.getType().getSemanticKey())
					throw "capture analysis found inconsistent receiver types";
				receiverType = node.getType();
				if (origin != null
					&& (origin.receiverType == null || origin.receiverType.getSemanticKey() != receiverType.getSemanticKey()))
					throw "lowering changed the receiver type";
				useReceiver(scope);
			case SuperValue:
				useReceiver(scope);
			case NameRead:
				if (node.getFieldInfo() != null && !node.getFieldInfo().getIsStatic())
					useReceiver(scope);
				// A selected static method is a value without a lexical receiver or
				// local capture, even when grouping separates it from a call node.
				if (node.getFieldInfo() == null
					&& node.getType().isFunction()
					&& !resolvedCallee
					&& (node.getDeclaration() == null || !node.getDeclaration().getIsStatic()))
					throw "capture analysis requires an exact declaration for a bare method value in "
						+ owner
						+ " at "
						+ path
						+ ": "
						+ node.getTexts().join(".");
			case Call:
				if (node.getDeclaration() != null
					&& !node.getDeclaration().getSignature().getIsStatic()
					&& children.length > 0
					&& children[0].getTag() == NameRead)
					useReceiver(scope);
			case ControlRegion | ControlBranch | ControlWhile | FixedRange:
				if (origin == null)
					throw "capture analysis requires the authored typed body before control lowering in "
						+ owner
						+ " at "
						+ path
						+ ": "
						+ node.getTag();
				if (node.getTag() == ControlRegion
					&& node.getControlTarget() != null
					&& node.getControlTarget().getCanonicalIdentity() != scope.controlTargetIdentity)
					throw "lowered function region belongs to another lexical function";
			case Opaque:
				throw "capture analysis cannot prove dependencies inside opaque source syntax";
			case _:
		}
		for (index in 0...children.length)
			expression(children[index], scope, path + "/e" + index, node.getTag() == Call && index == 0 && node.getDeclaration() != null);
	}

	function statement(node:TypedStmt, scope:CaptureFunctionState, path:String):Void {
		final creation = switch (node.getTag()) {
			case ForIn | ForKeyValue: LoopIteration;
			case Switch: PatternMatch;
			case Try: CatchEntry;
			case _: Declaration;
		};
		declareAll(node.getLocalBindings(), scope, path, creation);
		for (use in node.getCatchUses())
			scope.references.push(use.binding);
		final values = node.getExpressions();
		for (index in 0...values.length)
			expression(values[index], scope, path + "/e" + index);
		final children = node.getStatements();
		for (index in 0...children.length)
			statement(children[index], scope, path + "/s" + index);
	}

	public function run():Void {
		final root = functionAt("root", null, null);
		declareAll(input.parameters, root, "entry", FunctionEntry);
		for (index in 0...input.statements.length)
			statement(input.statements[index], root, "s" + index);
		for (index in 0...input.expressions.length)
			expression(input.expressions[index], root, "e" + index);
		for (local in (origin == null && input.locals != null ? input.locals : [])) {
			final declaration = declarations.get(local.getIdentity().getCanonicalKey());
			if (declaration == null || declaration.binding.getCanonicalIdentity() != local.getCanonicalIdentity())
				throw "capture analysis did not account for the complete frozen local catalog";
		}
		for (scope in functions)
			for (reference in scope.references) {
				final key = reference.getIdentity().getCanonicalKey();
				final binding = declarations.get(key);
				if (binding == null || binding.binding.getCanonicalIdentity() != reference.getCanonicalIdentity())
					throw "capture reference lacks its exact frozen declaration";
				if (binding.functionIdentity == scope.identity)
					continue;
				if (origin != null && binding.binding.getKind() == CompilerTemporary)
					throw "control lowering introduced a captured temporary without an authored dependency";
				scope.direct.set(key, true);
				var cursor:Null<CaptureFunctionState> = scope;
				while (cursor != null && cursor.identity != binding.functionIdentity) {
					cursor.captures.set(key, true);
					cursor = cursor.parent;
				}
				if (cursor == null)
					throw "capture reference is outside its lexical function ancestry";
			}
		if (origin != null)
			for (scope in functions) {
				final source = scope.parent == null ? origin.getFunctions()[0] : sourceFunctions.get(scope.controlTargetIdentity);
				final allowed = new StringMap<Bool>();
				for (binding in source.getCaptures())
					allowed.set(binding.getIdentity().getCanonicalKey(), true);
				for (key in scope.captures.keys())
					if (!allowed.exists(key))
						throw "lowering introduced a new capture dependency";
				if (scope.capturesReceiver && !source.capturesReceiver)
					throw "lowering introduced a new receiver capture";
			}
	}

	/** Declaration traversal order makes capture order independent of reference order and map iteration. */
	public function freezeFunctions():Array<TypedCaptureFunction>
		return [
			for (scope in functions)
				new TypedCaptureFunction({
					identity: scope.identity,
					parentIdentity: scope.parent == null ? null : scope.parent.identity,
					occurrence: scope.occurrence,
					controlTargetIdentity: scope.controlTargetIdentity,
					namedBinding: scope.namedBinding,
					directCaptures: [
						for (fact in bindings)
							if (scope.direct.exists(fact.binding.getIdentity().getCanonicalKey())) fact.binding
					],
					captures: [
						for (fact in bindings)
							if (scope.captures.exists(fact.binding.getIdentity().getCanonicalKey())) fact.binding
					],
					directReceiver: scope.directReceiver,
					capturesReceiver: scope.capturesReceiver
				})
		];
}
