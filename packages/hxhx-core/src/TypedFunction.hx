/**
	A typed function couples source declaration provenance with its semantic body.

	Backends may inspect the source declaration for signature, metadata, and
	diagnostics, but semantic emission must use `getBody()`. When available, the
	shared declaration record supplies the exact stable declaration identity.
**/
class TypedFunction {
	final ownerName:String;
	final sourceOrdinal:Int;
	final sourceDeclaration:HxFunctionDecl;
	final declaration:Null<TyDeclarationInfo>;
	final environment:Null<TyFunctionEnv>;
	final body:TypedFunctionBody;

	public function new(ownerName:String, sourceOrdinal:Int, sourceDeclaration:HxFunctionDecl, declaration:Null<TyDeclarationInfo>,
			environment:Null<TyFunctionEnv>, body:TypedFunctionBody) {
		this.ownerName = ownerName == null ? "" : ownerName;
		this.sourceOrdinal = sourceOrdinal;
		this.sourceDeclaration = sourceDeclaration;
		this.declaration = declaration;
		this.environment = environment;
		this.body = body;
	}

	public function getOwnerName():String
		return ownerName;

	public function getSourceOrdinal():Int
		return sourceOrdinal;

	public function getSourceDeclaration():HxFunctionDecl
		return sourceDeclaration;

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getEnvironment():Null<TyFunctionEnv>
		return environment;

	public function getBody():TypedFunctionBody
		return body;

	/** Return the same declaration revision with a structurally lowered semantic body. **/
	public function withBody(loweredBody:TypedFunctionBody):TypedFunction
		return new TypedFunction(ownerName, sourceOrdinal, sourceDeclaration, declaration, environment, loweredBody);

	/** Compute the exact owner used by function-local identities before body typing begins. **/
	public static function stableIdentityFor(ownerName:String, sourceOrdinal:Int, sourceDeclaration:HxFunctionDecl,
			declaration:Null<TyDeclarationInfo>):String {
		if (declaration != null)
			return declaration.getIdentity().getCanonicalKey();
		return (ownerName == null ? "" : ownerName)
			+ "#"
			+ (HxFunctionDecl.getIsStatic(sourceDeclaration) ? "static:" : "instance:")
			+ HxFunctionDecl.getName(sourceDeclaration)
			+ "#"
			+ sourceOrdinal;
	}

	public function getStableIdentity():String
		return stableIdentityFor(ownerName, sourceOrdinal, sourceDeclaration, declaration);

	public function assertParsedBodyCurrent():Void {
		final current = TypedBodyFingerprint.forStatements(HxFunctionDecl.getBody(sourceDeclaration));
		if (current != body.getSourceFingerprint())
			throw "typed body revision mismatch for " + getStableIdentity() + "; retype the changed declaration before backend emission";
	}
}
