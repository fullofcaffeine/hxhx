/**
	Retain the source line and each checked argument type of one `trace(...)`
	call.

	Why: upstream Haxe prints a trace as `file:line: value`, and appends extra
	arguments separated by commas (`trace(42, "x")` prints `Main.hx:5: 42,x`).
	The source-shaped call `trace(...)` keeps neither the line nor the argument
	types, so a target could only print the bare value, and a Bool would print
	as `1` in native OCaml.

	The owning projection checks membership before exposing this record.
**/
class TypedBackendTraceOccurrence {
	public final expression:HxExpr;
	public final arguments:Array<HxExpr>;
	public final argumentTypes:Array<TyType>;

	/** The 1-based source line of the call, or 0 when typing had no position. */
	public final line:Int;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.source.getTag() != TraceCall)
			throw "trace occurrence requires a checked trace call";
		final projected = switch input.expression {
			case ECall(EIdent("trace"), values): values;
			case _: throw "trace projection changed its call shape";
		};
		final checked = input.source.getExpressions();
		if (checked.length != projected.length)
			throw "trace projection changed its argument count";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		arguments = projected.copy();
		argumentTypes = [for (value in checked) value.getType()];
		final position = input.source.getPosition();
		line = position == null ? 0 : position.getLine();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Equal text cannot substitute a different call or executable owner. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "trace occurrence belongs to another executable or changed after projection";
		switch expression {
			case ECall(EIdent("trace"), values) if (values.length == arguments.length):
				for (index in 0...values.length)
					if (values[index] != arguments[index])
						throw "trace arguments were replaced";
			case _:
				throw "trace call was replaced";
		}
	}
}
