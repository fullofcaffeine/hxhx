package backend.cpp;

/** Identify storage that preserves null rather than coercing it to a scalar default. */
function retainsNull(type:TyType, ?casts:CppManagedCastPlan):Bool {
	CppManagedClosureAbi.assertComplete(type);
	if (type.isNullLiteral()
		|| type.isDynamic()
		|| type.isNullable()
		|| type.isAnonymous()
		|| type.isFunction()
		|| type.getSemanticKey() == 'primitive:String')
		return true;
	return (type.getNominalIdentity() != null || type.getClassValueScheme() != null) && casts != null && casts.retainsNull(type);
}

/**
	Validate representation-preserving transfers after shared source typing.
	Nullable wrappers retain the same boxed value. Removing a wrapper is safe only
	when the destination itself preserves null. Numeric coercions, abstract
	conversions and structural adaptation remain separate. Ordinary class upcasts
	retain one allocation only after the program's exact ancestor graph admits them.
	An Array class handle may widen its element argument to Dynamic without
	changing its descriptor. This rule does not narrow stored class handles or
	convert array contents; contextual Array literals are checked by their owner.
 */
function accepts(target:TyType, source:TyType, ?casts:CppManagedCastPlan):Bool {
	try {
		CppManagedClosureAbi.assertComplete(target);
		CppManagedClosureAbi.assertComplete(source);
	} catch (error:haxe.Exception) {
		throw new haxe.Exception('managed value transfer requires complete types: ' + source.getSemanticKey() + ' -> ' + target.getSemanticKey(), error);
	}
	if (CppManagedNumericErasure.selects(target, source, casts))
		return false;
	if (target.isDynamic() || target.getSemanticKey() == source.getSemanticKey())
		return true;
	// Shared typing and abstract lowering have already selected any authored
	// conversion. An opaque backing value then copies its existing runtime tag.
	if (casts != null && target.getNominalIdentity() != null && casts.representationType(target).isDynamic())
		return true;
	if (target.isFunction() && source.isFunction() && CppManagedCallableRepresentation.compatible(target, source))
		return true;
	if (casts != null && casts.permitsArrayClassErasure(target, source))
		return true;
	if (casts != null && casts.permitsClassSchemeContext(target, source))
		return true;
	if (casts != null && casts.permitsClassUpcast(target, source))
		return true;
	if (source.isNullLiteral())
		return retainsNull(target, casts);
	if (target.getNullableInner() != null && target.getNullableInner().getSemanticKey() == source.getSemanticKey())
		return true;
	return source.getNullableInner() != null
		&& source.getNullableInner().getSemanticKey() == target.getSemanticKey()
		&& retainsNull(target, casts);
}

/** Native Int/Bool destinations convert an absent matching nullable value to zero/false; nullable destinations retain null. */
function needsScalarConversion(target:TyType, source:TyType, ?casts:CppManagedCastPlan):Bool {
	if (source.getNullableInner() == null || source.getNullableInner().getSemanticKey() != target.getSemanticKey())
		return false;
	final stored = scalarRepresentation(target, casts);
	return stored.getSemanticKey() == "primitive:Int" || stored.getSemanticKey() == "primitive:Bool";
}

/** Every signed 32-bit Int has an exact Float representation; other source types need their own conversion. */
function needsIntegerWidening(target:TyType, source:TyType):Bool
	return target.getSemanticKey() == "primitive:Float" && source.getSemanticKey() == "primitive:Int";

/** Scalar recovery, numeric widening, and Float erasure execute before publication. */
function needsConversion(target:TyType, source:TyType, ?casts:CppManagedCastPlan):Bool
	return needsScalarConversion(target, source, casts)
		|| needsIntegerWidening(target, source)
		|| CppManagedNumericErasure.selects(target, source, casts);

/** Admit either an unchanged copy or an explicitly selected storage conversion. */
function supports(target:TyType, source:TyType, ?casts:CppManagedCastPlan):Bool
	return accepts(target, source, casts) || needsConversion(target, source, casts);

/**
	Choose storage for already typed conditional branches without coercing either branch.
	An Int/Bool callback can physically return null even through a concrete function
	alias. Keep that null until the enclosing destination selects scalar conversion.
	This does not admit unrelated branch types or change Float conversion policy.
 */
function conditionalStorage(left:TyType, right:TyType):TyType {
	CppManagedClosureAbi.assertComplete(left);
	CppManagedClosureAbi.assertComplete(right);
	if (left.getSemanticKey() == right.getSemanticKey())
		return left;
	if (needsScalarConversion(left, right))
		return right;
	if (needsScalarConversion(right, left))
		return left;
	throw "managed conditional requires matching branch storage types";
}

/**
	Convert an already evaluated temporary root before publishing it to scalar storage.
	The source binding is untouched, and this operation neither allocates nor repeats
	source effects. Callers must separately validate the transfer with supports;
	other type pairs emit no conversion and gain no admission from this helper.
 */
function convertRoot(target:TyType, source:TyType, root:String, indent:String, ?casts:CppManagedCastPlan):Array<String> {
	if (needsIntegerWidening(target, source))
		return [
			indent + root + ".set(hxhx::managed::Value::floating(static_cast<double>(" + root + ".get().asInteger())));"
		];
	if (CppManagedNumericErasure.selects(target, source, casts))
		return CppManagedNumericErasure.render(root, indent);
	if (!needsScalarConversion(target, source, casts))
		return [];
	final storedTarget = scalarRepresentation(target, casts);
	final storedSource = TyType.nullable(storedTarget);
	final expression = storedTarget.getSemanticKey() == "primitive:Int" ? "integer("
		+ CppManagedInteger.numericValue(storedSource, root + ".get()") : "boolean("
		+ CppManagedBoolean.conditionValue(storedSource, root + ".get()");
	return [indent + root + ".set(hxhx::managed::Value::" + expression + "));"];
}

/** Primitive transfers do not need to inspect unrelated program declarations. */
private function scalarRepresentation(type:TyType, casts:Null<CppManagedCastPlan>):TyType
	return casts == null || type.getNominalIdentity() == null ? type : casts.representationType(type);
