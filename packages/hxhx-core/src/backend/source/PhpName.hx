package backend.source;

/**
	Deterministic PHP identifier and type-path spelling.

	The module owns PHP syntax policy only: reserved type words, predefined
	superglobal value names, and namespace separators. It has no compiler or
	request state and receives every source spelling explicitly.
**/
class PhpName {
	/** Spells one PHP type identifier and avoids case-insensitive reserved words. **/
	public static function typeIdentifier(name:String):String {
		final clean = SourceIdentifier.sanitize(name);
		return isReservedTypeIdentifier(clean) ? clean + "_" : clean;
	}

	/** Spells one PHP value identifier and avoids predefined superglobal names. **/
	public static function valueIdentifier(name:String):String {
		final clean = SourceIdentifier.sanitize(name);
		return isReservedValueIdentifier(clean) ? clean + "_" : clean;
	}

	/** Spells one global PHP function name through the shared identifier contract. **/
	public static function globalFunction(name:String):String {
		return SourceIdentifier.sanitize(name);
	}

	/**
		Spells one Haxe type path as a PHP class path.

		Standard-library `php.*` and `haxe.*` paths retain namespace segments.
		Other paths use their final type segment, matching the existing target
		output contract.
	**/
	public static function typePath(path:String):String {
		if (path == null || path.length == 0)
			return "Unknown";
		if (StringTools.startsWith(path, "std."))
			return typePath(path.substr(4));
		if (path == "haxe.io.Error")
			return typeIdentifier("Error");
		if (StringTools.startsWith(path, "php.") || StringTools.startsWith(path, "haxe."))
			return [for (part in path.split(".")) typeIdentifier(part)].join("\\");
		final parts = path.split(".");
		return typeIdentifier(parts[parts.length - 1]);
	}

	static function isReservedValueIdentifier(name:String):Bool {
		return switch (name == null ? "" : name) {
			case "GLOBALS" | "_SERVER" | "_GET" | "_POST" | "_FILES" | "_COOKIE" | "_REQUEST" | "_ENV" | "_SESSION":
				true;
			case _:
				false;
		};
	}

	static function isReservedTypeIdentifier(name:String):Bool {
		return switch (name == null ? "" : name.toLowerCase()) {
			case "abstract" | "and" | "array" | "as" | "break" | "callable" | "case" | "catch" | "class" | "clone" | "const" | "continue" | "declare" |
				"default" | "die" | "do" | "echo" | "else" | "elseif" | "empty" | "enddeclare" | "endfor" | "endforeach" | "endif" | "endswitch" |
				"endwhile" | "enum" | "error" | "eval" | "exit" | "extends" | "final" | "finally" | "fn" | "for" | "foreach" | "function" | "global" |
				"goto" | "if" | "implements" | "include" | "include_once" | "instanceof" | "insteadof" | "interface" | "isset" | "list" | "match" |
				"namespace" | "new" | "or" | "parent" | "print" | "private" | "protected" | "public" | "readonly" | "require" | "require_once" | "return" |
				"self" | "static" | "switch" | "throw" | "trait" | "try" | "unset" | "use" | "var" | "while" | "xor" | "yield" | "from" | "true" | "false" |
				"null":
				true;
			case _:
				false;
		};
	}
}
