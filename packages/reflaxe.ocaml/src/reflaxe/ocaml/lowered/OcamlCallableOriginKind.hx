package reflaxe.ocaml.lowered;

/**
	Identity construction for a newly admitted function value.

	This is independent of its invocation layout. A function plan must also prove
	argument/result storage before wrapping a native arrow in a callback view.
	Existing views retain their token through OcamlCallableViewLocalConversion;
	they must never pass through an origin constructor again.
**/
enum OcamlCallableOriginKind {
	/** Each evaluation creates a Haxe function, even if OCaml shares its closure. */
	FreshLiteral;

	/** Reads of one ordinary static method refer to its stable declaration closure. */
	StaticDeclaration(calleeId:String);
}
