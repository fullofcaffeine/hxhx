package reflaxe.ocaml.target;

/** Request-owned lookup from host field handles to immutable target facts. **/
class OcamlTargetFieldInitializerCatalog {
	var factsByHostFieldId:Map<String, OcamlTargetFieldInitializerFact> = [];

	public function new() {}

	/** Start a request without retaining handles from the prior compiler run. **/
	public function beginRequest():Void {
		factsByHostFieldId = [];
	}

	public function register(hostFieldId:String, fact:OcamlTargetFieldInitializerFact):Void {
		final id = required(hostFieldId);
		if (fact == null)
			throw "OCaml target field initializer catalog requires a fact";
		final existing = factsByHostFieldId.get(id);
		if (existing != null && existing.getCanonicalIdentity() != fact.getCanonicalIdentity())
			throw 'OCaml target field initializer catalog received conflicting facts for "$id"';
		factsByHostFieldId.set(id, fact);
	}

	public function find(hostFieldId:String):Null<OcamlTargetFieldInitializerFact>
		return factsByHostFieldId.get(required(hostFieldId));

	/** Return one target-centric fact per identity, independent of host handles. **/
	public function copyFacts():Array<OcamlTargetFieldInitializerFact> {
		final byTargetIdentity:Map<String, OcamlTargetFieldInitializerFact> = [];
		for (fact in factsByHostFieldId) {
			final identity = fact.getTargetIdentity();
			final existing = byTargetIdentity.get(identity);
			if (existing != null && existing.getCanonicalIdentity() != fact.getCanonicalIdentity())
				throw 'OCaml target field initializer catalog contains conflicting target facts for "$identity"';
			byTargetIdentity.set(identity, fact);
		}
		final identities = [for (identity in byTargetIdentity.keys()) identity];
		identities.sort(compareText);
		final result = new Array<OcamlTargetFieldInitializerFact>();
		for (identity in identities) {
			final fact = byTargetIdentity.get(identity);
			if (fact == null)
				throw 'OCaml target field initializer catalog lost target fact "$identity"';
			result.push(fact);
		}
		return result;
	}

	static function required(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target field initializer catalog requires a host field ID";
		return normalized;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
