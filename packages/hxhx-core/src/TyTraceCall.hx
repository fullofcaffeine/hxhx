/**
	Identify the bare, nonempty trace syntax owned by the language. With no-traces,
	its operands are not typed or evaluated, even when a local has the same name.
	Qualified calls, parenthesized callees, and empty calls remain ordinary calls.
	Enabled logging keeps a language operation, not a callable declaration.

	The parser spells a trace that is a whole arrow body `__hxhx_trace_at_<line>(...)`,
	with the line of that body (HxParser.markTraceExpressionLine), because the call has no
	position of its own. It is the same language operation (haxe_ocaml-n4s2a): its result
	is Void, and the typed trace reports that line.
 */
private final MARKED_PREFIX = "__hxhx_trace_at_";

function isLanguageCall(expression:HxExpr):Bool {
	return switch expression {
		case ECall(EIdent(name), arguments): arguments.length > 0 && (name == "trace" || markedNameLine(name) > 0);
		case _: false;
	};
}

/** Apply request policy before typing any operands of the language operation. */
function isDisabled(expression:HxExpr, disabled:Bool):Bool
	return disabled && isLanguageCall(expression);

/** The position a typed trace reports: the parser's recorded arrow-body line when it has one. */
function position(expression:HxExpr, fallback:Null<HxPos>):Null<HxPos> {
	final line = switch expression {
		case ECall(EIdent(name), _): markedNameLine(name);
		case _: 0;
	};
	if (line <= 0)
		return fallback;
	return fallback == null ? new HxPos(0, line, 0) : new HxPos(fallback.getIndex(), line, fallback.getColumn());
}

private function markedNameLine(name:String):Int {
	if (!StringTools.startsWith(name, MARKED_PREFIX))
		return 0;
	final line = Std.parseInt(name.substr(MARKED_PREFIX.length));
	return line == null ? 0 : line;
}
