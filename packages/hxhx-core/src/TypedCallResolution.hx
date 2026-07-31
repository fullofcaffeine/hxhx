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
	final extensionProvider:Null<TyNominalTypeId>;

	public function new(?declaration:TyDeclarationInfo, requiresOwnerQualification:Bool = false, ?extensionProvider:TyNominalTypeId) {
		this.declaration = declaration;
		this.requiresOwnerQualification = requiresOwnerQualification;
		this.extensionProvider = extensionProvider;
		if (requiresOwnerQualification && (declaration == null || !declaration.getIsStatic()))
			throw "owner-qualified call resolution requires an exact static declaration";
		if (extensionProvider != null && (declaration == null || !declaration.getIsStatic()))
			throw "extension call resolution requires an exact static declaration";
	}

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getRequiresOwnerQualification():Bool
		return requiresOwnerQualification;

	/** Type named by the winning `using` directive, when this is an extension call. **/
	public function getExtensionProvider():Null<TyNominalTypeId>
		return extensionProvider;
}
