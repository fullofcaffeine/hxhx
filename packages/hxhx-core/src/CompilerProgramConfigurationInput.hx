/**
	One request-wide compiler setting observed before dependency publication.

	The long-lived record retains a report-safe input name and a SHA-256 revision.
	It deliberately does not retain the raw target or define value, because those
	values may contain private build configuration. The revision remains exact
	enough for in-process comparison while reports can explain which input changed.
**/
class CompilerProgramConfigurationInput {
	public final name:String;

	final observedInputRevision:String;

	private function new(name:String, observedInputRevision:String) {
		this.name = name == null ? "" : StringTools.trim(name);
		this.observedInputRevision = observedInputRevision == null ? "" : observedInputRevision;
		if (this.name.length == 0)
			throw "compiler configuration input name is required";
		if (this.observedInputRevision.length == 0)
			throw "compiler configuration input revision is required";
	}

	/** Hash one normalized value without retaining it in the observation. **/
	public static function fromValue(name:String, value:Null<String>):CompilerProgramConfigurationInput {
		final normalizedName = name == null ? "" : StringTools.trim(name);
		if (normalizedName.length == 0)
			throw "compiler configuration input name is required";
		final revision = haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode(["compiler-program-configuration-input-v1", normalizedName, value]));
		return new CompilerProgramConfigurationInput(reportSafeName(normalizedName), revision);
	}

	public function getObservedInputRevision():String
		return observedInputRevision;

	public function canonicalKey():String
		return CompilerCacheIdentity.encode(["compiler-program-configuration-fact-v1", name, observedInputRevision]);

	/**
		Escape control, path, and report-delimiter characters in an input name.

		Define names normally contain only letters, digits, dots, underscores, and
		hyphens. Percent-encoding every other UTF-16 code unit keeps unusual but
		valid names deterministic without allowing a name to inject report lines or
		reveal a path-like label.
	**/
	static function reportSafeName(value:String):String {
		final out = new StringBuf();
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			final safe = code >= "a".code && code <= "z".code || code >= "A".code && code <= "Z".code || code >= "0".code && code <= "9".code
				|| code == "_".code || code == "-".code || code == ".".code || code == ":".code;
			if (safe)
				out.addChar(code);
			else
				out.add("%" + StringTools.hex(code, 4).toLowerCase());
		}
		return out.toString();
	}
}
