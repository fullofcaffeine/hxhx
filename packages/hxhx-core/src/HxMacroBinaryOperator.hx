import haxe.macro.Expr.Binop;

/**
	Convert source operator tokens to the public Haxe macro representation.

	Comparisons ending in '=' are distinct from compound assignments. Only the
	explicit compound-assignment tokens acquire a nested OpAssignOp node.
	Target adapters provide their object constructor; they do not reinterpret
	tokens or serialize an operator as an untyped string.
 */
function parse(token:String):Binop {
	final compound = token == "??=" ? "??" : HxBinaryOperatorTools.baseOperator(token);
	if (compound != null)
		return OpAssignOp(parse(compound));
	return switch token {
		case "+": OpAdd;
		case "-": OpSub;
		case "*": OpMult;
		case "/": OpDiv;
		case "%": OpMod;
		case "=": OpAssign;
		case "==": OpEq;
		case "!=": OpNotEq;
		case ">": OpGt;
		case ">=": OpGte;
		case "<": OpLt;
		case "<=": OpLte;
		case "&&": OpBoolAnd;
		case "||": OpBoolOr;
		case "&": OpAnd;
		case "|": OpOr;
		case "^": OpXor;
		case "<<": OpShl;
		case ">>": OpShr;
		case ">>>": OpUShr;
		case "in": OpIn;
		case "...": OpInterval;
		case "=>": OpArrow;
		case "??": OpNullCoal;
		case _: throw "unsupported macro binary operator: " + token;
	};
}

/** Construct target macro values from the same typed operator used by the host. */
function render(token:String, makeEnum:(String, Array<String>) -> String):String {
	return renderOperation(parse(token), makeEnum);
}

function renderOperation(operation:Binop, makeEnum:(String, Array<String>) -> String):String {
	return switch operation {
		case OpAssignOp(inner): makeEnum("OpAssignOp", [renderOperation(inner, makeEnum)]);
		case OpAdd: makeEnum("OpAdd", []);
		case OpSub: makeEnum("OpSub", []);
		case OpMult: makeEnum("OpMult", []);
		case OpDiv: makeEnum("OpDiv", []);
		case OpMod: makeEnum("OpMod", []);
		case OpAssign: makeEnum("OpAssign", []);
		case OpEq: makeEnum("OpEq", []);
		case OpNotEq: makeEnum("OpNotEq", []);
		case OpGt: makeEnum("OpGt", []);
		case OpGte: makeEnum("OpGte", []);
		case OpLt: makeEnum("OpLt", []);
		case OpLte: makeEnum("OpLte", []);
		case OpBoolAnd: makeEnum("OpBoolAnd", []);
		case OpBoolOr: makeEnum("OpBoolOr", []);
		case OpAnd: makeEnum("OpAnd", []);
		case OpOr: makeEnum("OpOr", []);
		case OpXor: makeEnum("OpXor", []);
		case OpShl: makeEnum("OpShl", []);
		case OpShr: makeEnum("OpShr", []);
		case OpUShr: makeEnum("OpUShr", []);
		case OpIn: makeEnum("OpIn", []);
		case OpInterval: makeEnum("OpInterval", []);
		case OpArrow: makeEnum("OpArrow", []);
		case OpNullCoal: makeEnum("OpNullCoal", []);
	};
}
