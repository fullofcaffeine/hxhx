import HxTypeSyntax.HxTypeSyntaxParameter;

/** Source spelling determines whether a trailing expression is an implicit result. */
enum HxParsedFunctionForm {
	Ordinary;
	Arrow;
}

/** Generated administrative functions have no authored declaration to diagnose. */
enum HxParsedFunctionOrigin {
	Authored;
	Generated;
}

/** Preserve blocks and short-arrow results. For an Arrow block, typing must account for the final expression's implicit result. */
enum HxParsedFunctionBody {
	Statements(body:Array<HxStmt>);
	ImplicitResult(expression:HxExpr);
}

/**
	Attach source facts to the existing argument declaration.

	The declaration stores the written optional/rest markers and default expression.
	Its type hint remains the authored element hint for an ellipsis parameter.
	Call optionality and the body-visible rest container are later typing decisions.
	The end position is the next argument delimiter, including preceding trivia.
 */
typedef HxParsedFunctionArgument = {
	final declaration:HxFunctionArg;
	final hasTypeAnnotation:Bool;
	final pos:HxPos;
	final endPos:HxPos;
};

/**
	Keep an authored function's signature and statements together before typing.

	A null name or resultTypeHint means that source omitted that part. Explicit
	Dynamic, Void, and Null<T> annotations remain non-null hint text. The body
	keeps bare return, value return, and fallthrough distinct. Generic binders use
	the same structured type syntax as typedef declarations.

	This is parsed syntax, not a sealed typed function. Its arrays follow the
	existing mutable AST ownership contract. HxFunctionSyntaxParser constructs
	this payload in preparation for replacing names-only ELambda consumers.
 */
typedef HxParsedFunction = {
	final form:HxParsedFunctionForm;
	final origin:HxParsedFunctionOrigin;
	final name:Null<String>;
	final typeParameters:Array<HxTypeSyntaxParameter>;
	final arguments:Array<HxParsedFunctionArgument>;
	final resultTypeHint:Null<String>;
	final metadata:Array<String>;
	final pos:HxPos;
	final endPos:HxPos;
	final body:HxParsedFunctionBody;
};
