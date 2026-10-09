package backend.cpp;

/**
	Retain the element storage selected before an array loses its source type.
	This tag distinguishes fixed primitive storage from Dynamic element storage,
	including empty arrays. It does not implement recovery or element conversion.
	Nullable elements use reference storage even when their inner type is scalar.
	Abstracts use the same exact backing-type plan as other managed transfers.
 */
function select(element:TyType, ?casts:CppManagedCastPlan):String {
	CppManagedClosureAbi.assertComplete(element);
	final stored = casts == null ? element : casts.representationType(element);
	final kind = switch stored.getSemanticKey() {
		case "primitive:Bool": "Boolean";
		case "primitive:Int": "Integer";
		case "primitive:Float": "Float";
		case "primitive:String": "String";
		case _:
			if (stored.isDynamic()) "Dynamic"; else if (stored.isNullable() || stored.isAnonymous() || stored.isFunction()) "Reference"; else
				if (stored.getNominalIdentity() != null
				&& casts != null) "Reference"; else throw "managed array representation requires exact element storage facts";
	};
	return "hxhx::managed::ArrayRepresentation::" + kind;
}
