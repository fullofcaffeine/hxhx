/**
	Stable target-neutral facts for one declared Haxe field.

	The semantic index creates this record while it resolves the owning type and
	field type. Later compiler analyses can therefore identify `Api.limit` from
	typed facts instead of guessing that `Api` is a type from its spelling. The
	record deliberately contains no target-language name or generated-code shape.
**/
class TyFieldInfo {
	final owner:TyNominalTypeId;
	final modulePath:String;
	final name:String;
	final type:TyType;
	final isStatic:Bool;
	final isPublic:Bool;
	final isFinal:Bool;
	final isInline:Bool;
	final hasInitializer:Bool;
	final canonicalKey:String;

	public function new(owner:TyNominalTypeId, modulePath:String, name:String, type:TyType, isStatic:Bool, isPublic:Bool, isFinal:Bool, isInline:Bool,
			hasInitializer:Bool) {
		this.owner = owner;
		this.modulePath = modulePath == null ? "" : StringTools.trim(modulePath);
		this.name = name == null ? "" : StringTools.trim(name);
		this.type = type == null ? TyType.unknown() : type;
		this.isStatic = isStatic;
		this.isPublic = isPublic;
		this.isFinal = isFinal;
		this.isInline = isInline;
		this.hasInitializer = hasInitializer;
		final ownerName = owner == null ? "" : owner.getCanonicalName();
		canonicalKey = ownerName + "#" + (isStatic ? "static" : "instance") + "#" + this.name;
		if (ownerName.length == 0 || this.modulePath.length == 0 || this.name.length == 0)
			throw "typed field information requires owner, module, and field identities";
	}

	public function getOwner():TyNominalTypeId
		return owner;

	public function getModulePath():String
		return modulePath;

	public function getName():String
		return name;

	public function getType():TyType
		return type;

	public function getIsStatic():Bool
		return isStatic;

	public function getIsPublic():Bool
		return isPublic;

	public function getIsFinal():Bool
		return isFinal;

	public function getIsInline():Bool
		return isInline;

	public function getHasInitializer():Bool
		return hasInitializer;

	public function getCanonicalKey():String
		return canonicalKey;

	/** Whether another module may compile the initializer value into a reader. **/
	public function canEmbedCrossModuleValue():Bool
		return isPublic && isStatic && hasInitializer && (isFinal || isInline);
}
