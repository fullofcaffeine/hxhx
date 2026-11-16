/**
	One place where typing let a function value enter a `haxe.Constraints.Function`
	slot other than a call argument or a plain `Function` local.

	Why: a `Function` value is later called through the Dynamic convention, with
	arguments of any category. A target whose functions are typed natively needs
	a calling-convention adapter at the point where the value is stored. Typing
	records every such point here, so a target can refuse the ones it did not
	adapt instead of storing a closure that crashes when it is called.

	Call arguments are not listed here: `TypedBackendCallArgument` already keeps
	their expected and actual types.
**/
typedef TypedBackendFunctionConstraintFlow = {
	/** What holds the value, in words: "field", "function result", "structure field", ... */
	final site:String;

	final position:Null<HxPos>;
};
