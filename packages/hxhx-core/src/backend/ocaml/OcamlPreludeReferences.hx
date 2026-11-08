package backend.ocaml;

/**
	Collects the names one static initializer or one class method refers to, so the
	native OCaml emitter can decide which methods must be written before the static values.

	Why
	- Haxe lets `static final table = build();` use a method declared later in the class.
	- OCaml evaluates top-level bindings in order. The emitter therefore writes the methods
	  that static initializers need into an early "prelude" `let rec` group, before the
	  static values, and follows the references of each selected method to close that group.
	- A method can be needed without being called: `["a"].map(shout)` or
	  `final f = shout;` reads `shout` as a first-class value. If the search only follows
	  direct calls, `shout` stays after the static values and OCaml reports `Unbound value`.

	What
	- `calls` holds every name that can select a module-local method binding: direct call
	  targets, exact typed call targets, typed method values owned by the current OCaml
	  module, and bare identifiers that are not locals. The caller keeps only names that
	  are methods of the class.
	- `idents` holds bare identifiers that are not locals. The caller uses it to find methods
	  that read static values, which cannot move before those values.

	How
	- The search uses `TypedBackendSourceWalk` children, so it visits every node the body
	  emitter renders, including groups, declarations and loops made by inline lowering.
	- Locals are recognized through the exact typed local catalog, not by source spelling
	  at each scope. A lambda parameter named like a method therefore does not select it.
	- Typed transport markers are decoded first, so their reserved marker names are never
	  recorded as references.
**/
class OcamlPreludeReferences {
	/** Names that may select a module-local method binding. */
	public final calls:Map<String, Bool> = new Map();

	/** Bare non-local identifiers, used to detect reads of static values. */
	public final idents:Map<String, Bool> = new Map();

	final locals:Null<TypedBackendLocalCatalog>;
	final findMethodUse:HxExpr->Null<TypedBackendMethodOccurrence>;
	final ownsMethod:TypedBackendMethodOccurrence->Bool;

	function new(locals:Null<TypedBackendLocalCatalog>, findMethodUse:HxExpr->Null<TypedBackendMethodOccurrence>,
			ownsMethod:TypedBackendMethodOccurrence->Bool) {
		this.locals = locals;
		this.findMethodUse = findMethodUse;
		this.ownsMethod = ownsMethod;
	}

	/**
		Collect the references of one method body, including its default argument values.
		`ownsMethod` must return true only for method values that the OCaml emitter renders
		as a binding of the module being emitted.
	**/
	public static function ofFunction(projection:TypedBackendFunctionProjection, ownsMethod:TypedBackendMethodOccurrence->Bool):OcamlPreludeReferences {
		final references = new OcamlPreludeReferences(projection.getLocalCatalog(), projection.findMethodUse, ownsMethod);
		final declaration = projection.getDeclaration();
		for (argument in HxFunctionDecl.getArgs(declaration))
			switch HxFunctionArg.getDefaultValue(argument) {
				case NoDefault:
				case Default(value):
					references.expression(value);
			}
		for (statement in HxFunctionDecl.getBody(declaration))
			references.statement(statement);
		return references;
	}

	/**
		Collect the references of one field initializer value.
		Without a typed projection (declaration-only bring-up modules), the value is still
		searched, but no name counts as a local and no typed method value is available.
	**/
	public static function ofInitializer(value:Null<HxExpr>, initializer:Null<TypedBackendFieldInitializerProjection>,
			ownsMethod:TypedBackendMethodOccurrence->Bool):OcamlPreludeReferences {
		final references = initializer == null ? new OcamlPreludeReferences(null, _ -> null,
			ownsMethod) : new OcamlPreludeReferences(initializer.getLocalCatalog(), initializer.findMethodUse, ownsMethod);
		references.expression(value);
		return references;
	}

	function isLocal(name:String):Bool
		return locals != null && locals.findByProjectedName(name) != null;

	function reference(name:Null<String>):Void {
		if (name != null && name.length > 0)
			calls.set(name, true);
	}

	function statement(node:Null<HxStmt>):Void {
		if (node == null)
			return;
		if (node.match(STargetScope(_, _, _)))
			throw "native target scope is not valid in this source or target phase";
		TypedBackendSourceWalk.statementChildren(node, expression, statement);
	}

	function expression(node:Null<HxExpr>):Void {
		if (node == null)
			return;
		// An enum constructor marker carries its constructor path; only the arguments execute.
		final enumCall = TypedExactEnumConstructorSource.decode(node);
		if (enumCall != null) {
			for (argument in enumCall.arguments)
				expression(argument);
			return;
		}
		final exactCall = TypedExactStaticCallSource.decode(node);
		if (exactCall != null) {
			reference(exactCall.method);
			expression(TypedExactStaticCallSource.ordinaryCall(exactCall));
			return;
		}
		// Typed method values (`this.method`, a bare `method`, or `Owner.method`) emit the
		// owner's binding by name, exactly as the method-value renderer selects it.
		final methodValue = findMethodUse(node);
		if (methodValue != null && ownsMethod(methodValue))
			reference(methodValue.getDeclaration().getSignature().getName());
		switch (node) {
			case EIdent(name) if (name != null && name.length > 0 && !isLocal(name)):
				idents.set(name, true);
				reference(name);
			// A call through a local callback does not select a same-named method.
			case ECall(EIdent(name), _) if (isLocal(name)):
			case ECall(_, _):
				reference(OcamlLocalCallDependency.calleeName(node));
			case _:
		}
		TypedBackendSourceWalk.expressionChildren(node, expression);
	}
}
