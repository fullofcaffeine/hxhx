import haxe.macro.Context;
import haxe.macro.Expr;
class Z {
  public static macro function edge(e:Expr):Expr {
    Context.warning("zero", Context.makePosition({min: 5, max: 5, file: "Nope.hx"}));
    Context.warning("unknown", Context.makePosition({min: -1, max: -1, file: "A.hx"}));
    Context.warning("span", Context.makePosition({min: 30, max: 60, file: "A.hx"}));
    return macro null;
  }
}
