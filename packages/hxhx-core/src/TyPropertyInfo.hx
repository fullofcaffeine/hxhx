/**
	Semantic accessor contract for one declared Haxe property.

	The shared typer uses this record to distinguish a property update from an
	abstract operator applied to an ordinary field. Backends receive already
	selected getter/setter calls and do not rediscover this distinction from source
	text.
**/
class TyPropertyInfo {
	final name:String;
	final type:TyType;
	final isStatic:Bool;
	final getterAccess:String;
	final setterAccess:String;

	public function new(name:String, type:TyType, isStatic:Bool, getterAccess:String, setterAccess:String) {
		this.name = name == null ? "" : name;
		this.type = type == null ? TyType.unknown() : type;
		this.isStatic = isStatic;
		this.getterAccess = getterAccess == null ? "" : getterAccess;
		this.setterAccess = setterAccess == null ? "" : setterAccess;
	}

	public function getName():String
		return name;

	public function getType():TyType
		return type;

	public function getIsStatic():Bool
		return isStatic;

	public function hasExplicitGetter():Bool
		return getterAccess == "get";

	public function hasExplicitSetter():Bool
		return setterAccess == "set";

	/** Whether reads or writes cross a declared accessor rather than direct field storage. **/
	public function usesExplicitAccessors():Bool
		return hasExplicitGetter() || hasExplicitSetter();

	public function getGetterName():String
		return "get_" + name;

	public function getSetterName():String
		return "set_" + name;
}
