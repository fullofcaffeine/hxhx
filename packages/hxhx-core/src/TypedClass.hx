/**
	A source class/abstract declaration paired with its resolved header, typed
	functions, and field initializers.

	The resolved header keeps the exact parent and interfaces selected during
	typing. This matters when the source uses a local import alias: target
	projection must receive the provider type, not repeat Haxe name lookup from a
	name that only existed in the source module.
**/
class TypedClass {
	final sourceDeclaration:HxClassDecl;
	final semanticInfo:Null<TyNominalInfo>;
	final resolvedExtends:Null<TyType>;
	final resolvedImplements:Array<TyType>;
	final functions:Array<TypedFunction>;
	final fieldInitializers:Array<TypedFieldInitializer>;

	public function new(sourceDeclaration:HxClassDecl, semanticInfo:Null<TyNominalInfo>, functions:Array<TypedFunction>,
			?fieldInitializers:Array<TypedFieldInitializer>, ?resolvedExtends:TyType, ?resolvedImplements:Array<TyType>) {
		this.sourceDeclaration = sourceDeclaration;
		this.semanticInfo = semanticInfo;
		this.resolvedExtends = resolvedExtends;
		this.resolvedImplements = resolvedImplements == null ? [] : resolvedImplements.copy();
		this.functions = functions == null ? [] : functions.copy();
		this.fieldInitializers = fieldInitializers == null ? [] : fieldInitializers.copy();
	}

	public function getSourceDeclaration():HxClassDecl
		return sourceDeclaration;

	public function getSemanticInfo():Null<TyNominalInfo>
		return semanticInfo;

	public function getResolvedExtends():Null<TyType>
		return resolvedExtends;

	public function getResolvedImplements():Array<TyType>
		return resolvedImplements.copy();

	public function getFunctions():Array<TypedFunction>
		return functions.copy();

	public function getFieldInitializers():Array<TypedFieldInitializer>
		return fieldInitializers.copy();

	/** Return the same source/semantic class paired with rewritten typed functions. **/
	public function withFunctions(loweredFunctions:Array<TypedFunction>):TypedClass
		return new TypedClass(sourceDeclaration, semanticInfo, loweredFunctions, fieldInitializers, resolvedExtends, resolvedImplements);
}
