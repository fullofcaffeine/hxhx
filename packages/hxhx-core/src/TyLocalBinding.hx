/**
	Immutable typed fact shared by one local declaration and all of its uses.

	`sourceName` is what the Haxe program wrote. `type` is the semantic type the
	typer selected. Source type-hint text remains on the typed declaration node,
	so inferred meaning never fabricates an annotation during source projection.
**/
class TyLocalBinding {
	final identity:TyLocalId;
	final sourceName:String;
	final type:TyType;
	final kind:TyLocalDeclarationKind;

	public function new(identity:TyLocalId, sourceName:String, type:TyType, kind:TyLocalDeclarationKind) {
		if (identity == null)
			throw "typed local binding requires an identity";
		if (type == null)
			throw "typed local binding requires a semantic type";
		this.identity = identity;
		this.sourceName = sourceName == null ? "" : sourceName;
		this.type = type;
		this.kind = kind;
	}

	public function getIdentity():TyLocalId
		return identity;

	public function getSourceName():String
		return sourceName;

	public function getType():TyType
		return type;

	public function getKind():TyLocalDeclarationKind
		return kind;

	public function getCanonicalIdentity():String
		return identity.getCanonicalKey() + ":type:" + type.getSemanticKey();
}
