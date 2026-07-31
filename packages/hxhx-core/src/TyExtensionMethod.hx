/**
	One ordered `using` extension candidate selected from exact typed module facts.

	`usingProvider` is the type named by the directive. `declaringProvider` owns
	the static method, which may be inherited by the using provider. Keeping both
	identities prevents a backend from repeating directive order, inheritance, or
	visibility lookup.
**/
class TyExtensionMethod {
	final usingProvider:TyNominalTypeId;
	final declaringProvider:TyNominalInfo;
	final memberName:String;
	final candidates:Array<TyFunSig>;

	public function new(usingProvider:TyNominalTypeId, declaringProvider:TyNominalInfo, memberName:String, candidates:Array<TyFunSig>) {
		if (usingProvider == null)
			throw "extension method requires its exact using provider";
		if (declaringProvider == null)
			throw "extension method requires its exact declaring provider";
		if (memberName == null || memberName.length == 0)
			throw "extension method requires its original member name";
		if (candidates == null || candidates.length == 0)
			throw "extension method requires at least one eligible overload";
		this.usingProvider = usingProvider;
		this.declaringProvider = declaringProvider;
		this.memberName = memberName;
		this.candidates = candidates.copy();
	}

	public function getUsingProvider():TyNominalTypeId
		return usingProvider;

	public function getDeclaringProvider():TyNominalInfo
		return declaringProvider;

	public function getMemberName():String
		return memberName;

	public function getCandidates():Array<TyFunSig>
		return candidates.copy();
}
