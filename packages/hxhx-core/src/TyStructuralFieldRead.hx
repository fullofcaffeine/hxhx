/**
	Resolve a value field without inventing a nominal declaration.
	Required record fields keep their exact structural type; an optional field reads as
	`Null<T>` (`readType`). Dynamic fields remain
	Dynamic. Null-safe access adds its result wrapper at the caller; an ordinary
	read through a nullable receiver still has the field's own type.
 */
function resolve(receiver:TyType, name:String):Null<TyType> {
	final value = TyAliasExpansion.revealNonNullable(receiver);
	if (value.isDynamic())
		return TyType.fromHintText("Dynamic");
	if (!value.isAnonymous())
		return null;
	for (field in value.getAnonymousFields())
		if (field.name == name)
			return readType(field);
	return null;
}

/**
	The type a read of one structure field produces. An optional field holds null when
	absent, so Haxe 4.3.7 reads `?crc:Int` as `Null<Int>`. The declared field type stays
	`Int`: field absence is recorded on the field, not as value nullability, and structural
	compatibility compares declared types. An unknown inference hole keeps its type.

	Known deviation: upstream also wraps Dynamic (`{?d:Dynamic}` reads as `Null<Dynamic>`,
	typeload.ml `tnull`). Dynamic stays Dynamic here, because Dynamic already holds null and the
	C++ record-write lane rejected `Null<Dynamic>` storage. No std `haxe` structure has one.
**/
function readType(field:TyAnonymousField):TyType {
	final type = field.type;
	return type.isUnknown() || type.isDynamic() ? type : TyAnonymousField.valueType(field);
}
