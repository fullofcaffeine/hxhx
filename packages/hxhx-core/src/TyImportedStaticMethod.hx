/**
	One bare static method name selected from the current module's imports.

	The provider and its original member name travel together because an aliased
	import can rename the method locally. Keeping both facts in one value prevents
	a caller from accidentally taking the provider from one import and the method
	name from another import that uses the same local name.
**/
class TyImportedStaticMethod {
	final provider:TyNominalInfo;
	final memberName:String;
	final candidates:Array<TyFunSig>;

	public function new(provider:TyNominalInfo, memberName:String, candidates:Array<TyFunSig>) {
		if (provider == null)
			throw "imported static method requires its exact provider";
		if (memberName == null || memberName.length == 0)
			throw "imported static method requires its original member name";
		if (candidates == null || candidates.length == 0)
			throw "imported static method requires at least one eligible overload";
		this.provider = provider;
		this.memberName = memberName;
		this.candidates = candidates.copy();
	}

	public function getProvider():TyNominalInfo
		return provider;

	public function getMemberName():String
		return memberName;

	/** Return the overloads admitted by this exact import operation. **/
	public function getCandidates():Array<TyFunSig>
		return candidates.copy();
}
