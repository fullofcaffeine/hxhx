/**
	One exact bare field read carried across the temporary source-shaped backend
	boundary.

	`projectedName` is the spelling retained in the projected function body. The
	authoritative owner, static/instance kind, type, and declaration properties
	remain on `field`; backends must not infer them from the transport spelling.
**/
class TypedBackendFieldReadProjection {
	final projectedName:String;
	final field:TyFieldInfo;
	final canonicalIdentity:String;

	public function new(projectedName:String, field:TyFieldInfo) {
		if (projectedName == null || projectedName.length == 0)
			throw "typed backend field-read projection requires a transport name";
		if (field == null)
			throw "typed backend field-read projection requires exact field information";
		this.projectedName = projectedName;
		this.field = field;
		this.canonicalIdentity = [
			field.getCanonicalKey(),
			"module:" + field.getModulePath(),
			"type:" + field.getType().getSemanticKey(),
			"public:" + Std.string(field.getIsPublic()),
			"final:" + Std.string(field.getIsFinal()),
			"inline:" + Std.string(field.getIsInline()),
			"initializer:" + Std.string(field.getHasInitializer()),
			"no-import-global:" + Std.string(field.getNoImportGlobal())
		].join("|");
	}

	public function getProjectedName():String
		return projectedName;

	public function getField():TyFieldInfo
		return field;

	/** Compare every immutable semantic field fact, not merely owner and name. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;
}
