package reflaxe.ocaml.ast;

using StringTools;

/**
	Finds identifier tokens in authored OCaml code without treating strings or
	comments as executable names.

	The compiler uses this narrow scanner to reserve its private `Hx...` runtime
	namespace at raw-text boundaries. It is not a parser and must not make target
	semantic decisions; structured compiler output remains represented by the
	OCaml target AST instead.
**/
class OcamlCodeIdentifierScanner {
	/** Returns identifiers that occur in OCaml code, excluding strings and nested comments. */
	public static function scan(text:String):Array<String> {
		final out:Array<String> = [];
		var index = 0;
		var inString = false;
		var commentDepth = 0;
		while (index < text.length) {
			final code = text.fastCodeAt(index);
			final next = index + 1 < text.length ? text.fastCodeAt(index + 1) : -1;
			if (commentDepth > 0) {
				if (code == "(".code && next == "*".code) {
					commentDepth++;
					index += 2;
				} else if (code == "*".code && next == ")".code) {
					commentDepth--;
					index += 2;
				} else {
					index++;
				}
				continue;
			}
			if (inString) {
				if (code == "\\".code) {
					index += 2;
				} else {
					if (code == '"'.code)
						inString = false;
					index++;
				}
				continue;
			}
			if (code == "(".code && next == "*".code) {
				commentDepth = 1;
				index += 2;
				continue;
			}
			if (code == '"'.code) {
				inString = true;
				index++;
				continue;
			}
			if (isIdentifierStart(code)) {
				final start = index;
				index++;
				while (index < text.length && isIdentifierPart(text.fastCodeAt(index)))
					index++;
				out.push(text.substring(start, index));
				continue;
			}
			index++;
		}
		return out;
	}

	/** Reports whether a token belongs to the compiler-owned `Hx` plus uppercase namespace. */
	public static function isPrivateRuntimeIdentifier(identifier:String):Bool {
		if (identifier.length < 3 || !identifier.startsWith("Hx"))
			return false;
		final third = identifier.fastCodeAt(2);
		return third >= "A".code && third <= "Z".code;
	}

	/** Reports whether one ASCII code can continue an OCaml identifier token. */
	public static function isIdentifierPartCode(code:Int):Bool {
		return isIdentifierStart(code) || (code >= "0".code && code <= "9".code) || code == "'".code;
	}

	static function isIdentifierStart(code:Int):Bool {
		return (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code) || code == "_".code;
	}

	static inline function isIdentifierPart(code:Int):Bool
		return isIdentifierPartCode(code);
}
