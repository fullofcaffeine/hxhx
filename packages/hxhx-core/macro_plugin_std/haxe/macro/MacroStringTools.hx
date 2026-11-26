package haxe.macro;

import haxe.macro.Expr;

/**
	hxhx's `haxe.macro.MacroStringTools` for project-macro plugins.

	Why
	- Upstream's `formatString` calls the macro interpreter (`Context.load("format_string", 2)`,
	  `std/haxe/macro/MacroStringTools.hx` line 44 in Haxe 4.3.7), which a native plugin does not
	  have. The plugin build puts this classpath before the standard library, as for `Context`.

	What
	- `formatString` is upstream's `format_string` (`src/typing/typer.ml`, lines 733-831), run in
	  the plugin. The code of each `${...}` goes to `Context.parseInlineString`, which is the parser
	  call upstream makes there (`ParserEntry.parse_expr_string ... true`, line 816; the same
	  function as `do_parse` with `inl = true`, `src/typing/macroContext.ml` lines 130-135).
	- The other functions give upstream's results in forms the Stage3 plugin emitter accepts:
	  `toFieldExpr` folds with a loop instead of `Lambda.fold` (an iterator over a type parameter),
	  and `isFormatExpr` uses `switch` instead of `match` with a `_` argument.

	Positions follow upstream: `pos` is the string literal, with `min` at its opening quote; a part
	starts after the text before it, `$` and `${` and `}` count, and each `'` moves later parts by
	one. hxhx's `parseInlineString` gives every node of a `${...}` the range of its code for now,
	so only that expression's root matches upstream exactly (`haxe_ocaml-9sj5p.2`).
**/
class MacroStringTools {
	/**
		Formats `String` `s` using the usual interpolation rules.

		The returned expression is a concatenation of string parts and escaped
		elements.
	**/
	static public function formatString(s:String, pos:Position):Expr {
		return new FormatString(s, pos).run();
	}

	/**
		Tells if `e` is a format string, i.e. uses single quotes `'` as
		delimiters.
	**/
	static public function isFormatExpr(e:ExprOf<String>):Bool {
		return switch e.expr {
			case EConst(CString(_, SingleQuotes)): true;
			case _: false;
		}
	}

	/**
		Converts an array of Strings `sl` to a field expression.

		If `sl` has no elements, the result is null.

		If `sl` has one element, the result is `EConst(CIdent(sl[0])`.

		Otherwise the result is a chain of `EField` nodes.

		If `sl` is null, the result is unspecified.
	**/
	static public function toFieldExpr(sl:Array<String>, ?pos):Expr {
		var e:Null<Expr> = null;
		if (pos == null) {
			// Upstream's `Lambda.fold` from null, as a loop over the array.
			for (s in sl)
				e = e == null ? (macro $i{s}) : (macro $e.$s);
			return e;
		}
		for (v in sl)
			if (e == null)
				e = {expr: EConst(CIdent(v)), pos: pos};
			else
				e = {expr: EField(e, v), pos: pos};
		return e;
	}

	/**
		Converts a path given by package `pack` and name `name` to a `String`
		separated by dots.

		If `pack` has no elements, the result is `name`.

		If `pack` is null, the result is unspecified.

		Otherwise the elements of `pack` are joined with a separating dot, with
		an appended dot separating the result from `name`.
	**/
	static public function toDotPath(pack:Array<String>, name:String):String {
		return if (pack.length == 0) name else pack.join(".") + "." + name;
	}

	static public function toComplex(path:String):ComplexType {
		var pack = path.split(".");
		return TPath({pack: pack, name: pack.pop(), params: []});
	}
}

/**
	One run of upstream's `format_string` (`src/typing/typer.ml`, lines 733-831), with its names:
	`pmin` is where index 0 of `s` would be without the opening quote, `min` is where the next part
	starts, and `result` is the concatenation so far.
**/
private class FormatString {
	final s:String;
	final file:String;
	final len:Int;
	var pmin:Int;
	var min:Int;
	var result:Null<Expr> = null;

	public function new(s:String, pos:Position) {
		final infos = Context.getPosInfos(pos);
		this.s = s;
		this.file = infos.file;
		this.len = s.length;
		this.pmin = infos.min;
		this.min = infos.min + 1;
	}

	public function run():Expr {
		parse(0, 0);
		return result;
	}

	function at(min:Int, max:Int):Position
		return Context.makePosition({min: min, max: max, file: file});

	/** `add_expr`: the next part, joined with `+` over both ranges (`punion`, `src/core/ast.ml` lines 449-454). */
	function addExpr(next:Expr, length:Int):Void {
		min += length;
		if (result == null) {
			result = next;
			return;
		}
		final before = Context.getPosInfos(result.pos);
		final after = Context.getPosInfos(next.pos);
		final joined = at(before.min < after.min ? before.min : after.min, before.max > after.max ? before.max : after.max);
		result = {expr: EBinop(OpAdd, result, next), pos: joined};
	}

	function add(kind:ExprDef, length:Int):Void
		addExpr({expr: kind, pos: at(min, min + length)}, length);

	/** `add_sub`: the text from `start` to `end`; an empty text only when nothing came before. */
	function addText(start:Int, end:Int):Void {
		final length = end - start;
		if (length > 0 || result == null)
			add(EConst(CString(s.substr(start, length), DoubleQuotes)), length);
	}

	function parse(start:Int, pos:Int):Void {
		while (true) {
			if (pos == len) {
				addText(start, pos);
				return;
			}
			final c = s.charCodeAt(pos);
			pos++;
			if (c == "'".code) {
				pmin++;
				min++;
			}
			if (c != "$".code || pos == len)
				continue;
			final next = s.charCodeAt(pos);
			if (next == "$".code) {
				// `$$`: the text keeps one `$`.
				addText(start, pos);
				pos++;
				start = pos;
			} else if (next == "{".code) {
				pos = group(start, pos);
				start = pos;
			} else if (isIdentStart(next)) {
				addText(start, pos - 1);
				min++;
				var end = pos + 1;
				while (end < len && isIdentPart(s.charCodeAt(end)))
					end++;
				final length = end - pos;
				add(EConst(CIdent(s.substr(pos, length))), length);
				pos += length;
				start = pos;
			}
			// Any other character after `$` stays in the text.
		}
	}

	/** `parse_group` for `${`, with `{` at `open`; returns the index after the closing `}`. */
	function group(start:Int, open:Int):Int {
		addText(start, open - 1);
		final groups = [open];
		var i = open + 1;
		while (true) {
			if (i == len)
				Context.error("Unclosed brace", at(pmin + groups[groups.length - 1] + 1, pmin + groups[groups.length - 1] + 2));
			final c = s.charCodeAt(i);
			if (c == "{".code) {
				groups.push(i);
			} else if (c == "}".code) {
				groups.pop();
				if (groups.length == 0)
					break;
			}
			i++;
		}
		final close = i;
		final length = close - open - 1;
		final code = s.substr(open + 1, length);
		min += 2;
		final codePos = at(pmin + open + 2, pmin + close + 1);
		if (isWhitespace(code))
			Context.error("Expression cannot be empty", codePos);
		addExpr(Context.parseInlineString(code, codePos), length);
		min += 1;
		return close + 1;
	}

	static function isIdentStart(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code;

	static function isIdentPart(c:Int):Bool
		return isIdentStart(c) || (c >= "0".code && c <= "9".code);

	/** `Lexer.string_is_whitespace` (`src/syntax/lexer.ml`, lines 341-353). */
	static function isWhitespace(code:String):Bool {
		for (i in 0...code.length) {
			final c = code.charCodeAt(i);
			if (c != " ".code && c != "\n".code && c != "\r".code && c != "\t".code)
				return false;
		}
		return true;
	}
}
