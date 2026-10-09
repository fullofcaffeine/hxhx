package backend.cpp;

/**
	Keep one callable allocation across generic Int/Bool storage views.
	A function value transports these scalars in common rooted values. Its entry
	converts concrete parameters; scalar destinations convert returned null values.
	Changing a view therefore needs no wrapper and preserves callable identity.
	This is physical storage compatibility after typing, not callable subtyping.
 */
function compatible(target:TyType, source:TyType):Bool {
	CppManagedClosureAbi.assertComplete(target);
	CppManagedClosureAbi.assertComplete(source);
	if (target.getSemanticKey() == source.getSemanticKey())
		return true;
	if (scalarNullPair(target, source) || scalarNullPair(source, target))
		return true;
	if (!target.isFunction() || !source.isFunction())
		return false;
	final to = target.getFunctionParameters();
	final from = source.getFunctionParameters();
	if (to.length != from.length)
		return false;
	final toTypes = target.getFunctionArguments();
	final fromTypes = source.getFunctionArguments();
	for (index in 0...to.length)
		if (to[index].isOptional != from[index].isOptional
			|| to[index].isRest != from[index].isRest
			|| !compatible(toTypes[index], fromTypes[index]))
			return false;
	return compatible(target.getFunctionReturn(), source.getFunctionReturn());
}

/** Only the established Int/Bool generic-null contract changes transport here. */
function scalar(type:TyType):Bool
	return type.getSemanticKey() == "primitive:Int" || type.getSemanticKey() == "primitive:Bool";

function scalarNullPair(wrapped:TyType, plain:TyType):Bool
	return scalar(plain) && wrapped.getNullableInner() != null && wrapped.getNullableInner().getSemanticKey() == plain.getSemanticKey();

/** A function alias may return generic null; a concrete storage destination decides coercion. */
function resultStorage(type:TyType):TyType
	return scalar(type) ? TyType.nullable(type) : type;

/** Identity comparison accepts the same compatible function views as storage transfer. */
function selectsEquality(op:String, left:TyType, right:TyType):Bool
	return (op == "==" || op == "!=") && left.isFunction() && right.isFunction() && compatible(left, right);
