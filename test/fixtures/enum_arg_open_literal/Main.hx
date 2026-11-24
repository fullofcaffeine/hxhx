import haxe.macro.Expr;

/**
	Records with open fields (`[]`, `null`) stored in a local and then passed where a typedef'd
	record is expected, as upstream `tests/unit/src/unit/UnitBuilder.hx` passes `FFun(func)`.
	Upstream Haxe 4.3.7 binds each open field type when the argument unifies with
	`haxe.macro.Expr.Function`. `readDir` repeats UnitBuilder's shape inside a local function,
	where hxhx sees the open fields as `Dynamic`; upstream unifies `Dynamic` with any field type.
**/
class Main {
	static function make(body:Expr):Field {
		var func = {
			args: [],
			ret: null,
			params: [],
			expr: body
		}
		return {
			name: "test",
			kind: FFun(func),
			pos: body.pos,
			access: [APublic],
			doc: null,
			meta: []
		};
	}

	static function nullOnly(body:Expr):FieldType {
		var func = {
			args: new Array<FunctionArg>(),
			ret: null,
			expr: body
		}
		return FFun(func);
	}

	static function take(f:Function):Int
		return f.args.length;

	static function viaFunction(body:Expr):Int {
		var func = {args: [], expr: body}
		return take(func);
	}

	static final defined = new Array<String>();

	static function define(path:String, types:Array<TypeDefinition>):Void
		defined.push(path + ":" + types[0].fields.length);

	static function defineInLocalFunction(body:Expr):Void {
		var numFiles = 0;
		function readDir(names:Array<String>) {
			for (name in names) {
				numFiles++;
				var func = {
					args: [],
					ret: null,
					params: [],
					expr: body
				}
				var field = {
					name: "test",
					kind: FFun(func),
					pos: body.pos,
					access: [APublic],
					doc: null,
					meta: name.length > 1 ? [{name: ":keep", params: [], pos: body.pos}] : []
				};
				define("unit.spec.Test" + name, [
					{
						pack: ["unit", "spec"],
						name: "Test" + name,
						pos: body.pos,
						kind: TDClass(),
						fields: [field]
					}
				]);
			}
		}
		readDir(["A", "Bb"]);
	}

	static function main() {
		final body = {expr: EConst(CInt("1")), pos: null};
		final field = make(body);
		switch field.kind {
			case FFun(f):
				Sys.println(field.name + " " + f.args.length + " " + (f.ret == null) + " " + f.params.length);
			case _:
				Sys.println("other");
		}
		final kind = switch nullOnly(body) {
			case FFun(_): "FFun";
			case _: "other";
		}
		Sys.println(kind + " " + viaFunction(body));
		defineInLocalFunction(body);
		Sys.println(defined.join(" "));
	}
}
