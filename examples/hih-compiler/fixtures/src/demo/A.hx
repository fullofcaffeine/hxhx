package demo;

import demo.Util;

class A {
  static function main() {}

  // Acceptance fixture for Stage 3 typer:
  // - no return type hint (must infer `String`)
  static function greet() return "hello";

  // Acceptance fixture for Stage 3 local scope:
  // - infer return type via identifier resolution (`s : String`)
  static function echo(s:String) return s;

  // Acceptance fixture: infer `Int` literal return.
  static function fortyTwo() return 42;

  // Acceptance fixture: infer `Bool` literal return.
  static function flag() return true;
}
