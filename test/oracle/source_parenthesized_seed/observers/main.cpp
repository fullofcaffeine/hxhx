#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
/*RUNTIME*/

static std::string operation(const __HxMacroExpr& node) {
  if (node.__hx_ctor == "OpAssignOp") {
    if (node.__hx_params.size() != 1) throw std::runtime_error("compound arity");
    return "OpAssignOp(" + operation(node.__hx_params.at(0)) + ")";
  }
  if (!node.__hx_params.empty()) throw std::runtime_error("operator arity");
  return node.__hx_ctor;
}
static void check(const std::string& token, const __HxMacroExpr& value) {
  auto node = value;
  for (int i = 0; i < 2; ++i) {
    if (!node.expr || node.expr->__hx_ctor != "EParenthesis" || node.expr->__hx_params.size() != 1)
      throw std::runtime_error("parenthesis shape");
    const auto inner = node.expr->__hx_params.at(0);
    node = inner;
  }
  if (!node.expr || node.expr->__hx_ctor != "EBinop" || node.expr->__hx_params.size() != 3)
    throw std::runtime_error("binary shape");
  const auto& args = node.expr->__hx_params;
  for (int i = 1; i < 3; ++i) {
    const auto& leaf = *args.at(i).expr;
    if (leaf.__hx_ctor != "EConst" || leaf.__hx_params.at(0).__hx_ctor != "CIdent"
        || leaf.__hx_params.at(0).__hx_params.at(0).__hx_value != (i == 1 ? "left" : "right"))
      throw std::runtime_error("operand order");
  }
  std::cout << token << "\t" << operation(args.at(0)) << "\n";
}
int main() {
/*VALUES*/
}
