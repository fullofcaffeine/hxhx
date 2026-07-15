/**
	The source-level unary operators preserved by the bootstrap syntax tree.

	Why
	- Abstract operator selection distinguishes the operator token from whether
	  it appears before or after its operand.
	- Raw strings previously combined those facts in values such as `post++`,
	  which allowed invalid token/fixity combinations to spread across backends.

	What
	- Models only unary tokens accepted by upstream Haxe 4.3.7 in the current
	  parser scope.
	- Prefix/postfix placement lives separately in `HxUnaryFixity`.

	Gotchas
	- Unary positive is intentionally absent because upstream Haxe 4.3.7 rejects
	  `+value`.
	- Spread remains on the parser's explicit spread-call seam and is not part of
	  this enum.
**/
enum HxUnaryOperator {
	Increment;
	Decrement;
	Negate;
	LogicalNot;
	BitwiseNot;
}
