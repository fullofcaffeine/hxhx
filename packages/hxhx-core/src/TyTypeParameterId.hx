/**
	Stable semantic identity for one declared generic type parameter.

	The readable source name is not enough because Haxe allows a method
	parameter to shadow a same-name class parameter. The scope identifies the
	declaring nominal type or method occurrence, while the ordinal distinguishes
	parameters declared together. Target spelling continues to use `name`.
**/
class TyTypeParameterId {
	final scopeIdentity:String;
	final ordinal:Int;
	final name:String;
	final canonicalKey:String;

	public function new(scopeIdentity:String, ordinal:Int, name:String) {
		this.scopeIdentity = normalize(scopeIdentity);
		this.ordinal = ordinal;
		this.name = normalize(name);
		if (this.scopeIdentity.length == 0 || this.ordinal < 0 || this.name.length == 0)
			throw "type parameter identity requires a scope, non-negative ordinal, and name";
		canonicalKey = CompilerCacheIdentity.encode([
			"type-parameter-identity-v1",
			this.scopeIdentity,
			Std.string(this.ordinal),
			this.name
		]);
	}

	/** Create a class- or abstract-level parameter identity. **/
	public static function nominal(owner:TyNominalTypeId, ordinal:Int, name:String):TyTypeParameterId {
		if (owner == null)
			throw "nominal type parameter identity requires an owner";
		return new TyTypeParameterId("nominal:" + owner.getCanonicalName(), ordinal, name);
	}

	/**
		Create a method-level parameter identity before its signature is sealed.

		`occurrence` is counted among methods with the same owner, static/instance
		form, and source name. It breaks the declaration/signature cycle without
		using allocation identity, file paths, or target traversal.
	**/
	public static function method(owner:TyNominalTypeId, isStatic:Bool, methodName:String, occurrence:Int, ordinal:Int, name:String):TyTypeParameterId {
		if (owner == null)
			throw "method type parameter identity requires an owner";
		final cleanMethodName = normalize(methodName);
		if (cleanMethodName.length == 0 || occurrence < 0)
			throw "method type parameter identity requires a method name and non-negative occurrence";
		final form = isStatic ? "static" : "instance";
		return new TyTypeParameterId("method:" + owner.getCanonicalName() + "#" + form + "#" + cleanMethodName + "#" + occurrence, ordinal, name);
	}

	public function getScopeIdentity():String
		return scopeIdentity;

	public function getOrdinal():Int
		return ordinal;

	public function getName():String
		return name;

	public function getCanonicalKey():String
		return canonicalKey;

	public function equals(other:TyTypeParameterId):Bool
		return other != null && canonicalKey == other.getCanonicalKey();

	public function toString():String
		return canonicalKey;

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
