package backend.ocaml;

/**
	Emit checked Int bitwise operations through the existing 32-bit runtime.
	Ordered application evaluates each operand once, left to right. HxInt owns
	signed wraparound and shift-count masking; this adapter selects no runtime policy.
 */
function render(input:{
	facts:TypedBackendBitwiseOccurrence,
	left:String,
	right:String,
	names:Stage3OcamlLocalNames
}):String {
	if (!input.facts.isConcreteInt())
		throw "native Int bitwise lowering requires concrete Int operands and result";
	final operation = switch input.facts.operation {
		case "&": "logand";
		case "|": "logor";
		case "^": "logxor";
		case "<<": "shl";
		case ">>": "shr";
		case ">>>": "ushr";
		case _: throw "unsupported native Int bitwise operator";
	};
	return Stage3OcamlCallOrder.render({callee: "HxInt." + operation, arguments: [input.left, input.right], names: input.names});
}
