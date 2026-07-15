/**
	Stable program-local identity for a declared nominal type.

	The canonical Haxe type path is the semantic key. Display text and target
	representations are deliberately excluded so abstract identity survives
	carrier erasure and remains identical across eager and lazy module loading.
**/
class TyNominalTypeId {
	final canonicalName:String;

	public function new(canonicalName:String) {
		this.canonicalName = canonicalName == null ? "" : StringTools.trim(canonicalName);
	}

	public function getCanonicalName():String
		return canonicalName;

	public function equals(other:TyNominalTypeId):Bool
		return other != null && canonicalName == other.getCanonicalName();

	public function toString():String
		return canonicalName;
}
