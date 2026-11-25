class D {
#if nope
  static var x = "😀éé";
#else /* é */
#end
  static function main() {
    M.p(/* cé */ base /* t */);
    M.p(this1(null, (base)));
    M.p(-base + base++);
    M.p({a: 1, b: base.x});
    M.p(function(a = null) return a);
    M.p(while (true) { break; });
    M.p(~/a\/b/gi);
  }
  static var base = 1; static function this1(a,b) return 1;
}
