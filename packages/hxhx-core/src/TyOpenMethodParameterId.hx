/** Immutable identity of a valid method-instantiation parameter left open after local inference. */
class TyOpenMethodParameterId {
	final key:String;
	final name:String;

	public function new(executable:String, occurrence:Int, declaration:TyTypeParameterId) {
		if (executable == null || executable.length == 0 || occurrence < 0 || declaration == null)
			throw "open method parameter requires executable, occurrence, and declaration identities";
		name = declaration.getName();
		key = CompilerCacheIdentity.encode([
			"open-method-parameter-v1",
			executable,
			Std.string(occurrence),
			declaration.getCanonicalKey()
		]);
	}

	public function getCanonicalKey():String
		return key;

	public function getName():String
		return name;
}
