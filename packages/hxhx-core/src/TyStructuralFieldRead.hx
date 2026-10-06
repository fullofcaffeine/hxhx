/**
	Resolve a value field without inventing a nominal declaration.
	Required record fields keep their exact structural type. Dynamic fields remain
	Dynamic. Null-safe access adds its result wrapper at the caller; an ordinary
	read through a nullable receiver still has the field's own type.
 */
function resolve(receiver:TyType, name:String):Null<TyType> {
	var value = receiver;
	while (value.isNullable())
		value = value.unwrapNull();
	if (value.isDynamic())
		return TyType.fromHintText("Dynamic");
	if (!value.isAnonymous())
		return null;
	final index = value.getAnonymousFieldNames().indexOf(name);
	return index < 0 ? null : value.getAnonymousFieldTypes()[index];
}
