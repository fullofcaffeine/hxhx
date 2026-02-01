/**
	Stage 2 parser skeleton.

	What:
	- For now, this does *not* implement the Haxe grammar.
	- It exists to establish the module boundary and the “AST in / AST out” flow.

	How:
	- We return a tiny placeholder ParsedModule so downstream stages can be
	  written and tested without waiting for a full parser.
**/
class ParserStage {
	public function new() {}

	public static function parse(source:String):ParsedModule {
		final decl = new HxParser(source).parseModule();
		return new ParsedModule(source, decl);
	}
}
