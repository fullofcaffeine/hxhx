package hxhx.macro;

/**
	Compiler-owned local-import snapshot helper for the external-host macro runtime.

	Why
	- Runtime `Context.getLocalImports()` is useful for real target macros, especially metadata and
	  import-resolution helpers in compiler-shaped libraries like `reflaxe.elixir`.
	- Our current parsed-module representation only stores raw import strings and intentionally drops
	  alias mode (`import Foo as Bar`) information.
	- We therefore need a narrower, honest rung that preserves import semantics without widening the
	  external-host ABI to a full AST transport.

	What
	- Reads the active source file and scans only the top-of-module `import` block.
	- Preserves:
	  - normal imports (`import String;`)
	  - aliased imports (`import haxe.Template as T;`)
	  - wildcard imports (`import haxe.macro.*;`)
	- Encodes the result as a length-prefixed payload for the existing macro-host protocol.

	How
	- Uses the repo's lexer (`HxLexer`) instead of regex so comments and strings do not produce fake
	  `import` matches.
	- Stops scanning after the package/import section; later declarations are intentionally ignored.
	- Returns synthetic positions derived from token offsets in the source file. Current consumers care
	  about `path`/`mode`, not exact import-source spans.

	Gotchas
	- This is a bring-up rung, not full upstream import metadata parity.
	- `using` directives are intentionally ignored because `Context.getLocalImports()` only returns
	  imports, not usings.
**/
class MacroLocalImports {
	static inline final MODE_NORMAL:String = "normal";
	static inline final MODE_ALIAS:String = "alias";
	static inline final MODE_ALL:String = "all";

	public static function encodePayloadFromSourceFile(sourceFile:String):String {
		final imports = readImports(sourceFile);
		final parts = new Array<String>();
		parts.push(MacroProtocol.encodeLen("c", Std.string(imports.length)));
		for (i in 0...imports.length) {
			final entry = imports[i];
			parts.push(MacroProtocol.encodeLen("p" + i, entry.path));
			parts.push(MacroProtocol.encodeLen("m" + i, entry.mode));
			parts.push(MacroProtocol.encodeLen("f" + i, entry.file));
			parts.push(MacroProtocol.encodeLen("mi" + i, Std.string(entry.min)));
			parts.push(MacroProtocol.encodeLen("ma" + i, Std.string(entry.max)));
			if (entry.alias != null)
				parts.push(MacroProtocol.encodeLen("a" + i, entry.alias));
		}
		return parts.join(" ");
	}

	static function readImports(sourceFile:String):Array<MacroLocalImportEntry> {
		final out = new Array<MacroLocalImportEntry>();
		if (sourceFile == null || sourceFile.length == 0)
			return out;

		final source = try sys.io.File.getContent(sourceFile) catch (_:String) null;
		if (source == null)
			return out;

		final lexer = new HxLexer(source);
		var cur = lexer.next();

		inline function bump():Void
			cur = lexer.next();

		function acceptKeyword(expected:HxKeyword):Bool {
			return switch (cur.kind) {
				case TKeyword(actual) if (actual == expected):
					bump();
					true;
				case _:
					false;
			};
		}

		function readIdentToken():Null<ImportToken> {
			return switch (cur.kind) {
				case TIdent(name):
					final token = {name: name, pos: cur.pos};
					bump();
					token;
				case _:
					null;
			};
		}

		function skipToSemicolon():Void {
			while (true) {
				switch (cur.kind) {
					case TSemicolon:
						bump();
						return;
					case TEof:
						return;
					case _:
						bump();
				}
			}
		}

		function consumeImportEntry(isUsing:Bool):Void {
			final first = readIdentToken();
			if (first == null) {
				skipToSemicolon();
				return;
			}

			final names = new Array<String>();
			names.push(first.name);

			var wildcard = false;
			var alias:Null<String> = null;
			var min = first.pos.index;
			var max = first.pos.index + first.name.length;

			var scanningPath = true;
			while (scanningPath) {
				switch (cur.kind) {
					case TDot:
						bump();
						switch (cur.kind) {
							case TOther(code) if (code == "*".code):
								wildcard = true;
								max = cur.pos.index + 1;
								bump();
								scanningPath = false;
							case TIdent(name):
								names.push(name);
								max = cur.pos.index + name.length;
								bump();
							case _:
								skipToSemicolon();
								return;
						}
					case _:
						scanningPath = false;
				}
			}

			if (!isUsing && acceptKeyword(KAs)) {
				final aliasToken = readIdentToken();
				if (aliasToken != null) {
					alias = aliasToken.name;
					max = aliasToken.pos.index + aliasToken.name.length;
				}
			}

			switch (cur.kind) {
				case TSemicolon:
					bump();
				case _:
					skipToSemicolon();
			}

			if (isUsing)
				return;

			out.push({
				path: names.join("."),
				mode: wildcard ? MODE_ALL : (alias == null ? MODE_NORMAL : MODE_ALIAS),
				alias: alias,
				file: sourceFile,
				min: min < 0 ? 0 : min,
				max: max < min ? min : max
			});
		}

		if (acceptKeyword(KPackage)) {
			var packageDone = false;
			while (!packageDone) {
				switch (cur.kind) {
					case TSemicolon:
						bump();
						packageDone = true;
					case TEof:
						return out;
					case _:
						bump();
				}
			}
		}

		while (true) {
			switch (cur.kind) {
				case TKeyword(KImport):
					bump();
					consumeImportEntry(false);
				case TKeyword(KUsing):
					bump();
					consumeImportEntry(true);
				case _:
					return out;
			}
		}

		return out;
	}
}

private typedef ImportToken = {
	var name:String;
	var pos:HxPos;
}

private typedef MacroLocalImportEntry = {
	var path:String;
	var mode:String;
	var alias:Null<String>;
	var file:String;
	var min:Int;
	var max:Int;
}
