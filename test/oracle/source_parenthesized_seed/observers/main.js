function operation(node) {
  if (node.__hx_ctor === "OpAssignOp") {
    if (node.__hx_params.length !== 1) throw new Error("compound arity");
    return "OpAssignOp(" + operation(node.__hx_params[0]) + ")";
  }
  if (node.__hx_params.length !== 0) throw new Error("operator arity");
  return node.__hx_ctor;
}
function check(token, value) {
  for (let i = 0; i < 2; i++) {
    if (value.expr.__hx_ctor !== "EParenthesis" || value.expr.__hx_params.length !== 1)
      throw new Error("parenthesis shape");
    value = value.expr.__hx_params[0];
  }
  if (value.expr.__hx_ctor !== "EBinop" || value.expr.__hx_params.length !== 3)
    throw new Error("binary shape");
  const args = value.expr.__hx_params;
  for (let i = 1; i < 3; i++) {
    const leaf = args[i].expr;
    if (leaf.__hx_ctor !== "EConst" || leaf.__hx_params[0].__hx_ctor !== "CIdent"
        || leaf.__hx_params[0].__hx_params[0] !== (i === 1 ? "left" : "right"))
      throw new Error("operand order");
  }
  console.log(token + "\t" + operation(args[0]));
}
/*VALUES*/
