/**
	Token kind enum for the Haxe-in-Haxe parser subset.

	Why:
	- Separating token "kind" from the token's position keeps the data model
	  simple and makes it easier to write tests for lexing vs parsing.
**/
enum HxTokenKind {
	TEof;
	TIdent(name:String);
	TString(value:String);
	TKeyword(k:HxKeyword);
	TLBrace;    // {
	TRBrace;    // }
	TLParen;    // (
	TRParen;    // )
	TSemicolon; // ;
	TColon;     // :
	TDot;       // .
	TComma;     // ,
	TOther(code:Int); // any single character we don't model yet
}
