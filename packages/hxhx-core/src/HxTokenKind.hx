/**
	Token kind enum for the Haxe-in-Haxe parser subset.

	Why:
	- Separating token "kind" from the token's position keeps the data model
	  simple and makes it easier to write tests for lexing vs parsing.
**/
enum HxTokenKind {
	TEof;
	TIdent(name:String);

	/**
		String literal payload.

		`interpolate` is true only for Haxe's single-quoted interpolation strings.
		Double-quoted strings can contain `$NAME` literally, which matters for
		upstream sys argument tests that pass shell-looking data through unchanged.
	**/
	TString(value:String, interpolate:Bool);

	TInt(value:Int);
	TFloat(value:Float);
	TRegex(pattern:String, flags:String);
	TKeyword(k:HxKeyword);
	TLBrace; // {
	TRBrace; // }
	TLParen; // (
	TRParen; // )
	TSemicolon; // ;
	TColon; // :
	TDot; // .
	TComma; // ,
	TOther(code:Int); // any single character we don't model yet
}
