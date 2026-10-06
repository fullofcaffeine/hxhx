/** Shared type and runtime-target queries bound to the exact lexical and declaration context. */
typedef TypedExprTypeResolver = {
	/** Select a callable contract with contextual arguments before replaying its body. */
	final lambdaType:(names:Array<String>, body:HxExpr, argumentTypes:Array<TyType>, signature:Null<HxLambdaSignature>, diagnosticPosition:HxPos,
		environment:TyFunctionEnv) -> TyType;

	final expressionType:(expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv, expected:Null<TyType>) -> TyType;

	/** A direct method call does not create a stored-method inference occurrence, even when no overload applies. */
	final callTargetType:(expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> TyType;

	/** Resolve written local context with the current declaration's exact generic binders. */
	final declaredType:(hint:String, environment:TyFunctionEnv) -> TyType;

	final runtimeTypeTarget:(expression:HxExpr, environment:TyFunctionEnv, namespace:TypedRuntimeTypeNamespace) -> Null<TypedRuntimeTypeTarget>;
	final catchUse:(binding:TyLocalBinding) -> Null<TypedCatchUse>;

	/** Apply the scrutinee enum's exact generic arguments before declaring payload locals. */
	final enumPatternArguments:(input:TyType, name:String, arity:Int, position:HxPos) -> Null<Array<TyType>>;

	/** Prove constructor coverage against the exact input enum before pattern locals enter scope. */
	final enumSwitchCoverage:(input:TyType, patterns:Array<HxSwitchPattern>, position:HxPos, isCapture:String->Bool) -> Bool;

	/** Select an applied constructor using typed arguments without replaying their effects or lexical declarations. */
	final constructorApplication:(constructed:TyType, arguments:Array<TyType>, sources:Array<HxExpr>) -> Null<TypedConstructorApplication>;

	/** Materialize a selected executable conversion at a written value boundary, retaining the original typed operand. */
	final convertValue:(value:TypedExpr, expected:TyType) -> TypedExpr;
}
