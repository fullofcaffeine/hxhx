/**
	Records whether a unary operator appears before or after its operand.

	This value preserves source syntax only. It does not imply mutation,
	writeback, or old/new result semantics; abstract operator declarations may
	define those behaviors differently.
**/
enum HxUnaryFixity {
	Prefix;
	Postfix;
}
