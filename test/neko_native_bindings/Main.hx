import neko.Lib as Native;

/** Exercise early native bindings and their later assignments through real standard providers. */
class Main {
	static var literalEarly = probe(literal);
	static var aliasEarly = probe(alias);
	static var typedEarly = probe(typed);
	static var computedEarly = probe(computed);
	static var concatEarly = probe(concat);
	static var factoryEarly = probe(factory);
	static var literal = neko.Lib.load("std", "sys_string", 0);
	static var alias = Native.load("std", "sys_string", 0);
	static var typed:Void->String = neko.Lib.load("std", "sys_string", 0);
	static var computed = neko.Lib.load(library(), "sys_string", 0);
	static var concat = neko.Lib.load("s" + "td", "sys_string", 0);
	static var factory = create();
	static var saved = reassigned;
	static var changed = replace();
	static var reassigned = neko.Lib.load("std", "sys_string", 0);

	static function library():String {
		Sys.println("library");
		return "std";
	}

	static function create():Dynamic {
		return neko.Lib.load("std", "sys_string", 0);
	}

	// Dynamic is the native-loader API's return type; invocation is confined to this observer.
	static function probe(value:Dynamic):Bool {
		try {
			return value() != null;
		} catch (error:Dynamic) {
			return false;
		}
	}

	static function replace():Bool {
		reassigned = function() {
			return null;
		};
		return reassigned() == null;
	}

	static function main():Void {
		Sys.println(literalEarly);
		Sys.println(aliasEarly);
		Sys.println(typedEarly);
		Sys.println(computedEarly);
		Sys.println(concatEarly);
		Sys.println(factoryEarly);
		Sys.println(probe(saved));
		Sys.println(changed);
		Sys.println(probe(reassigned));
	}
}
