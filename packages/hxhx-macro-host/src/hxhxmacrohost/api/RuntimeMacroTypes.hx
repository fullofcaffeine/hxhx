package hxhxmacrohost.api;

import haxe.macro.Expr;
import haxe.macro.Expr.Metadata;
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Position;
import haxe.macro.Type;

/**
	Minimal runtime `haxe.macro.Type` model for external-host bring-up.

	Why
	- Runtime macro modules compiled into `hxhx-macro-host` execute outside upstream eval/neko, so
	  they cannot ask the compiler for real typed structures on demand.
	- A small but *honest* subset is still useful for library initialization and parity probes:
	  builtin type lookup, simple `resolveType`, and literal `typeof`.

	What
	- Builds real `haxe.macro.Type` values for the builtin types we can model safely today:
	  `String`, `Int`, `Float`, `Bool`, `Void`, `Dynamic`, and `Null<T>`.
	- Uses a synthetic named-type model for the non-`Dynamic` cases, which is sufficient for
	  path rendering and literal probes without pretending to expose full compiler-internal kinds.
	- Converts those values back to `ComplexType` and to deterministic debug strings.
	- Rejects unsupported shapes explicitly instead of fabricating richer compiler state.

	How
	- Construct minimal `ClassType` / `Ref<T>` structures entirely inside the macro host process.
	- Represent the named builtin cases through synthetic `TInst` values so runtime macro code can
	  stringify and round-trip them without pretending to mirror upstream compiler internals exactly.
	- Restrict inference and resolution to syntax we can justify locally:
	  - builtin `ComplexType` paths
	  - `Dynamic<T>`
	  - `Null<T>`
	  - literal/parenthesized/check-typed expressions and simple `+` expressions

	Gotchas
	- This is not a general type-checker.
	- Named builtin types currently use a synthetic instance model (`TInst`) rather than exact
	  upstream kind fidelity.
	- Unsupported paths fail fast so future work can extend the model intentionally.
**/
class RuntimeMacroTypes {
	static inline final DEFAULT_FILE:String = "<macro>";

	public static function describe(t:Type):String {
		return "builtin:" + toString(t);
	}

	public static function getTypeByName(name:String):Type {
		return switch (normalizeName(name)) {
			case "String":
				stringType();
			case "Int":
				intType();
			case "Float":
				floatType();
			case "Bool":
				boolType();
			case "Void":
				voidType();
			case "Dynamic":
				TDynamic(null);
			case _:
				throw "runtime macro type lookup is only implemented for builtin names: " + name;
		}
	}

	/**
		Parse a narrow Haxe type-text snapshot into the runtime type model.

		Why
		- Compiler-side snapshots for `Context.getLocalType()` and `getExpectedType()` are easiest to
		  exchange over RPC as small Haxe type strings.
		- Reusing the same builtin-only model keeps the runtime query surface honest.
	**/
	public static function parseTypeText(text:String):Null<Type> {
		final trimmed = StringTools.trim(text == null ? "" : text);
		if (trimmed.length == 0)
			return null;
		if (StringTools.startsWith(trimmed, "Null<") && StringTools.endsWith(trimmed, ">"))
			return nullType(requireInnerType("Null", trimmed));
		if (StringTools.startsWith(trimmed, "Dynamic<") && StringTools.endsWith(trimmed, ">"))
			return TDynamic(requireInnerType("Dynamic", trimmed));
		return getTypeByName(trimmed);
	}

	public static function resolveComplexType(t:ComplexType):Type {
		return switch (t) {
			case null:
				throw "runtime macro resolveType: null complex type";
			case TParent(inner):
				resolveComplexType(inner);
			case TNamed(_, inner):
				resolveComplexType(inner);
			case TOptional(inner):
				nullType(resolveComplexType(inner));
			case TFunction(args, ret):
				TFun([
					for (i in 0...args.length)
						{
							name: "arg" + i,
							opt: false,
							t: resolveComplexType(args[i])
						}
				], resolveComplexType(ret));
			case TPath(path):
				resolveTypePath(path);
			case TAnonymous(_):
				throw "runtime macro resolveType: anonymous structures are not implemented yet";
			case TExtend(_, _):
				throw "runtime macro resolveType: extends anonymous types are not implemented yet";
			case TIntersection(_):
				throw "runtime macro resolveType: intersection types are not implemented yet";
		}
	}

	public static function typeofExpr(e:Expr):Type {
		if (e == null)
			throw "runtime macro typeof: null expr";
		return switch (e.expr) {
			case EConst(CString(_, _)):
				stringType();
			case EConst(CInt(_, _)):
				intType();
			case EConst(CFloat(_, _)):
				floatType();
			case EConst(CIdent("true")) | EConst(CIdent("false")):
				boolType();
			case EConst(CIdent("null")):
				TDynamic(null);
			case EParenthesis(inner):
				typeofExpr(inner);
			case ECheckType(inner, ct):
				final _ = typeofExpr(inner);
				resolveComplexType(ct);
			case EBinop(OpAdd, e1, e2):
				resolveAddType(typeofExpr(e1), typeofExpr(e2));
			case _:
				throw "runtime macro typeof: unsupported expr shape";
		}
	}

	public static function toComplexType(t:Type):Null<ComplexType> {
		return switch (t) {
			case null:
				null;
			case TInst(c, params):
				final base = c.get();
				TPath({
					pack: base.pack.copy(),
					name: base.module,
					sub: base.name == base.module ? null : base.name,
					params: [for (param in params) TPType(toComplexType(param))]
				});
			case TEnum(e, params):
				final base = e.get();
				TPath({
					pack: base.pack.copy(),
					name: base.module,
					sub: base.name == base.module ? null : base.name,
					params: [for (param in params) TPType(toComplexType(param))]
				});
			case TType(td, params):
				final base = td.get();
				TPath({
					pack: base.pack.copy(),
					name: base.module,
					sub: base.name == base.module ? null : base.name,
					params: [for (param in params) TPType(toComplexType(param))]
				});
			case TAbstract(a, params):
				final base = a.get();
				TPath({
					pack: base.pack.copy(),
					name: base.module,
					sub: base.name == base.module ? null : base.name,
					params: [for (param in params) TPType(toComplexType(param))]
				});
			case TFun(args, ret):
				TFunction([for (arg in args) toComplexType(arg.t)], toComplexType(ret));
			case TDynamic(inner):
				if (inner == null) macro :Dynamic else {
					final ct = toComplexType(inner);
					macro :Dynamic<$ct>;
				}
			case TMono(tm):
				final inner = tm.get();
				inner == null ? null : toComplexType(inner);
			case TLazy(f):
				toComplexType(f());
			case TAnonymous(_):
				null;
		}
	}

	public static function toString(t:Type):String {
		return switch (t) {
			case TInst(c, params):
				renderNamedType(c.get().pack, c.get().name, params);
			case TEnum(e, params):
				renderNamedType(e.get().pack, e.get().name, params);
			case TType(td, params):
				renderNamedType(td.get().pack, td.get().name, params);
			case TAbstract(a, params):
				renderNamedType(a.get().pack, a.get().name, params);
			case TFun(args, ret):
				"(" + [for (arg in args) toString(arg.t)].join(", ") + ") -> " + toString(ret);
			case TDynamic(inner):
				inner == null ? "Dynamic" : ("Dynamic<" + toString(inner) + ">");
			case TAnonymous(_):
				"{...}";
			case TLazy(_):
				"<lazy>";
			case TMono(_):
				"<mono>";
		}
	}

	public static function classRefOf(t:Type):Null<Ref<ClassType>> {
		return switch (t) {
			case TInst(c, _):
				c;
			case _:
				null;
		}
	}

	static function renderNamedType(pack:Array<String>, name:String, params:Array<Type>):String {
		final fullName = fullPath(pack, name);
		if (params == null || params.length == 0)
			return fullName;
		return fullName + "<" + [for (param in params) toString(param)].join(", ") + ">";
	}

	static function resolveAddType(left:Type, right:Type):Type {
		final leftName = toString(left);
		final rightName = toString(right);
		if (leftName == "String" || rightName == "String")
			return stringType();
		if (leftName == "Float" || rightName == "Float")
			return floatType();
		if (leftName == "Int" && rightName == "Int")
			return intType();
		throw "runtime macro typeof: unsupported add operands " + leftName + " + " + rightName;
	}

	static function resolveTypePath(path:TypePath):Type {
		final pathName = fullPath(path.pack, path.sub == null ? path.name : path.name + "." + path.sub);
		final params = [
			for (param in path.params)
				switch (param) {
					case TPType(t):
						resolveComplexType(t);
					case _:
						throw "runtime macro resolveType: non-type parameter is not implemented yet";
				}
		];
		return switch (pathName) {
			case "String":
				ensureNoParams(pathName, params);
				stringType();
			case "Int":
				ensureNoParams(pathName, params);
				intType();
			case "Float":
				ensureNoParams(pathName, params);
				floatType();
			case "Bool":
				ensureNoParams(pathName, params);
				boolType();
			case "Void":
				ensureNoParams(pathName, params);
				voidType();
			case "Dynamic":
				if (params.length == 0) TDynamic(null) else if (params.length == 1) TDynamic(params[0]) else
					throw "runtime macro resolveType: Dynamic expects at most one type parameter";
			case "Null":
				if (params.length != 1)
					throw "runtime macro resolveType: Null expects exactly one type parameter";
				nullType(params[0]);
			case _:
				throw "runtime macro resolveType: unsupported type path " + pathName;
		}
	}

	static function ensureNoParams(pathName:String, params:Array<Type>):Void {
		if (params.length != 0)
			throw "runtime macro resolveType: " + pathName + " does not accept type parameters";
	}

	static function normalizeName(name:String):String {
		final trimmed = StringTools.trim(name == null ? "" : name);
		if (trimmed.length == 0)
			return "";
		final parts = trimmed.split(".");
		return parts[parts.length - 1];
	}

	static function requireInnerType(wrapper:String, text:String):Type {
		final start = wrapper.length + 1;
		final innerText = text.substr(start, text.length - start - 1);
		final inner = parseTypeText(innerText);
		if (inner == null)
			throw "runtime macro type text: " + wrapper + " requires a non-empty inner type";
		return inner;
	}

	static function fullPath(pack:Array<String>, name:String):String {
		return (pack == null || pack.length == 0) ? name : (pack.join(".") + "." + name);
	}

	static function stringType():Type {
		return TInst(classRef([], "String", "String"), []);
	}

	static function intType():Type {
		return TInst(classRef([], "Int", "Int"), []);
	}

	static function floatType():Type {
		return TInst(classRef([], "Float", "Float"), []);
	}

	static function boolType():Type {
		return TInst(classRef([], "Bool", "Bool"), []);
	}

	static function voidType():Type {
		return TInst(classRef([], "Void", "Void"), []);
	}

	static function nullType(inner:Type):Type {
		return TInst(classRef([], "Null", "Null"), [inner]);
	}

	static function classRef(pack:Array<String>, name:String, module:String):Ref<ClassType> {
		final value:ClassType = {
			pack: pack.copy(),
			name: name,
			module: module,
			pos: defaultPos(),
			isPrivate: false,
			isExtern: true,
			params: [],
			meta: emptyMetaAccess(),
			doc: null,
			exclude: function():Void {},
			kind: KNormal,
			isInterface: false,
			isFinal: false,
			isAbstract: false,
			superClass: null,
			interfaces: [],
			fields: makeRef([], fullPath(pack, name) + ".fields"),
			statics: makeRef([], fullPath(pack, name) + ".statics"),
			constructor: null,
			init: null,
			overrides: []
		};
		return makeRef(value, fullPath(pack, name));
	}

	static function makeRef<T>(value:T, label:String):Ref<T> {
		return {
			get: function():T {
				return value;
			},
			toString: function():String {
				return label;
			}
		};
	}

	static function emptyMetaAccess():MetaAccess {
		var entries:Metadata = [];
		return {
			get: function():Metadata {
				return entries.copy();
			},
			extract: function(name:String):Array<MetadataEntry> {
				return [for (entry in entries) if (entry.name == name) entry];
			},
			add: function(name:String, params:Array<Expr>, pos:Position):Void {
				entries.push({
					name: name,
					params: params == null ? [] : params.copy(),
					pos: pos == null ? defaultPos() : pos
				});
			},
			remove: function(name:String):Void {
				entries = [for (entry in entries) if (entry.name != name) entry];
			},
			has: function(name:String):Bool {
				for (entry in entries)
					if (entry.name == name)
						return true;
				return false;
			}
		};
	}

	static function defaultPos():Position {
		return cast {
			file: DEFAULT_FILE,
			min: 0,
			max: 0
		};
	}
}
