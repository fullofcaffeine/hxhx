import HxTypeSyntax.HxTypeSyntaxParameter;

/**
	Retain local generic declarations and structured constraint types.

	The shared type grammar owns the declarations and source ranges. Both typing
	and macro conversion consume those nodes without reconstructing grammar from
	names. Returned arrays are defensive copies, so the precomputed syntax identity
	remains valid after callers inspect the declarations.
**/
class HxSourceFunctionGenerics {
	final parameters:Array<HxTypeSyntaxParameter>;
	final canonicalIdentity:String;

	public function new(parameters:Array<HxTypeSyntaxParameter>) {
		this.parameters = HxTypeSyntax.copyParameters(parameters);
		final out = new StringBuf();
		ParsedTypedefIntegrity.appendParameters(out, this.parameters);
		canonicalIdentity = CompilerCacheIdentity.encode(["source-function-generics-v1", out.toString()]);
	}

	public static function empty():HxSourceFunctionGenerics
		return new HxSourceFunctionGenerics([]);

	public function getParameters():Array<HxTypeSyntaxParameter>
		return HxTypeSyntax.copyParameters(parameters);

	/** Include constraints, defaults, metadata, and source ranges in syntax integrity. */
	public function getCanonicalIdentity():String
		return canonicalIdentity;
}
