/**
	Semantic surface for an ordinary Haxe class.

	Shared nominal lookup lives in `TyNominalInfo`; this concrete subtype keeps
	class identity distinct from `TyAbstractInfo` so operator catalogs cannot be
	attached to ordinary classes by accident.
**/
class TyClassInfo extends TyNominalInfo {
	public function new(identity:TyNominalTypeId, shortName:String, modulePath:String, fields:haxe.ds.StringMap<TyType>,
			properties:haxe.ds.StringMap<TyPropertyInfo>, staticMethods:haxe.ds.StringMap<TyFunSig>, instanceMethods:haxe.ds.StringMap<TyFunSig>,
			staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>, instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>,
			declarations:Array<TyDeclarationInfo>) {
		super(identity, shortName, modulePath, fields, properties, staticMethods, instanceMethods, staticMethodLists, instanceMethodLists, declarations);
	}
}
