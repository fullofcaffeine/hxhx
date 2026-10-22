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
	var iterationStorage:Null<JsIterationCaptureStorage> = null;
	var allocationScope:Null<JsFunctionScope> = null;
	var initializerPrefix:String = "";
	var enumDeclarations:Null<String->JsClassInheritancePlan.JsClassInheritanceNode>;
	var abstractPlan:Null<JsAbstractValuePlan>;
	var abstractValues:Null<JsAbstractValueScope>;

	/** Initializers and nested closures keep their exact executable occurrence owner. */
	public function setAbstractPlan(plan:JsAbstractValuePlan):Void {
		abstractPlan = plan;
		abstractValues = controlProjection == null ? null : plan.forFunction(controlProjection);
	}

	/** Share the program's admitted enum owners with every expression and nested initializer. */
	public function setEnumDeclarations(resolve:String->JsClassInheritancePlan.JsClassInheritanceNode):Void {
		enumDeclarations = resolve;
	}

	/** Fields share their enclosing JavaScript variable scope, but never another field's local bindings. */
	public static function initializer(parent:JsFunctionScope, projection:TypedBackendFieldInitializerProjection, types:JsRuntimeTypeScope):JsFunctionScope {
		projection.assertCurrent();
		final child = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, projection.getLocalCatalog(), projection.getFieldReadCatalog(), types,
			projection.findMethodUse);
		final outer = parent.exprScope();
		child.abstractPlan = parent.abstractPlan;
		child.abstractValues = parent.abstractPlan == null ? null : parent.abstractPlan.forInitializer(projection);
		child.iterationStorage = new JsIterationCaptureStorage(projection.requireCaptureCatalog, projection.getLocalCatalog());
		child.parentScope = {
			resolveLocal: outer.resolveLocal,
			resolveClassRef: outer.resolveClassRef,
			resolveSuperClassRef: outer.resolveSuperClassRef,
			runtimeTypes: types,
			abstractValues: child.abstractValues,
			enumDeclarations: outer.enumDeclarations,
			namedPatterns: projection.findNamedPattern,
			methodUses: projection.findMethodUse,
			lambdaUses: projection.findLambda,
			iterationStorage: child.iterationStorage,
			resolveIterationCell: outer.resolveIterationCell,
			callableExpressions: projection.findCallableExpression,
			requireExpression: projection.requireExpression,
			abstractReceiver: outer.abstractReceiver
		};
		child.abstractReceiver = outer.abstractReceiver == true;
		child.allocationScope = parent;
		// Exact UTF-8 encoding keeps different field owners distinct even when their
		// punctuation would collapse to the same ordinary JavaScript identifier.
		child.initializerPrefix = "__hx_init_" + haxe.io.Bytes.ofString(projection.getStableIdentity()).toHex() + "_";
		return child;
	}

	/** Retain the exact method owner; validate it only when emitting shared control. */
	public function setControlProjection(projection:TypedBackendFunctionProjection):Void {
		controlProjection = projection;
		iterationStorage = new JsIterationCaptureStorage(projection.requireCaptureCatalog, projection.getLocalCatalog());
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
		child.iterationStorage = parent == null ? null : parent.iterationStorage;
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
		if (allocationScope != null)
			return allocationScope.reserve(initializerPrefix + name);
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

	/**
		Each switch attempt owns its local bindings and shares the enclosing name allocator.
		Emission can fail without changing the parent's bindings or catching its error.
		This is a lexical block in the same function, so exact typing and capture facts stay shared.
	 */
	public function lexicalChild():JsFunctionScope {
		final child = new JsFunctionScope(classRefs, instanceFields, superClassRef, localCatalog, fieldCatalog, runtimeTypes, methodUses);
		for (name => value in locals)
			child.locals.set(name, value);
		child.parentScope = parentScope;
		child.abstractReceiver = abstractReceiver;
		child.controlProjection = controlProjection;
		child.iterationStorage = iterationStorage;
		child.allocationScope = this;
		child.enumDeclarations = enumDeclarations;
		child.abstractPlan = abstractPlan;
		child.abstractValues = abstractValues;
		return child;
	}

	/** A wrapper parameter captures the cell object, while ordinary reads use its value. */
	public function bindIterationCell(raw:String):String {
		if (!isIterationCapture(raw))
			throw "JavaScript capture wrapper requires an exact captured declaration";
		final name = reserve("$hx_iteration");
		locals.set(raw, name);
		return name;
	}

	public function isIterationCapture(raw:String):Bool
		return iterationStorage != null && iterationStorage.isCaptured(raw);

	/** Resolve cell identity separately from its mutable value, including forwarded captures. */
	public function resolveIterationCell(raw:String):Null<String> {
		final local = locals.get(raw);
		if (local != null && isIterationCapture(raw))
			return local;
		return parentScope == null || parentScope.resolveIterationCell == null ? null : parentScope.resolveIterationCell(raw);
	}

	/** Resolve lexical locals first, then the exact field selected by shared typing. */
	public function resolveLocal(raw:String):Null<String> {
		final local = locals.get(raw);
		if (local != null)
			return isIterationCapture(raw) ? local + ".value" : local;
		// Exact bare reads can belong to a static or inherited field. Locals have
		// already been resolved above, so lexical shadowing retains precedence.
		final read = fieldCatalog == null ? null : fieldCatalog.findByProjectedName(raw);
		if (read != null) {
			final field = read.getField();
			final receiver = field.getIsStatic() ? resolveClassRef(field.getOwner().getCanonicalName()) : "this";
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
			abstractValues: abstractValues != null ? abstractValues : parentScope == null ? null : parentScope.abstractValues,
			enumDeclarations: enumDeclarations != null ? enumDeclarations : parentScope == null ? null : parentScope.enumDeclarations,
			namedPatterns: controlProjection != null ? controlProjection.findNamedPattern : parentScope == null ? null : parentScope.namedPatterns,
			methodUses: initializerMethods == null ? methodUses : initializerMethods,
			lambdaUses: initializerLambdas != null ? initializerLambdas : controlProjection != null ? controlProjection.findLambda : parentScope == null ? null : parentScope.lambdaUses,
			iterationStorage: iterationStorage,
			resolveIterationCell: self.resolveIterationCell,
			callableExpressions: controlProjection != null ? controlProjection.findCallableExpression : parentScope == null ? null : parentScope.callableExpressions,
			requireExpression: initializerLambdas != null ? null : controlProjection != null ? controlProjection.requireExpression : parentScope == null ? null : parentScope.requireExpression,
			abstractReceiver: abstractReceiver
		};
	}
}
