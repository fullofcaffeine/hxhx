/**
	Untyped record literals passed to enum constructors (haxe_ocaml-areu3), in the shapes upstream's
	`tests/unit/src/unit/UnitBuilder.hx` uses: `var func = {args: [], ret: null, params: [],
	expr: ...}` then `FFun(func)` (also inside a local function), and a `TypePath`-like record
	written without its optional fields. Upstream binds the open parts (`[]`, `null`) when the
	constructor call unifies them.
**/
typedef Arg = {name:String};

typedef Signature = {
	var args:Array<Arg>;
	var ret:Null<Kind>;
	var ?params:Array<String>;
	var body:String;
}

typedef Path = {
	var pack:Array<String>;
	var name:String;
	var ?sub:String;
}

enum Kind {
	KFun(signature:Signature);
	KPath(path:Path);
}

class Main {
	static function describe(kind:Kind):String {
		return switch kind {
			case KFun(signature):
				"fun args="
				+ signature.args.length
				+ " ret="
				+ (signature.ret == null ? "none" : "some")
				+ " body="
				+ signature.body;
			case KPath(path):
				"path "
				+ path.pack.join(".")
				+ (path.pack.length == 0 ? "" : ".")
				+ path.name
				+ (path.sub == null ? "" : "." + path.sub);
		};
	}

	static function main():Void {
		var func = {
			args: [],
			ret: null,
			params: [],
			body: "a"
		};
		Sys.println(describe(KFun(func)));
		Sys.println(describe(KFun({args: [], ret: null, body: "b"})));
		Sys.println(describe(KPath({pack: [], name: "Base"})));
		function define(name:String):Kind {
			var signature = {
				args: [],
				ret: null,
				params: [],
				body: name
			};
			return KFun(signature);
		}
		Sys.println(describe(define("c")));
	}
}
