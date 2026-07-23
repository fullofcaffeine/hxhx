/**
	Immutable identity for declarations produced by `@:build` macros for one module.

	Build macros can change fields or methods without changing the annotated `.hx`
	file. The dependency observer therefore needs a separate revision for the macro
	result. Raw generated member text is used only while computing a SHA-256 digest;
	it is never retained by this object or exposed in ordinary server reports.
**/
class CompilerGeneratedDeclarationObservation {
	static final EMPTY = new CompilerGeneratedDeclarationObservation(0, "generated-declaration-empty-v1");

	final generatedMemberCount:Int;
	final resultRevision:String;
	final canonicalIdentity:String;

	public function new(generatedMemberCount:Int, resultRevision:String) {
		this.generatedMemberCount = generatedMemberCount;
		this.resultRevision = resultRevision == null ? "" : resultRevision;
		if (this.generatedMemberCount < 0)
			throw "generated-declaration observation requires a non-negative member count";
		if (this.resultRevision.length == 0)
			throw "generated-declaration observation requires a result revision";
		canonicalIdentity = CompilerCacheIdentity.encode([
			"generated-declaration-observation-v1",
			Std.string(this.generatedMemberCount),
			this.resultRevision
		]);
	}

	/** Hash generated member snippets without retaining their source text. **/
	public static function fromGeneratedMemberSnippets(members:Array<String>):CompilerGeneratedDeclarationObservation {
		if (members == null || members.length == 0)
			return empty();
		final values = new Array<Null<String>>();
		values.push("generated-declaration-result-v1");
		values.push(Std.string(members.length));
		for (member in members)
			values.push(member == null ? "" : member);
		return new CompilerGeneratedDeclarationObservation(members.length, haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode(values)));
	}

	/** Reuse one immutable empty value so ordinary modules perform no hashing. **/
	public static function empty():CompilerGeneratedDeclarationObservation
		return EMPTY;

	public function getGeneratedMemberCount():Int
		return generatedMemberCount;

	public function getCanonicalIdentity():String
		return canonicalIdentity;
}
