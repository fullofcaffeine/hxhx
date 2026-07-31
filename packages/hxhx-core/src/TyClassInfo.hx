/**
	Semantic surface for an ordinary Haxe class.

	Shared nominal lookup lives in `TyNominalInfo`; this concrete subtype keeps
	class identity distinct from `TyAbstractInfo` so operator catalogs cannot be
	attached to ordinary classes by accident.
**/
class TyClassInfo extends TyNominalInfo {
	final superType:Null<TyType>;
	final typeParameters:Array<TyTypeParameterId>;

	public function new(identity:TyNominalTypeId, shortName:String, modulePath:String, fields:haxe.ds.StringMap<TyFieldInfo>,
			properties:haxe.ds.StringMap<TyPropertyInfo>, staticMethods:haxe.ds.StringMap<TyFunSig>, instanceMethods:haxe.ds.StringMap<TyFunSig>,
			staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>, instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>,
			declarations:Array<TyDeclarationInfo>, visibility:HxVisibility = HxVisibility.Public, isEnum:Bool = false, ?superType:TyType,
			?typeParameters:Array<TyTypeParameterId>) {
		super(identity, shortName, modulePath, fields, properties, staticMethods, instanceMethods, staticMethodLists, instanceMethodLists, declarations,
			visibility, isEnum);
		this.superType = superType;
		this.typeParameters = typeParameters == null ? [] : typeParameters.copy();
	}

	/** Exact superclass selected while the program declaration index is built. **/
	public function getSuperType():Null<TyType>
		return superType;

	/** Class-level generic parameters in their declared order. **/
	public function getTypeParameters():Array<String>
		return [for (parameter in typeParameters) parameter.getName()];

	/** Exact class-level generic binder identities in declared order. **/
	public function getTypeParameterIds():Array<TyTypeParameterId>
		return typeParameters.copy();
}
