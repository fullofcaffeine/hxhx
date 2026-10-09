/** Exact named-call identity and final operand types, retained after conversions and before target adaptation. */
class TypedNamedCallBinding {
	final declaration:TyDeclarationInfo;
	final declarationSignature:String;
	final extensionProvider:Null<TyNominalTypeId>;
	final arguments:TyCallArgumentBinding;

	@:allow(TypedNamedCallPlan)
	@:allow(TypedMultiTypeConstruction)
	@:allow(TyAbstractMethodConversion)
	function new(declaration:TyDeclarationInfo, extensionProvider:Null<TyNominalTypeId>, arguments:TyCallArgumentBinding) {
		this.declaration = declaration;
		this.extensionProvider = extensionProvider;
		this.arguments = arguments;
		declarationSignature = TyCallableSignature.fromDeclaration(declaration).getFunctionType().getSemanticKey();
	}

	public function getArguments():TyCallArgumentBinding
		return arguments;

	/** The selected declaration stays fixed while its invocation facts follow the enclosing inline specialization. */
	@:allow(TypedExpr)
	function substituteTypes(bindings:haxe.ds.StringMap<TyType>):TypedNamedCallBinding
		return new TypedNamedCallBinding(declaration, extensionProvider, arguments.substituteTypes(bindings));

	/** Equal-looking declarations cannot borrow a call; structural rewrites must retain its final input and result types. */
	public function assertCurrent(selected:TyDeclarationInfo, provider:Null<TyNominalTypeId>, types:Array<TyType>,
			kinds:Array<TyCallAlignment.TyCallOperandKind>, result:TyType):Void {
		if (selected != declaration
			|| provider != extensionProvider
			|| declarationSignature != TyCallableSignature.fromDeclaration(declaration).getFunctionType().getSemanticKey())
			throw "named call binding belongs to another or changed declaration";
		arguments.assertCurrent(arguments.getFunctionType(), types, kinds);
		if (result.getSemanticKey() != arguments.getFunctionType().getFunctionReturn().getSemanticKey())
			throw "named call binding has a stale result type";
	}

	public function getSemanticKey():String
		return CompilerCacheIdentity.encode([
			                            declaration.getIdentity().getCanonicalKey(),     declarationSignature,
			extensionProvider == null ? null : extensionProvider.getCanonicalName(), arguments.getSemanticKey()
		]);
}
