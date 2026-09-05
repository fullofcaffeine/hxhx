package reflaxe.ocaml.target;

/** Request-owned lookup from a host function handle to its immutable target fact. **/
class OcamlTargetFunctionCatalog {
	var factsByHostFunctionId:Map<String, OcamlTargetFunctionFact> = [];

	public function new() {}

	/** Starts a new compilation without retaining host function handles. **/
	public function beginRequest():Void {
		factsByHostFunctionId = [];
	}

	public function register(hostFunctionId:String, fact:OcamlTargetFunctionFact):Void {
		final id = required(hostFunctionId);
		if (fact == null)
			throw "OCaml target function catalog requires a fact";
		final existing = factsByHostFunctionId.get(id);
		if (existing != null && existing.getCanonicalIdentity() != fact.getCanonicalIdentity())
			throw 'OCaml target function catalog received conflicting facts for "$id"';
		factsByHostFunctionId.set(id, fact);
	}

	public function find(hostFunctionId:String):Null<OcamlTargetFunctionFact>
		return factsByHostFunctionId.get(required(hostFunctionId));

	/** Return one target-centric fact per identity, independent of host handles. **/
	public function copyFacts():Array<OcamlTargetFunctionFact> {
		final byTargetIdentity:Map<String, OcamlTargetFunctionFact> = [];
		for (fact in factsByHostFunctionId) {
			final identity = fact.getTargetIdentity();
			final existing = byTargetIdentity.get(identity);
			if (existing != null && existing.getCanonicalIdentity() != fact.getCanonicalIdentity())
				throw 'OCaml target function catalog contains conflicting target facts for "$identity"';
			byTargetIdentity.set(identity, fact);
		}
		final identities = [for (identity in byTargetIdentity.keys()) identity];
		identities.sort(compareText);
		final result = new Array<OcamlTargetFunctionFact>();
		for (identity in identities) {
			final fact = byTargetIdentity.get(identity);
			if (fact == null)
				throw 'OCaml target function catalog lost target fact "$identity"';
			result.push(fact);
		}
		return result;
	}

	static function required(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target function catalog requires a host function ID";
		return normalized;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
