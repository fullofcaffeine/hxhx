package hxhxmacrohost.api;

import haxe.macro.Expr;
import haxe.macro.Expr.Metadata;
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import hxhxmacrohost.OcamlInjection;

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

	/**
		Create a synthetic runtime type parameter declaration.

		Why
		- External-host runtime tests and bring-up helpers sometimes need to model typedef/abstract
		  parameter substitution without access to upstream compiler-internal `TypeParameter` values.
		- Reusing the same synthetic `KTypeParameter` shape keeps the runtime `TypeTools`
		  substitution/follow logic honest.

		What
		- Produces a `TypeParameter` whose `t` is a synthetic `TInst` carrying a `KTypeParameter`
		  class-kind with the supplied constraints.
	**/
	public static function typeParameter(name:String, ?constraints:Array<Type>, ?defaultType:Null<Type>):TypeParameter {
		final safeConstraints = constraints == null ? [] : constraints.copy();
		return {
			name: name == null ? "" : name,
			t: TInst(classRef([], name == null ? "" : name, name == null ? "" : name, null, KTypeParameter(safeConstraints)), []),
			defaultType: defaultType
		};
	}

	/**
		Create a synthetic typedef reference for runtime substitution/follow probes.
	**/
	public static function syntheticDefTypeRef(pack:Array<String>, name:String, module:String, params:Array<TypeParameter>, type:Type,
			?metadataEntries:Array<String>):Ref<DefType> {
		return defTypeRef(pack, name, module, params, type, metadataEntries);
	}

	/**
		Create a synthetic abstract reference for runtime substitution/follow probes.
	**/
	public static function syntheticAbstractRef(pack:Array<String>, name:String, module:String, params:Array<TypeParameter>, type:Type,
			?metadataEntries:Array<String>):Ref<AbstractType> {
		return abstractRef(pack, name, module, params, type, metadataEntries);
	}

	/**
		Create a synthetic abstract instance inside the runtime type model.

		Why
		- External-host macro probes and backend helpers need a real `TAbstract`
		  wrapper for parity-sensitive lookup and substitution behavior.
		- Generated OCaml cannot construct `TAbstract(...)` safely by itself because
		  the generated `haxe_macro_Type.ml` also defines
		  `haxe.macro.ModuleType.TAbstract`.

		How
		- Routes construction through the local typed `OcamlInjection.__ocaml__(...)`
		  shim plus placeholder-aware backend lowering.
		- The injected OCaml expression pins the result type to
		  `Haxe_macro_Type.hx_type`, which disambiguates the constructor even though
		  the generated module also contains `haxe.macro.ModuleType.TAbstract`.
	**/
	public static function abstractType(abstractRefValue:Ref<AbstractType>, ?params:Array<Type>):Type {
		final safeParams = params == null ? [] : params.copy();
		#if ocaml_output
		return cast(OcamlInjection.__ocaml__("((Haxe_macro_Type.TAbstract ((Obj.magic {0}), (Obj.magic {1}))) : Haxe_macro_Type.hx_type)", abstractRefValue,
			safeParams));
		#else
		return TAbstract(abstractRefValue, safeParams);
		#end
	}

	/**
		Wrap a runtime type in the synthetic `Null<T>` instance form.
	**/
	public static function nullWrapped(inner:Type):Type {
		return nullType(inner);
	}

	/**
		Follow the small runtime type model to a more concrete type.

		Why
		- Runtime `TypeTools.follow(...)` and `Context.follow(...)` are exercised by Reflaxe-style
		  backend code, but the external host only has a builtin subset of `Type`.

		What
		- Resolves `TMono` and `TLazy` wrappers inside that subset.
		- Leaves named builtin instances unchanged because the runtime model does not currently
		  synthesize typedef/abstract wrappers beyond those shells.
	**/
	public static function follow(t:Type, once:Bool = false):Type {
		if (t == null)
			return null;
		return switch (t) {
			case TMono(tm):
				final inner = tm.get();
				if (inner == null) t else if (once) inner else follow(inner, false);
			case TLazy(f):
				final inner = f();
				if (inner == null) t else if (once) inner else follow(inner, false);
			case TType(td, params):
				final inner = applyTypeParameters(td.get().type, td.get().params, params);
				if (once) inner else follow(inner, false);
			case _:
				t;
		}
	}

	public static function followWithAbstracts(t:Type, once:Bool = false):Type {
		// Upstream `followWithAbstracts(...)` follows abstracts to their underlying implementation.
		// The external-host runtime now preserves synthetic abstract wrappers for lookup and
		// substitution rungs, but following still intentionally unwraps them.
		return follow(t, once);
	}

	/**
		Check unification inside the builtin runtime type model.

		Why
		- Some backend helpers ask `Context.unify(...)` or `TypeTools.unify(...)` to compare builtin
		  types while running in the external host.

		What
		- Supports equality, `Dynamic` wildcard behavior, and `Null<T>` vs `T` within the builtin
		  runtime model.

		Gotchas
		- This is intentionally narrower than upstream typer unification.
		- Rich abstract/typedef/module-type semantics remain outside the current runtime rung.
	**/
	public static function unify(t1:Type, t2:Type):Bool {
		final left = follow(t1);
		final right = follow(t2);
		if (left == null || right == null)
			return false;
		if (toString(left) == toString(right))
			return true;
		if (isDynamicType(left) || isDynamicType(right))
			return true;
		if (isNullWrapper(left))
			return unify(extractNullInner(left), right);
		if (isNullWrapper(right))
			return unify(left, extractNullInner(right));
		return false;
	}

	/**
		Apply type-parameter substitutions inside the synthetic runtime type model.

		Why
		- Real backend code uses `TypeTools.applyTypeParameters(...)` when following typedef and
		  abstract payloads.
		- Returning identity here makes runtime macro code lie about `TType` / `TAbstract`
		  semantics.

		What
		- Recursively substitutes synthetic `KTypeParameter` instances by name through the supported
		  runtime `Type` subset.
		- Preserves wrapper kinds (`TType`, `TAbstract`, `TFun`, etc.) while mapping their children.

		Gotchas
		- This still operates on the synthetic runtime model, not full upstream typer state.
		- Parameter matching is by type-parameter name, which is sufficient for the current runtime
		  bring-up model because synthetic parameter refs are uniquely named within a single apply.
	**/
	public static function applyTypeParameters(t:Type, typeParameters:Array<TypeParameter>, concreteTypes:Array<Type>):Type {
		final params = typeParameters == null ? [] : typeParameters;
		final concretes = concreteTypes == null ? [] : concreteTypes;
		if (params.length != concretes.length)
			throw "typeParameters and concreteTypes must have the same length";
		if (params.length == 0 || t == null)
			return t;

		final substitutions = new Map<String, Type>();
		for (i in 0...params.length) {
			final param = params[i];
			if (param == null || param.name == null)
				continue;
			substitutions.set(param.name, concretes[i]);
		}
		return substituteTypeParameters(t, substitutions);
	}

	/**
		Call `f` on each direct subtype of `t` inside the synthetic runtime model.
	**/
	public static function iter(t:Type, f:Type->Void):Void {
		if (t == null || f == null)
			return;
		switch (t) {
			case TMono(tm):
				final inner = tm.get();
				if (inner != null)
					f(inner);
			case TEnum(_, tl) | TInst(_, tl) | TType(_, tl) | TAbstract(_, tl):
				for (tt in tl)
					f(tt);
			case TDynamic(t2):
				if (t2 != null)
					f(t2);
			case TLazy(ft):
				f(ft());
			case TAnonymous(an):
				for (field in an.get().fields)
					f(field.type);
			case TFun(args, ret):
				for (arg in args)
					f(arg.t);
				f(ret);
		}
	}

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

	/**
		Create a conservative synthetic module payload for `Context.getModule()`.

		Why
		- Some macro probes only need to know that a module resolved to something non-empty.
		- Returning a deterministic synthetic named type is sufficient for this existence-only rung.
	**/
	public static function moduleTypesForPath(modulePath:String, ?metadataEntries:Array<String>):Array<Type> {
		final trimmed = StringTools.trim(modulePath == null ? "" : modulePath);
		if (trimmed.length == 0)
			return [];
		return [typeForResolvedDecl(trimmed, "class", metadataEntries)];
	}

	public static function moduleTypesForModule(modulePath:String, entries:Array<{
		name:String,
		kind:String,
		metadata:Array<String>,
		staticFields:Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>,
		file:String,
		min:Int,
		max:Int
	}>, ?moduleFields:Array<{
		name:String,
		kind:String,
		metadata:Array<String>,
		initExpr:Null<String>,
		args:Array<{
			name:String,
			opt:Bool,
			typeText:String
		}>,
		returnTypeText:Null<String>,
		file:String,
		min:Int,
		max:Int
	}>):Array<Type> {
		final trimmed = StringTools.trim(modulePath == null ? "" : modulePath);
		if (trimmed.length == 0)
			return [];
		final parts = trimmed.split(".");
		if (parts.length == 0)
			return [];
		final moduleName = parts.pop();
		final out = new Array<Type>();
		final seen = new Map<String, Bool>();
		final resolvedFields = moduleFields == null ? [] : moduleFields;
		if (resolvedFields.length > 0)
			out.push(TInst(moduleFieldsCarrier(parts, moduleName, trimmed, resolvedFields), []));
		final resolvedEntries = (entries == null || entries.length == 0) ? [
			{
				name: moduleName,
				kind: "class",
				metadata: [],
				staticFields: [],
				file: DEFAULT_FILE,
				min: 0,
				max: 0
			}
		] : entries;
		for (entry in resolvedEntries) {
			final trimmedName = StringTools.trim(entry == null || entry.name == null ? "" : entry.name);
			if (trimmedName.length == 0 || seen.exists(trimmedName))
				continue;
			seen.set(trimmedName, true);
			out.push(typeFromResolvedDecl(parts, moduleName, trimmedName, entry.kind, entry.metadata, entry.file, entry.min, entry.max, entry.staticFields));
		}
		return out;
	}

	public static function typeForPath(typePath:String, ?metadataEntries:Array<String>):Type {
		return typeForResolvedDecl(typePath, "class", metadataEntries);
	}

	public static function typeForResolvedDecl(typePath:String, kind:String, ?metadataEntries:Array<String>, ?moduleNameOverride:String, ?file:String,
			?min:Int, ?max:Int, ?staticFields:Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>):Type {
		final trimmed = StringTools.trim(typePath == null ? "" : typePath);
		if (trimmed.length == 0)
			throw "runtime macro type path lookup: empty type path";
		final parts = trimmed.split(".");
		if (parts.length == 0)
			throw "runtime macro type path lookup: invalid type path";
		final name = parts.pop();
		final moduleName = moduleNameOverride == null || moduleNameOverride.length == 0 ? name : moduleNameOverride;
		return typeFromResolvedDecl(parts, moduleName, name, kind, metadataEntries, file, min, max, staticFields);
		}

	public static function localUsingRefsForPaths(paths:Array<String>):Array<Ref<ClassType>> {
		final out = new Array<Ref<ClassType>>();
		if (paths == null || paths.length == 0)
			return out;
		for (path in paths) {
			final trimmed = StringTools.trim(path == null ? "" : path);
			if (trimmed.length == 0)
				continue;
			final parts = trimmed.split(".");
			if (parts.length == 0)
				continue;
			final name = parts.pop();
			out.push(classRef(parts, name, name));
		}
		return out;
	}

	public static function localTVar(name:String, typeText:String, id:Int, capture:Bool, isStatic:Bool):TVar {
		return {
			id: id <= 0 ? 1 : id,
			name: name == null ? "" : name,
			t: getTypeByName(typeText == null ? "Dynamic" : typeText),
			capture: capture,
			extra: null,
			meta: null,
			isStatic: isStatic
		};
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
				switch (base.kind) {
					case KTypeParameter(_):
						TPath({
							pack: [],
							name: base.name,
							sub: null,
							params: []
						});
					case _:
						TPath({
							pack: base.pack.copy(),
							name: base.module,
							sub: base.name == base.module ? null : base.name,
							params: [for (param in params) TPType(toComplexType(param))]
						});
				}
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

	/**
		Return the synthetic implementation class carrier for a runtime abstract ref.

		Why
		- Real sibling consumers inspect `abs.impl.get().statics.get()` when an abstract exposes
		  compile-time helper constants/functions.
		- Matching on `haxe.macro.Type` directly inside generated macro-host code is still the easiest
		  place to trip backend constructor-name seams, so the runtime helper layer should own that
		  pattern match.
	**/
	public static function abstractImplClassRefOf(t:Type):Null<Ref<ClassType>> {
		return switch (t) {
			case TAbstract(a, _):
				final abs = a.get();
				abs == null ? null : abs.impl;
			case _:
				null;
		}
	}

	/**
		Return the synthetic `KModuleFields(...)` carrier for `t`, if it exists.

		Why
		- External-host probes and sibling Reflaxe macros need to inspect synthetic module-field
		  carriers, but matching on `haxe.macro.Type` directly inside generated macro-host modules
		  still trips the current generated-OCaml `TAbstract(...)` seam.
		- Keeping the pattern match in this shared runtime helper avoids duplicating that unstable
		  match shape in user-side macro probes.
	**/
	public static function moduleFieldsCarrierOf(t:Type):Null<Ref<ClassType>> {
		final cls = classRefOf(t);
		if (cls == null)
			return null;
		return switch (cls.get().kind) {
			case KModuleFields(_):
				cls;
			case _:
				null;
		}
	}

	/**
		Return the declaration/source position carried by a synthetic runtime type reference.

		Why
		- External-host probes and sibling analyzers need to assert/use `type.pos`, but direct
		  pattern matching on `haxe.macro.Type` inside generated macro-host code is still the most
		  fragile place to hit backend constructor-name seams.
		- Keeping the switch here centralizes that risk in the runtime helper layer.
	**/
	public static function typePos(t:Type):Position {
		return switch (t) {
			case TInst(c, _):
				c.get().pos;
			case TEnum(e, _):
				e.get().pos;
			case TType(td, _):
				td.get().pos;
			case TAbstract(a, _):
				a.get().pos;
			case _:
				defaultPos();
		}
	}

	public static function metaHas(t:Type, metadataName:String):Bool {
		if (metadataName == null || metadataName.length == 0)
			return false;
		return switch (t) {
			case TInst(c, _):
				c.get().meta.has(metadataName);
			case TEnum(e, _):
				e.get().meta.has(metadataName);
			case TType(td, _):
				td.get().meta.has(metadataName);
			case TAbstract(a, _):
				a.get().meta.has(metadataName);
			case _:
				false;
		}
	}

	static function renderNamedType(pack:Array<String>, name:String, params:Array<Type>):String {
		final fullName = fullPath(pack, name);
		if (params == null || params.length == 0)
			return fullName;
		return fullName + "<" + [for (param in params) toString(param)].join(", ") + ">";
	}

	static function isDynamicType(t:Type):Bool {
		return switch (t) {
			case TDynamic(_):
				true;
			case _:
				false;
		}
	}

	static function isNullWrapper(t:Type):Bool {
		return switch (t) {
			case TInst(c, params): c.get().name == "Null" && params.length == 1;
			case _:
				false;
		}
	}

	static function extractNullInner(t:Type):Type {
		return switch (t) {
			case TInst(_, params):
				params[0];
			case _:
				t;
		}
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

	static function typeFromResolvedDecl(pack:Array<String>, module:String, name:String, kind:String, ?metadataEntries:Array<String>, ?file:String, ?min:Int,
			?max:Int, ?staticFields:Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>):Type {
		final pos = position(file, min, max);
		return switch (kind == null ? "" : StringTools.trim(kind).toLowerCase()) {
			case "enum":
				TEnum(enumRef(pack, name, module, metadataEntries, pos), []);
			case "typedef":
				TType(defTypeRef(pack, name, module, [], TDynamic(null), metadataEntries, pos), []);
			case "abstract":
				abstractType(abstractRef(pack, name, module, [], TDynamic(null), metadataEntries, pos, staticFields), []);
			case _:
				classType(pack, module, name, metadataEntries, file, min, max, staticFields);
		}
		}

	static function substituteTypeParameters(t:Type, substitutions:Map<String, Type>):Type {
		return switch (t) {
			case TInst(c, params):
				final cls = c.get();
				switch (cls.kind) {
					case KTypeParameter(_):
						final replacement = substitutions.get(cls.name);
						replacement == null ? t : replacement;
					case _:
						final mappedParams = [for (param in params) substituteTypeParameters(param, substitutions)];
						final rebuilt:Type = TInst(c, mappedParams);
						rebuilt;
				}
			case TEnum(e, params):
				final mappedParams = [for (param in params) substituteTypeParameters(param, substitutions)];
				final rebuilt:Type = TEnum(e, mappedParams);
				rebuilt;
			case TType(td, params):
				final mappedParams = [for (param in params) substituteTypeParameters(param, substitutions)];
				final rebuilt:Type = TType(td, mappedParams);
				rebuilt;
			case TAbstract(a, params):
				final mappedParams = [for (param in params) substituteTypeParameters(param, substitutions)];
				abstractType(a, mappedParams);
			case TFun(args, ret):
				TFun([
					for (arg in args)
						{
							name: arg.name,
							opt: arg.opt,
							t: substituteTypeParameters(arg.t, substitutions)
						}
				], substituteTypeParameters(ret, substitutions));
			case TAnonymous(an):
				final source = an.get();
				TAnonymous(makeRef({
					fields: [
						for (field in source.fields)
							{
								name: field.name,
								type: substituteTypeParameters(field.type, substitutions),
								isPublic: field.isPublic,
								isExtern: field.isExtern,
								isFinal: field.isFinal,
								isAbstract: field.isAbstract,
								params: field.params,
								meta: field.meta,
								kind: field.kind,
								expr: field.expr,
								pos: field.pos,
								doc: field.doc,
								overloads: field.overloads
							}
					],
					status: source.status
				}, "anon"));
			case TDynamic(inner):
				TDynamic(inner == null ? null : substituteTypeParameters(inner, substitutions));
			case TMono(tm):
				final inner = tm.get();
				inner == null ? t : substituteTypeParameters(inner, substitutions);
			case TLazy(f):
				substituteTypeParameters(f(), substitutions);
		}
	}

	static function classType(pack:Array<String>, module:String, name:String, ?metadataEntries:Array<String>, ?file:String, ?min:Int, ?max:Int,
			?staticFieldEntries:Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>):Type {
		final staticFields = staticFieldEntries == null ? [] : [
			for (entry in staticFieldEntries)
				classField(entry.name, entry.kind, entry.metadata, entry.initExpr, entry.args, entry.returnTypeText, entry.file, entry.min, entry.max)
		];
		final value:Type = TInst(classRef(pack, name, module, metadataEntries, null, staticFields, position(file, min, max)), []);
		return value;
		}

	static function moduleFieldsCarrier(pack:Array<String>, module:String, modulePath:String, entries:Array<{
		name:String,
		kind:String,
		metadata:Array<String>,
		initExpr:Null<String>,
		args:Array<{
			name:String,
			opt:Bool,
			typeText:String
		}>,
		returnTypeText:Null<String>,
		file:String,
		min:Int,
		max:Int
	}>):Ref<ClassType> {
		final statics = [
			for (entry in entries)
				classField(entry.name, entry.kind, entry.metadata, entry.initExpr, entry.args, entry.returnTypeText, entry.file, entry.min, entry.max)
		];
		return classRef(pack, module, module, null, KModuleFields(modulePath), statics);
	}

	static function classRef(pack:Array<String>, name:String, module:String, ?metadataEntries:Array<String>, ?kind:ClassKind, ?staticFields:Array<ClassField>,
			?pos:Position):Ref<ClassType> {
		final value:ClassType = {
			pack: pack.copy(),
			name: name,
			module: module,
			pos: pos == null ? defaultPos() : pos,
			isPrivate: false,
			isExtern: true,
			params: [],
			meta: metadataAccess(metadataEntries),
			doc: null,
			exclude: function():Void {},
			kind: kind == null ? KNormal : kind,
			isInterface: false,
			isFinal: false,
			isAbstract: false,
			superClass: null,
			interfaces: [],
			fields: makeRef([], fullPath(pack, name) + ".fields"),
			statics: makeRef(staticFields == null ? [] : staticFields.copy(), fullPath(pack, name) + ".statics"),
			constructor: null,
			init: null,
			overrides: []
		};
		return makeRef(value, fullPath(pack, name));
	}

	static function classField(name:String, kind:String, ?metadataEntries:Array<String>, ?initExpr:Null<String>,
			?args:Array<{name:String, opt:Bool, typeText:String}>, ?returnTypeText:Null<String>, ?file:String, ?min:Int, ?max:Int):ClassField {
		final lowered = kind == null ? "" : StringTools.trim(kind).toLowerCase();
		final pos = position(file, min, max);
		final typedExpr = buildFieldExpr(initExpr, pos);
		final functionType = buildMethodType(args, returnTypeText);
		final fieldType = switch (lowered) {
			case "method":
				functionType;
			case _ if (typedExpr != null):
				typedExpr.t;
			case _:
				TDynamic(null);
		};
		final fieldKind = switch (lowered) {
			case "method":
				FMethod(MethNormal);
			case "final":
				FVar(AccNormal, AccNever);
			case _:
				FVar(AccNormal, AccNormal);
		};
		return {
			name: name,
			type: fieldType,
			isPublic: true,
			isExtern: true,
			isFinal: lowered == "final",
			isAbstract: false,
			params: [],
			meta: metadataAccess(metadataEntries),
			kind: fieldKind,
			expr: function():Null<TypedExpr> {
				return typedExpr;
			},
			pos: pos,
			doc: null,
			overloads: makeRef([], name + ".overloads")
		};
	}

	static function buildMethodType(args:Array<{name:String, opt:Bool, typeText:String}>, returnTypeText:Null<String>):Type {
		final safeArgs = args == null ? [] : args;
		return TFun([
			for (arg in safeArgs)
				{
					name: arg == null || arg.name == null ? "" : arg.name,
					opt: arg != null && arg.opt,
					t: typeFromText(arg == null ? null : arg.typeText)
				}
		], typeFromText(returnTypeText));
	}

	static function typeFromText(text:Null<String>):Type {
		final trimmed = StringTools.trim(text == null ? "" : text);
		if (trimmed.length == 0)
			return TDynamic(null);
		return try {
			parseTypeText(trimmed);
		} catch (_:Dynamic) {
			typeForPath(trimmed);
		}
	}

	static function buildFieldExpr(exprText:Null<String>, pos:Position):Null<TypedExpr> {
		final trimmed = StringTools.trim(exprText == null ? "" : exprText);
		if (trimmed.length == 0)
			return null;
		return try {
			buildFieldTypedExpr(RuntimeMacroExprs.parseInlineString(trimmed, pos == null ? defaultPos() : pos));
		} catch (_:String) {
			null;
		}
	}

	static function buildFieldTypedExpr(expr:Expr):TypedExpr {
		if (expr == null)
			throw "runtime macro module field expr: null expr";
		return switch (expr.expr) {
			case EConst(CInt(raw, suffix)):
				if (suffix != null) {}
				makeTypedExpr(expr.pos, TConst(TInt(Std.parseInt(raw))), intType());
			case EConst(CFloat(raw)):
				makeTypedExpr(expr.pos, TConst(TFloat(raw)), floatType());
			case EConst(CString(text, kind)):
				if (kind != null) {}
				makeTypedExpr(expr.pos, TConst(TString(text)), stringType());
			case EConst(CIdent("true")):
				makeTypedExpr(expr.pos, TConst(TBool(true)), boolType());
			case EConst(CIdent("false")):
				makeTypedExpr(expr.pos, TConst(TBool(false)), boolType());
			case EConst(CIdent("null")):
				makeTypedExpr(expr.pos, TConst(TNull), TDynamic(null));
			case EParenthesis(inner):
				final typedInner = buildFieldTypedExpr(inner);
				makeTypedExpr(expr.pos, TParenthesis(typedInner), typedInner.t);
			case ECast(inner, _):
				final typedInner = buildFieldTypedExpr(inner);
				makeTypedExpr(expr.pos, TCast(typedInner, null), typedInner.t);
			case EMeta(meta, inner):
				final typedInner = buildFieldTypedExpr(inner);
				makeTypedExpr(expr.pos, TMeta(meta, typedInner), typedInner.t);
			case _:
				throw "runtime macro module field expr: unsupported expr shape";
		}
	}

	static function makeTypedExpr(pos:Position, expr:TypedExprDef, t:Type):TypedExpr {
		return {
			expr: expr,
			pos: pos == null ? defaultPos() : pos,
			t: t
		};
	}

	static function enumRef(pack:Array<String>, name:String, module:String, ?metadataEntries:Array<String>, ?pos:Position):Ref<EnumType> {
		final value:EnumType = {
			pack: pack.copy(),
			name: name,
			module: module,
			pos: pos == null ? defaultPos() : pos,
			isPrivate: false,
			isExtern: true,
			params: [],
			meta: metadataAccess(metadataEntries),
			doc: null,
			exclude: function():Void {},
			constructs: new Map(),
			names: []
		};
		return makeRef(value, fullPath(pack, name));
	}

	static function defTypeRef(pack:Array<String>, name:String, module:String, ?params:Array<TypeParameter>, ?type:Type, ?metadataEntries:Array<String>,
			?pos:Position):Ref<DefType> {
		final value:DefType = {
			pack: pack.copy(),
			name: name,
			module: module,
			pos: pos == null ? defaultPos() : pos,
			isPrivate: false,
			isExtern: true,
			params: params == null ? [] : params.copy(),
			meta: metadataAccess(metadataEntries),
			doc: null,
			exclude: function():Void {},
			type: type == null ? TDynamic(null) : type
		};
		return makeRef(value, fullPath(pack, name));
	}

	static function abstractRef(pack:Array<String>, name:String, module:String, ?params:Array<TypeParameter>, ?type:Type, ?metadataEntries:Array<String>,
			?pos:Position, ?staticFieldEntries:Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>):Ref<AbstractType> {
		final implStatics = staticFieldEntries == null ? [] : [
			for (entry in staticFieldEntries)
				classField(entry.name, entry.kind, entry.metadata, entry.initExpr, entry.args, entry.returnTypeText, entry.file, entry.min, entry.max)
		];
		final implRef = implStatics.length == 0 ? null : classRef(pack, name + "_Impl_", module, null, null, implStatics, pos);
		final value:AbstractType = {
			pack: pack.copy(),
			name: name,
			module: module,
			pos: pos == null ? defaultPos() : pos,
			isPrivate: false,
			isExtern: true,
			params: params == null ? [] : params.copy(),
			meta: metadataAccess(metadataEntries),
			doc: null,
			exclude: function():Void {},
			type: type == null ? TDynamic(null) : type,
			impl: implRef,
			binops: [],
			unops: [],
			from: [],
			to: [],
			array: [],
			resolve: null,
			resolveWrite: null
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

	static function metadataAccess(metadataEntries:Array<String>):MetaAccess {
		final access = emptyMetaAccess();
		if (metadataEntries == null || metadataEntries.length == 0)
			return access;
		for (raw in metadataEntries) {
			final entry = parseMetadataEntry(raw);
			if (entry != null)
				access.add(entry.name, entry.params, entry.pos);
		}
		return access;
	}

	public static function parseMetadataEntries(metadataEntries:Array<String>):Metadata {
		return metadataAccess(metadataEntries).get();
	}

	static function parseMetadataEntry(raw:String):Null<MetadataEntry> {
		final text = StringTools.trim(raw == null ? "" : raw);
		if (!StringTools.startsWith(text, "@:"))
			return null;
		final open = text.indexOf("(");
		final close = text.lastIndexOf(")");
		final name = if (open == -1) text.substr(1) else text.substr(1, open - 1);
		if (name.length == 0)
			return null;
		final params = new Array<Expr>();
		if (open != -1 && close > open) {
			for (argText in splitMetadataArgs(text.substr(open + 1, close - open - 1))) {
				final trimmed = StringTools.trim(argText);
				if (trimmed.length == 0)
					continue;
				params.push(RuntimeMacroExprs.parseInlineString(trimmed, defaultPos()));
			}
		}
		return {
			name: name,
			params: params,
			pos: defaultPos()
		};
	}

	static function splitMetadataArgs(raw:String):Array<String> {
		final out = new Array<String>();
		if (raw == null || raw.length == 0)
			return out;
		var depth = 0;
		var start = 0;
		var i = 0;
		while (i < raw.length) {
			final ch = raw.charAt(i);
			switch (ch) {
				case "(" | "[" | "{":
					depth += 1;
				case ")" | "]" | "}":
					if (depth > 0)
						depth -= 1;
				case ",":
					if (depth == 0) {
						out.push(raw.substr(start, i - start));
						start = i + 1;
					}
				case _:
			}
			i += 1;
		}
		out.push(raw.substr(start));
		return out;
	}

	static function defaultPos():Position {
		return cast {
			file: DEFAULT_FILE,
			min: 0,
			max: 0
		};
	}

	public static function position(file:Null<String>, min:Null<Int>, max:Null<Int>):Position {
		final resolvedFile = file == null || StringTools.trim(file).length == 0 ? DEFAULT_FILE : StringTools.trim(file);
		final resolvedMin = min == null || min < 0 ? 0 : min;
		final resolvedMax = max == null || max < resolvedMin ? resolvedMin : max;
		return cast {
			file: resolvedFile,
			min: resolvedMin,
			max: resolvedMax
		};
	}
}
