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

	static function required(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target function catalog requires a host function ID";
		return normalized;
	}
}
