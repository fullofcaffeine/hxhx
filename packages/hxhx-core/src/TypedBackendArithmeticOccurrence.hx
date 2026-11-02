/**
	Keep the checked operand and result types of one arithmetic or ordering
	expression (`+ - * / %` and `< <= > >=`) attached to that exact expression.

	Why
	- A native target must pick a different machine operation for `a + b` when
	  the operands are Int, Float, or String. The source-shaped body that reaches
	  the backend no longer says which: `c.get() + 0.5`, `cell.value / 8` (a field
	  of type `T` instantiated with `Float`), `items[0] + items[1]`, and `this / 2`
	  in a Float-backed abstract all look like plain binary syntax. Guessing the
	  types again from that syntax misses calls, fields, indexed reads, and
	  abstract `this`.
	- The typer already decided each operand type and the result type (`Int / Int`
	  is `Float`; `String + Float` is `String`). This record keeps those decisions
	  so a backend reads them instead of guessing.

	The owning projection checks that the expression still belongs to the current
	body before it exposes this record. Bitwise operators have their own record,
	`TypedBackendBitwiseOccurrence`, and equality has
	`TypedBackendEqualityOccurrence`.
 */
class TypedBackendArithmeticOccurrence {
	public final expression:HxExpr;
	public final left:HxExpr;
	public final right:HxExpr;
	public final operation:String;
	public final leftType:TyType;
	public final rightType:TyType;
	public final resultType:TyType;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.source.getTag() != Binary || input.source.getExpressions().length != 2)
			throw "arithmetic occurrence requires two checked operands";
		operation = input.source.getTexts()[0];
		if (!supports(operation))
			throw "arithmetic occurrence requires an arithmetic or ordering operator";
		final operands = switch input.expression {
			case EBinop(op, a, b) if (op == operation): {left: a, right: b};
			case _: throw "arithmetic projection changed its operator";
		};
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		left = operands.left;
		right = operands.right;
		leftType = input.source.getExpressions()[0].getType();
		rightType = input.source.getExpressions()[1].getType();
		resultType = input.source.getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public static function supports(operation:String):Bool {
		return switch operation {
			case "+" | "-" | "*" | "/" | "%" | "<" | "<=" | ">" | ">=": true;
			case _: false;
		};
	}

	/** Equal text cannot replace the original operands or move facts to another body. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "arithmetic occurrence belongs to another executable or changed after projection";
		switch expression {
			case EBinop(op, a, b) if (op == operation && a == left && b == right):
			case _:
				throw "arithmetic operands were replaced";
		}
	}
}
