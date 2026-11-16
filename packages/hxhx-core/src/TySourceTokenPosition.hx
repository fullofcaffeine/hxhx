/**
	Finds where a piece of already parsed source was written, for placing diagnostics.

	Type hints and call arguments in the syntax tree carry no position of their own, so
	a diagnostic that wants to point at them has to look at the module text again. This
	module does that over `HxLexer` tokens rather than raw characters, so text inside a
	comment, string or regular expression can never be mistaken for code.

	Every search returns the position it was given when it cannot identify exactly one
	place. A less precise line is better than a precise wrong one.
**/
class TySourceTokenPosition {
	/** The module's tokens, or none when the text cannot be lexed (no position is then refined). **/
	public static function tokens(source:Null<String>):Array<HxToken> {
		if (source == null || source.length == 0)
			return [];
		try {
			return HxLexer.tokenize(source);
		} catch (_:HxParseError) {
			return [];
		}
	}

	/**
		Find a type hint written at or after `anchor`, before the next top-level `;` starts.

		Hints are stored without whitespace (`Box<Int,String>`), while tokens drop the
		whitespace and comments of the source, so the two compare directly.
	**/
	public static function typeHint(tokens:Array<HxToken>, source:Null<String>, hint:Null<String>, anchor:HxPos):HxPos {
		if (source == null || hint == null || hint.length == 0 || anchor.getIndex() < 0)
			return anchor;
		final wanted = ~/\s+/g.replace(hint, "");
		var index = firstAtOrAfter(tokens, anchor.getIndex());
		while (index < tokens.length && !tokens[index].kind.match(TEof | TSemicolon)) {
			if (hintStartsAt(tokens, source, index, wanted))
				return tokens[index].pos;
			index++;
		}
		return anchor;
	}

	/** The closing `)` of the parameter list after `start`, so a return hint is searched past its arguments. **/
	public static function afterParameterList(tokens:Array<HxToken>, start:HxPos):HxPos {
		if (start.getIndex() < 0)
			return start;
		var depth = 0;
		for (index in firstAtOrAfter(tokens, start.getIndex())...tokens.length) {
			switch (tokens[index].kind) {
				case TLParen:
					depth++;
				case TRParen:
					if (--depth == 0)
						return new HxPos(tokens[index].pos.getIndex(), start.getLine(), start.getColumn());
				case _:
			}
		}
		return start;
	}

	/**
		Find argument `surplus` (0-based) of the `new` expression inside the statement at `statement`.

		A typed `new` knows only its statement's position, and one statement can hold several
		`new` expressions. A candidate must therefore have the same type path and argument
		count; when that does not leave exactly one, the statement position is kept.
	**/
	public static function surplusConstructorArgument(tokens:Array<HxToken>, statement:HxPos, typePath:String, argumentCount:Int, surplus:Int):HxPos {
		if (statement == null || statement.getIndex() < 0 || surplus < 0)
			return statement;
		final angle = typePath.indexOf("<");
		final path = angle < 0 ? typePath : typePath.substring(0, angle);
		var found:Null<HxPos> = null;
		var matches = 0;
		var depth = 0;
		var index = firstAtOrAfter(tokens, statement.getIndex());
		while (index < tokens.length) {
			switch (tokens[index].kind) {
				case TEof:
					break;
				case TSemicolon if (depth == 0):
					break;
				case TLParen | TLBrace | TOther("[".code):
					depth++;
				case TRParen | TRBrace | TOther("]".code):
					if (--depth < 0)
						break;
				case TKeyword(KNew):
					final open = constructorArgumentsOpen(tokens, index, path);
					final starts = open < 0 ? null : argumentStarts(tokens, open);
					if (starts != null && starts.length == argumentCount && surplus < starts.length) {
						matches++;
						found = tokens[starts[surplus]].pos;
					}
				case _:
			}
			index++;
		}
		return matches == 1 ? found : statement;
	}

	/** First token whose start is at or after a source offset. **/
	static function firstAtOrAfter(tokens:Array<HxToken>, offset:Int):Int {
		var low = 0;
		var high = tokens.length;
		while (low < high) {
			final middle = (low + high) >> 1;
			if (tokens[middle].pos.getIndex() < offset)
				low = middle + 1;
			else
				high = middle;
		}
		return low;
	}

	static function hintStartsAt(tokens:Array<HxToken>, source:String, start:Int, wanted:String):Bool {
		var matched = 0;
		var index = start;
		while (matched < wanted.length) {
			if (index >= tokens.length || tokens[index].kind.match(TEof))
				return false;
			final text = source.substring(tokens[index].pos.getIndex(), tokens[index].endIndex);
			if (text.length == 0 || wanted.substr(matched, text.length) != text)
				return false;
			matched += text.length;
			index++;
		}
		return true;
	}

	/**
		The `(` opening the arguments of the `new` token at `newIndex`, or -1.
		A non-null `path` must equal the written dotted path, without its type arguments.
	**/
	static function constructorArgumentsOpen(tokens:Array<HxToken>, newIndex:Int, ?path:String):Int {
		var index = newIndex + 1;
		final written = new StringBuf();
		while (index < tokens.length) {
			switch (tokens[index].kind) {
				case TIdent(name):
					written.add(name);
				case TDot:
					written.add(".");
				case _:
					break;
			}
			index++;
		}
		if (path != null && written.toString() != path)
			return -1;
		if (index < tokens.length && tokens[index].kind.match(TOther("<".code))) {
			var angle = 0;
			var brace = 0;
			while (index < tokens.length) {
				switch (tokens[index].kind) {
					case TEof:
						return -1;
					case TLBrace:
						brace++;
					case TRBrace:
						brace--;
					case TOther("<".code):
						angle++;
					case TOther(">".code) if (brace == 0 && !tokens[index - 1].kind.match(TOther("-".code))):
						if (--angle == 0) {
							index++;
							return index < tokens.length && tokens[index].kind.match(TLParen) ? index : -1;
						}
					case _:
				}
				index++;
			}
			return -1;
		}
		return index < tokens.length && tokens[index].kind.match(TLParen) ? index : -1;
	}

	/** Token indexes where each top-level argument begins, or null when the list never closes. **/
	static function argumentStarts(tokens:Array<HxToken>, open:Int):Null<Array<Int>> {
		var index = open + 1;
		if (index < tokens.length && tokens[index].kind.match(TRParen))
			return [];
		final starts = [index];
		var depth = 0;
		while (index < tokens.length) {
			switch (tokens[index].kind) {
				case TEof:
					return null;
				case TKeyword(KNew):
					// A nested `new Box<A,B>(...)` has commas that do not separate this list.
					final nested = constructorArgumentsOpen(tokens, index);
					if (nested >= 0) {
						index = nested;
						continue;
					}
				case TLParen | TLBrace | TOther("[".code):
					depth++;
				case TRParen if (depth == 0):
					return starts;
				case TRParen | TRBrace | TOther("]".code):
					depth--;
				case TComma if (depth == 0):
					starts.push(index + 1);
				case _:
			}
			index++;
		}
		return null;
	}
}
