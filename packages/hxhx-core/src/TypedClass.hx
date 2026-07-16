/** A source class/abstract declaration paired with all of its typed functions. **/
class TypedClass {
	final sourceDeclaration:HxClassDecl;
	final semanticInfo:Null<TyNominalInfo>;
	final functions:Array<TypedFunction>;

	public function new(sourceDeclaration:HxClassDecl, semanticInfo:Null<TyNominalInfo>, functions:Array<TypedFunction>) {
		this.sourceDeclaration = sourceDeclaration;
		this.semanticInfo = semanticInfo;
		this.functions = functions == null ? [] : functions.copy();
	}

	public function getSourceDeclaration():HxClassDecl
		return sourceDeclaration;

	public function getSemanticInfo():Null<TyNominalInfo>
		return semanticInfo;

	public function getFunctions():Array<TypedFunction>
		return functions.copy();
}
