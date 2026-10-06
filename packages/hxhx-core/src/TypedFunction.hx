/**
	A typed function owns its semantic body and conditional parameter defaults.

	Backends may inspect the source declaration for signature, metadata, and
	diagnostics, but semantic emission must use `getBody()` and `getDefaults()`. When available, the
	shared declaration record supplies the exact stable declaration identity.
	The parsed body and arguments keep separate exact identities because their
	arrays can change after typing. Deriving another body must reject such edits.
**/
class TypedFunction {
	final ownerName:String;
	final sourceOrdinal:Int;
	final sourceDeclaration:HxFunctionDecl;
	final sourceBodyIdentity:String;
	final sourceArgumentsIdentity:String;
	final declaration:Null<TyDeclarationInfo>;
	final environment:Null<TyFunctionEnv>;
	final body:TypedFunctionBody;
	final defaults:Array<TypedFunctionDefault>;

	public function new(ownerName:String, sourceOrdinal:Int, sourceDeclaration:HxFunctionDecl, declaration:Null<TyDeclarationInfo>,
			environment:Null<TyFunctionEnv>, body:TypedFunctionBody, ?defaults:Array<TypedFunctionDefault>) {
		this.ownerName = ownerName == null ? "" : ownerName;
		this.sourceOrdinal = sourceOrdinal;
		this.sourceDeclaration = sourceDeclaration;
		sourceBodyIdentity = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(sourceDeclaration));
		sourceArgumentsIdentity = TypedFunctionDefault.sourceIdentity(HxFunctionDecl.getArgs(sourceDeclaration));
		this.declaration = declaration;
		this.environment = environment;
		this.body = body;
		this.defaults = defaults == null ? [] : defaults.copy();
		final expected = [
			for (index in 0...HxFunctionDecl.getArgs(sourceDeclaration).length)
				if (HxFunctionArg.getDefaultValue(HxFunctionDecl.getArgs(sourceDeclaration)[index]) != HxDefaultValue.NoDefault) index
		];
		if (expected.length != this.defaults.length)
			throw "typed function defaults do not cover the declared parameters";
		for (index in 0...expected.length)
			if (this.defaults[index].getParameterIndex() != expected[index])
				throw "typed function default parameter slot mismatch";
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

	/** Retain declaration order without exposing the owned default list to mutation. */
	public function getDefaults():Array<TypedFunctionDefault>
		return defaults.copy();

	/** Return the same declaration revision with a structurally lowered semantic body. **/
	public function withBody(loweredBody:TypedFunctionBody, ?loweredDefaults:Array<TypedFunctionDefault>):TypedFunction {
		assertParsedBodyCurrent();
		return new TypedFunction(ownerName, sourceOrdinal, sourceDeclaration, declaration, environment, loweredBody,
			loweredDefaults == null ? defaults : loweredDefaults);
	}

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
		final parsed = HxFunctionDecl.getBody(sourceDeclaration);
		// Parsed arrays remain mutable after typing. A compact hash collision must
		// not let a changed declaration retain the old semantic body or captures.
		if (TypedBodyFingerprint.forStatements(parsed) != body.getSourceFingerprint()
			|| TypedBodyFingerprint.exactStatements(parsed) != sourceBodyIdentity
			|| TypedFunctionDefault.sourceIdentity(HxFunctionDecl.getArgs(sourceDeclaration)) != sourceArgumentsIdentity)
			throw "typed body revision mismatch for " + getStableIdentity() + "; retype the changed declaration before backend emission";
	}
}
