import haxe.macro.Context;
import haxe.macro.Type;

/**
	Upstream side of the frontend typed oracle. Runs as a compiler macro inside upstream Haxe 4.3.7.

	After typing, it records the typed signature of every method in the compiled modules: each
	parameter's name, whether it is optional, and its type, and the return type, with inferred
	types filled in. Types print in one canonical form that the hxhx side reproduces
	(`TypedOracleHxhx.canonical`):
	- Types are named by module: `haxe.Constraints.IMap`, not `haxe.IMap`; `haxe.ds.List.ListNode`,
	  not the private `haxe.ds._List.ListNode`.
	- Typedefs are expanded, because hxhx does not always keep the alias name.
	- Function types print as `(A,B)->R`, anonymous structures print their fields sorted by name,
	  and an unresolved monomorph prints as `?`.
	- An abstract's instance method drops the implicit `this` parameter that upstream adds to its
	  implementation function.
**/
class TypedOracleUpstream {
	static var written = false;

	public static function install(out:String):Void {
		Context.onAfterTyping(types -> {
			if (written)
				return;
			written = true;
			final records:Array<{key:String, file:String, signature:String}> = [];
			for (type in types)
				switch type {
					case TClassDecl(ref):
						final c = ref.get();
						final owner = c.module + "." + (StringTools.endsWith(c.name, "_Impl_") ? c.name.substr(0, c.name.length - 6) : c.name);
						final file = Context.getPosInfos(c.pos).file;
						final fields = c.fields.get().concat(c.statics.get());
						if (c.constructor != null)
							fields.push(c.constructor.get());
						for (field in fields)
							switch [field.kind, Context.follow(field.type)] {
								case [FMethod(_), TFun(args, ret)]:
									final declared = StringTools.endsWith(c.name, "_Impl_")
										&& args.length > 0
										&& args[0].name == "this" ? args.slice(1) : args;
									// An abstract's constructor is the implementation function `_new`.
									final isAbstractConstructor = StringTools.endsWith(c.name, "_Impl_") && field.name == "_new";
									final name = isAbstractConstructor ? "new" : field.name;
									// Its implementation returns the abstract value; as a declaration it is a constructor (Void).
									records.push({
										key: owner + "." + name,
										file: file,
										signature: isAbstractConstructor ? signature(declared, Context.getType("Void")) : signature(declared, ret)
									});
								case _:
							}
					case _:
				}
			final defines = Context.getDefines();
			sys.io.File.saveContent(out, haxe.Json.stringify({
				defines: [for (key in defines.keys()) {name: key, value: defines.get(key)}],
				records: records
			}));
		});
	}

	static function signature(args:Array<{name:String, opt:Bool, t:Type}>, ret:Type):String
		return "(" + [for (arg in args) (arg.opt ? "?" : "") + arg.name + ":" + canonical(arg.t)].join(",") + ")->" + canonical(ret);

	/** Name a type by its module: the module path, plus the type name when it differs from the module's last part. */
	static function path(module:String, name:String):String {
		// Core types (Int, Bool, Null, Iterator, ...) live in the StdTypes module and keep their bare names.
		if (module == "StdTypes")
			return name;
		final last = module.substr(module.lastIndexOf(".") + 1);
		return last == name ? module : module + "." + name;
	}

	static function params(types:Array<Type>, depth:Int):String
		return types.length == 0 ? "" : "<" + [for (t in types) canonical(t, depth + 1)].join(",") + ">";

	/**
		`depth` counts structural nesting only, as on the hxhx side: a typedef hop adds nothing, so
		both printers cut a type at the same place even though hxhx expands most typedefs before it
		prints. It still stops a self-referencing typedef, because every cycle passes a structure.
	**/
	public static function canonical(t:Null<Type>, depth:Int = 0):String {
		if (depth > 12)
			return "...";
		if (t == null)
			return "?";
		return switch t {
			case TMono(ref): ref.get() == null ? "?" : canonical(ref.get(), depth);
			case TLazy(f): canonical(f(), depth);
			case TInst(ref, ps):
				final c = ref.get();
				switch c.kind {
					case KTypeParameter(_): c.name;
					case _: path(c.module, c.name) + params(ps, depth);
				}
			case TEnum(ref, ps): path(ref.get().module, ref.get().name) + params(ps, depth);
			case TType(_, _): canonical(Context.follow(t, true), depth);
			case TAbstract(ref, ps): path(ref.get().module, ref.get().name) + params(ps, depth);
			case TFun(args, ret): "(" + [for (arg in args) canonical(arg.t, depth + 1)].join(",") + ")->" + canonical(ret, depth + 1);
			case TAnonymous(ref):
				final fields = [for (f in ref.get().fields) f.name + ":" + canonical(f.type, depth + 1)];
				fields.sort(Reflect.compare);
				"{" + fields.join(",") + "}";
			case TDynamic(null): "Dynamic";
			case TDynamic(inner): "Dynamic<" + canonical(inner, depth + 1) + ">";
		}
	}
}
