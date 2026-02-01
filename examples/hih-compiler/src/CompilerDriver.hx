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
	public static function run():Void {
		final source = [
			"package demo;",
			"import demo.Util;",
			"class A {",
			"  static function main() {}",
			"}",
		].join("\n");

		final ast = ParserStage.parse(source);
		final decl = ast.getDecl();
		Sys.println("parse=ok");
		Sys.println("package=" + (decl.packagePath.length == 0 ? "<none>" : decl.packagePath));
		Sys.println("imports=" + decl.imports.length);
		Sys.println("class=" + decl.mainClass.name);
		Sys.println("hasStaticMain=" + (decl.mainClass.hasStaticMain ? "yes" : "no"));

		final typed = TyperStage.typeModule(ast);
		Sys.println("typer=ok");

		final expanded = MacroStage.expand(typed);
		Sys.println("macros=stub");

		EmitterStage.emit(expanded);
		Sys.println("emit=stub");
	}
}
