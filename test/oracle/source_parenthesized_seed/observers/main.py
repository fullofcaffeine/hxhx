from types import SimpleNamespace

hxhx_anon = SimpleNamespace

def operation(node):
    if node.__hx_ctor == "OpAssignOp":
        assert len(node.__hx_params) == 1, "compound arity"
        return "OpAssignOp(" + operation(node.__hx_params[0]) + ")"
    assert not node.__hx_params, "operator arity"
    return node.__hx_ctor

def check(token, value):
    for _ in range(2):
        assert value.expr.__hx_ctor == "EParenthesis" and len(value.expr.__hx_params) == 1, "parenthesis shape"
        value = value.expr.__hx_params[0]
    assert value.expr.__hx_ctor == "EBinop" and len(value.expr.__hx_params) == 3, "binary shape"
    args = value.expr.__hx_params
    for index, name in [(1, "left"), (2, "right")]:
        leaf = args[index].expr
        assert leaf.__hx_ctor == "EConst" and leaf.__hx_params[0].__hx_ctor == "CIdent", "operand shape"
        assert leaf.__hx_params[0].__hx_params[0] == name, "operand order"
    print(token + "\t" + operation(args[0]))

# VALUES
