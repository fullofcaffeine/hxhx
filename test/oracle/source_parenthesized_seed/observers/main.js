// Read the runtime enum contract used by upstream JavaScript and its Type API.
// Constructor metadata supplies payload names; declaration order is not fixed here.
function constructor(node) {
  const owner = $hxEnums[node.__enum__];
  if (!owner) throw new Error("unknown enum owner");
  const selected = owner.__constructs__[node._hx_index];
  if (!selected) throw new Error("unknown enum constructor");
  return selected;
}
function name(node) {
  return constructor(node)._hx_name;
}
function parameters(node) {
  return (constructor(node).__params__ || []).map(field => node[field]);
}
function operation(node) {
  if (name(node) === "OpAssignOp") {
    if (parameters(node).length !== 1) throw new Error("compound arity");
    return "OpAssignOp(" + operation(parameters(node)[0]) + ")";
  }
  if (parameters(node).length !== 0) throw new Error("operator arity");
  return name(node);
}
function check(token, value) {
  for (let i = 0; i < 2; i++) {
    if (name(value.expr) !== "EParenthesis" || parameters(value.expr).length !== 1)
      throw new Error("parenthesis shape");
    value = parameters(value.expr)[0];
  }
  if (name(value.expr) !== "EBinop" || parameters(value.expr).length !== 3)
    throw new Error("binary shape");
  const args = parameters(value.expr);
  for (let i = 1; i < 3; i++) {
    const leaf = args[i].expr;
    if (name(leaf) !== "EConst" || name(parameters(leaf)[0]) !== "CIdent"
        || parameters(parameters(leaf)[0])[0] !== (i === 1 ? "left" : "right"))
      throw new Error("operand order");
  }
  console.log(token + "\t" + operation(args[0]));
}
/*VALUES*/
