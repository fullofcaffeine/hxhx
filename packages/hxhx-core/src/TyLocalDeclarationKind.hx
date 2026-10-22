/**
	Source or compiler role that introduced one function-local declaration.

	The role is part of the local's deterministic identity. It prevents a
	parameter, catch variable, loop binding, or compiler temporary at the same
	declaration ordinal from being treated as interchangeable semantic facts.
**/
enum TyLocalDeclarationKind {
	Parameter;
	Variable;

	/** A named function introduces a readable callable binding that source code cannot overwrite. */
	NamedFunction;

	LoopVariable;
	CatchVariable;
	PatternVariable;
	LambdaParameter;
	ComprehensionVariable;
	CompilerTemporary;
}

/** Canonical names used by revisions and diagnostics. **/
class TyLocalDeclarationKindTools {
	public static function canonicalName(kind:TyLocalDeclarationKind):String {
		return switch (kind) {
			case Parameter: "parameter";
			case Variable: "variable";
			case NamedFunction: "named-function";
			case LoopVariable: "loop-variable";
			case CatchVariable: "catch-variable";
			case PatternVariable: "pattern-variable";
			case LambdaParameter: "lambda-parameter";
			case ComprehensionVariable: "comprehension-variable";
			case CompilerTemporary: "compiler-temporary";
		};
	}
}
