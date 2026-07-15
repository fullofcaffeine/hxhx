/**
	Deterministic identity for one semantic declaration.

	Keys combine the canonical owner, static/instance form, semantic signature,
	and a source-order discriminator for otherwise identical declarations. They
	do not depend on allocation identity or backend traversal order.
**/
class TyDeclarationId {
	final canonicalKey:String;

	public function new(canonicalKey:String) {
		this.canonicalKey = canonicalKey == null ? "" : canonicalKey;
	}

	public function getCanonicalKey():String
		return canonicalKey;

	public function equals(other:TyDeclarationId):Bool
		return other != null && canonicalKey == other.getCanonicalKey();

	public function toString():String
		return canonicalKey;
}
