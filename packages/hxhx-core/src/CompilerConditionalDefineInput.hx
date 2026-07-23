/**
	One compile-time definition consulted while Haxe chose an active `#if` branch.

	The raw definition value is deliberately not retained. Value-sensitive checks
	use a SHA-256 revision over the key, presence, and value, so comparisons can
	explain which key changed without keeping private build configuration in the
	long-lived observation catalog. Presence-only checks do not hash or retain the
	unused value.
**/
class CompilerConditionalDefineInput {
	public final name:String;
	public final access:CompilerConditionalDefineAccess;

	final observedInputRevision:String;

	public function new(name:String, access:CompilerConditionalDefineAccess, observedInputRevision:String) {
		this.name = name == null ? "" : StringTools.trim(name);
		this.access = access;
		this.observedInputRevision = observedInputRevision == null ? "" : observedInputRevision;
		if (this.name.length == 0)
			throw "conditional-compilation definition name is required";
		if (this.access == null)
			throw "conditional-compilation definition access is required";
		if (this.observedInputRevision.length == 0)
			throw "conditional-compilation observed input revision is required";
	}

	/** Build a path-safe observation without retaining the raw definition value. **/
	public static function fromDefines(name:String, access:CompilerConditionalDefineAccess, defines:haxe.ds.StringMap<String>):CompilerConditionalDefineInput {
		final normalized = name == null ? "" : StringTools.trim(name);
		final present = normalized.length > 0 && defines != null && defines.exists(normalized);
		final value:Null<String> = present ? defines.get(normalized) : null;
		final accessName = access == CompilerConditionalDefineAccess.Value ? "value" : "presence";
		final identityInputs = [
			"conditional-define-input-v2",
			normalized,
			accessName,
			present ? "present" : "absent",
			access == CompilerConditionalDefineAccess.Value ? value : null
		];
		final revision = access == CompilerConditionalDefineAccess.Value ? haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode(identityInputs)) : CompilerCacheIdentity.encode(identityInputs);
		return new CompilerConditionalDefineInput(normalized, access, revision);
	}

	public function getObservedInputRevision():String
		return observedInputRevision;

	/** Stable identity for one define name plus the way it was consulted. **/
	public function accessKey():String
		return CompilerCacheIdentity.encode([
			"conditional-define-access-key-v1",
			name,
			access == CompilerConditionalDefineAccess.Value ? "value" : "presence"
		]);

	public function canonicalKey():String
		return CompilerCacheIdentity.encode([
			"conditional-define-fact-v2",
			name,
			access == CompilerConditionalDefineAccess.Value ? "value" : "presence",
			observedInputRevision
		]);
}
