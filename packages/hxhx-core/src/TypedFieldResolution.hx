/**
	The exact field selected for one read and whether a bare imported name must be
	projected through its owning Haxe type.
**/
class TypedFieldResolution {
	final field:TyFieldInfo;
	final requiresOwnerQualification:Bool;

	public function new(field:TyFieldInfo, requiresOwnerQualification:Bool = false) {
		if (field == null)
			throw "typed field resolution requires an exact field";
		if (requiresOwnerQualification && !field.getIsStatic())
			throw "owner-qualified field resolution requires a static field";
		this.field = field;
		this.requiresOwnerQualification = requiresOwnerQualification;
	}

	public function getField():TyFieldInfo
		return field;

	public function getRequiresOwnerQualification():Bool
		return requiresOwnerQualification;
}
