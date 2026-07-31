package backend.source;

import backend.source.PhpFunctionLoweringPlan.PhpFunctionPlanLocalFact;

enum PhpLexicalScopeKind {
	Function;
	Block;
	Loop;
	Catch;
	SwitchCase;
	Lambda;
}

typedef PhpLexicalLocalFact = {
	final targetName:String;
	final bindingIdentity:Null<String>;
	final sourceName:String;
	final semanticType:Null<TyType>;
	final typeIdentity:Null<String>;
	final typeDisplay:String;
	final targetTypeHint:String;
	final declarationKind:TyLocalDeclarationKind;
	final isRestCarrier:Bool;
	final isTargetSynthetic:Bool;
};

/**
	Request-local lexical state for rendering one PHP function body.

	The root activates exact typed parameters from `PhpFunctionLoweringPlan`.
	Entering a declaration activates another exact planned local; target-only
	temporaries must be added explicitly. Every derivation copies its maps, so a
	block, loop, catch, switch case, or lambda cannot mutate a parent or sibling.

	This state is intentionally not revision-keyed or cacheable. Initializer
	expressions and capture decisions belong only to the active rendering
	request, while semantic local identity remains owned by the immutable plan.
**/
class PhpLexicalRenderScope {
	final plan:PhpFunctionLoweringPlan;
	final kind:PhpLexicalScopeKind;
	final depth:Int;
	final locals:haxe.ds.StringMap<PhpLexicalLocalFact>;
	final initializers:haxe.ds.StringMap<HxExpr>;
	final referenceCaptures:haxe.ds.StringMap<Bool>;
	final optionalLambdaArguments:haxe.ds.StringMap<Bool>;
	final thisValueSlot:Bool;
	final thisCaptureName:Null<String>;
	final preferredEnumOwnerIdentity:Null<String>;

	/** Create the validated root scope for one exact function plan. **/
	public static function forFunction(plan:PhpFunctionLoweringPlan):PhpLexicalRenderScope
		return new PhpLexicalRenderScope(plan, Function, 0, null, null, null, null, false, null, null);

	function new(plan:PhpFunctionLoweringPlan, kind:PhpLexicalScopeKind, depth:Int, ?locals:haxe.ds.StringMap<PhpLexicalLocalFact>,
			?initializers:haxe.ds.StringMap<HxExpr>, ?referenceCaptures:haxe.ds.StringMap<Bool>, ?optionalLambdaArguments:haxe.ds.StringMap<Bool>,
			thisValueSlot:Bool, ?thisCaptureName:String, ?preferredEnumOwnerIdentity:String) {
		if (plan == null)
			throw "PHP lexical render scope requires an exact function plan";
		this.plan = plan;
		this.kind = kind;
		this.depth = depth;
		if (this.depth < 0)
			throw "PHP lexical render scope requires a non-negative depth";
		this.locals = locals == null ? rootLocals(plan) : copyLocalMap(locals);
		this.initializers = copyExprMap(initializers);
		this.referenceCaptures = copyBoolMap(referenceCaptures);
		this.optionalLambdaArguments = copyBoolMap(optionalLambdaArguments);
		this.thisValueSlot = thisValueSlot;
		this.thisCaptureName = normalizeNullable(thisCaptureName);
		this.preferredEnumOwnerIdentity = normalizeNullable(preferredEnumOwnerIdentity);
	}

	public function getPlan():PhpFunctionLoweringPlan
		return plan;

	public function getKind():PhpLexicalScopeKind
		return kind;

	public function getDepth():Int
		return depth;

	/** Derive an independent lexical child with the requested semantic role. **/
	public function derive(childKind:PhpLexicalScopeKind):PhpLexicalRenderScope {
		if (childKind == null || childKind.match(Function))
			throw "PHP lexical child scope requires block, loop, catch, switch-case, or lambda kind";
		return copyState(childKind, depth + 1, locals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	/** Activate one exact typed local when its declaration enters lexical scope. **/
	public function withPlannedLocal(targetName:String):PhpLexicalRenderScope {
		final normalized = normalize(targetName);
		final planned = plan.findLocalByTargetName(normalized);
		if (planned == null)
			throw "PHP lexical scope cannot find planned local " + normalized + " in " + plan.getFunctionIdentity();
		final nextLocals = copyLocalMap(locals);
		final existing = nextLocals.get(normalized);
		if (existing != null && existing.bindingIdentity != planned.bindingIdentity)
			throw "PHP lexical scope cannot replace active local " + normalized + " with a different binding";
		nextLocals.set(normalized, fromPlanned(planned));
		return copyState(kind, depth, nextLocals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	/** Add a PHP-only temporary without inventing a target-neutral binding identity. **/
	public function withSyntheticLocal(targetName:String, ?targetTypeHint:String):PhpLexicalRenderScope {
		final normalized = requireTargetName(targetName);
		if (plan.findLocalByTargetName(normalized) != null)
			throw "PHP lexical scope cannot replace planned local " + normalized + " with a target-synthetic local";
		final nextLocals = copyLocalMap(locals);
		final existing = nextLocals.get(normalized);
		if (existing != null && !existing.isTargetSynthetic)
			throw "PHP lexical scope cannot replace exact local " + normalized + " with a target-synthetic local";
		nextLocals.set(normalized, {
			targetName: normalized,
			bindingIdentity: null,
			sourceName: "",
			semanticType: null,
			typeIdentity: null,
			typeDisplay: "",
			targetTypeHint: normalize(targetTypeHint),
			declarationKind: CompilerTemporary,
			isRestCarrier: false,
			isTargetSynthetic: true
		});
		return copyState(kind, depth, nextLocals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	/**
		Add a bounded PHP representation hint without replacing exact typing.

		A known semantic type or the required rest-array carrier is immutable.
		Only an unknown semantic type or an explicitly target-synthetic local may
		receive a different hint.
	**/
	public function withTargetTypeHint(targetName:String, targetTypeHint:String):PhpLexicalRenderScope {
		final normalized = requireTargetName(targetName);
		final incoming = normalize(targetTypeHint);
		final existing = locals.get(normalized);
		if (existing == null)
			throw "PHP lexical scope cannot add a type hint for inactive local " + normalized;
		if (!existing.isTargetSynthetic
			&& existing.semanticType != null
			&& !existing.semanticType.isUnknown()
			&& !existing.semanticType.isNoNormalCompletion()) {
			if (incoming == existing.targetTypeHint)
				return this;
			throw "PHP lexical scope cannot replace exact type " + existing.typeDisplay + " for " + normalized;
		}
		if (existing.isRestCarrier && incoming != existing.targetTypeHint)
			throw "PHP lexical scope cannot replace rest-array carrier for " + normalized;
		final nextLocals = copyLocalMap(locals);
		nextLocals.set(normalized, copyLocalWithHint(existing, incoming));
		return copyState(kind, depth, nextLocals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	public function withInitializer(targetName:String, initializer:HxExpr):PhpLexicalRenderScope {
		final normalized = requireActiveLocal(targetName);
		if (initializer == null)
			throw "PHP lexical scope requires an initializer expression for " + normalized;
		final nextInitializers = copyExprMap(initializers);
		nextInitializers.set(normalized, initializer);
		return copyState(kind, depth, locals, nextInitializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	public function withReferenceCapture(targetName:String):PhpLexicalRenderScope {
		final normalized = requireActiveLocal(targetName);
		final nextCaptures = copyBoolMap(referenceCaptures);
		nextCaptures.set(normalized, true);
		return copyState(kind, depth, locals, initializers, nextCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName, preferredEnumOwnerIdentity);
	}

	public function withOptionalLambdaArgument(targetName:String):PhpLexicalRenderScope {
		final normalized = requireActiveLocal(targetName);
		final nextOptional = copyBoolMap(optionalLambdaArguments);
		nextOptional.set(normalized, true);
		return copyState(kind, depth, locals, initializers, referenceCaptures, nextOptional, thisValueSlot, thisCaptureName, preferredEnumOwnerIdentity);
	}

	/**
		Record the PHP array carrier selected for one active rest parameter.

		The exact Haxe type remains `haxe.Rest<T>` in the immutable function plan.
		The rest-lambda marker selects PHP's variadic array representation only
		for this lexical scope, so sibling lambdas cannot inherit it.
	**/
	public function withRestCarrier(targetName:String):PhpLexicalRenderScope {
		final normalized = requireActiveLocal(targetName);
		final existing = locals.get(normalized);
		if (existing == null || existing.isTargetSynthetic)
			throw "PHP lexical scope requires an exact planned rest parameter " + normalized;
		final nextLocals = copyLocalMap(locals);
		final copy = copyLocal(existing);
		nextLocals.set(normalized, {
			targetName: copy.targetName,
			bindingIdentity: copy.bindingIdentity,
			sourceName: copy.sourceName,
			semanticType: copy.semanticType,
			typeIdentity: copy.typeIdentity,
			typeDisplay: copy.typeDisplay,
			targetTypeHint: "Array<RestValue>",
			declarationKind: copy.declarationKind,
			isRestCarrier: true,
			isTargetSynthetic: false
		});
		return copyState(kind, depth, nextLocals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			preferredEnumOwnerIdentity);
	}

	public function withThisValueSlot(enabled:Bool):PhpLexicalRenderScope
		return copyState(kind, depth, locals, initializers, referenceCaptures, optionalLambdaArguments, enabled, thisCaptureName, preferredEnumOwnerIdentity);

	public function withThisCapture(targetName:String):PhpLexicalRenderScope
		return copyState(kind, depth, locals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, requireTargetName(targetName),
			preferredEnumOwnerIdentity);

	/** Carry one exact enum owner while rendering a peer expression. **/
	public function withPreferredEnumOwner(ownerIdentity:String):PhpLexicalRenderScope
		return copyState(kind, depth, locals, initializers, referenceCaptures, optionalLambdaArguments, thisValueSlot, thisCaptureName,
			requireIdentity(ownerIdentity));

	public function findLocal(targetName:String):Null<PhpLexicalLocalFact> {
		final fact = locals.get(normalize(targetName));
		return fact == null ? null : copyLocal(fact);
	}

	public function copyLocals():Array<PhpLexicalLocalFact> {
		final names = [for (name in locals.keys()) name];
		names.sort((left, right) -> Reflect.compare(left, right));
		return [for (name in names) copyLocal(locals.get(name))];
	}

	/** Return active target type hints without exposing the mutable backing map. **/
	public function copyTargetTypeHints():haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		for (local in copyLocals())
			out.set(local.targetName, local.targetTypeHint);
		return out;
	}

	public function copyInitializers():haxe.ds.StringMap<HxExpr>
		return copyExprMap(initializers);

	public function copyReferenceCaptures():Array<String>
		return sortedBoolKeys(referenceCaptures);

	public function copyOptionalLambdaArguments():Array<String>
		return sortedBoolKeys(optionalLambdaArguments);

	public function usesThisValueSlot():Bool
		return thisValueSlot;

	public function getThisCaptureName():Null<String>
		return thisCaptureName;

	public function getPreferredEnumOwnerIdentity():Null<String>
		return preferredEnumOwnerIdentity;

	function requireActiveLocal(targetName:String):String {
		final normalized = requireTargetName(targetName);
		if (!locals.exists(normalized))
			throw "PHP lexical scope cannot find active local " + normalized;
		return normalized;
	}

	function copyState(nextKind:PhpLexicalScopeKind, nextDepth:Int, nextLocals:haxe.ds.StringMap<PhpLexicalLocalFact>,
			nextInitializers:haxe.ds.StringMap<HxExpr>, nextCaptures:haxe.ds.StringMap<Bool>, nextOptional:haxe.ds.StringMap<Bool>, nextThisValueSlot:Bool,
			nextThisCaptureName:Null<String>, nextPreferredEnumOwnerIdentity:Null<String>):PhpLexicalRenderScope
		return new PhpLexicalRenderScope(plan, nextKind, nextDepth, nextLocals, nextInitializers, nextCaptures, nextOptional, nextThisValueSlot,
			nextThisCaptureName, nextPreferredEnumOwnerIdentity);

	static function rootLocals(plan:PhpFunctionLoweringPlan):haxe.ds.StringMap<PhpLexicalLocalFact> {
		final out = new haxe.ds.StringMap<PhpLexicalLocalFact>();
		for (local in plan.copyLocals())
			if (local.declarationKind.match(Parameter))
				out.set(local.targetName, fromPlanned(local));
		return out;
	}

	static function fromPlanned(local:PhpFunctionPlanLocalFact):PhpLexicalLocalFact
		return {
			targetName: local.targetName,
			bindingIdentity: local.bindingIdentity,
			sourceName: local.sourceName,
			semanticType: local.semanticType,
			typeIdentity: local.typeIdentity,
			typeDisplay: local.typeDisplay,
			targetTypeHint: local.targetTypeHint,
			declarationKind: local.declarationKind,
			isRestCarrier: local.isRestCarrier,
			isTargetSynthetic: false
		};

	static function copyLocal(fact:PhpLexicalLocalFact):PhpLexicalLocalFact
		return {
			targetName: fact.targetName,
			bindingIdentity: fact.bindingIdentity,
			sourceName: fact.sourceName,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			targetTypeHint: fact.targetTypeHint,
			declarationKind: fact.declarationKind,
			isRestCarrier: fact.isRestCarrier,
			isTargetSynthetic: fact.isTargetSynthetic
		};

	static function copyLocalWithHint(fact:PhpLexicalLocalFact, targetTypeHint:String):PhpLexicalLocalFact {
		final copy = copyLocal(fact);
		return {
			targetName: copy.targetName,
			bindingIdentity: copy.bindingIdentity,
			sourceName: copy.sourceName,
			semanticType: copy.semanticType,
			typeIdentity: copy.typeIdentity,
			typeDisplay: copy.typeDisplay,
			targetTypeHint: targetTypeHint,
			declarationKind: copy.declarationKind,
			isRestCarrier: copy.isRestCarrier,
			isTargetSynthetic: copy.isTargetSynthetic
		};
	}

	static function copyLocalMap(values:haxe.ds.StringMap<PhpLexicalLocalFact>):haxe.ds.StringMap<PhpLexicalLocalFact> {
		final out = new haxe.ds.StringMap<PhpLexicalLocalFact>();
		if (values != null)
			for (name => fact in values)
				out.set(name, copyLocal(fact));
		return out;
	}

	static function copyExprMap(values:haxe.ds.StringMap<HxExpr>):haxe.ds.StringMap<HxExpr> {
		final out = new haxe.ds.StringMap<HxExpr>();
		if (values != null)
			for (name => expression in values)
				out.set(name, expression);
		return out;
	}

	static function copyBoolMap(values:haxe.ds.StringMap<Bool>):haxe.ds.StringMap<Bool> {
		final out = new haxe.ds.StringMap<Bool>();
		if (values != null)
			for (name => enabled in values)
				out.set(name, enabled);
		return out;
	}

	static function sortedBoolKeys(values:haxe.ds.StringMap<Bool>):Array<String> {
		final out = [for (name => enabled in values) if (enabled) name];
		out.sort((left, right) -> Reflect.compare(left, right));
		return out;
	}

	static function requireTargetName(value:String):String {
		final normalized = normalize(value);
		if (normalized.length == 0)
			throw "PHP lexical scope requires a target local name";
		return normalized;
	}

	static function requireIdentity(value:String):String {
		final normalized = normalize(value);
		if (normalized.length == 0)
			throw "PHP lexical scope requires a non-empty semantic identity";
		return normalized;
	}

	static function normalize(value:Null<String>):String
		return value == null ? "" : StringTools.trim(value);

	static function normalizeNullable(value:Null<String>):Null<String> {
		final normalized = normalize(value);
		return normalized.length == 0 ? null : normalized;
	}
}
