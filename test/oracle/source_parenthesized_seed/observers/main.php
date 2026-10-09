<?php
function operation($node) {
    if ($node->__hx_ctor === "OpAssignOp") {
        if (count($node->__hx_params) !== 1) throw new Exception("compound arity");
        return "OpAssignOp(" . operation($node->__hx_params[0]) . ")";
    }
    if (count($node->__hx_params) !== 0) throw new Exception("operator arity");
    return $node->__hx_ctor;
}
function check($token, $value) {
    for ($i = 0; $i < 2; $i++) {
        if ($value->expr->__hx_ctor !== "EParenthesis" || count($value->expr->__hx_params) !== 1)
            throw new Exception("parenthesis shape");
        $value = $value->expr->__hx_params[0];
    }
    if ($value->expr->__hx_ctor !== "EBinop" || count($value->expr->__hx_params) !== 3)
        throw new Exception("binary shape");
    $args = $value->expr->__hx_params;
    for ($i = 1; $i < 3; $i++) {
        $leaf = $args[$i]->expr;
        if ($leaf->__hx_ctor !== "EConst" || $leaf->__hx_params[0]->__hx_ctor !== "CIdent"
            || $leaf->__hx_params[0]->__hx_params[0] !== ($i === 1 ? "left" : "right"))
            throw new Exception("operand order");
    }
    echo $token, "\t", operation($args[0]), "\n";
}
/*VALUES*/
