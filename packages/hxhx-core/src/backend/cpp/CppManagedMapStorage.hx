package backend.cpp;

/** Select physical map storage from resolved key types; runtime headers never infer source semantics. */
function select(type:TyType, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors):{
	payload:String,
	keyAccessor:String,
	runtimeClass:String,
	keyType:TyType,
	valueType:TyType
} {
	final identity = type.getNominalIdentity();
	final arguments = type.getTypeArguments();
	if (identity == null || identity.getCanonicalName() != "haxe.ds.Map" || arguments.length != 2 || type.hasUnknownComponent())
		throw "managed map storage requires its resolved Map provider and arguments";
	final storage = switch arguments[0].getSemanticKey() {
		case "primitive:Int": {payload: "IntMapPayload", keyAccessor: "asInteger", runtimeClass: "haxe.ds.IntMap"};
		case "primitive:String": {payload: "StringMapPayload", keyAccessor: "asString", runtimeClass: "haxe.ds.StringMap"};
		case _ if (arguments[0].isAnonymous()): {payload: "ObjectMapPayload", keyAccessor: "asManaged", runtimeClass: "haxe.ds.ObjectMap"};
		case _ if (enums != null && enums.findNullarySymbol(arguments[0]) != null):
			// A parameterless constructor is completely identified by its ordinal
			// within this exact enum. Payload enums need structural comparison.
			{payload: "IntMapPayload", keyAccessor: "", runtimeClass: "haxe.ds.EnumValueMap"};
		case _ if (arguments[0].getNominalIdentity() != null && classes != null):
			// Ordinary classes share allocation identity with anonymous keys. Their
			// exact program-owned layout must be admitted before that choice is valid.
			classes.requireType(arguments[0]);
			{payload: "ObjectMapPayload", keyAccessor: "asManaged", runtimeClass: "haxe.ds.ObjectMap"};
		case _: throw "managed map key storage requires an implemented key representation";
	};
	return {
		payload: storage.payload,
		keyAccessor: storage.keyAccessor,
		runtimeClass: storage.runtimeClass,
		keyType: arguments[0],
		valueType: arguments[1]
	};
}

/** Decode copied rooted storage, preserving a null object key without evaluating a source operand again. */
function renderKey(type:TyType, rootedValue:String, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors):String {
	final storage = select(type, classes, enums);
	if (storage.runtimeClass == 'haxe.ds.EnumValueMap')
		return 'static_cast<std::int32_t>('
			+ rootedValue
			+ '.asManaged().as<hxhx::managed::EnumPayload>()->constructorIndex('
			+ enums.findNullarySymbol(storage.keyType)
			+ '))';
	final read = rootedValue + "." + storage.keyAccessor + "()";
	return storage.runtimeClass == "haxe.ds.ObjectMap" ? "("
		+ rootedValue
		+ ".kind() == hxhx::managed::ValueKind::Null ? hxhx::managed::ErasedRef{} : "
		+ read
		+ ")" : read;
}
