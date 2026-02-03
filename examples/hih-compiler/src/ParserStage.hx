/**
	Stage 2 parser skeleton.

	What:
	- For now, this does *not* implement the Haxe grammar.
	- It exists to establish the module boundary and the “AST in / AST out” flow.

	How:
	- We return a tiny placeholder ParsedModule so downstream stages can be
	  written and tested without waiting for a full parser.

	Native hook:
	- When `-D hih_native_parser` is enabled, we call into the OCaml “native”
	  lexer/parser stubs (`HxHxNativeLexer` / `HxHxNativeParser`) via externs.
	  This matches the upstream bootstrap strategy: keep the frontend native
	  while we port the rest of the compiler pipeline into Haxe.
**/
class ParserStage {
	public function new() {}

	public static function parse(source:String):ParsedModule {
		final decl = #if hih_native_parser
			parseViaNativeHooks(source);
		#else
			new HxParser(source).parseModule();
		#end
		return new ParsedModule(source, decl);
	}

	#if hih_native_parser
	static function parseViaNativeHooks(source:String):HxModuleDecl {
		// Ensure the lexer is reachable too (even though the parser itself already
		// calls it internally).
		final _tokens = native.NativeLexer.tokenize(source);

		final encoded = native.NativeParser.parseModuleDecl(source);
		var packagePath = "";
		final imports = new Array<String>();
		var className = "Unknown";
		var hasStaticMain = false;

		for (line in encoded.split("\n")) {
			if (line.length == 0) continue;
			final i = line.indexOf(":");
			if (i <= 0) continue;
			final key = line.substr(0, i);
			final value = line.substr(i + 1);
			switch (key) {
				case "package":
					packagePath = value;
				case "imports":
					final v = value;
					if (v.length > 0) {
						for (p in v.split("|")) {
							if (p.length > 0) imports.push(p);
						}
					}
				case "class":
					className = value;
				case "staticMain":
					hasStaticMain = value == "1";
				case _:
					// ignore unknown keys for forwards-compat
			}
		}

		return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain));
	}
	#end
}
