package backend.cpp;

/** Class and enum handles compare declaration identity only within their own category. */
function selects(op:String, left:TyType, right:TyType, classes:Null<CppManagedClassStorage>):Bool {
	return (op == '==' || op == '!=')
		&& classes != null
		&& ((classes.isClassValue(left) && classes.isClassValue(right)) || (classes.isEnumHandle(left) && classes.isEnumHandle(right)));
}

/** Related ordinary instance types retain one allocation across aliases and checked class upcasts. */
function selectsInstances(op:String, left:TyType, right:TyType, classes:Null<CppManagedClassStorage>, casts:Null<CppManagedCastPlan>):Bool {
	if ((op != '==' && op != '!=') || classes == null || casts == null || !classes.isInstanceValue(left) || !classes.isInstanceValue(right))
		return false;
	final a = left.getNullableInner() == null ? left : left.getNullableInner();
	final b = right.getNullableInner() == null ? right : right.getNullableInner();
	return a.getSemanticKey() == b.getSemanticKey() || casts.permitsClassUpcast(a, b) || casts.permitsClassUpcast(b, a);
}

/**
	Ordinary equality may compare an opaque value with a known class reference.
	Shared lowering has already consumed overloaded abstract operators. Resolve
	the remaining abstract's declared backing storage, including Any, without
	using its source name or treating other abstracts as class instances.
 */
function selectsOpaqueInstances(op:String, left:TyType, right:TyType, classes:Null<CppManagedClassStorage>, casts:Null<CppManagedCastPlan>):Bool {
	if ((op != '==' && op != '!=') || classes == null || casts == null)
		return false;
	return (classes.isInstanceValue(right) && casts.representationType(left).isDynamic())
		|| (classes.isInstanceValue(left) && casts.representationType(right).isDynamic());
}

/**
	Both operands are already rooted and evaluated once in source order. Descriptors
	have static lifetime and one address per admitted program declaration. Null stays
	distinct from a descriptor; other value tags fail at the checked storage accessor.
 */
function compute(op:String, left:String, right:String, destination:String, indent:String, enumHandle:Bool = false):Array<String> {
	if (op != '==' && op != '!=')
		throw 'managed class comparison requires equality or inequality';
	final accessor = enumHandle ? '.asEnumDescriptor()' : '.asDescriptor()';
	final a = '(' + left + '.kind() == hxhx::managed::ValueKind::Null ? nullptr : ' + left + accessor + ')';
	final b = '(' + right + '.kind() == hxhx::managed::ValueKind::Null ? nullptr : ' + right + accessor + ')';
	return [
		indent + destination + '.set(hxhx::managed::Value::boolean(' + a + ' ' + op + ' ' + b + '));'
	];
}
