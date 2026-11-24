import haxe.macro.Context;
import haxe.macro.Expr;
class M {
  public static macro function p(e:Expr):Expr {
    var i = Context.getPosInfos(e.pos);
    Sys.println('ARG ' + haxe.macro.ExprTools.toString(e) + ' min=' + i.min + ' max=' + i.max + ' ' + e.pos + ' def=' + e.expr);
    function walk(x:Expr) { var j = Context.getPosInfos(x.pos); Sys.println('  sub ' + haxe.macro.ExprTools.toString(x) + ' ' + j.min + '-' + j.max); haxe.macro.ExprTools.iter(x, walk); }
    haxe.macro.ExprTools.iter(e, walk);
    return macro null;
  }
  public static macro function bad(e:Expr):Expr {
    var p = Context.makePosition({min: 5, max: 2, file: "Nope.hx"});
    Context.warning("w1", p);
    Context.warning("w2", Context.makePosition({min: 0, max: 3, file: ""}));
    Context.warning("w3", Context.makePosition({min: -5, max: 3, file: "A.hx"}));
    return {expr: EConst(CIdent("nosuch")), pos: Context.makePosition({min: 2, max: 9, file: "M.hx"})};
  }
}
