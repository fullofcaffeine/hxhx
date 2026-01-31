/**
	A minimal, staged “compiler driver”.

	Why:
	- The real Haxe compiler is a pipeline (parse → type → macro → generate).
	- Even before we implement the full semantics, we want the *shape* and the
	  “seams” to exist: each stage has an explicit input/output and can be
	  validated independently.
	- This file should stay small and orchestration-only; the real work lives in
	  the dedicated stage modules.
**/
class CompilerDriver {
	public function new() {}

	public function run():Void {
		final source = "class A { static function main() {} }";

		final ast = new ParserStage().parse(source);
		Sys.println("parse=ok");

		final typed = new TyperStage().type(ast);
		Sys.println("typer=ok");

		final expanded = new MacroStage().expand(typed);
		Sys.println(expanded.macroMode ? "macros=stub" : "macros=stub");

		new EmitterStage().emit(expanded);
		Sys.println("emit=stub");
	}
}

