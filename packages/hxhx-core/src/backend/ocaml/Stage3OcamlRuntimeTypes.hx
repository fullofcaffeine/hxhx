package backend.ocaml;

/** A standard predicate keeps its value operand and exact declaration-selected type argument. */
private typedef Stage3OcamlNominalCall = {
	final target:TypedBackendRuntimeTypeOccurrence;
	final value:HxExpr;
}

/**
	Check class predicates against the exact declarations and executable projections
	of one native request. Only generated Haxe objects carry the private descriptor
	used here. Runtime-owned classes and type values need separate representations.
	Validation precedes output so unsupported operations cannot replace an artifact.
 */
class Stage3OcamlRuntimeTypes {
	final classes:Stage3OcamlClassStorage;
	final functions = new haxe.ds.ObjectMap<TypedBackendFunctionProjection, Bool>();
	final initializers = new haxe.ds.ObjectMap<TypedBackendFieldInitializerProjection, Bool>();
	final occurrences = new haxe.ds.ObjectMap<TypedBackendRuntimeTypeOccurrence, Bool>();
	final predicateArguments = new haxe.ds.ObjectMap<TypedBackendRuntimeTypeOccurrence, Bool>();

	public function new(modules:Array<TypedModule>, classes:Stage3OcamlClassStorage) {
		this.classes = classes;
		for (module in modules)
			for (owner in module.getBackendProjection().getClasses()) {
				for (fn in owner.getFunctions()) {
					functions.set(fn, true);
					fn.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inFunction(fn.getDeclaration()));
					TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
						final call = selectCall(expression, fn, null);
						if (call != null)
							predicateArguments.set(call.target, true);
					}, _ -> {});
					for (entry in fn.getRuntimeTypeCatalog().getEntries()) {
						reference(fn.requireRuntimeType(entry.getExpression()));
						occurrences.set(entry, true);
					}
				}
				for (field in owner.getFieldInitializers()) {
					initializers.set(field, true);
					field.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inExpression(field.getExpression()));
					TypedBackendSourceWalk.expression(field.getExpression(), expression -> {
						final call = selectCall(expression, null, field);
						if (call != null)
							predicateArguments.set(call.target, true);
					});
					for (entry in field.getRuntimeTypeCatalog().getEntries()) {
						reference(field.requireRuntimeType(entry.getExpression()));
						occurrences.set(entry, true);
					}
				}
			}
		if (occurrences.keys().hasNext()) {
			final identities = new Map<String, String>();
			for (module in modules)
				for (owner in module.getTypedClasses()) {
					final identity = owner.getSemanticInfo().getIdentity();
					final name = classes.nominalName(TyType.nominal(identity, []));
					if (name == null)
						continue;
					if (identities.exists(name) && identities.get(name) != identity.getCanonicalName())
						throw "OCaml class predicates require distinct runtime names: " + name;
					identities.set(name, identity.getCanonicalName());
				}
		}
	}

	/** A checked target is an admitted class declaration, never its source spelling. */
	function reference(entry:TypedBackendRuntimeTypeOccurrence):String {
		entry.assertCurrent();
		if (entry.getValue() == null && !predicateArguments.exists(entry))
			throw "OCaml emitter does not support runtime type operands for first-class type values: " + entry.getTarget().getSemanticKey();
		if (entry.getValueType() != null && entry.getValueType().hasUnknownComponent())
			throw "OCaml class predicate requires its complete operand type";
		final name = switch entry.getTarget().getKind() {
			case Nominal(identity): classes.nominalName(TyType.nominal(identity, []));
			case _: throw "OCaml emitter does not support runtime type operands for " + entry.getTarget().getSemanticKey();
		};
		if (name == null)
			throw "OCaml class predicate requires an admitted generated class: " + entry.getTarget().getSemanticKey();
		// Core-name collisions need their own compatibility contract. A nominal
		// descriptor must not silently acquire the primitive's runtime behavior.
		switch name {
			case "Int" | "Float" | "Bool" | "String" | "Array" | "Dynamic" | "Class" | "Enum":
				throw "OCaml emitter does not support runtime type operands with a reserved core runtime name: " + name;
			case _:
		}
		return name;
	}

	/** Std.isOfType is an ordinary typed call; its exact second argument supplies the class value. */
	function selectCall(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>,
			field:Null<TypedBackendFieldInitializerProjection>):Null<Stage3OcamlNominalCall> {
		final call = TypedExactStaticCallSource.decode(expression);
		final identity = "Std#static:isOfType(required:dynamic,required:dynamic)->primitive:Bool#0";
		if (call == null || call.declaration != identity)
			return null;
		if (field == null && (fn == null || !functions.exists(fn)) || field != null && !initializers.exists(field))
			throw "OCaml class predicate has a foreign executable projection";
		final fact = field != null ? field.findCallableExpression(expression) : fn.findCallableExpression(expression);
		if (fact == null || fact.getTag() != Call || fact.getExpressions().length != 3)
			throw "OCaml class predicate requires its exact typed call";
		final declaration = fact.getExpressions()[0].getDeclaration();
		if (declaration == null || !declaration.getIsStatic() || declaration.getIdentity().getCanonicalKey() != identity)
			throw "OCaml class predicate lost its selected standard declaration";
		if (call.arguments.length != 2)
			throw "OCaml class predicate requires a direct checked nominal type argument";
		var target = call.arguments[1];
		while (true) {
			switch target {
				case EParenthesized(inner, _):
					target = inner;
				case _:
					break;
			}
		}
		if (!TypedRuntimeTypeSource.isMarker(target))
			throw "OCaml class predicate requires a direct checked nominal type argument";
		final entry = occurrence(target, fn, field);
		if (entry.getValue() != null)
			throw "OCaml class predicate requires a class value as its type argument";
		final valueType = fact.getExpressions()[1].getType();
		if (valueType.hasUnknownComponent())
			throw "OCaml class predicate requires its complete operand type";
		return {target: entry, value: call.arguments[0]};
	}

	/** Consume the call before ordinary call rendering can reinterpret its class argument. */
	public function renderCall(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>,
			emit:HxExpr->String, names:Stage3OcamlLocalNames, quote:String->String):Null<String> {
		final call = selectCall(expression, fn, field);
		return call == null ? null : predicate(call.target, emit(call.value), names, quote);
	}

	/** Resolve only an occurrence owned by the current request's exact executable. */
	public function occurrence(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>,
			field:Null<TypedBackendFieldInitializerProjection>):TypedBackendRuntimeTypeOccurrence {
		if (field != null) {
			if (!initializers.exists(field))
				throw "OCaml runtime type scope has a foreign field initializer";
			return field.requireRuntimeType(expression);
		}
		if (fn == null || !functions.exists(fn))
			throw "OCaml runtime type scope has a foreign function projection";
		return fn.requireRuntimeType(expression);
	}

	/** Preserve operand checks while treating an admitted class argument as compiler-owned syntax. */
	public function checkedValue(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>):Null<HxExpr> {
		final entry = occurrence(expression, fn, field);
		if (!occurrences.exists(entry))
			throw "OCaml runtime type validation has a foreign occurrence";
		reference(entry);
		return entry.getValue();
	}

	/**
		Evaluate once, then test the private class descriptor and declared ancestry.
		Obj.repr preserves a native value without converting it. Checking HxAnon first
		keeps primitive tags and public anonymous fields from impersonating a class.
	 */
	public function render(entry:TypedBackendRuntimeTypeOccurrence, rendered:String, names:Stage3OcamlLocalNames, quote:String->String):String {
		if (!occurrences.exists(entry))
			throw "OCaml runtime type rendering has a foreign occurrence";
		if (entry.getValue() == null)
			throw "OCaml class value must remain inside its exact predicate call";
		return predicate(entry, rendered, names, quote);
	}

	function predicate(entry:TypedBackendRuntimeTypeOccurrence, rendered:String, names:Stage3OcamlLocalNames, quote:String->String):String {
		if (!occurrences.exists(entry))
			throw "OCaml runtime type rendering has a foreign occurrence";
		final target = reference(entry);
		if (names == null)
			throw "OCaml class predicate requires exact local naming ownership";
		final value = names.internalName("__hx_type_test_value");
		return "(let " + value + " = Obj.repr (" + rendered + ") in HxAnon.is_anon " + value + " && HxType.isOfType " + value + " (HxType.class_ "
			+ quote(target) + "))";
	}
}
