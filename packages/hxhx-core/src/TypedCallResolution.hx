/**
	The exact declaration selected for one call and whether a bare imported name
	must be projected through its owning Haxe type.

	For example, `import model.Api.twice as double; double(2)` selects `Api.twice`
	and requires owner qualification when the typed body is projected. An ordinary
	bare call to a method on the current class keeps its original source shape.
**/
class TypedCallResolution {
	final declaration:Null<TyDeclarationInfo>;
	final requiresOwnerQualification:Bool;

	public function new(?declaration:TyDeclarationInfo, requiresOwnerQualification:Bool = false) {
		this.declaration = declaration;
		this.requiresOwnerQualification = requiresOwnerQualification;
		if (requiresOwnerQualification && (declaration == null || !declaration.getIsStatic()))
			throw "owner-qualified call resolution requires an exact static declaration";
	}

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getRequiresOwnerQualification():Bool
		return requiresOwnerQualification;
}
