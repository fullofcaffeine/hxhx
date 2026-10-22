/**
	A normalized semantic type plus the source declarations used to obtain it.

	For Alias = Original, equality uses Original's TyType identity. Dependency
	collection can still observe both Alias and Original through this separate
	record. Arrays are copied so later callers cannot change earlier evidence.
 */
class TyResolvedTypeUse {
	final type:TyType;
	final declarations:Array<TyTypeDeclaration>;
	final position:HxPos;

	public function new(type:TyType, declarations:Array<TyTypeDeclaration>, position:HxPos) {
		this.type = type;
		this.declarations = declarations.copy();
		this.position = position;
	}

	public function getType():TyType
		return type;

	public function getDeclarations():Array<TyTypeDeclaration>
		return declarations.copy();

	public function getPosition():HxPos
		return position;
}
