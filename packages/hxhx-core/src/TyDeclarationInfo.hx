/**
	Shared semantic record for a function declaration, including bodyless native
	or extern operator helpers.

	This record keeps the exact declaration identity, resolved signature,
	metadata, position, and parsed source declaration together. The parsed node
	is provenance/body input for later shared typing; it is not a backend binding
	key.
**/
class TyDeclarationInfo {
	final identity:TyDeclarationId;
	final owner:TyNominalTypeId;
	final signature:TyFunSig;
	final metadata:Array<String>;
	final sourceDeclaration:HxFunctionDecl;
	final position:HxPos;
	final isInline:Bool;

	public function new(identity:TyDeclarationId, owner:TyNominalTypeId, signature:TyFunSig, metadata:Array<String>, sourceDeclaration:HxFunctionDecl,
			position:HxPos, isInline:Bool) {
		this.identity = identity;
		this.owner = owner;
		this.signature = signature;
		this.metadata = metadata == null ? [] : metadata.copy();
		this.sourceDeclaration = sourceDeclaration;
		this.position = position == null ? HxPos.unknown() : position;
		this.isInline = isInline;
	}

	public function getIdentity():TyDeclarationId
		return identity;

	public function getOwner():TyNominalTypeId
		return owner;

	public function getSignature():TyFunSig
		return signature;

	public function getMetadata():Array<String>
		return metadata;

	public function getSourceDeclaration():HxFunctionDecl
		return sourceDeclaration;

	public function getPosition():HxPos
		return position;

	public function getIsStatic():Bool
		return signature.getIsStatic();

	public function getIsInline():Bool
		return isInline;

	/** Whether the declaration supplies Haxe code instead of target-native `;` behavior. */
	public function getHasBody():Bool
		return HxFunctionDecl.getHasBody(sourceDeclaration);

	/** Method-level generic parameters retained for overload diagnostics/binding. **/
	public function getTypeParameters():Array<String>
		return HxFunctionTypeParamMetadata.typeParamNames(metadata);

	/** Source-level method type-parameter constraints retained by the shared parser bridge. **/
	public function getTypeParameterConstraints():haxe.ds.StringMap<String>
		return HxFunctionTypeParamMetadata.constraints(metadata);
}
