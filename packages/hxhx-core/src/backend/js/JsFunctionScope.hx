package backend.js;

/**
	Function-local symbol scope for JS emission.

	Why
	- Stage3 AST keeps original Haxe identifiers; JS emission needs deterministic, valid local names.
	- A shared scope object keeps statement and expression lowering consistent.
**/
class JsFunctionScope {
	final locals:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	final used:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
	final classRefs:haxe.ds.StringMap<String>;
	final instanceFields:haxe.ds.StringMap<String>;
	final superClassRef:Null<String>;
	final localCatalog:Null<TypedBackendLocalCatalog>;
	final fieldCatalog:Null<TypedBackendFieldReadCatalog>;
	final runtimeTypes:Null<JsRuntimeTypeScope>;
	final methodUses:Null<HxExpr->Null<TypedBackendMethodOccurrence>>;
	var tempCounter:Int = 0;
	var parentScope:Null<JsEmitScope> = null;
	var abstractReceiver:Bool = false;
	var controlProjection:Null<TypedBackendFunctionProjection> = null;

	/** Retain the exact method owner; validate it only when emitting shared control. */
	public function setControlProjection(projection:TypedBackendFunctionProjection):Void {
		controlProjection = projection;
	}

	public function requireControlIdentity():String {
		if (controlProjection == null)
			throw "JavaScript method control requires its exact function projection";
		return controlProjection.requireRootControlIdentity();
	}

	/** Consume the receiver storage already selected during exact class admission. */
	public function setReceiverPlan(plan:JsClassInheritancePlan.JsClassInheritanceNode):Void {
		abstractReceiver = plan.abstractReceiver;
	}

	/** Create a closure scope before emission, retaining outer locals and exact expression facts. */
	public static function nested(parent:JsEmitScope):JsFunctionScope {
		final child = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, null, null, parent == null ? null : parent.runtimeTypes,
			parent == null ? null : parent.methodUses);
		child.parentScope = parent;
		child.abstractReceiver = parent != null && parent.abstractReceiver == true;
		return child;
	}

	public function new(classRefs:haxe.ds.StringMap<String>, ?instanceFields:haxe.ds.StringMap<String>, ?superClassRef:String,
			?localCatalog:TypedBackendLocalCatalog, ?fieldCatalog:TypedBackendFieldReadCatalog, ?runtimeTypes:JsRuntimeTypeScope,
			?methodUses:HxExpr->Null<TypedBackendMethodOccurrence>) {
		this.classRefs = classRefs == null ? new haxe.ds.StringMap<String>() : classRefs;
		this.instanceFields = instanceFields == null ? new haxe.ds.StringMap<String>() : instanceFields;
		this.superClassRef = superClassRef;
		this.localCatalog = localCatalog;
		this.fieldCatalog = fieldCatalog;
		this.runtimeTypes = runtimeTypes;
		this.methodUses = methodUses;
	}

	function reserve(name:String):String {
		var candidate = JsNameMangler.identifier(name);
		if (candidate.length == 0)
			candidate = "_";
		if (!used.exists(candidate)) {
			used.set(candidate, true);
			return candidate;
		}
		var suffix = 1;
		while (used.exists(candidate + "_" + suffix))
			suffix++;
		final unique = candidate + "_" + suffix;
		used.set(unique, true);
		return unique;
	}

	public function declareLocal(raw:String):String {
		final existing = locals.get(raw);
		if (existing != null)
			return existing;
		final exact = localCatalog == null ? null : localCatalog.findByProjectedName(raw);
		final displayName = exact == null ? raw : exact.getBinding().getSourceName();
		final safe = reserve(displayName);
		locals.set(raw, safe);
		return safe;
	}

	/** Resolve lexical locals first, then the exact field selected by shared typing. */
	public function resolveLocal(raw:String):Null<String> {
		final local = locals.get(raw);
		if (local != null)
			return local;
		// Exact bare reads can belong to a static or inherited field. Locals have
		// already been resolved above, so lexical shadowing retains precedence.
		final read = fieldCatalog == null ? null : fieldCatalog.findByProjectedName(raw);
		if (read != null) {
			final field = read.getField();
			final receiver = field.getIsStatic() ? classRefs.get(field.getOwner().getCanonicalName()) : "this";
			if (receiver == null)
				throw "JavaScript bare field has no exact emitted owner: " + field.getCanonicalKey();
			return receiver + JsNameMangler.propertySuffix(field.getName());
		}
		final instanceField = instanceFields == null ? null : instanceFields.get(raw);
		return instanceField != null ? instanceField : parentScope == null ? null : parentScope.resolveLocal(raw);
	}

	/** Return the exact semantic local selected for one projected transport name. **/
	public function resolveLocalBinding(raw:String):Null<TyLocalBinding> {
		if (localCatalog == null)
			return null;
		final exact = localCatalog.findByProjectedName(raw);
		return exact == null ? null : exact.getBinding();
	}

	public function resolveClassRef(raw:String):Null<String> {
		final local = classRefs.get(raw);
		return local != null ? local : parentScope == null ? null : parentScope.resolveClassRef(raw);
	}

	public function resolveSuperClassRef():Null<String> {
		return superClassRef != null ? superClassRef : parentScope == null ? null : parentScope.resolveSuperClassRef();
	}

	public function freshTemp(prefix:String):String {
		final base = prefix == null || prefix.length == 0 ? "__tmp" : prefix;
		while (true) {
			final name = reserve(base + "_" + tempCounter);
			tempCounter++;
			if (name != null && name.length > 0)
				return name;
		}
		return reserve("__tmp_fallback");
	}

	/** Initializers select their own executable catalog even when emitted inside a constructor. */
	public function exprScope(?initializerTypes:JsRuntimeTypeScope, ?initializerMethods:HxExpr->Null<TypedBackendMethodOccurrence>,
			?initializerLambdas:HxExpr->Null<TypedBackendLambdaOccurrence>):JsEmitScope {
		final self = this;
		return {
			resolveLocal: function(name:String):Null<String> return self.resolveLocal(name),
			resolveClassRef: function(name:String):Null<String> return self.resolveClassRef(name),
			resolveSuperClassRef: function():Null<String> return self.resolveSuperClassRef(),
			runtimeTypes: initializerTypes == null ? runtimeTypes : initializerTypes,
			methodUses: initializerMethods == null ? methodUses : initializerMethods,
			lambdaUses: initializerLambdas != null ? initializerLambdas : controlProjection != null ? controlProjection.findLambda : parentScope == null ? null : parentScope.lambdaUses,
			requireExpression: initializerLambdas != null ? null : controlProjection != null ? controlProjection.requireExpression : parentScope == null ? null : parentScope.requireExpression,
			abstractReceiver: abstractReceiver
		};
	}
}
