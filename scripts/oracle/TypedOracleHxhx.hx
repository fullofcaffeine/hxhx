/** One method signature after typing, or the reason a module could not be typed. */
typedef TypedOracleRecord = {key:String, ?signature:String, ?error:String};

/**
	hxhx side of the frontend typed oracle. Runs under `haxe --run` with the hxhx-core sources.

	It parses every module that the upstream dump names, with the defines that upstream reported,
	builds one typer index for all of them, and types each module through one shared module loader
	with the interp standard-library class paths. For each typed method it records the parameter
	names, optional flags, and types, and the return type, with inferred types filled in, in the
	canonical form that `upstream/TypedOracleUpstream.hx` prints.

	Usage: `TypedOracleHxhx <upstream.json> <out.json> <std-root>`
**/
class TypedOracleHxhx {
	static function main():Void {
		final args = Sys.args();
		if (args.length != 3)
			throw "usage: TypedOracleHxhx <upstream.json> <out.json> <std-root>";
		final upstream:{defines:Array<{name:String, value:String}>, records:Array<{key:String, file:String, signature:String}>} = haxe.Json.parse(sys.io.File.getContent(args[0]));
		final stdRoot = haxe.io.Path.removeTrailingSlashes(args[2]);
		final defines = new haxe.ds.StringMap<String>();
		for (entry in upstream.defines)
			defines.set(entry.name, entry.value);
		final classPaths = [stdRoot + "/eval/_std", stdRoot];
		final files = new Array<String>();
		final seen = new Map<String, Bool>();
		for (record in upstream.records)
			if (!seen.exists(record.file)) {
				seen.set(record.file, true);
				files.push(record.file);
			}

		final records:Array<TypedOracleRecord> = [];
		final moduleErrors:Array<{module:String, stage:String, error:String}> = [];
		final modules:Array<ResolvedModule> = [];
		for (file in files) {
			final modulePath = modulePathFor(file, classPaths);
			if (modulePath == null)
				continue;
			try {
				final filtered = HxConditionalCompilation.filterSource(sys.io.File.getContent(file), defines);
				modules.push(new ResolvedModule(modulePath, file, ParserStage.parse(filtered, file)));
			} catch (e:haxe.Exception) {
				moduleErrors.push({module: modulePath, stage: "parse", error: e.message});
			}
		}

		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(classPaths, defines, index);
		loader.markResolvedAlready(modules);
		for (module in modules) {
			final modulePath = ResolvedModule.getModulePath(module);
			final typed = try {
				TyperStage.typeResolvedModule(module, index, loader, true);
			} catch (e:haxe.Exception) {
				moduleErrors.push({module: modulePath, stage: "type", error: e.message});
				continue;
			}
			for (cls in typed.getTypedClasses()) {
				final owner = modulePath + "." + HxClassDecl.getName(cls.getSourceDeclaration());
				for (fn in cls.getFunctions()) {
					final key = owner + "." + HxFunctionDecl.getName(fn.getSourceDeclaration());
					try {
						records.push({key: key, signature: signature(fn)});
					} catch (e:haxe.Exception) {
						records.push({key: key, error: e.message});
					}
				}
				final inherited = inheritedConstructor(index, cls);
				if (inherited != null)
					records.push({key: owner + ".new", signature: inherited});
			}
		}
		sys.io.File.saveContent(args[1], haxe.Json.stringify({records: records, moduleErrors: moduleErrors}));
	}

	/** `haxe/ds/IntMap.hx` under a class path becomes `haxe.ds.IntMap`. */
	static function modulePathFor(file:String, classPaths:Array<String>):Null<String> {
		for (root in classPaths) {
			final prefix = root + "/";
			if (StringTools.startsWith(file, prefix))
				return haxe.io.Path.withoutExtension(file.substr(prefix.length)).split("/").join(".");
		}
		return null;
	}

	/**
		The derived record for a class that declares no `new` but inherits one, which upstream
		records as a typed field (`TypedConstructorPath.inheritedSignature`). Each argument prints
		like the ancestor's own `new`, with this class's view of its types.
	**/
	public static function inheritedConstructor(index:TyperIndex, cls:TypedClass):Null<String> {
		final inherited = TypedConstructorPath.inheritedSignature(index, cls.getSemanticInfo());
		if (inherited == null)
			return null;
		final sig = inherited.signature;
		final names = sig.getArgNames();
		final optional = sig.getArgOptional();
		final types = sig.getArgs();
		final source = HxFunctionDecl.getArgs(inherited.declaration.getSourceDeclaration());
		final parts = [
			for (index in 0...names.length)
				(optional[index] ? "?" : "")
				+ names[index]
				+ ":"
				+ canonical(index < source.length ? argumentReadType(source[index], types[index]) : types[index])];
		return "(" + parts.join(",") + ")->" + canonical(sig.getReturnType());
	}

	public static function signature(fn:TypedFunction):String {
		final declaration = fn.getDeclaration();
		if (declaration == null)
			throw "typed function has no declaration";
		final sig = declaration.getSignature();
		final env = fn.getEnvironment();
		final names = sig.getArgNames();
		final optional = sig.getArgOptional();
		final declared = sig.getArgs();
		final inferred = env == null ? null : env.getParams();
		final source = HxFunctionDecl.getArgs(fn.getSourceDeclaration());
		final parts = [
			for (index in 0...names.length) {
				final type = inferred != null && index < inferred.length ? inferred[index].getType() : declared[index]; (optional[index] ? "?" : "")
					+ names[index]
					+ ":"
					+ canonical(index < source.length ? argumentReadType(source[index], type) : type);
			}
		];
		final ret = env == null ? sig.getReturnType() : env.getReturnType();
		return "(" + parts.join(",") + ")->" + canonical(ret);
	}

	/**
		Haxe 4.3.7 types an argument written `?x:T`, or `x:T = null`, as `Null<T>` (typeload.ml
		`type_function_arg`); any other default keeps `T`. hxhx stores `T` and records the absence
		on the argument, so this prints the argument's read type, as `TyStructuralFieldRead.readType`
		does for an optional structure field. Like `readType`, it deliberately leaves Dynamic and
		unknown types unwrapped, where upstream prints `Null<Dynamic>` and `Null<?>`: a mismatch
		there is this printer convention, not a typer fault. The typer should store `Null<T>` itself
		(haxe_ocaml-1y7dw); until then, do not add more translations here.
	**/
	static function argumentReadType(argument:HxFunctionArg, type:TyType):TyType {
		final nullDefault = switch HxFunctionArg.getDefaultValue(argument) {
			case Default(ENull): true;
			case _: false;
		};
		if (!HxFunctionArg.getIsOptional(argument) && !nullDefault)
			return type;
		return type.isNullable() || type.isUnknown() || type.isDynamic() ? type : TyType.nullable(type);
	}

	static function params(types:Array<TyType>, depth:Int):String
		return types.length == 0 ? "" : "<" + [for (t in types) canonical(t, depth + 1)].join(",") + ">";

	/**
		Typedefs are expanded, as upstream's side does. `depth` counts structural nesting only: the
		typer has already expanded most typedefs, so counting the remaining hops would cut a type at
		a different place than upstream. It still stops a self-referencing typedef.
	**/
	public static function canonical(t:Null<TyType>, depth:Int = 0):String {
		if (depth > 12)
			return "...";
		if (t == null || t.isUnknown())
			return "?";
		final alias = t.getAliasDefinition();
		if (alias != null)
			return canonical(alias.instantiate(t.getTypeArguments()), depth);
		if (t.isDynamic())
			return "Dynamic";
		if (t.isNullWrapped() || t.isNullable()) {
			final inner = t.getNullableInner();
			if (inner != null)
				return "Null<" + canonical(inner, depth + 1) + ">";
		}
		if (t.isFunction())
			return "(" + [for (arg in t.getFunctionArguments()) canonical(arg, depth + 1)].join(",") + ")->" + canonical(t.getFunctionReturn(), depth + 1);
		if (t.isAnonymous()) {
			// Haxe 4.3.7 stores `Null<T>` as an optional structure field's type (typeload.ml
			// `tnull`). hxhx stores `T` and records the absence on the field, so this prints the
			// field's read type (`readType`), not its stored type. Generic binding still reads the
			// stored type: haxe_ocaml-3ynni.
			final fields = [
				for (field in t.getAnonymousFields())
					field.name + ":" + canonical(TyStructuralFieldRead.readType(field), depth + 1)
			];
			fields.sort(Reflect.compare);
			return "{" + fields.join(",") + "}";
		}
		if (t.isTypeParameter()) {
			final name = t.getTypeParameterName();
			return name == null ? "?" : name;
		}
		if (t.isPrimitive())
			return t.getDisplay();
		final nominal = t.getNominalIdentity();
		if (nominal != null) {
			// Upstream names every StdTypes type bare (TypedOracleUpstream `path`); a parameterized
			// Dynamic is the only one hxhx reaches through its module path, so print it bare too.
			final name = nominal.getCanonicalName() == "StdTypes.Dynamic" ? "Dynamic" : nominal.getCanonicalName();
			return name + params(t.getTypeArguments(), depth);
		}
		if (t.isUnresolved())
			return "?unresolved:" + t.getUnresolvedPath();
		return "?" + t.getDisplay();
	}
}
