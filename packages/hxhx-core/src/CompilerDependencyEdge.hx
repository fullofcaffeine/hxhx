/**
	One deterministic reason that a consumer module used a provider module.

	`phase` names where the compiler proved the relationship. `factIdentity` names
	the exact type, declaration, import, or program fact that was observed. It is
	useful for diagnostics and for distinguishing two reasons between the same
	modules; it is not source text and should stay path-neutral.
**/
class CompilerDependencyEdge {
	public final consumerModule:String;
	public final providerModule:String;
	public final phase:CompilerDependencyPhase;
	public final kind:CompilerDependencyKind;
	public final factIdentity:String;

	public function new(consumerModule:String, providerModule:String, phase:CompilerDependencyPhase, kind:CompilerDependencyKind, factIdentity:String) {
		this.consumerModule = normalize(consumerModule);
		this.providerModule = normalize(providerModule);
		this.phase = phase;
		this.kind = kind;
		this.factIdentity = normalize(factIdentity);
		if (this.consumerModule.length == 0 || this.providerModule.length == 0)
			throw "compiler dependency edges require consumer and provider module identities";
		if (this.factIdentity.length == 0)
			throw "compiler dependency edges require a fact identity";
	}

	public function canonicalKey():String {
		return CompilerCacheIdentity.encode([
			"compiler-dependency-edge-v2",
			consumerModule,
			providerModule,
			CompilerDependencyPhaseTools.name(phase),
			CompilerDependencyKindTools.name(kind),
			factIdentity
		]);
	}

	public function describe():String {
		return consumerModule + " uses " + providerModule + " (" + CompilerDependencyPhaseTools.name(phase) + "/" + CompilerDependencyKindTools.name(kind)
			+ ": " + factIdentity + ")";
	}

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
