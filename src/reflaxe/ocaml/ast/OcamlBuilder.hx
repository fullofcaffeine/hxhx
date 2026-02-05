package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)

import haxe.macro.Expr.Binop;
import haxe.macro.Expr;
import haxe.macro.Expr.Unop;
import haxe.macro.Expr.Position;
#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TConstant;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
import reflaxe.ocaml.ast.OcamlApplyArg;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlDebugPos;

/**
 * Milestone 2: minimal TypedExpr -> OcamlExpr lowering for expressions and function bodies.
 *
 * Notes:
 * - This pass is intentionally conservative: unsupported constructs emit `()` with a comment where possible.
 * - Local vars declared with `TVar` are treated as `ref` (mutable-by-default) for now; M3 will infer mutability.
 */
class OcamlBuilder {
	public final ctx:CompilationContext;
	public final typeExprFromHaxeType:Type->OcamlTypeExpr;
	public final emitSourceMap:Bool;

	#if macro
	static var sourceContentByFile:Map<String, String> = [];
	static var lineStartsByFile:Map<String, Array<Int>> = [];
	static var normalizedFileByFile:Map<String, String> = [];

	static function normalizeHaxeFilePath(file:String):String {
		if (file == null) return "";
		var s = StringTools.replace(file, "\\", "/");
		final cwd = StringTools.replace(Sys.getCwd(), "\\", "/");
		if (StringTools.startsWith(s, cwd)) {
			s = s.substr(cwd.length);
			if (StringTools.startsWith(s, "/")) s = s.substr(1);
		}
		return s;
	}

	static function ensureLineStarts(file:String):Array<Int> {
		final cached = lineStartsByFile.get(file);
		if (cached != null) return cached;

		final content = try {
			final c = sourceContentByFile.get(file);
			if (c != null) c else {
				final loaded = sys.io.File.getContent(file);
				sourceContentByFile.set(file, loaded);
				loaded;
			}
		} catch (_:Dynamic) {
			"";
		}

		final starts:Array<Int> = [0];
		for (i in 0...content.length) {
			if (content.charCodeAt(i) == "\n".code) starts.push(i + 1);
		}
		lineStartsByFile.set(file, starts);
		return starts;
	}

	static function debugPosFromHaxePos(pos:Position):Null<OcamlDebugPos> {
		final info = Context.getPosInfos(pos);
		if (info == null || info.file == null || info.file.length == 0) return null;

		final file = info.file;
		final starts = ensureLineStarts(file);
		final min = info.min;
		if (min == null || min < 0) return null;

		// Binary search: last lineStart <= min
		var lo = 0;
		var hi = starts.length - 1;
		while (lo < hi) {
			final mid = Std.int((lo + hi + 1) / 2);
			if (starts[mid] <= min) lo = mid else hi = mid - 1;
		}
		final lineIdx = lo; // 0-based
		final line = lineIdx + 1;
		final col = (min - starts[lineIdx]) + 1;

		var norm = normalizedFileByFile.get(file);
		if (norm == null) {
			norm = normalizeHaxeFilePath(file);
			normalizedFileByFile.set(file, norm);
		}

		return { file: norm, line: line, col: col };
	}

	static inline function shouldWrapPos(e:TypedExpr):Bool {
		return switch (e.expr) {
			case TConst(_), TLocal(_), TTypeExpr(_):
				false;
			case _:
				true;
		}
	}
	#end

	// Track locals introduced by TVar that we currently represent as `ref`.
	final refLocals:Map<Int, Bool> = [];

	var tmpId:Int = 0;

	// Tracks nesting of loops while building expressions (used for break/continue).
	var loopDepth:Int = 0;

	// Set while compiling a function body to decide whether TVar locals become `ref` or immutable `let`.
	var currentMutatedLocalIds:Null<Map<Int, Bool>> = null;

	// Used for pruning unused `let` bindings inside blocks (keeps dune warn-error happy).
	var currentUsedLocalIds:Null<Map<Int, Bool>> = null;

	// Set while compiling a switch arm to resolve TEnumParameter -> bound pattern variables.
	var currentEnumParamNames:Null<Map<String, String>> = null;

	public function new(ctx:CompilationContext, typeExprFromHaxeType:Type->OcamlTypeExpr, emitSourceMap:Bool = false) {
		this.ctx = ctx;
		this.typeExprFromHaxeType = typeExprFromHaxeType;
		this.emitSourceMap = emitSourceMap;
	}

	inline function freshTmp(prefix:String):String {
		tmpId += 1;
		return "__" + prefix + "_" + tmpId;
	}

	#if macro
	inline function guardrailError(msg:String, pos:Position):Void {
		if (!ctx.currentIsHaxeStd) {
			haxe.macro.Context.error(msg, pos);
		}
	}
	#end

	inline function isRefLocalId(id:Int):Bool {
		return refLocals.exists(id) && refLocals.get(id) == true;
	}

	static inline function isOcamlNativeEnumType(e:EnumType, name:String):Bool {
		return e.pack != null && e.pack.length == 1 && e.pack[0] == "ocaml" && e.name == name;
	}

	static inline function isStdArrayClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 0 && cls.name == "Array";
	}

	static inline function isStdStringClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 0 && cls.name == "String";
	}

	static inline function isStdBytesClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "haxe" && cls.pack[1] == "io" && cls.name == "Bytes";
	}

	static inline function isHaxeDsStringMapClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "haxe" && cls.pack[1] == "ds" && cls.name == "StringMap";
	}

	static inline function isHaxeDsIntMapClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "haxe" && cls.pack[1] == "ds" && cls.name == "IntMap";
	}

	static inline function isHaxeDsObjectMapClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "haxe" && cls.pack[1] == "ds" && cls.name == "ObjectMap";
	}

	static inline function isHaxeConstraintsIMapClass(cls:ClassType):Bool {
		// `haxe.Constraints.IMap`
		return cls.pack != null && cls.pack.length == 1 && cls.pack[0] == "haxe" && cls.module == "haxe.Constraints" && cls.name == "IMap";
	}

	static function mapKeyKindFromType(t:Type):Null<String> {
		final k = unwrapNullType(t);
		if (isStringType(k)) return "string";
		if (isIntType(k)) return "int";
		// Best-effort: everything else is treated as ObjectMap for now.
		return "object";
	}

	function mapKeyKindFromIMapExpr(objExpr:TypedExpr):Null<String> {
		return switch (objExpr.t) {
			case TInst(_, params) if (params != null && params.length >= 2):
				mapKeyKindFromType(params[0]);
			case _:
				null;
		}
	}

	function ocamlIteratorOfArray(items:OcamlExpr):OcamlExpr {
		return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "of_array"), [items]);
	}

	static function isStringType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				a.pack != null && a.pack.length == 0 && a.name == "Null" && isStringType(inner);
			case TInst(cRef, _):
				final c = cRef.get();
				isStdStringClass(c);
			case _:
				false;
		}
	}

	/**
		Follows monomorphs and typedefs, but intentionally does *not* follow
		abstracts (notably `Null<T>`).

		`haxe.macro.TypeTools.follow` uses `Context.follow`, which can collapse
		`Null<T>` to `T` (core-type behavior). For this backend we must preserve
		`Null<T>` so we can emit correct boxing/unboxing and null comparisons.
	**/
	static function followNoAbstracts(t:Type):Type {
		var current = t;
		while (true) {
			final next = switch (current) {
				case TLazy(f):
					f();
				case TMono(r):
					final inner = r.get();
					inner == null ? current : inner;
				case TType(tRef, params):
					final td = tRef.get();
					TypeTools.applyTypeParameters(td.type, td.params, params);
				case _:
					return current;
			}

			// Guard against unresolved/self-referential monomorphs and other cyclic shapes.
			// If following doesn't make progress, stop.
			if (next == current) return current;
			current = next;
		}
	}

	/**
		Unwraps monomorphs/lazy types but intentionally does *not* follow typedefs.

		Used for detecting special typedef-backed anonymous structures where we emit
		idiomatic OCaml records (e.g. `sys.FileStat`).
	**/
	static function unwrapNoTypedef(t:Type):Type {
		var current = t;
		while (true) {
			final next = switch (current) {
				case TLazy(f):
					f();
				case TMono(r):
					final inner = r.get();
					inner == null ? current : inner;
				case _:
					return current;
			}

			if (next == current) return current;
			current = next;
		}
	}

	static function isSysFileStatTypedef(t:Type):Bool {
		return switch (unwrapNoTypedef(t)) {
			case TType(tRef, _):
				final td = tRef.get();
				(td.pack ?? []).length == 1 && td.pack[0] == "sys" && td.module == "sys.FileSystem" && td.name == "FileStat";
			case _:
				false;
		}
	}

	static function isSysFileStatAnon(t:Type):Bool {
		final ft = followNoAbstracts(t);
		return switch (ft) {
			case TAnonymous(aRef):
				final a = aRef.get();
				final want = [
					"gid", "uid",
					"atime", "mtime", "ctime",
					"size",
					"dev", "ino", "nlink", "rdev", "mode"
				];
				final have:Map<String, Bool> = [];
				for (f in a.fields) have.set(f.name, true);
				for (n in want) {
					if (!have.exists(n)) return false;
				}
				true;
				case _:
					false;
			}
		}

		static function isStdAnyAbstract(t:Type):Bool {
			return switch (followNoAbstracts(t)) {
				case TAbstract(aRef, _):
					final a = aRef.get();
					(a.pack ?? []).length == 0 && a.name == "Any";
				case _:
					false;
			}
		}

		static function isIteratorAnon(t:Type):Bool {
			return switch (followNoAbstracts(t)) {
				case TAnonymous(aRef):
					final a = aRef.get();
					var hasHasNext = false;
					var hasNext = false;
					for (f in a.fields) {
						if (f.name == "hasNext") hasHasNext = true;
						else if (f.name == "next") hasNext = true;
					}
					hasHasNext && hasNext;
				case _:
					false;
			}
		}

		static function isKeyValueAnon(t:Type):Bool {
			return switch (followNoAbstracts(t)) {
				case TAnonymous(aRef):
					final a = aRef.get();
					var hasKey = false;
					var hasValue = false;
					for (f in a.fields) {
						if (f.name == "key") hasKey = true;
						else if (f.name == "value") hasValue = true;
					}
					hasKey && hasValue;
				case _:
					false;
			}
		}

		/**
			Decides whether a `TAnonymous` type should lower to the generic `HxAnon` runtime
			representation (`Obj.t`), or whether it is one of our “record-like”/tuple-like
			structural shapes with a dedicated OCaml representation.

			Why:
			- Haxe uses anonymous structures heavily (typedef-backed structural typing).
			- For most shapes we represent them as `Obj.t` with runtime field access
			  (`HxAnon.get/set`), because generating OCaml record types for arbitrary
			  structural types is not practical.
			- Some anonymous shapes are performance-critical and/or ubiquitous in the stdlib
			  and compiler tests (e.g. `Iterator<T>`, key/value pairs, `sys.FileStat`), so we
			  special-case them to real OCaml data structures.

			This predicate is used by coercions and `Std.string` lowering to avoid boxing
			record-like values into `Obj.t` accidentally (which would break record-field
			access such as `it.hasNext ()`).
		**/
		static function shouldAnonUseHxAnon(t:Type):Bool {
			if (isSysFileStatTypedef(t) || isSysFileStatAnon(t)) return false;
			if (isIteratorAnon(t)) return false;
			if (isKeyValueAnon(t)) return false;
			return true;
		}

	static function isIntType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				a.pack != null && a.pack.length == 0 && a.name == "Int";
			case _:
				false;
		}
	}

	static function isFloatType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				a.pack != null && a.pack.length == 0 && a.name == "Float";
			case _:
				false;
		}
	}

	static function isBoolType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				a.pack != null && a.pack.length == 0 && a.name == "Bool";
			case _:
				false;
		}
	}

	static function isVoidType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				a.pack != null && a.pack.length == 0 && a.name == "Void";
			case _:
				false;
		}
	}

	static function nullablePrimitiveKind(t:Type):Null<String> {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					if (isIntType(inner)) return "int";
					if (isFloatType(inner)) return "float";
					if (isBoolType(inner)) return "bool";
				}
				null;
			case _:
				null;
		}
	}

	static function unwrapNullType(t:Type):Type {
		return switch (t) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") inner else t;
			case _:
				t;
		}
	}

	inline function isDynamicLike(t:Type):Bool {
		final ft = followNoAbstracts(unwrapNullType(t));
		return switch (ft) {
			case TDynamic(_):
				true;
			case TAbstract(_, _) if (isStdAnyAbstract(t)):
				true;
			case TAnonymous(_) if (shouldAnonUseHxAnon(t)):
				true;
			case _:
				false;
		}
	}

	static function fullNameOfTypeEnum(t:Type):Null<String> {
		return switch (followNoAbstracts(unwrapNullType(t))) {
			case TEnum(eRef, _):
				fullNameOfEnumType(eRef.get());
			case _:
				null;
		}
	}

	static function isNullableEnumType(t:Type):Null<String> {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if ((a.pack ?? []).length == 0 && a.name == "Null") {
					switch (TypeTools.follow(inner)) {
						case TEnum(eRef, _):
							final e = eRef.get();
							(e.pack ?? []).concat([e.name]).join(".");
						case _:
							null;
					}
				} else {
					null;
				}
			case _:
				null;
		}
	}

	static inline function fullNameOfClassType(cls:ClassType):String {
		return (cls.pack ?? []).concat([cls.name]).join(".");
	}

	static inline function fullNameOfEnumType(e:EnumType):String {
		return (e.pack ?? []).concat([e.name]).join(".");
	}

	/**
		Returns the single "match tag" for a typed catch, or `null` if this is a
		`catch (e:Dynamic)`-style match-all.

		Important: this must be *precise* for the catch type.
		Do not include parent tags here, otherwise `catch (e:Child)` could match
		`throw (new Base())` via the shared base tag.
	**/
	static function catchTagForType(t:Type):Null<String> {
		final ft = followNoAbstracts(t);

		if (isIntType(ft)) return "Int";
		if (isFloatType(ft)) return "Float";
		if (isBoolType(ft)) return "Bool";
		if (isStringType(ft)) return "String";

		return switch (ft) {
			case TDynamic(_):
				null;
			case TInst(cRef, _):
				fullNameOfClassType(cRef.get());
			case TEnum(eRef, _):
				fullNameOfEnumType(eRef.get());
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					// Best-effort: treat `Null<T>` catch as a catch on `T` for now.
					catchTagForType(inner);
				} else {
					(a.pack ?? []).concat([a.name]).join(".");
				}
			case _:
				// Structural types and function types are not supported yet.
				null;
		}
	}

	/**
		Compute "throw tags" for a thrown value based on the *static* type of the
		expression being thrown.

		Tags are used to implement typed catches (`catch (e:T)`) without relying on
		OCaml runtime representation checks (which cannot disambiguate e.g. `int`
		and `bool` reliably).

		This is intentionally best-effort: for now it does not attempt to model
		precise runtime shapes for values whose static type is too generic.
	**/
	static function throwTagsForType(t:Type):Array<String> {
		final tags:Array<String> = [];
		final seen:Map<String, Bool> = [];

		inline function add(tag:String):Void {
			if (!seen.exists(tag)) {
				seen.set(tag, true);
				tags.push(tag);
			}
		}

		// Always include Dynamic so a catch-all can match predictably.
		add("Dynamic");

		final ft = followNoAbstracts(t);
		if (isIntType(ft)) {
			add("Int");
			return tags;
		}
		if (isFloatType(ft)) {
			add("Float");
			return tags;
		}
		if (isBoolType(ft)) {
			add("Bool");
			return tags;
		}
		if (isStringType(ft)) {
			add("String");
			return tags;
		}

		function addInterfaceTags(iface:ClassType, visited:Map<String, Bool>):Void {
			final name = fullNameOfClassType(iface);
			if (visited.exists(name)) return;
			visited.set(name, true);
			add(name);
			for (i in iface.interfaces) addInterfaceTags(i.t.get(), visited);
		}

		function addClassTags(cls:ClassType, visited:Map<String, Bool>):Void {
			final name = fullNameOfClassType(cls);
			if (visited.exists(name)) return;
			visited.set(name, true);
			add(name);
			for (i in cls.interfaces) addInterfaceTags(i.t.get(), visited);
			if (cls.superClass != null) addClassTags(cls.superClass.t.get(), visited);
		}

		return switch (ft) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					add("Null");
					for (t in throwTagsForType(inner)) add(t);
				}
				tags;
			case TInst(cRef, _):
				addClassTags(cRef.get(), []);
				tags;
			case TEnum(eRef, _):
				add(fullNameOfEnumType(eRef.get()));
				tags;
			case _:
				tags;
		}
	}

	function buildArrayJoinStringifier(arrayExpr:TypedExpr, pos:Position):OcamlExpr {
		var elemType:Null<Type> = null;
		switch (arrayExpr.t) {
			case TInst(_, params) if (params != null && params.length > 0):
				elemType = unwrapNullType(params[0]);
			case _:
		}

		if (elemType != null) {
			if (isStringType(elemType)) {
				final v = renameVar("x");
				return OcamlExpr.EFun([OcamlPat.PVar(v)], OcamlExpr.EIdent(v));
			}
			if (isIntType(elemType)) return OcamlExpr.EIdent("string_of_int");
			if (isBoolType(elemType)) return OcamlExpr.EIdent("string_of_bool");
			if (isFloatType(elemType)) return OcamlExpr.EIdent("string_of_float");
		}

		#if macro
		guardrailError(
			"reflaxe.ocaml (M6): Array.join currently supports elements of type String/Int/Float/Bool (others not implemented yet).",
			pos
		);
		#end
		return OcamlExpr.EFun([OcamlPat.PAny], OcamlExpr.EConst(OcamlConst.CString("<object>")));
	}

	static function unwrap(e:TypedExpr):TypedExpr {
		var current = e;
		while (true) {
			switch (current.expr) {
				case TParenthesis(inner):
					current = inner;
				case TMeta(_, inner):
					current = inner;
				case _:
					return current;
			}
		}
	}

	static function containsLoopControl(e:TypedExpr):Bool {
		var found = false;

		function visit(e:TypedExpr):Void {
			if (found) return;
			switch (e.expr) {
				case TBreak, TContinue:
					found = true;
				case TWhile(_, _, _), TFunction(_):
					// Skip nested loops/functions. Loop control only applies to the
					// innermost loop at the lexical site in Haxe.
				case _:
					TypedExprTools.iter(e, visit);
			}
		}

		visit(e);
		return found;
	}

	function buildCondition(cond:TypedExpr):OcamlExpr {
		// The Haxe typed AST can sometimes keep `Null<Bool>` in condition position
		// (notably after switch lowering to `if tmp == null ... else if tmp ...`).
		//
		// Our nullable primitive representation is `Obj.t`, so we must unbox to a
		// real OCaml `bool` before emitting `if/while`.
			return nullablePrimitiveKind(cond.t) == "bool"
				? safeUnboxNullableBool(buildExpr(cond))
				: buildExpr(cond);
		}

		inline function exprAsStatement(expr:OcamlExpr):OcamlExpr {
			return switch (expr) {
				// Never wrap `raise` in `ignore`: `raise` already typechecks in unit-context,
				// and wrapping forces `unit`, which breaks our `Hx_return`-based early-return
				// encoding when the return value is later used (e.g. std StringTools.trim).
				case ERaise(_):
					expr;
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [expr]);
			}
		}

		public function buildExpr(e:TypedExpr):OcamlExpr {
			final built:OcamlExpr = switch (e.expr) {
			case TTypeExpr(_):
				switch (e.expr) {
					case TTypeExpr(t):
						switch (t) {
							case TClassDecl(clsRef):
								final cls = clsRef.get();
								final name = (cls.pack ?? []).concat([cls.name]).join(".");
								OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"),
									[OcamlExpr.EConst(OcamlConst.CString(name))]
								);
							case TEnumDecl(enumRef):
								final en = enumRef.get();
								final name = (en.pack ?? []).concat([en.name]).join(".");
								OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enum_"),
									[OcamlExpr.EConst(OcamlConst.CString(name))]
								);
							case _:
								#if macro
								guardrailError(
									"reflaxe.ocaml (M10): type expressions for this type kind are not supported yet. (bd: haxe.ocaml-eli)",
									e.pos
								);
								#end
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
						}
					case _:
						OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
			case TConst(TThis):
				OcamlExpr.EIdent("self");
				case TConst(TSuper):
					// `super` as a value is lowered as `self`. The callsite decides whether it needs
					// base dispatch (e.g. `super.foo(...)`) or base ctor calls (`super(...)`).
					OcamlExpr.EIdent("self");
				case TConst(TNull):
					// `null` is used across many portable Haxe APIs (e.g. Sys.getEnv).
					//
					// - For nullable primitives (Null<Int>/Null<Float>/Null<Bool>), represent
					//   null as `HxRuntime.hx_null : Obj.t` directly (no cast).
					// - Otherwise cast it with `Obj.magic` so it unifies with the expected OCaml type
					//   (e.g. nullable strings use `Obj.magic hx_null : string`).
					nullablePrimitiveKind(e.t) != null
						? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
						: OcamlExpr.EApp(
							OcamlExpr.EIdent("Obj.magic"),
							[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
						);
			case TConst(c):
					// For nullable primitives, represent non-null values as `Obj.repr <prim>`.
					switch (nullablePrimitiveKind(e.t)) {
						case "int":
							switch (c) {
								case TInt(_):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
								case _:
									OcamlExpr.EConst(buildConst(c));
							}
						case "float":
							switch (c) {
								case TFloat(_):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
								case TInt(_):
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
										[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [OcamlExpr.EConst(buildConst(c))])]
									);
								case _:
									OcamlExpr.EConst(buildConst(c));
							}
						case "bool":
							switch (c) {
								case TBool(_):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
								case _:
									OcamlExpr.EConst(buildConst(c));
							}
						case _:
							OcamlExpr.EConst(buildConst(c));
					}
			case TLocal(v):
				// Haxe's core-type `Null<T>` can “collapse” in typed expressions depending on
				// target semantics and implicit conversions (e.g. `Null<Int>` used as `Int`).
				//
				// Locals may therefore be *stored* using the nullable representation (`Obj.t`)
				// but *used* in a non-nullable primitive context, which must be coerced to the
				// correct OCaml primitive type at the usage site.
				final base = buildLocal(v);
				final varKind = nullablePrimitiveKind(v.t);
				final useKind = nullablePrimitiveKind(e.t);

				if (varKind != null && useKind == null) {
					return switch (varKind) {
						case "int" if (isIntType(e.t)):
							safeUnboxNullableInt(base);
						case "int" if (isFloatType(e.t)):
							OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [safeUnboxNullableInt(base)]);
						case "float" if (isFloatType(e.t)):
							safeUnboxNullableFloat(base);
						case "bool" if (isBoolType(e.t)):
							safeUnboxNullableBool(base);
						case _:
							base;
					}
				}

				if (varKind == null && useKind != null) {
					return switch (useKind) {
						case "int" if (isIntType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case "float" if (isFloatType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case "float" if (isIntType(v.t)):
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
								[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [base])]
							);
						case "bool" if (isBoolType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case _:
							base;
					}
				}

				base;
			case TIdent(s):
				OcamlExpr.EIdent(s);
			case TParenthesis(inner):
				buildExpr(inner);
			case TBinop(op, e1, e2):
				buildBinop(op, e1, e2, e.t);
			case TUnop(op, postFix, inner):
				buildUnop(op, postFix, inner, e.t);
				case TFunction(tfunc):
					buildFunction(tfunc);
						case TIf(cond, eif, eelse):
							if (eelse == null) {
								// Haxe `if (cond) stmt;` is statement-typed (Void). Ensure both branches are `unit`
								// so the OCaml `if` is well-typed, even if `stmt` returns a value (e.g. Array.push).
								OcamlExpr.EIf(
									buildCondition(cond),
									exprAsStatement(buildExpr(eif)),
									OcamlExpr.EConst(OcamlConst.CUnit)
								);
							} else {
								final expected = e.t;
								if (isVoidType(expected)) {
									return OcamlExpr.EIf(
										buildCondition(cond),
										exprAsStatement(buildExpr(eif)),
										exprAsStatement(buildExpr(eelse))
									);
								}

							// Haxe can flow-type nullable primitives inside conditionals, but the typed AST
							// may still keep branch expressions as `Null<T>` even when the overall `if`
							// expression is typed as non-nullable `T` (notably from `??` lowering).
							//
						// Example (from upstream typed AST dumps):
						//   var a:Null<Int> = null;
						//   var b:Int = a ?? 2;
						// becomes:
						//   var tmp:Null<Int> = a;
						//   var b:Int = if (tmp != null) tmp else 2;
						// where the `then` is still typed as `Null<Int>`.
						//
							// OCaml requires both branches to have the same type, so we coerce between
							// `Null<primitive>` and `primitive` as needed.

							function coerceBranch(branch:TypedExpr):OcamlExpr {
								final toKind = nullablePrimitiveKind(expected);
								final fromKind = nullablePrimitiveKind(branch.t);

							// Null<prim> -> prim
							if (toKind == null) {
								if (isIntType(expected) && fromKind == "int") {
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [buildExpr(branch)]);
								}
								if (isFloatType(expected) && fromKind == "float") {
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_float_unwrap"), [buildExpr(branch)]);
								}
								if (isBoolType(expected) && fromKind == "bool") {
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_bool_unwrap"), [buildExpr(branch)]);
								}
							}

							// prim -> Null<prim>
							if (toKind != null && fromKind == null) {
								switch (toKind) {
									case "int" if (isIntType(branch.t)):
										return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
									case "float" if (isFloatType(branch.t)):
										return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
									case "float" if (isIntType(branch.t)):
										return OcamlExpr.EApp(
											OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
											[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(branch)])]
										);
									case "bool" if (isBoolType(branch.t)):
										return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
									case _:
								}
							}

							return buildExpr(branch);
						}

						OcamlExpr.EIf(buildCondition(cond), coerceBranch(eif), coerceBranch(eelse));
					}
				case TBlock(el):
					buildBlock(el);
			case TVar(v, init):
				// Variable declarations should generally be handled by `buildBlock`
				// so that scope covers the remainder of the block.
				OcamlExpr.EConst(OcamlConst.CUnit);
				case TNew(clsRef, _, args):
					final cls = clsRef.get();
					if (isStdArrayClass(cls) && args.length == 0) {
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					} else if (args.length == 0 && (isHaxeDsStringMapClass(cls) || isHaxeDsIntMapClass(cls) || isHaxeDsObjectMapClass(cls))) {
						final ctor = if (isHaxeDsStringMapClass(cls)) {
							"create_string";
						} else if (isHaxeDsIntMapClass(cls)) {
							"create_int";
						} else {
							"create_object";
						}
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), ctor), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					} else if (isStdBytesClass(cls)) {
						// Stdlib sometimes calls `new Bytes(len, data)` in `untyped` blocks (e.g. BytesBuffer).
						// For OCaml we treat BytesData as an opaque runtime value (currently `bytes`), so the
						// `len` argument is ignored and we just wrap the underlying data.
					if (args.length == 2) {
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofData"),
							[buildExpr(args[1]), OcamlExpr.EConst(OcamlConst.CUnit)]
						);
					} else {
						#if macro
						guardrailError(
							"reflaxe.ocaml (M6): unsupported Bytes constructor arity (expected new Bytes(len, data)).",
							e.pos
						);
						#end
						OcamlExpr.EConst(OcamlConst.CUnit);
					}
					} else {
						final modName = moduleIdToOcamlModuleName(cls.module);
						final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
						final createName = ctx.scopedValueName(cls.module, cls.name, "create");
						final fn = (selfMod != null && selfMod == modName)
							? OcamlExpr.EIdent(createName)
							: OcamlExpr.EField(OcamlExpr.EIdent(modName), createName);

						// Constructor callsites must fully apply all optional parameters.
						//
						// Why:
						// - reflaxe.ocaml represents Haxe optional parameters (`?x:T`) like `Null<T>`:
						//   missing args are supplied as `HxRuntime.hx_null` (cast via `Obj.magic` when needed).
						// - If we omit trailing optional ctor args in the emitted `Foo.create a0 a1`,
						//   OCaml treats it as *partial application* and we end up with a function value
						//   where an instance record is expected (breaking at compile time).
						//
						// This especially matters for `sys.io.Process` parity (optional args + detached)
						// used by HXHX Stage 4 macro transport (bd: haxe.ocaml-xgv.3.3).
						final expectedCtorArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = if (cls.constructor == null) {
							null;
						} else {
							final ctorField = cls.constructor.get();
							switch (TypeTools.follow(ctorField.type)) {
								case TFun(fargs, _): fargs;
								case _: null;
							}
						}

						final builtArgs:Array<OcamlExpr> = [];
						if (expectedCtorArgs != null) {
							inline function hxNullForType(t:Type):OcamlExpr {
								return nullablePrimitiveKind(t) != null
									? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
									: OcamlExpr.EApp(
										OcamlExpr.EIdent("Obj.magic"),
										[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
									);
							}

							for (i in 0...args.length) {
								if (i >= expectedCtorArgs.length) break;
								final ea = expectedCtorArgs[i];
								builtArgs.push(coerceForAssignment(ea.t, args[i]));
							}
							if (args.length < expectedCtorArgs.length) {
								for (i in args.length...expectedCtorArgs.length) {
									final ea = expectedCtorArgs[i];
									if (ea.opt) {
										builtArgs.push(hxNullForType(ea.t));
									} else {
										#if macro
										guardrailError(
											"reflaxe.ocaml: new " + cls.name + " is missing required constructor argument '" + ea.name + "'.",
											e.pos
										);
										#end
										builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
									}
								}
							}
						} else {
							for (a in args) builtArgs.push(buildExpr(a));
						}

						OcamlExpr.EApp(fn, builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
					}
			case TCall(fn, args):
				{
					// Escape hatch: raw OCaml injection.
					final injected:Null<OcamlExpr> = switch (unwrap(fn).expr) {
						case TIdent("__ocaml__"):
							if (args.length != 1) {
								#if macro
								guardrailError(
									"reflaxe.ocaml: __ocaml__ expects exactly one string argument.",
									e.pos
								);
								#end
								OcamlExpr.EConst(OcamlConst.CUnit);
							} else {
								final a = unwrap(args[0]);
								switch (a.expr) {
									case TConst(TString(s)):
										OcamlExpr.ERaw(s);
									case _:
										#if macro
										guardrailError(
											"reflaxe.ocaml: __ocaml__ argument must be a constant string.",
											e.pos
										);
										#end
										OcamlExpr.EConst(OcamlConst.CUnit);
								}
							}
						case _:
							null;
					};

					if (injected != null) {
						injected;
						} else switch (unwrap(fn).expr) {
							case TConst(TSuper):
								// Only lower `super()` when we are using the “virtual class” model (M10),
								// otherwise keep the previous (limited) behavior for upstream stdlib output
								// and other non-virtual cases.
								final curFull = ctx.currentTypeFullName;
								final allowSuperCtor = curFull != null && ctx.dispatchTypes.exists(curFull);
								if (!allowSuperCtor) {
									final builtArgs = args.map(buildExpr);
									OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
								} else {
								#if macro
								if (ctx.currentSuperModuleId == null || ctx.currentSuperTypeName == null) {
									guardrailError("reflaxe.ocaml (M10): encountered super() call, but current super class is unknown.", e.pos);
									OcamlExpr.EConst(OcamlConst.CUnit);
								} else {
								#end
									final supModId = ctx.currentSuperModuleId;
									final supTypeName = ctx.currentSuperTypeName;
									final ctorName = ctx.scopedValueName(supModId, supTypeName, "__ctor");

								final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
								final supModName = moduleIdToOcamlModuleName(supModId);
								final callFn = (selfMod != null && selfMod == supModName)
									? OcamlExpr.EIdent(ctorName)
									: OcamlExpr.EField(OcamlExpr.EIdent(supModName), ctorName);

								inline function hxNullForType(t:Type):OcamlExpr {
									return nullablePrimitiveKind(t) != null
										? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
										: OcamlExpr.EApp(
											OcamlExpr.EIdent("Obj.magic"),
											[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
										);
								}

								final builtArgs = args.map(buildExpr);
								final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("self")])].concat(builtArgs);
								final expected = ctx.currentSuperCtorArgs;
								if (expected != null) {
									if (builtArgs.length < expected.length) {
										for (i in builtArgs.length...expected.length) {
											final ea = expected[i];
											if (!ea.opt) {
												#if macro
												guardrailError("reflaxe.ocaml (M10): super() call is missing required argument '" + ea.name + "'.", e.pos);
												#end
											}
											callArgs.push(hxNullForType(ea.t));
										}
									}
									// Calling convention: if a ctor has zero Haxe args, represent it as `(... -> unit)` and pass `()`.
									if (expected.length == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
								} else {
									// Calling convention: `super()` supplies `unit` when there are no args.
									if (args.length == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
								}
									OcamlExpr.EApp(callFn, callArgs);
								#if macro
								}
								#end
								}
							case _:
								switch (fn.expr) {
						case TField(_, FStatic(clsRef, cfRef)):
							final cls = clsRef.get();
							final cf = cfRef.get();

						// Extern interop: labelled/optional args via @:ocamlLabel("...") on parameters.
						// (bd: haxe.ocaml-28t.8.3)
						if (cls.isExtern) {
							final labelsByArgName = extractOcamlLabelByArgName(cf);
							if (labelsByArgName != null && labelsByArgName.iterator().hasNext()) {
								final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (cf.type) {
									case TFun(fargs, _): fargs;
									case _: null;
								}

								final applyArgs:Array<OcamlApplyArg> = [];
								if (expectedArgs != null) {
									for (i in 0...args.length) {
										if (i >= expectedArgs.length) break;
										final ea = expectedArgs[i];
										final label = labelsByArgName.get(ea.name);
										final coerced = coerceForAssignment(ea.t, args[i]);
										if (label != null) {
											if (ea.opt) {
												applyArgs.push({
													label: label,
													isOptional: true,
													expr: buildOptionalArgOptionExprForInterop(args[i], ea.t)
												});
											} else {
												applyArgs.push({ label: label, isOptional: false, expr: coerced });
											}
										} else {
											applyArgs.push({ label: null, isOptional: false, expr: coerced });
										}
									}
								} else {
									for (a in args) applyArgs.push({ label: null, isOptional: false, expr: buildExpr(a) });
								}

								final builtFn = buildExpr(fn);
								return OcamlExpr.EAppArgs(builtFn, applyArgs.length == 0 ? [{ label: null, isOptional: false, expr: OcamlExpr.EConst(OcamlConst.CUnit) }] : applyArgs);
							}
						}

						// OCaml-native surface: `ocaml.Ref<T>` calls lower to `ref` / `!` / `:=`.
						//
						// This is an opt-in API surface for emitting idiomatic OCaml refs, separate from
						// the backend's internal ref-based lowering for portable Haxe mutability semantics.
						if (cls.pack != null && cls.pack.length == 1 && cls.pack[0] == "ocaml" && cls.name == "Ref") {
							switch (cf.name) {
								case "make" if (args.length == 1):
									return OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [buildExpr(args[0])]);
								case "get" if (args.length == 1):
									return OcamlExpr.EUnop(OcamlUnop.Deref, buildExpr(args[0]));
								case "set" if (args.length == 2):
									return OcamlExpr.EAssign(OcamlAssignOp.RefSet, buildExpr(args[0]), buildExpr(args[1]));
								case _:
							}
						}

						if (cls.pack != null && cls.pack.length == 0 && cls.name == "Sys") {
							final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
							switch (cf.name) {
								case "println" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EIdent("print_endline"), [buildStdString(args[0])]);
								case "print" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EIdent("print_string"), [buildStdString(args[0])]);
								case "args" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "args"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "getEnv" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "getEnv"), [buildExpr(args[0])]);
									case "putEnv" if (args.length == 2):
										final v1 = unwrap(args[1]);
										final opt = switch (v1.expr) {
											case TConst(TNull): OcamlExpr.EIdent("None");
											case _: OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [buildExpr(args[1])]);
										};
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "putEnv"), [buildExpr(args[0]), opt]);
									case "environment" if (args.length == 0):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "environment"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
									case "sleep" if (args.length == 1):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "sleep"), [buildExpr(args[0])]);
								case "getCwd" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "getCwd"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "setCwd" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "setCwd"), [buildExpr(args[0])]);
								case "systemName" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "systemName"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "command":
									final opt = if (args.length == 1) {
										OcamlExpr.EIdent("None");
									} else if (args.length == 2) {
										final a1 = unwrap(args[1]);
										switch (a1.expr) {
											case TConst(TNull): OcamlExpr.EIdent("None");
											case _: OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [buildExpr(args[1])]);
										}
									} else {
										#if macro
										guardrailError("reflaxe.ocaml (M6): Sys.command expects 1 or 2 args.", e.pos);
										#end
										OcamlExpr.EIdent("None");
									};
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "command"), [buildExpr(args[0]), opt]);
								case "exit" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "exit"), [buildExpr(args[0])]);
								case "time" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "time"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "cpuTime" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "cpuTime"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "programPath" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "programPath"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								case "executablePath" if (args.length == 0):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "programPath"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
									case "getChar" if (args.length == 1):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxSys"), "getChar"), [buildExpr(args[0])]);
									case "stdin" if (args.length == 0):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Sys_io_Stdio"), "stdin"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
									case "stdout" if (args.length == 0):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Sys_io_Stdio"), "stdout"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
									case "stderr" if (args.length == 0):
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Sys_io_Stdio"), "stderr"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
									case _:
										#if macro
										guardrailError("reflaxe.ocaml (M6): Sys." + cf.name + " is not implemented yet.", e.pos);
										#end
									anyNull;
							}
						} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Type") {
							final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
							switch (cf.name) {
								case "getClass" if (args.length == 1):
									final a0 = args[0];
									final a0Type = unwrapNullType(a0.t);
									final a0Expr = buildExpr(a0);
									final asObj:OcamlExpr = (nullablePrimitiveKind(a0Type) != null)
										? a0Expr
										: switch (a0Type) {
											case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_): a0Expr;
											case _: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [a0Expr]);
										}
									;
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClass"),
										[asObj]
									);
								case "getClassName" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClassName"), [buildExpr(args[0])]);
								case "getEnumName" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getEnumName"), [buildExpr(args[0])]);
								case "resolveClass" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "resolveClass"), [buildExpr(args[0])]);
								case "resolveEnum" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "resolveEnum"), [buildExpr(args[0])]);
								case _:
									#if macro
									guardrailError(
										"reflaxe.ocaml (M10): Type." + cf.name + " is not implemented yet. (bd: haxe.ocaml-eli)",
										e.pos
									);
									#end
									anyNull;
							}
						} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Reflect") {
							final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
							switch (cf.name) {
								case "field" if (args.length == 2):
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"),
										[
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
												[
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[0])]),
													buildExpr(args[1])
												]
											)
										]
									);
								case "setField" if (args.length == 3):
									final rhs = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[2])]);
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
										[
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[0])]),
											buildExpr(args[1]),
											rhs
										]
									);
								case "hasField" if (args.length == 2):
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "has"),
										[
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[0])]),
											buildExpr(args[1])
										]
									);
								case _:
									#if macro
									guardrailError("reflaxe.ocaml (M10): Reflect." + cf.name + " is not implemented yet. (bd: haxe.ocaml-k7o)", e.pos);
									#end
									anyNull;
							}
						} else if (cls.pack != null && cls.pack.length == 1 && cls.pack[0] == "sys" && cls.name == "FileSystem") {
							final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
							switch (cf.name) {
								case "exists" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "exists"), [buildExpr(args[0])]);
								case "rename" if (args.length == 2):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "rename"), [buildExpr(args[0]), buildExpr(args[1])]);
								case "fullPath" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "fullPath"), [buildExpr(args[0])]);
								case "absolutePath" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "absolutePath"), [buildExpr(args[0])]);
								case "isDirectory" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "isDirectory"), [buildExpr(args[0])]);
								case "createDirectory" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "createDirectory"), [buildExpr(args[0])]);
								case "deleteFile" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "deleteFile"), [buildExpr(args[0])]);
								case "deleteDirectory" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "deleteDirectory"), [buildExpr(args[0])]);
								case "readDirectory" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "readDirectory"), [buildExpr(args[0])]);
								case "stat" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFileSystem"), "stat"), [buildExpr(args[0])]);
								case _:
									#if macro
									guardrailError("reflaxe.ocaml (M6): sys.FileSystem." + cf.name + " is not implemented yet.", e.pos);
									#end
									anyNull;
							}
						} else if (cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "sys" && cls.pack[1] == "io" && cls.name == "File") {
							final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
							switch (cf.name) {
								case "getContent" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFile"), "getContent"), [buildExpr(args[0])]);
								case "saveContent" if (args.length == 2):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFile"), "saveContent"), [buildExpr(args[0]), buildExpr(args[1])]);
								case "getBytes" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFile"), "getBytes"), [buildExpr(args[0])]);
								case "saveBytes" if (args.length == 2):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFile"), "saveBytes"), [buildExpr(args[0]), buildExpr(args[1])]);
								case "copy" if (args.length == 2):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxFile"), "copy"), [buildExpr(args[0]), buildExpr(args[1])]);
								case _:
									#if macro
									guardrailError("reflaxe.ocaml (M6): sys.io.File." + cf.name + " is not implemented yet.", e.pos);
									#end
									anyNull;
							}
						} else
						if (isStdStringClass(cls) && cf.name == "fromCharCode" && args.length == 1) {
							final a0 = args[0];
							final coerced = nullablePrimitiveKind(a0.t) == "int" ? safeUnboxNullableInt(buildExpr(a0)) : buildExpr(a0);
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "fromCharCode"), [coerced]);
						} else if (isStdBytesClass(cls)) {
							switch (cf.name) {
								case "alloc" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "alloc"), [buildExpr(args[0])]);
								case "ofString":
									final encodingExpr = args.length > 1 ? unwrap(args[1]) : null;
									final okDefaultEncoding = encodingExpr == null || switch (encodingExpr.expr) {
										case TConst(TNull): true;
										case _: false;
									};
									if (args.length == 1 || (args.length == 2 && okDefaultEncoding)) {
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofString"), [buildExpr(args[0]), OcamlExpr.EConst(OcamlConst.CUnit)]);
									} else {
										#if macro
										guardrailError(
											"reflaxe.ocaml (M6): Bytes.ofString only supports default encoding for now (pass no encoding or null). (bd: haxe.ocaml-28t.7.5)",
											e.pos
										);
										#end
										OcamlExpr.EConst(OcamlConst.CUnit);
									}
								case "ofData" if (args.length == 1):
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofData"), [buildExpr(args[0]), OcamlExpr.EConst(OcamlConst.CUnit)]);
								case _:
									#if macro
									guardrailError(
										"reflaxe.ocaml (M6): unsupported Bytes static method '" + cf.name + "'. (bd: haxe.ocaml-28t.7.5)",
										e.pos
									);
									#end
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
							} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "int" && args.length == 1) {
								final arg = unwrap(args[0]);
								switch (arg.expr) {
									case TBinop(OpDiv, a, b) if (isIntType(a.t) && isIntType(b.t)):
										// Haxe `Std.int(a / b)` with Int operands: lower directly to OCaml int division.
										OcamlExpr.EBinop(OcamlBinop.Div, buildExpr(a), buildExpr(b));
									case _ if (isIntType(arg.t)):
										buildExpr(arg);
									case _:
										OcamlExpr.EApp(OcamlExpr.EIdent("int_of_float"), [buildExpr(arg)]);
								}
							} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "isOfType" && args.length == 2) {
								final a0 = args[0];
								final a0Type = unwrapNullType(a0.t);
								final a0Expr = buildExpr(a0);
								final asObj:OcamlExpr = (nullablePrimitiveKind(a0Type) != null)
									? a0Expr
									: switch (followNoAbstracts(a0Type)) {
										case TDynamic(_):
											a0Expr;
										case TAbstract(_, _) if (isStdAnyAbstract(a0Type)):
											a0Expr;
										case TAnonymous(_) if (shouldAnonUseHxAnon(a0.t)):
											a0Expr;
										case _:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [a0Expr]);
									}
								;
								OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "isOfType"),
									[asObj, buildExpr(args[1])]
								);
							} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "string" && args.length == 1) {
								buildStdString(args[0]);
								} else {
									final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (cf.type) {
										case TFun(fargs, _): fargs;
										case _: null;
									}
									inline function hxNullForType(t:Type):OcamlExpr {
										return nullablePrimitiveKind(t) != null
											? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
											: OcamlExpr.EApp(
												OcamlExpr.EIdent("Obj.magic"),
												[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
											);
									}
									final builtArgs:Array<OcamlExpr> = [];
									if (expectedArgs != null) {
										for (i in 0...args.length) {
											builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
										}
										if (args.length < expectedArgs.length) {
											for (i in args.length...expectedArgs.length) {
												final ea = expectedArgs[i];
												if (!ea.opt) {
													#if macro
													guardrailError(
														"reflaxe.ocaml: call is missing required argument '" + ea.name + "'.",
														e.pos
													);
													#end
													builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
												} else {
													builtArgs.push(hxNullForType(ea.t));
												}
											}
										}
									} else {
										for (a in args) builtArgs.push(buildExpr(a));
									}
									OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
								}
					case TField(objExpr, FInstance(clsRef, _, cfRef)):
						final cf = cfRef.get();
						switch (cf.kind) {
							case FMethod(_):
								final cls = clsRef.get();
								if (isStdArrayClass(cls)) {
									switch (cf.name) {
											case "concat":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "concat"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "join":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "join"),
													[buildExpr(objExpr), buildExpr(args[0]), buildArrayJoinStringifier(objExpr, e.pos)]
												);
											case "push":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
										case "pop":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "pop"),
												[buildExpr(objExpr), OcamlExpr.EConst(OcamlConst.CUnit)]
											);
											case "shift":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "shift"),
													[buildExpr(objExpr), OcamlExpr.EConst(OcamlConst.CUnit)]
												);
											case "reverse":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "reverse"),
													[buildExpr(objExpr), OcamlExpr.EConst(OcamlConst.CUnit)]
												);
											case "unshift":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "unshift"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
										case "insert":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "insert"),
												[buildExpr(objExpr), buildExpr(args[0]), buildExpr(args[1])]
											);
											case "remove":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "remove"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "contains":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "contains"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "indexOf":
												final fromExpr = if (args.length > 1) {
													final unwrapped = unwrap(args[1]);
													switch (unwrapped.expr) {
														case TConst(TNull):
															OcamlExpr.EConst(OcamlConst.CInt(0));
														case _:
															buildExpr(args[1]);
													}
												} else {
													OcamlExpr.EConst(OcamlConst.CInt(0));
												}
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "indexOf"),
													[buildExpr(objExpr), buildExpr(args[0]), fromExpr]
												);
											case "lastIndexOf":
												final defaultFrom = OcamlExpr.EBinop(
													OcamlBinop.Sub,
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(objExpr)]),
													OcamlExpr.EConst(OcamlConst.CInt(1))
												);
												final fromExpr = if (args.length > 1) {
													final unwrapped = unwrap(args[1]);
													switch (unwrapped.expr) {
														case TConst(TNull):
															defaultFrom;
														case _:
															buildExpr(args[1]);
													}
												} else {
													defaultFrom;
												}
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "lastIndexOf"),
													[buildExpr(objExpr), buildExpr(args[0]), fromExpr]
												);
											case "copy":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "copy"),
													[buildExpr(objExpr)]
												);
											case "map":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "map"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "filter":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "filter"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "resize":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "resize"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "sort":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "sort"),
													[buildExpr(objExpr), buildExpr(args[0])]
												);
											case "splice":
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "splice"),
													[buildExpr(objExpr), buildExpr(args[0]), buildExpr(args[1])]
												);
										case "slice":
											final endExpr = if (args.length > 1) {
												final unwrapped = unwrap(args[1]);
												switch (unwrapped.expr) {
													case TConst(TNull):
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(objExpr)]);
													case _:
														buildExpr(args[1]);
												}
											} else {
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(objExpr)]);
											}
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "slice"),
												[buildExpr(objExpr), buildExpr(args[0]), endExpr]
											);
										case _:
											#if macro
											guardrailError(
												"reflaxe.ocaml (M6): unsupported Array method '" + cf.name + "'. (bd: haxe.ocaml-28t.7.3)",
												e.pos
											);
											#end
											OcamlExpr.EConst(OcamlConst.CUnit);
									}
								} else if (isStdStringClass(cls)) {
									final self = buildExpr(objExpr);
									switch (cf.name) {
										case "toUpperCase":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toUpperCase"),
												[self, OcamlExpr.EConst(OcamlConst.CUnit)]
											);
										case "toLowerCase":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toLowerCase"),
												[self, OcamlExpr.EConst(OcamlConst.CUnit)]
											);
										case "charAt":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "charAt"),
												[self, buildExpr(args[0])]
											);
										case "charCodeAt":
											final raw = OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "charCodeAt"),
												[self, buildExpr(args[0])]
											);
											// Haxe's `String.charCodeAt` is `Null<Int>` but it is frequently used in
											// non-nullable `Int` contexts (via implicit conversions). Our runtime
											// always returns `Obj.t` (either `hx_null` or `Obj.repr int`), so unwrap
											// when the typed AST expects an `Int`.
											isIntType(e.t)
												? OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"),
													[raw]
												)
												: raw;
										case "indexOf":
											final startExpr = if (args.length > 1) {
												final unwrapped = unwrap(args[1]);
												switch (unwrapped.expr) {
													case TConst(TNull):
														OcamlExpr.EConst(OcamlConst.CInt(0));
													case _:
														coerceNullableIntToInt(args[1]);
												}
											} else {
												OcamlExpr.EConst(OcamlConst.CInt(0));
											}
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "indexOf"),
												[self, buildExpr(args[0]), startExpr]
											);
										case "lastIndexOf":
											final defaultStart = OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"),
												[self]
											);
											final startExpr = if (args.length > 1) {
												final unwrapped = unwrap(args[1]);
												switch (unwrapped.expr) {
													case TConst(TNull):
														defaultStart;
													case _:
														coerceNullableIntToInt(args[1]);
												}
											} else {
												defaultStart;
											}
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "lastIndexOf"),
												[self, buildExpr(args[0]), startExpr]
											);
										case "split":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "split"),
												[self, buildExpr(args[0])]
											);
										case "substr":
											final lenExpr = if (args.length > 1) {
												final unwrapped = unwrap(args[1]);
												switch (unwrapped.expr) {
													case TConst(TNull):
														OcamlExpr.EConst(OcamlConst.CInt(-1));
													case _:
														coerceNullableIntToInt(args[1]);
												}
											} else {
												OcamlExpr.EConst(OcamlConst.CInt(-1));
											}
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "substr"),
												[self, buildExpr(args[0]), lenExpr]
											);
										case "substring":
											final defaultEnd = OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"),
												[self]
											);
											final endExpr = if (args.length > 1) {
												final unwrapped = unwrap(args[1]);
												switch (unwrapped.expr) {
													case TConst(TNull):
														defaultEnd;
													case _:
														coerceNullableIntToInt(args[1]);
												}
											} else {
												defaultEnd;
											}
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "substring"),
												[self, buildExpr(args[0]), endExpr]
											);
										case "toString":
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toString"),
												[self, OcamlExpr.EConst(OcamlConst.CUnit)]
											);
										case _:
											#if macro
											guardrailError(
												"reflaxe.ocaml (M6): unsupported String method '" + cf.name + "'. (bd: haxe.ocaml-28t.7.4)",
												e.pos
											);
											#end
											OcamlExpr.EConst(OcamlConst.CUnit);
									}
								} else if (isStdBytesClass(cls)) {
									final self = buildExpr(objExpr);
									switch (cf.name) {
										case "get" if (args.length == 1):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "get"),
												[self, buildExpr(args[0])]
											);
										case "set" if (args.length == 2):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "set"),
												[self, buildExpr(args[0]), coerceNullableIntToInt(args[1])]
											);
										case "blit" if (args.length == 4):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "blit"),
												[self, buildExpr(args[0]), buildExpr(args[1]), buildExpr(args[2]), buildExpr(args[3])]
											);
										case "fill" if (args.length == 3):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "fill"),
												[self, buildExpr(args[0]), buildExpr(args[1]), coerceNullableIntToInt(args[2])]
											);
										case "sub" if (args.length == 2):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "sub"),
												[self, buildExpr(args[0]), buildExpr(args[1])]
											);
										case "compare" if (args.length == 1):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "compare"),
												[self, buildExpr(args[0])]
											);
										case "getString":
											final encodingExpr = args.length > 2 ? unwrap(args[2]) : null;
											final okDefaultEncoding = encodingExpr == null || switch (encodingExpr.expr) {
												case TConst(TNull): true;
												case _: false;
											};
											if (args.length == 2 || (args.length == 3 && okDefaultEncoding)) {
												OcamlExpr.EApp(
													OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "getString"),
													[self, buildExpr(args[0]), buildExpr(args[1]), OcamlExpr.EConst(OcamlConst.CUnit)]
												);
											} else {
												#if macro
												guardrailError(
													"reflaxe.ocaml (M6): Bytes.getString only supports default encoding for now (pass no encoding or null). (bd: haxe.ocaml-28t.7.5)",
													e.pos
												);
												#end
												OcamlExpr.EConst(OcamlConst.CUnit);
											}
										case "toString" if (args.length == 0):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "toString"),
												[self, OcamlExpr.EConst(OcamlConst.CUnit)]
											);
										case "getData" if (args.length == 0):
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "getData"),
												[self, OcamlExpr.EConst(OcamlConst.CUnit)]
											);
										case _:
											#if macro
											guardrailError(
												"reflaxe.ocaml (M6): unsupported Bytes method '" + cf.name + "'. (bd: haxe.ocaml-28t.7.5)",
												e.pos
											);
											#end
											OcamlExpr.EConst(OcamlConst.CUnit);
									}
								} else if (isHaxeDsStringMapClass(cls) || isHaxeDsIntMapClass(cls) || isHaxeDsObjectMapClass(cls) || isHaxeConstraintsIMapClass(cls)) {
									final kind = if (isHaxeDsStringMapClass(cls)) {
										"string";
									} else if (isHaxeDsIntMapClass(cls)) {
										"int";
									} else if (isHaxeDsObjectMapClass(cls)) {
										"object";
									} else {
										mapKeyKindFromIMapExpr(objExpr);
									}
									if (kind == null) {
										#if macro
										guardrailError("reflaxe.ocaml (M6): could not determine Map key kind for IMap call.", e.pos);
										#end
										OcamlExpr.EConst(OcamlConst.CUnit);
									} else {
										final self = buildExpr(objExpr);
										switch (cf.name) {
											case "set" if (args.length == 2):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "set_" + kind), [self, buildExpr(args[0]), buildExpr(args[1])]);
											case "get" if (args.length == 1):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "get_" + kind), [self, buildExpr(args[0])]);
											case "exists" if (args.length == 1):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "exists_" + kind), [self, buildExpr(args[0])]);
											case "remove" if (args.length == 1):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "remove_" + kind), [self, buildExpr(args[0])]);
											case "clear" if (args.length == 0):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "clear_" + kind), [self]);
											case "copy" if (args.length == 0):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "copy_" + kind), [self]);
											case "toString" if (args.length == 0):
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "toString_" + kind), [self]);
											case "keys" if (args.length == 0):
												ocamlIteratorOfArray(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "keys_" + kind), [self]));
											case "iterator" if (args.length == 0):
												ocamlIteratorOfArray(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "values_" + kind), [self]));
											case "keyValueIterator" if (args.length == 0):
												ocamlIteratorOfArray(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), "pairs_" + kind), [self]));
											case _:
												#if macro
												guardrailError("reflaxe.ocaml (M6): unsupported Map method '" + cf.name + "'.", e.pos);
												#end
												OcamlExpr.EConst(OcamlConst.CUnit);
										}
									}
									} else {
										final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (cf.type) {
											case TFun(fargs, _): fargs;
											case _: null;
										}
										inline function hxNullForType(t:Type):OcamlExpr {
											return nullablePrimitiveKind(t) != null
												? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
												: OcamlExpr.EApp(
													OcamlExpr.EIdent("Obj.magic"),
													[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
												);
										}
										final coercedArgs:Array<OcamlExpr> = [];
										if (expectedArgs != null) {
											for (i in 0...args.length) {
												coercedArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
											}
											if (args.length < expectedArgs.length) {
												for (i in args.length...expectedArgs.length) {
													final ea = expectedArgs[i];
													if (!ea.opt) {
														#if macro
														guardrailError(
															"reflaxe.ocaml: call is missing required argument '" + ea.name + "'.",
															e.pos
														);
														#end
														coercedArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
													} else {
														coercedArgs.push(hxNullForType(ea.t));
													}
												}
											}
										} else {
											for (a in args) coercedArgs.push(buildExpr(a));
										}
	
										final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;

										final unwrappedObj = unwrap(objExpr);
										final isSuperReceiver = switch (unwrappedObj.expr) {
											case TConst(TSuper): true;
											case _: false;
										}

									// Dynamic dispatch subset (M10): if the receiver's static type participates in
									// inheritance/interfaces, call through the record-stored method function.
									final recvFullName = classFullNameFromType(objExpr.t);
									final isDispatchRecv = recvFullName != null && (ctx.dispatchTypes.exists(recvFullName) || ctx.interfaceTypes.exists(recvFullName));

									final allowSuperCall = !ctx.currentIsHaxeStd
										&& ctx.currentTypeFullName != null
										&& ctx.dispatchTypes.exists(ctx.currentTypeFullName);

										if (isSuperReceiver && allowSuperCall) {
										// `super.foo(...)`: call the base implementation directly (no virtual dispatch).
										final modName = moduleIdToOcamlModuleName(cls.module);
										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final implName = ctx.scopedValueName(cls.module, cls.name, cf.name + "__impl");
										final callFn = (selfMod != null && selfMod == modName)
											? OcamlExpr.EIdent(implName)
											: OcamlExpr.EField(OcamlExpr.EIdent(modName), implName);

											final builtArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("self")])].concat(coercedArgs);
											// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
											if (expectsNoArgs) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
											OcamlExpr.EApp(callFn, builtArgs);
										} else if (isDispatchRecv) {
										final recvExpr = buildExpr(objExpr);
										final tmpName = switch (recvExpr) {
											case EIdent(_): null;
											case _: freshTmp("obj");
										}
										final recvVar = tmpName == null ? recvExpr : OcamlExpr.EIdent(tmpName);
											final methodField = OcamlExpr.EField(recvVar, cf.name);
											final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar])].concat(coercedArgs);
											// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
											if (expectsNoArgs) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
											final call = OcamlExpr.EApp(methodField, callArgs);
											tmpName == null ? call : OcamlExpr.ELet(tmpName, recvExpr, call, false);
										} else {
										final modName = moduleIdToOcamlModuleName(cls.module);
										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
											final callFn = (selfMod != null && selfMod == modName)
												? OcamlExpr.EIdent(scoped)
												: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
											final builtArgs = [buildExpr(objExpr)].concat(coercedArgs);
											// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
											if (expectsNoArgs) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
											OcamlExpr.EApp(callFn, builtArgs);
										}
										}
									case _:
										final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (TypeTools.follow(fn.t)) {
											case TFun(fargs, _): fargs;
											case _: null;
										}
										inline function hxNullForType(t:Type):OcamlExpr {
											return nullablePrimitiveKind(t) != null
												? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
												: OcamlExpr.EApp(
													OcamlExpr.EIdent("Obj.magic"),
													[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
												);
										}
										final builtArgs:Array<OcamlExpr> = [];
										if (expectedArgs != null) {
											for (i in 0...args.length) {
												builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
											}
											if (args.length < expectedArgs.length) {
												for (i in args.length...expectedArgs.length) {
													final ea = expectedArgs[i];
													if (!ea.opt) {
														#if macro
														guardrailError(
															"reflaxe.ocaml: call is missing required argument '" + ea.name + "'.",
															e.pos
														);
														#end
														builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
													} else {
														builtArgs.push(hxNullForType(ea.t));
													}
												}
											}
										} else {
											for (a in args) builtArgs.push(buildExpr(a));
										}
										final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;
										if (expectsNoArgs) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
										OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
								}
							case TField(_, FEnum(eRef, ef)):
							final en = eRef.get();

						// ocaml.List.Cons(h, t) -> h :: t
						if (isOcamlNativeEnumType(en, "List") && ef.name == "Cons" && args.length == 2) {
							OcamlExpr.EBinop(OcamlBinop.Cons, buildExpr(args[0]), buildExpr(args[1]));
						} else if (isOcamlNativeEnumType(en, "List") && ef.name == "Nil" && args.length == 0) {
							OcamlExpr.EList([]);
						} else if (args.length > 1) {
							// Enum constructors with multiple args take a tuple in OCaml: `C (a, b)`.
							OcamlExpr.EApp(buildExpr(fn), [OcamlExpr.ETuple(args.map(buildExpr))]);
							} else {
								OcamlExpr.EApp(buildExpr(fn), args.map(buildExpr));
							}
							case _:
								final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (TypeTools.follow(fn.t)) {
									case TFun(fargs, _): fargs;
									case _: null;
								}
								inline function hxNullForType(t:Type):OcamlExpr {
									return nullablePrimitiveKind(t) != null
										? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")
										: OcamlExpr.EApp(
											OcamlExpr.EIdent("Obj.magic"),
											[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
										);
								}
								final builtArgs:Array<OcamlExpr> = [];
								if (expectedArgs != null) {
									for (i in 0...args.length) {
										builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
									}
									if (args.length < expectedArgs.length) {
										for (i in args.length...expectedArgs.length) {
											final ea = expectedArgs[i];
											if (!ea.opt) {
												#if macro
												guardrailError(
													"reflaxe.ocaml: call is missing required argument '" + ea.name + "'.",
													e.pos
												);
												#end
												builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
											} else {
												builtArgs.push(hxNullForType(ea.t));
											}
										}
									}
								} else {
									for (a in args) builtArgs.push(buildExpr(a));
								}
								final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;
								if (expectsNoArgs) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
								OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
						}
						}
					}
				case TField(obj, fa):
				buildField(obj, fa, e.pos);
			case TMeta(_, e1):
				buildExpr(e1);
			case TCast(e1, _):
				// Haxe uses casts for nullable primitive flows (boxing/unboxing + flow typing).
				//
				// We represent:
				// - `Null<Int>/Null<Float>/Null<Bool>` as `Obj.t` (null is `HxRuntime.hx_null`).
				// - Non-null primitives as `Obj.repr <prim>` when assigned to nullable slots.
				//
				// So we must explicitly box/unbox at cast boundaries.
				switch ({ from: nullablePrimitiveKind(e1.t), to: nullablePrimitiveKind(e.t) }) {
					case { from: null, to: "int" } if (isIntType(e1.t)):
						{
							final inner = buildExpr(e1);
							// Avoid double-boxing: `Obj.repr (Obj.repr x)` is not a valid `Null<Int>` value.
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case { from: null, to: "float" } if (isFloatType(e1.t)):
						{
							final inner = buildExpr(e1);
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case { from: null, to: "float" } if (isIntType(e1.t)):
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
							[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(e1)])]
						);
					case { from: null, to: "bool" } if (isBoolType(e1.t)):
						{
							final inner = buildExpr(e1);
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case { from: "int", to: null } if (isIntType(e.t)):
						safeUnboxNullableInt(buildExpr(e1));
					case { from: "float", to: null } if (isFloatType(e.t)):
						safeUnboxNullableFloat(buildExpr(e1));
					case { from: "bool", to: null } if (isBoolType(e.t)):
						safeUnboxNullableBool(buildExpr(e1));
						case _:
							{
								// `Null<Enum>` is represented as `Obj.t` (null is `HxRuntime.hx_null`).
								// When Haxe inserts a cast to a non-null enum (often after a null-check),
								// we must unbox explicitly so downstream pattern matches typecheck.
								final fromU = unwrapNullType(e1.t);
								final toU = unwrapNullType(e.t);
								final nullableEnumCast = (fromU != e1.t) && (switch (TypeTools.follow(fromU)) {
									case TEnum(_, _): true;
									case _: false;
								}) && (switch (TypeTools.follow(toU)) {
									case TEnum(_, _): true;
									case _: false;
								});
								if (nullableEnumCast) {
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(e1)]);
								} else {
									// Dynamic-like -> concrete casts: `Any` / `Dynamic` / HxAnon-backed `TAnonymous`
									// values are represented as `Obj.t`. To cast to a concrete OCaml type we must
									// unbox with `Obj.obj`.
									final fromDynLike = switch (followNoAbstracts(unwrapNullType(e1.t))) {
										case TDynamic(_):
											true;
										case TAbstract(_, _) if (isStdAnyAbstract(e1.t)):
											true;
										case TAnonymous(_) if (shouldAnonUseHxAnon(e1.t)):
											true;
										case _:
											false;
									}
									final toConcrete = switch (followNoAbstracts(unwrapNullType(e.t))) {
										case TInst(_, _), TEnum(_, _):
											true;
										case _:
											false;
									}
									(fromDynLike && toConcrete)
										? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(e1)])
										: buildExpr(e1);
								}
							}
					}
			case TEnumParameter(enumValueExpr, ef, index):
				final key = ef.name + ":" + index;
				if (currentEnumParamNames != null && currentEnumParamNames.exists(key)) {
					OcamlExpr.EIdent(currentEnumParamNames.get(key));
				} else {
					final unwrappedType = unwrapNullType(enumValueExpr.t);
					final isNullable = unwrappedType != enumValueExpr.t;
					final enumType:Null<EnumType> = switch (unwrappedType) {
						case TEnum(eRef, _): eRef.get();
						case _: null;
					}
					if (enumType == null) {
						OcamlExpr.EConst(OcamlConst.CUnit);
					} else {
						final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
							ef.name;
						} else if (isOcamlNativeEnumType(enumType, "List")) {
							ef.name == "Nil" ? "[]" : (ef.name == "Cons" ? "::" : ef.name);
						} else {
							final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;
							isSameModule ? ef.name : (moduleIdToOcamlModuleName(enumType.module) + "." + ef.name);
						}

						final argCount = switch (ef.type) {
							case TFun(args, _): args.length;
							case _: 0;
						}
						if (index < 0 || index >= argCount) {
							OcamlExpr.EConst(OcamlConst.CUnit);
						} else {
							final wanted = freshTmp("enum_param");
							final patArgs:Array<OcamlPat> = [];
							for (i in 0...argCount) {
								patArgs.push(i == index ? OcamlPat.PVar(wanted) : OcamlPat.PAny);
							}
							final scrutRaw = buildExpr(enumValueExpr);
							final scrut = isNullable
								? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [scrutRaw])
								: scrutRaw;

							final matchExpr = OcamlExpr.EMatch(scrut, [
								{ pat: OcamlPat.PConstructor(ctorName, patArgs), guard: null, expr: OcamlExpr.EIdent(wanted) },
								{
									pat: OcamlPat.PAny,
									guard: null,
									expr: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))])
								}
							]);

							if (isNullable) {
								final tmp = freshTmp("enum_param");
								final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
								OcamlExpr.ELet(
									tmp,
									scrutRaw,
									OcamlExpr.EIf(
										OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
										OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))]),
										OcamlExpr.EMatch(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]), [
											{ pat: OcamlPat.PConstructor(ctorName, patArgs), guard: null, expr: OcamlExpr.EIdent(wanted) },
											{
												pat: OcamlPat.PAny,
												guard: null,
												expr: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))])
											}
										])
									),
									false
								);
							} else {
								matchExpr;
							}
						}
					}
				}
			case TEnumIndex(_):
				switch (e.expr) {
					case TEnumIndex(enumValueExpr):
						final unwrappedType = unwrapNullType(enumValueExpr.t);
						final isNullable = unwrappedType != enumValueExpr.t;
						switch (unwrappedType) {
							case TEnum(eRef, _):
								final enumType = eRef.get();
								final scrutRaw = buildExpr(enumValueExpr);
								final scrut = isNullable
									? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [scrutRaw])
									: scrutRaw;
								final modName = moduleIdToOcamlModuleName(enumType.module);
								final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;

								final ctors:Array<EnumField> = [];
								for (name in enumType.names) {
									final ef = enumType.constructs.get(name);
									if (ef != null) ctors.push(ef);
								}
								ctors.sort((a, b) -> a.index - b.index);

								final arms:Array<OcamlMatchCase> = [];
								for (ef in ctors) {
									final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
										ef.name;
									} else if (isOcamlNativeEnumType(enumType, "List")) {
										ef.name == "Nil" ? "[]" : (ef.name == "Cons" ? "::" : ef.name);
									} else {
										isSameModule ? ef.name : (modName + "." + ef.name);
									}

									final argCount = switch (ef.type) {
										case TFun(args, _): args.length;
										case _: 0;
									}
									final patArgs:Array<OcamlPat> = [];
									for (_ in 0...argCount) patArgs.push(OcamlPat.PAny);

									arms.push({
										pat: OcamlPat.PConstructor(ctorName, patArgs),
										guard: null,
										expr: OcamlExpr.EConst(OcamlConst.CInt(ef.index))
									});
								}
								if (isNullable) {
									final tmp = freshTmp("enum_idx");
									final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
									final nonNullIdx = if (arms.length == 0) {
										OcamlExpr.EConst(OcamlConst.CInt(-1));
									} else {
										OcamlExpr.EMatch(
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]),
											arms
										);
									}
									OcamlExpr.ELet(
										tmp,
										scrutRaw,
										OcamlExpr.EIf(
											OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
											OcamlExpr.EConst(OcamlConst.CInt(-1)),
											nonNullIdx
										),
										false
									);
								} else {
									// If the enum has constructors, the match is exhaustive: no default arm
									// (avoid redundant-case warnings under -warn-error).
									if (arms.length == 0) OcamlExpr.EConst(OcamlConst.CInt(-1)) else OcamlExpr.EMatch(scrut, arms);
								}
							case _:
								OcamlExpr.EConst(OcamlConst.CInt(-1));
						}
					case _:
						OcamlExpr.EConst(OcamlConst.CInt(-1));
				}
			case TBreak:
				if (loopDepth <= 0) {
					#if macro
					guardrailError(
						"reflaxe.ocaml: `break` is only supported inside loops.",
						e.pos
					);
					#end
					OcamlExpr.EConst(OcamlConst.CUnit);
				} else {
					OcamlExpr.ERaise(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_break"));
				}
				case TContinue:
					if (loopDepth <= 0) {
					#if macro
					guardrailError(
						"reflaxe.ocaml: `continue` is only supported inside loops.",
						e.pos
					);
					#end
					OcamlExpr.EConst(OcamlConst.CUnit);
				} else {
					OcamlExpr.ERaise(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_continue"));
				}
				case TWhile(cond, body, normalWhile):
					final condExpr = buildCondition(cond);
					final needsControl = containsLoopControl(body);
					loopDepth += 1;
					final builtBody = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(body)]);
					loopDepth -= 1;

					if (needsControl) {
						final continueCase:OcamlMatchCase = {
							pat: OcamlPat.PConstructor("HxRuntime.Hx_continue", []),
							guard: null,
							expr: OcamlExpr.EConst(OcamlConst.CUnit)
						};
						final breakCase:OcamlMatchCase = {
							pat: OcamlPat.PConstructor("HxRuntime.Hx_break", []),
							guard: null,
							expr: OcamlExpr.EConst(OcamlConst.CUnit)
						};

							final bodyWithContinue = OcamlExpr.ETry(builtBody, [continueCase]);
							final whileExpr = OcamlExpr.EWhile(condExpr, bodyWithContinue);
							final loopExpr = OcamlExpr.ETry(whileExpr, [breakCase]);

							if (!normalWhile) {
								// do { body } while (cond): execute body once, then behave like a while loop.
								//
								// Control-flow:
								// - `continue` skips to the condition check (handled by `bodyWithContinue`).
								// - `break` exits the loop without evaluating `cond` (handled by outer try).
								return OcamlExpr.ETry(OcamlExpr.ESeq([bodyWithContinue, loopExpr]), [breakCase]);
							}

							return loopExpr;
						}

						if (!normalWhile) {
							OcamlExpr.ESeq([
								builtBody,
								OcamlExpr.EWhile(condExpr, builtBody)
						]);
					} else {
						OcamlExpr.EWhile(condExpr, builtBody);
					}
			case TSwitch(scrutinee, cases, edef):
				buildSwitch(scrutinee, cases, edef, e.t);
			case TArray(arr, idx):
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"), [buildExpr(arr), buildExpr(idx)]);
			case TArrayDecl(items):
				// Haxe array literal: build runtime array and push all values.
				final tmp = freshTmp("arr");
				final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
				final seq:Array<OcamlExpr> = [];
				for (item in items) {
					seq.push(OcamlExpr.EApp(
						OcamlExpr.EIdent("ignore"),
						[OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"), [OcamlExpr.EIdent(tmp), buildExpr(item)])]
					));
				}
				seq.push(OcamlExpr.EIdent(tmp));
				OcamlExpr.ELet(tmp, create, OcamlExpr.ESeq(seq), false);
			case TObjectDecl(fields):
				// Anonymous structure literal: `{ foo: 1, bar: "x" }`.
				//
				// In OCaml we represent this as a runtime object (`HxAnon.t`) wrapped in `Obj.t`,
				// so distinct anonymous-structure types can share a uniform representation.
				final tmp = freshTmp("anon");
				final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
				final seq:Array<OcamlExpr> = [];
				for (f in fields) {
					final rhs = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(f.expr)]);
					seq.push(
						OcamlExpr.EApp(
							OcamlExpr.EIdent("ignore"),
							[
								OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
									[OcamlExpr.EIdent(tmp), OcamlExpr.EConst(OcamlConst.CString(f.name)), rhs]
								)
							]
						)
					);
				}
				seq.push(OcamlExpr.EIdent(tmp));
				OcamlExpr.ELet(tmp, create, OcamlExpr.ESeq(seq), false);
				case TThrow(expr):
					final built = buildExpr(expr);
					final kind = nullablePrimitiveKind(expr.t);
					final enumName = fullNameOfTypeEnum(expr.t);
					final nullableEnumName = isNullableEnumType(expr.t);

					// Produce the thrown payload as `Obj.t`.
					var payload:OcamlExpr;
					if (kind != null) {
						// Nullable primitives already use the `Obj.t` representation.
						payload = built;
					} else if (nullableEnumName != null) {
						// `Null<Enum>` is represented as `Obj.t`.
						payload = built;
					} else {
						switch (followNoAbstracts(unwrapNullType(expr.t))) {
							case TDynamic(_):
								// Dynamic values already use `Obj.t`.
								payload = built;
							case TAnonymous(_) if (shouldAnonUseHxAnon(expr.t)):
								// Anonymous structures represented via `HxAnon` already use `Obj.t`.
								payload = built;
							case TAbstract(_, _) if (isStdAnyAbstract(expr.t)):
								// `Std.Any` (and friends) already use `Obj.t`.
								payload = built;
							case _ if (isBoolType(expr.t)):
								// Booleans stored as `Obj.t` must be boxed to avoid int/bool ambiguity.
								payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [built]);
							case _:
								payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
						}
					}

					// Enums carried as `Obj.t` must be boxed so typed catches can recover the enum identity
					// even for constant constructors (which compile to immediates).
					if (enumName != null) {
						payload = OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
							[OcamlExpr.EConst(OcamlConst.CString(enumName)), payload]
						);
					} else if (nullableEnumName != null) {
						payload = OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
							[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), payload]
						);
					}
					final tags = throwTagsForType(expr.t);
					final tagExpr = OcamlExpr.EList(tags.map(t -> OcamlExpr.EConst(OcamlConst.CString(t))));
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "hx_throw_typed_rtti"), [payload, tagExpr]);
			case TTry(tryExpr, catches):
				if (catches.length == 0) {
					buildExpr(tryExpr);
				} else {
					final builtTry = buildExpr(tryExpr);

					inline function isDynamicCatchType(t:Type):Bool {
						return switch (followNoAbstracts(t)) {
							case TDynamic(_): true;
							case _: false;
						}
					}

					inline function isHaxeExceptionCatchType(t:Type):Bool {
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(cRef, _):
								final c = cRef.get();
								c.pack.length == 1 && c.pack[0] == "haxe" && c.name == "Exception";
							case _:
								false;
						}
					}

					inline function isHaxeValueExceptionCatchType(t:Type):Bool {
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(cRef, _):
								final c = cRef.get();
								c.pack.length == 1 && c.pack[0] == "haxe" && c.name == "ValueException";
							case _:
								false;
						}
					}

					function buildCatchChain(valueExpr:OcamlExpr, tagsExpr:OcamlExpr, fallback:OcamlExpr):OcamlExpr {
						var current = fallback;
						for (i in 0...catches.length) {
							final c = catches[catches.length - 1 - i];
							final catchVarName = renameVar(c.v.name);

							final isDynamic = isDynamicCatchType(c.v.t);
							final isHaxeException = isHaxeExceptionCatchType(c.v.t);
							final isHaxeValueException = isHaxeValueExceptionCatchType(c.v.t);
							final isEnumCatch = switch (followNoAbstracts(unwrapNullType(c.v.t))) {
								case TEnum(_, _): true;
								case _: false;
							}
							final isBoolCatch = isBoolType(c.v.t);
							final tag = catchTagForType(c.v.t);
							if (!isDynamic && !isHaxeException && !isHaxeValueException && tag == null) {
								#if macro
								guardrailError(
									"reflaxe.ocaml (M10): typed catch is not supported for this type yet; use `catch (e:Dynamic)` as a fallback for now.",
									e.pos
								);
								#end
							}

							final cond:OcamlExpr = if (isDynamic) {
								OcamlExpr.EConst(OcamlConst.CBool(true));
							} else if (isHaxeException) {
								// `haxe.Exception` is a wildcard catch in Haxe: it must catch any thrown value.
								OcamlExpr.EConst(OcamlConst.CBool(true));
							} else if (isHaxeValueException) {
								// `haxe.ValueException` catches values which do *not* extend `haxe.Exception`,
								// plus explicitly thrown `ValueException` instances.
								//
								// This matches upstream behavior where `throw 123` can be caught as either
								// `ValueException` or `Int`.
								final isValueExn = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
									[tagsExpr, OcamlExpr.EConst(OcamlConst.CString("haxe.ValueException"))]
								);
								final isAnyException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
									[tagsExpr, OcamlExpr.EConst(OcamlConst.CString("haxe.Exception"))]
								);
								OcamlExpr.EBinop(OcamlBinop.Or, isValueExn, OcamlExpr.EUnop(OcamlUnop.Not, isAnyException));
							} else if (tag != null) {
								OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
									[tagsExpr, OcamlExpr.EConst(OcamlConst.CString(tag))]
								);
							} else {
								OcamlExpr.EConst(OcamlConst.CBool(false));
							}

							var body = buildExpr(c.expr);
							final boundValue:OcamlExpr = if (isDynamic) {
								valueExpr;
							} else if (isHaxeException) {
								// If the thrown payload already extends `haxe.Exception`, bind it directly.
								// Otherwise, wrap it as `haxe.ValueException` (with `native != null`) so
								// `haxe.Exception.stack` captures the exception stack.
								final isAnyException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
									[tagsExpr, OcamlExpr.EConst(OcamlConst.CString("haxe.Exception"))]
								);
								final asException = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpr]);
								final hxNullAsException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"),
									[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
								);
								final mkValueException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("Haxe_ValueException"), "create"),
									[valueExpr, hxNullAsException, valueExpr]
								);
								final asExceptionWrapped = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"), [mkValueException]);
								OcamlExpr.EIf(isAnyException, asException, asExceptionWrapped);
							} else if (isHaxeValueException) {
								// For non-Exception throws, wrap as `ValueException` so `catch(e:ValueException)`
								// works even if the throw site is not explicitly `new ValueException(...)`.
								final isValueExn = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
									[tagsExpr, OcamlExpr.EConst(OcamlConst.CString("haxe.ValueException"))]
								);
								final asValueException = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpr]);
								final hxNullAsException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"),
									[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]
								);
								final mkValueException = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("Haxe_ValueException"), "create"),
									[valueExpr, hxNullAsException, valueExpr]
								);
								OcamlExpr.EIf(isValueExn, asValueException, mkValueException);
							} else if (isBoolCatch) {
								// Booleans might be carried as boxed `Obj.t` in dynamic contexts.
								// Unbox if needed; fall back to `Obj.obj` for typed `throw true` (immediate).
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [valueExpr]);
							} else if (isEnumCatch && tag != null) {
								final unboxed = OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
									[OcamlExpr.EConst(OcamlConst.CString(tag)), valueExpr]
								);
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [unboxed]);
							} else {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpr]);
							};
							// Always bind the catch variable.
							// Also force a use via `ignore` to avoid unused-binding warnings under `-warn-error`.
							final annotatedBoundValue = OcamlExpr.EAnnot(boundValue, typeExprFromHaxeType(c.v.t));
							body = OcamlExpr.ELet(
								catchVarName,
								annotatedBoundValue,
								OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent(catchVarName)]), body]),
								false
							);

							current = OcamlExpr.EIf(cond, body, current);
						}
						return current;
					}

					final breakCase:OcamlMatchCase = {
						pat: OcamlPat.PConstructor("HxRuntime.Hx_break", []),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_break"))
					};
					final continueCase:OcamlMatchCase = {
						pat: OcamlPat.PConstructor("HxRuntime.Hx_continue", []),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_continue"))
					};
					final returnVar = freshTmp("ret");
					final returnCase:OcamlMatchCase = {
						pat: OcamlPat.PConstructor("HxRuntime.Hx_return", [OcamlPat.PVar(returnVar)]),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_return"), [OcamlExpr.EIdent(returnVar)]))
					};

					final hxValVar = freshTmp("exn_v");
					final hxTagsVar = freshTmp("exn_tags");
					final hxFallback = OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_throw_typed"),
						[OcamlExpr.EIdent(hxValVar), OcamlExpr.EIdent(hxTagsVar)]
					);
					final hxHandlerExpr = buildCatchChain(OcamlExpr.EIdent(hxValVar), OcamlExpr.EIdent(hxTagsVar), hxFallback);
					final hxExceptionCase:OcamlMatchCase = {
						pat: OcamlPat.PConstructor("HxRuntime.Hx_exception", [OcamlPat.PVar(hxValVar), OcamlPat.PVar(hxTagsVar)]),
						guard: null,
						expr: hxHandlerExpr
					};

					final ocamlExnVar = freshTmp("exn");
					final ocamlFallback = OcamlExpr.ERaise(OcamlExpr.EIdent(ocamlExnVar));
					final ocamlHandlerExpr = buildCatchChain(
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(ocamlExnVar)]),
						OcamlExpr.EList([OcamlExpr.EConst(OcamlConst.CString("OcamlExn"))]),
						ocamlFallback
					);
					final ocamlExnCase:OcamlMatchCase = {
						pat: OcamlPat.PVar(ocamlExnVar),
						guard: null,
						expr: ocamlHandlerExpr
					};

					OcamlExpr.ETry(builtTry, [breakCase, continueCase, returnCase, hxExceptionCase, ocamlExnCase]);
				}
			case TReturn(ret):
				final valueExpr = ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
				final payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [valueExpr]);
				OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_return"), [payload]));
				case _:
					OcamlExpr.EConst(OcamlConst.CUnit);
			};

		#if macro
		if (emitSourceMap && shouldWrapPos(e)) {
			final dp = debugPosFromHaxePos(e.pos);
			return dp != null ? OcamlExpr.EPos(dp, built) : built;
		}
		#end
		return built;
	}

	function buildStdString(inner:TypedExpr):OcamlExpr {
		final e = unwrap(inner);
		// Best-effort `Std.string` for `Dynamic` / structural values carried as `Obj.t`.
		// Avoid applying this to typedef-backed anonymous structures that we represent as real OCaml records.
		switch (followNoAbstracts(e.t)) {
			case TDynamic(_):
				return OcamlExpr.EApp(
					OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_toStdString"),
					[buildExpr(e)]
				);
			case TAbstract(_, _) if (isStdAnyAbstract(e.t)):
				return OcamlExpr.EApp(
					OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_toStdString"),
					[buildExpr(e)]
				);
			case TAnonymous(_) if (shouldAnonUseHxAnon(e.t)):
				return OcamlExpr.EApp(
					OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_toStdString"),
					[buildExpr(e)]
				);
			case _:
		}

		switch (e.expr) {
			case TConst(TNull):
				return OcamlExpr.EConst(OcamlConst.CString("null"));
			case TConst(TString(_)):
				// String literals are never `null`; avoid redundant runtime wrapping.
				return buildExpr(e);
			case TBinop(OpAdd, _, _) if (isStringType(e.t)):
				// String concatenation always produces a real OCaml string (never hx_null),
				// because we convert nullable operands via `HxString.toStdString` before `^`.
				// Avoid re-wrapping the result (this prevents `HxString.toStdString (...)` nesting).
				return buildExpr(e);
			case _:
		}

		inline function toStdString(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(
				OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString"),
				[expr]
			);
		}

		return switch (e.t) {
			case TAbstract(aRef, params):
				final a = aRef.get();
				switch (a.name) {
					case "Int":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_int"), [buildExpr(e)]);
					case "Float":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_float"), [buildExpr(e)]);
					case "Bool":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_bool"), [buildExpr(e)]);
					case "Null":
						if (params != null && params.length == 1) {
							final inner = params[0];
							if (isStringType(inner)) {
								toStdString(buildExpr(e));
							} else if (isIntType(inner)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_toStdString"), [buildExpr(e)]);
							} else if (isFloatType(inner)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_float_toStdString"), [buildExpr(e)]);
							} else if (isBoolType(inner)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_bool_toStdString"), [buildExpr(e)]);
							} else {
								OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
							}
						} else {
							OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
						}
					default:
						OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
				}
			case TInst(cRef, _):
				final c = cRef.get();
				if (isStdStringClass(c)) {
					toStdString(buildExpr(e));
				} else {
					var hasToString = false;
					try {
						for (f in c.fields.get()) {
							if (f.name == "toString") {
								hasToString = true;
								break;
							}
						}
					} catch (_:Dynamic) {}

					if (hasToString) {
						final modName = moduleIdToOcamlModuleName(c.module);
						final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
						final callFn = (selfMod != null && selfMod == modName)
							? OcamlExpr.EIdent("toString")
							: OcamlExpr.EField(OcamlExpr.EIdent(modName), "toString");
						OcamlExpr.EApp(callFn, [buildExpr(e), OcamlExpr.EConst(OcamlConst.CUnit)]);
					} else {
						// Still evaluate the value (important under `-warn-error` where unused
						// parameters become hard errors in the OCaml build).
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_toStdString"),
							[OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)])]
						);
					}
				}
			case _:
				// Fallback: treat the value as `Dynamic` and stringify best-effort.
				//
				// This is important for generic code in the upstream stdlib (e.g. `StringBuf.add<T>(x:T)`),
				// which relies on string concatenation behavior even when `T` is not statically known.
				//
				// Note: this is not perfect for OCaml immediates (bool vs int), but it preserves
				// the key invariants: the value is used (avoids unused-var under -warn-error),
				// and the output is stable enough for debugging and early bootstrap workloads.
				final built = buildExpr(e);
				final asObj:OcamlExpr = (nullablePrimitiveKind(e.t) != null)
					? built
					: switch (unwrapNullType(e.t)) {
						case TDynamic(_), TAnonymous(_):
							built;
						case _:
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
					}
				;
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_toStdString"), [asObj]);
		}
	}

	function buildConst(c:TConstant):OcamlConst {
		return switch (c) {
			case TInt(v): OcamlConst.CInt(v);
			case TFloat(v): OcamlConst.CFloat(v);
			case TString(v): OcamlConst.CString(v);
			case TBool(v): OcamlConst.CBool(v);
			case TNull: OcamlConst.CUnit;
			case TThis, TSuper:
				OcamlConst.CUnit;
		}
	}

	function buildLocal(v:TVar):OcamlExpr {
		final name = renameVar(v.name);
		final isRef = isRefLocalId(v.id);
		return isRef ? OcamlExpr.EUnop(OcamlUnop.Deref, OcamlExpr.EIdent(name)) : OcamlExpr.EIdent(name);
	}

	function renameVar(name:String):String {
		final existing = ctx.variableRenameMap.get(name);
		if (existing != null) return existing;

		// `_` is a valid Haxe identifier, but in OCaml it is a wildcard (not a real binding).
		// If we emitted `_` as a value identifier, it would be unreferencable and could
		// also trigger confusing “unbound value” errors when Haxe code legitimately uses it.
		if (name == "_") {
			ctx.variableRenameMap.set(name, "_hx");
			return "_hx";
		}

		// Reflaxe has some reserved-name handling, but we still need to ensure we never emit
		// OCaml keywords as identifiers (e.g. `end`), otherwise dune builds will fail with
		// syntax errors for perfectly valid Haxe code (and even for Haxe stdlib helpers like
		// StringTools.endsWith(s, end)).
		final renamed = isOcamlReservedValueName(name) ? ("hx_" + name) : name;
		ctx.variableRenameMap.set(name, renamed);
		return renamed;
	}

	static function isOcamlReservedValueName(name:String):Bool {
		return switch (name) {
			// Keywords (OCaml 4.x)
			case "and", "as", "assert", "begin", "class", "constraint", "do", "done", "downto", "else", "end",
				"exception", "external", "false", "for", "fun", "function", "functor", "if", "in", "include",
				"inherit", "initializer", "lazy", "let", "match", "method", "module", "mutable", "new", "nonrec",
				"object", "of", "open", "or", "private", "rec", "sig", "struct", "then", "to", "true", "try",
				"type", "val", "virtual", "when", "while", "with":
				true;
			// Commonly-problematic identifiers
			case _:
				false;
		}
	}

	function buildVarDecl(v:TVar, init:Null<TypedExpr>):OcamlExpr {
		// Kept for compatibility when TVar occurs outside of a block (rare in typed output).
		// Prefer `buildBlock` handling for correct scoping.
					final initExpr = init != null ? coerceForAssignment(v.t, init) : defaultValueForType(v.t);
		final isMutable = currentMutatedLocalIds != null
			&& currentMutatedLocalIds.exists(v.id)
			&& currentMutatedLocalIds.get(v.id) == true;
		if (isMutable) {
			refLocals.set(v.id, true);
			return OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
		}
		refLocals.remove(v.id);
		return initExpr;
	}

	function defaultValueForType(t:Type):OcamlExpr {
		final anyNull:OcamlExpr = OcamlExpr.EApp(
			OcamlExpr.EIdent("Obj.magic"),
			[OcamlExpr.EConst(OcamlConst.CUnit)]
		);

		return switch (t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					case "Null":
						// Nullable primitives default to null, not a value like 0.
						switch (nullablePrimitiveKind(t)) {
							case "int", "float", "bool":
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
							case _:
								anyNull;
						}
					default: anyNull;
				}
			case TInst(cRef, _):
				final c = cRef.get();
				if (c.pack != null && c.pack.length == 0 && c.name == "String") {
					OcamlExpr.EConst(OcamlConst.CString(""));
				} else {
					anyNull;
				}
			case TEnum(_, _):
				anyNull;
			case _:
				anyNull;
		}
	}

		function buildBinop(op:Binop, e1:TypedExpr, e2:TypedExpr, resultType:Type):OcamlExpr {
		inline function isNullExpr(e:TypedExpr):Bool {
			final u = unwrap(e);
			return switch (u.expr) {
				case TConst(TNull): true;
				case _: false;
			}
		}

		inline function toStdString(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(
				OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString"),
				[expr]
			);
		}

		inline function objObj(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [expr]);
		}

		inline function toIntExpr(expr:TypedExpr):OcamlExpr {
			return nullablePrimitiveKind(expr.t) == "int" ? safeUnboxNullableInt(buildExpr(expr)) : buildExpr(expr);
		}

		inline function toFloatExpr(expr:TypedExpr):OcamlExpr {
			return switch (nullablePrimitiveKind(expr.t)) {
				case "float":
					safeUnboxNullableFloat(buildExpr(expr));
				case "int":
					OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [safeUnboxNullableInt(buildExpr(expr))]);
				case _:
					if (isIntType(expr.t)) {
						OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(expr)]);
					} else {
						buildExpr(expr);
					}
			}
		}

		function buildNullablePrimitiveEq(lhsKind:Null<String>, lhs:TypedExpr, rhsKind:Null<String>, rhs:TypedExpr):Null<OcamlExpr> {
			final kind = lhsKind != null ? lhsKind : rhsKind;
			if (kind == null) return null;

			final lhsIsNullable = lhsKind != null;
			final rhsIsNullable = rhsKind != null;

			inline function withTmp(expr:OcamlExpr, f:String->OcamlExpr):OcamlExpr {
				final tmp = freshTmp("nullable");
				return OcamlExpr.ELet(tmp, expr, f(tmp), false);
			}

			final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

			// Both nullable (only when the underlying primitive kinds match).
			if (lhsIsNullable && rhsIsNullable) {
				if (lhsKind != rhsKind) return null;

				return withTmp(buildExpr(lhs), (lName) ->
					withTmp(buildExpr(rhs), (rName) -> {
						final lId = OcamlExpr.EIdent(lName);
						final rId = OcamlExpr.EIdent(rName);
						final isLNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, lId, hxNull);
						final isRNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, rId, hxNull);
						final bothNull = OcamlExpr.EBinop(OcamlBinop.And, isLNull, isRNull);
						final rNotNull = OcamlExpr.EUnop(OcamlUnop.Not, isRNull);
						final eqPrim = OcamlExpr.EBinop(OcamlBinop.Eq, objObj(lId), objObj(rId));
						final rhsNotNullAndEq = OcamlExpr.EBinop(OcamlBinop.And, rNotNull, eqPrim);
						OcamlExpr.EIf(isLNull, bothNull, rhsNotNullAndEq);
					})
				);
			}

			// Nullable vs non-nullable primitive (best-effort, same-kind only).
			final nullableExpr = lhsIsNullable ? lhs : rhs;
			final otherExpr = lhsIsNullable ? rhs : lhs;
			final otherType = otherExpr.t;

			switch (kind) {
				case "int":
					if (!isIntType(otherType)) return null;
				case "float":
					if (!isFloatType(otherType) && !isIntType(otherType)) return null;
				case "bool":
					if (!isBoolType(otherType)) return null;
				case _:
					return null;
			}

			return withTmp(buildExpr(nullableExpr), (nName) -> {
				final nId = OcamlExpr.EIdent(nName);
				final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, nId, hxNull);
				final otherBuilt = (kind == "float" && isIntType(otherType))
					? OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(otherExpr)])
					: buildExpr(otherExpr);
				final eqPrim = OcamlExpr.EBinop(OcamlBinop.Eq, objObj(nId), otherBuilt);
				OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)), eqPrim);
			});
		}

		function buildNullablePrimitiveCompare(binop:OcamlBinop, lhs:TypedExpr, rhs:TypedExpr):Null<OcamlExpr> {
			final k1 = nullablePrimitiveKind(lhs.t);
			final k2 = nullablePrimitiveKind(rhs.t);
			final kind = k1 != null ? k1 : k2;
			if (kind == null) return null;

			// Only numeric comparisons are supported here (int/float).
			if (kind != "int" && kind != "float") return null;

			final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

			inline function withTmp(expr:OcamlExpr, f:String->OcamlExpr):OcamlExpr {
				final tmp = freshTmp("nullable");
				return OcamlExpr.ELet(tmp, expr, f(tmp), false);
			}

			// Decide which side is the nullable one (or both).
			final lhsIsNullable = k1 != null;
			final rhsIsNullable = k2 != null;

			// Reject mismatched underlying kinds when both are nullable.
			if (lhsIsNullable && rhsIsNullable && k1 != k2) return null;

			return withTmp(buildExpr(lhs), (lName) ->
				withTmp(buildExpr(rhs), (rName) -> {
					final lId = OcamlExpr.EIdent(lName);
					final rId = OcamlExpr.EIdent(rName);

					final lNull = lhsIsNullable
						? OcamlExpr.EBinop(OcamlBinop.PhysEq, lId, hxNull)
						: OcamlExpr.EConst(OcamlConst.CBool(false));
					final rNull = rhsIsNullable
						? OcamlExpr.EBinop(OcamlBinop.PhysEq, rId, hxNull)
						: OcamlExpr.EConst(OcamlConst.CBool(false));

					// Haxe semantics for comparisons involving null are target-dependent.
					// For now we choose "null => false" to avoid crashes and match common
					// "nullable used as number" patterns in bootstrapping workloads.
					final anyNull = if (lhsIsNullable && rhsIsNullable) {
						OcamlExpr.EBinop(OcamlBinop.Or, lNull, rNull);
					} else if (lhsIsNullable) {
						lNull;
					} else {
						rNull;
					}

					final lVal:OcamlExpr = lhsIsNullable ? objObj(lId) : lId;
					final rValRaw:OcamlExpr = rhsIsNullable ? objObj(rId) : rId;

					final rVal:OcamlExpr = if (kind == "float" && !rhsIsNullable && isIntType(rhs.t)) {
						// int -> float promotion (Haxe allows Int/Float comparisons)
						OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [rValRaw]);
					} else if (kind == "float" && !lhsIsNullable && isIntType(lhs.t) && rhsIsNullable) {
						// lhs is int (non-null) but kind float due to rhs:Null<Float>
						// Promote lhs when needed by caller; here keep rhs path simple.
						rValRaw;
					} else {
						rValRaw;
					}

					final lVal2:OcamlExpr = if (kind == "float" && !lhsIsNullable && isIntType(lhs.t) && !rhsIsNullable && isFloatType(rhs.t)) {
						OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [lVal]);
					} else {
						lVal;
					}

					final cmp = OcamlExpr.EBinop(binop, lVal2, rVal);
					OcamlExpr.EIf(anyNull, OcamlExpr.EConst(OcamlConst.CBool(false)), cmp);
				})
			);
		}

		inline function coerceForComparison(left:TypedExpr, right:TypedExpr):{ l:OcamlExpr, r:OcamlExpr } {
			// Haxe allows comparisons between `Int` and `Float` by promoting `Int` to `Float`.
			// OCaml requires both operands to have the same type.
			if (isFloatType(left.t) && isIntType(right.t)) {
				return { l: buildExpr(left), r: OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(right)]) };
			}
			if (isIntType(left.t) && isFloatType(right.t)) {
				return { l: OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(left)]), r: buildExpr(right) };
			}
			return { l: buildExpr(left), r: buildExpr(right) };
		}

				return switch (op) {
						case OpAssign:
							// Handle local ref assignment: x = v  ->  x := v
							switch (e1.expr) {
								case TLocal(v) if (isRefLocalId(v.id)):
								final tmp = freshTmp("assign");
								final rhs = coerceForAssignment(v.t, e2);
								OcamlExpr.ELet(
									tmp,
									rhs,
									OcamlExpr.ESeq([
										OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), OcamlExpr.EIdent(tmp)),
										OcamlExpr.EIdent(tmp)
									]),
									false
								);
							case TField(obj, FInstance(_, _, cfRef)):
								final cf = cfRef.get();
					switch (cf.kind) {
									case FVar(_, _):
										final tmp = freshTmp("assign");
										final rhs = coerceForAssignment(e1.t, e2);
										OcamlExpr.ELet(
											tmp,
											rhs,
											OcamlExpr.ESeq([
												OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(buildExpr(obj), cf.name), OcamlExpr.EIdent(tmp)),
												OcamlExpr.EIdent(tmp)
											]),
											false
											);
										case _:
											OcamlExpr.EConst(OcamlConst.CUnit);
									}
								case TField(_, FStatic(clsRef, cfRef)):
									final cls = clsRef.get();
									final cf = cfRef.get();
									final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
									final isMutableStatic = switch (cf.kind) {
										case FVar(_, _): ctx.mutableStaticFields.exists(key) && ctx.mutableStaticFields.get(key) == true;
										case _: false;
									}
									if (!isMutableStatic) {
										#if macro
										guardrailError(
											"reflaxe.ocaml (M6): assignment to immutable static field '" + key + "' is not supported yet.",
											e1.pos
										);
										#end
										OcamlExpr.EConst(OcamlConst.CUnit);
									} else {
										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final modName = moduleIdToOcamlModuleName(cls.module);
										final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
										final lhsCell = (selfMod != null && selfMod == modName)
											? OcamlExpr.EIdent(scoped)
											: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
										final tmp = freshTmp("assign");
										final rhs = coerceForAssignment(e1.t, e2);
										OcamlExpr.ELet(
											tmp,
											rhs,
											OcamlExpr.ESeq([
												OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, OcamlExpr.EIdent(tmp)),
												OcamlExpr.EIdent(tmp)
											]),
											false
										);
									}
								case TField(obj, FAnon(cfRef)):
									final cf = cfRef.get();
									switch (cf.name) {
										case "key", "value", "hasNext", "next":
											OcamlExpr.EConst(OcamlConst.CUnit);
									case _:
										if (isSysFileStatAnon(obj.t)) {
											OcamlExpr.EConst(OcamlConst.CUnit);
										} else {
											final tmp = freshTmp("assign");
											final rhs = coerceForAssignment(e1.t, e2);
											final rhsObj = OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
												[OcamlExpr.EIdent(tmp)]
											);
											OcamlExpr.ELet(
												tmp,
												rhs,
												OcamlExpr.ESeq([
													OcamlExpr.EApp(
														OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
														[buildExpr(obj), OcamlExpr.EConst(OcamlConst.CString(cf.name)), rhsObj]
													),
													OcamlExpr.EIdent(tmp)
												]),
												false
											);
										}
								}
							case TField(obj, FDynamic(name)):
								final tmp = freshTmp("assign");
								final rhs = coerceForAssignment(e1.t, e2);
								final rhsObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(tmp)]);
								OcamlExpr.ELet(
									tmp,
									rhs,
									OcamlExpr.ESeq([
										OcamlExpr.EApp(
											OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
											[
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(obj)]),
												OcamlExpr.EConst(OcamlConst.CString(name)),
												rhsObj
											]
										),
										OcamlExpr.EIdent(tmp)
									]),
									false
								);
							case TArray(arr, idx):
								final tmp = freshTmp("assign");
								final rhs = coerceForAssignment(e1.t, e2);
								OcamlExpr.ELet(
									tmp,
									rhs,
									// `HxArray.set` already returns the assigned value, matching Haxe's
									// assignment-expression semantics (`a[i] = v` evaluates to `v`).
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
										[buildExpr(arr), buildExpr(idx), OcamlExpr.EIdent(tmp)]
									),
									false
								);
							case _:
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
				case OpAssignOp(inner):
						// Handle compound assignment for ref locals:
						// x += v  ->  x := (!x) + v
						switch (e1.expr) {
							case TLocal(v) if (isRefLocalId(v.id)):
						final lhs = buildLocal(v);
						final floatMode = isFloatType(v.t) || nullablePrimitiveKind(v.t) == "float";
						final rhs = switch (inner) {
							case OpAdd:
								if (isStringType(v.t) || isStringType(e2.t)) {
									OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
								} else if (floatMode) {
									OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
								} else {
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
								}
							case OpSub:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.SubF, lhs, toFloatExpr(e2))
									: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
							case OpMult:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.MulF, lhs, toFloatExpr(e2))
									: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
							case OpDiv:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.DivF, lhs, toFloatExpr(e2))
									: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
							case OpMod:
								floatMode
									? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [lhs, toFloatExpr(e2)])
									: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
							case OpAnd:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
							case OpOr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
							case OpXor:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
							case OpShl:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
							case OpShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
							case OpUShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
							case _: OcamlExpr.EConst(OcamlConst.CUnit);
						}
								OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), rhs);
							case TField(_, FStatic(clsRef, cfRef)):
								final cls = clsRef.get();
								final cf = cfRef.get();
								final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
								final isMutableStatic = switch (cf.kind) {
									case FVar(_, _): ctx.mutableStaticFields.exists(key) && ctx.mutableStaticFields.get(key) == true;
									case _: false;
								}
								if (!isMutableStatic) {
									#if macro
									guardrailError(
										"reflaxe.ocaml (M6): compound assignment to immutable static field '" + key + "' is not supported yet.",
										e1.pos
									);
									#end
									OcamlExpr.EConst(OcamlConst.CUnit);
								} else {
									final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
									final modName = moduleIdToOcamlModuleName(cls.module);
									final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
									final lhsCell = (selfMod != null && selfMod == modName)
										? OcamlExpr.EIdent(scoped)
										: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
									final lhs = OcamlExpr.EUnop(OcamlUnop.Deref, lhsCell);
									final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
									final rhs = switch (inner) {
										case OpAdd:
											if (isStringType(e1.t) || isStringType(e2.t)) {
												OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
											} else if (floatMode) {
												OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
											} else {
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
											}
										case OpSub:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.SubF, lhs, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
										case OpMult:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.MulF, lhs, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
										case OpDiv:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.DivF, lhs, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
										case OpMod:
											floatMode
												? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [lhs, toFloatExpr(e2)])
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
										case OpAnd:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
										case OpOr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
										case OpXor:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
										case OpShl:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
										case OpShr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
										case OpUShr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
										case _: OcamlExpr.EConst(OcamlConst.CUnit);
									}
									OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, rhs);
								}
							case TField(obj, FInstance(_, _, cfRef)):
								final cf = cfRef.get();
								switch (cf.kind) {
								case FVar(_, _):
									// Support compound assignment on instance vars (notably used by
									// inline-stdlib code like `StringBuf.add`, which lowers to `b += x`).
									//
									// We avoid re-evaluating the receiver expression by binding it once.
									final recvTmp = freshTmp("recv");
									final recvExpr = buildExpr(obj);
									final lhsField = OcamlExpr.EField(OcamlExpr.EIdent(recvTmp), cf.name);
									final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
									final rhs = switch (inner) {
										case OpAdd:
											if (isStringType(e1.t) || isStringType(e2.t)) {
												OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhsField), buildStdString(e2));
											} else if (floatMode) {
												OcamlExpr.EBinop(OcamlBinop.AddF, lhsField, toFloatExpr(e2));
											} else {
												OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhsField, toIntExpr(e2)]);
											}
										case OpSub:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.SubF, lhsField, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhsField, toIntExpr(e2)]);
										case OpMult:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.MulF, lhsField, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhsField, toIntExpr(e2)]);
										case OpDiv:
											floatMode
												? OcamlExpr.EBinop(OcamlBinop.DivF, lhsField, toFloatExpr(e2))
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhsField, toIntExpr(e2)]);
										case OpMod:
											floatMode
												? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [lhsField, toFloatExpr(e2)])
												: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhsField, toIntExpr(e2)]);
										case OpAnd:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhsField, toIntExpr(e2)]);
										case OpOr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhsField, toIntExpr(e2)]);
										case OpXor:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhsField, toIntExpr(e2)]);
										case OpShl:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhsField, toIntExpr(e2)]);
										case OpShr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhsField, toIntExpr(e2)]);
										case OpUShr:
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhsField, toIntExpr(e2)]);
										case _:
											OcamlExpr.EConst(OcamlConst.CUnit);
									}
									OcamlExpr.ELet(
										recvTmp,
										recvExpr,
										OcamlExpr.EAssign(OcamlAssignOp.FieldSet, lhsField, rhs),
										false
									);
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
						case TArray(arr, idx):
							// a[i] += v  ->  set a i ((get a i) + v)
							final arrExpr = buildExpr(arr);
							final idxExpr = buildExpr(idx);
							final tmpArr = freshTmp("arr");
							final tmpIdx = freshTmp("idx");
							final lhs = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"), [OcamlExpr.EIdent(tmpArr), OcamlExpr.EIdent(tmpIdx)]);
							final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
							final rhs = switch (inner) {
								case OpAdd:
									if (isStringType(e1.t) || isStringType(e2.t)) {
										OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
									} else if (floatMode) {
										OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
									} else {
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
									}
								case OpSub:
									floatMode
										? OcamlExpr.EBinop(OcamlBinop.SubF, lhs, toFloatExpr(e2))
										: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
								case OpMult:
									floatMode
										? OcamlExpr.EBinop(OcamlBinop.MulF, lhs, toFloatExpr(e2))
										: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
								case OpDiv:
									floatMode
										? OcamlExpr.EBinop(OcamlBinop.DivF, lhs, toFloatExpr(e2))
										: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
								case OpMod:
									floatMode
										? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [lhs, toFloatExpr(e2)])
										: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
								case OpAnd:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
								case OpOr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
								case OpXor:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
								case OpShl:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
								case OpShr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
								case OpUShr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
							final setExpr = OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
								[OcamlExpr.EIdent(tmpArr), OcamlExpr.EIdent(tmpIdx), rhs]
							);
							OcamlExpr.ELet(tmpArr, arrExpr, OcamlExpr.ELet(tmpIdx, idxExpr, setExpr, false), false);
						case _:
							OcamlExpr.EConst(OcamlConst.CUnit);
					}
			case OpAdd:
				if (isStringType(e1.t) || isStringType(e2.t) || isStringType(resultType)) {
					// Haxe string concat: always uses `Std.string` semantics on both sides
					// (e.g. `"x" + null == "xnull"`).
					function collectConcatParts(expr:TypedExpr, out:Array<TypedExpr>):Void {
						final u = unwrap(expr);
						switch (u.expr) {
							case TBinop(OpAdd, a, b) if (isStringType(u.t) || isStringType(a.t) || isStringType(b.t)):
								collectConcatParts(a, out);
								collectConcatParts(b, out);
							case _:
								out.push(expr);
						}
					}

					final parts:Array<TypedExpr> = [];
					collectConcatParts(e1, parts);
					collectConcatParts(e2, parts);

					var acc:OcamlExpr = buildStdString(parts[0]);
					for (i in 1...parts.length) {
						acc = OcamlExpr.EBinop(OcamlBinop.Concat, acc, buildStdString(parts[i]));
					}
					acc;
				} else {
					final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
					if (floatMode) {
						OcamlExpr.EBinop(OcamlBinop.AddF, toFloatExpr(e1), toFloatExpr(e2));
					} else {
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [toIntExpr(e1), toIntExpr(e2)]);
					}
				}
			case OpSub:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.SubF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpMult:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.MulF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpDiv:
				// Haxe `/` always produces Float (Int/Int => Float). OCaml needs `/.` with
				// float operands, so we promote ints as needed.
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.DivF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpMod:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [toFloatExpr(e1), toFloatExpr(e2)]);
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpAnd:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpOr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpXor:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpShl:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpShr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpUShr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpEq:
				// Null checks must use physical equality (==) so we don't accidentally invoke
				// specialized structural equality (notably for strings).
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysEq, buildExpr(e1), buildExpr(e2));
				} else {
					inline function toDynamicObj(e:TypedExpr):OcamlExpr {
						if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null) return buildExpr(e);
						final enumName = fullNameOfTypeEnum(e.t);
						final nullableEnumName = isNullableEnumType(e.t);

						// Map `Null<String>` sentinel to the canonical `hx_null` when crossing into `Obj.t`
						// comparisons by relying on `HxRuntime.dynamic_equals` to treat the sentinel as null.
						if (isBoolType(e.t)) {
							return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(e)]);
						}

						var obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)]);
						if (enumName != null) {
							obj = OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]
							);
						} else if (nullableEnumName != null) {
							obj = OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]
							);
						}
						return obj;
					}

					if (isDynamicLike(e1.t) || isDynamicLike(e2.t)) {
						return OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_equals"),
							[toDynamicObj(e1), toDynamicObj(e2)]
						);
					}

					inline function shouldUsePhysicalEq(t:Type):Bool {
						if (isStringType(t) || nullablePrimitiveKind(t) != null) return false;
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(_, _): true; // class instances use reference equality in Haxe
							case TAnonymous(_):
								// Anonymous structures compare by identity in Haxe.
								// Use physical equality, but avoid double-boxing `HxAnon` values (handled above).
								!shouldAnonUseHxAnon(t);
							case TFun(_, _): true; // functions compare by identity in Haxe
							case _: false;
						}
					}

					final k1 = nullablePrimitiveKind(e1.t);
					final k2 = nullablePrimitiveKind(e2.t);
					final primEq = buildNullablePrimitiveEq(k1, e1, k2, e2);
					if (primEq != null) {
						primEq;
					} else if (isStringType(e1.t) || isStringType(e2.t)) {
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "equals"),
							[buildExpr(e1), buildExpr(e2)]
						);
					} else if (shouldUsePhysicalEq(e1.t) || shouldUsePhysicalEq(e2.t)) {
						OcamlExpr.EBinop(
							OcamlBinop.PhysEq,
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e2)])
						);
					} else {
						OcamlExpr.EBinop(OcamlBinop.Eq, buildExpr(e1), buildExpr(e2));
					}
				}
			case OpNotEq:
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysNeq, buildExpr(e1), buildExpr(e2));
				} else {
					inline function toDynamicObj(e:TypedExpr):OcamlExpr {
						if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null) return buildExpr(e);
						final enumName = fullNameOfTypeEnum(e.t);
						final nullableEnumName = isNullableEnumType(e.t);

						if (isBoolType(e.t)) {
							return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(e)]);
						}

						var obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)]);
						if (enumName != null) {
							obj = OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]
							);
						} else if (nullableEnumName != null) {
							obj = OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]
							);
						}
						return obj;
					}

					if (isDynamicLike(e1.t) || isDynamicLike(e2.t)) {
						return OcamlExpr.EUnop(
							OcamlUnop.Not,
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_equals"),
								[toDynamicObj(e1), toDynamicObj(e2)]
							)
						);
					}

					inline function shouldUsePhysicalEq(t:Type):Bool {
						if (isStringType(t) || nullablePrimitiveKind(t) != null) return false;
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(_, _): true;
							case TAnonymous(_): !shouldAnonUseHxAnon(t);
							case TFun(_, _): true;
							case _: false;
						}
					}

					final k1 = nullablePrimitiveKind(e1.t);
					final k2 = nullablePrimitiveKind(e2.t);
					final primEq = buildNullablePrimitiveEq(k1, e1, k2, e2);
					if (primEq != null) {
						OcamlExpr.EUnop(OcamlUnop.Not, primEq);
					} else if (isStringType(e1.t) || isStringType(e2.t)) {
						OcamlExpr.EUnop(
							OcamlUnop.Not,
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "equals"),
								[buildExpr(e1), buildExpr(e2)]
							)
						);
					} else if (shouldUsePhysicalEq(e1.t) || shouldUsePhysicalEq(e2.t)) {
						OcamlExpr.EBinop(
							OcamlBinop.PhysNeq,
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e2)])
						);
					} else {
						OcamlExpr.EBinop(OcamlBinop.Neq, buildExpr(e1), buildExpr(e2));
					}
				}
			case OpLt:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Lt, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Lt, c.l, c.r);
				}
			case OpLte:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Lte, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Lte, c.l, c.r);
				}
			case OpGt:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Gt, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Gt, c.l, c.r);
				}
			case OpGte:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Gte, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Gte, c.l, c.r);
				}
			case OpBoolAnd: OcamlExpr.EBinop(OcamlBinop.And, buildExpr(e1), buildExpr(e2));
			case OpBoolOr: OcamlExpr.EBinop(OcamlBinop.Or, buildExpr(e1), buildExpr(e2));
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
			}
		}

	function coerceNullableIntToInt(value:TypedExpr):OcamlExpr {
		return nullablePrimitiveKind(value.t) == "int" ? safeUnboxNullableInt(buildExpr(value)) : buildExpr(value);
	}

	function safeUnboxNullableInt(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_int");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(
			tmp,
			expr,
			OcamlExpr.EIf(
				OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
				OcamlExpr.EConst(OcamlConst.CInt(0)),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
			),
			false
		);
	}

	function safeUnboxNullableFloat(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_float");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(
			tmp,
			expr,
			OcamlExpr.EIf(
				OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
				OcamlExpr.EConst(OcamlConst.CFloat("0.")),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
			),
			false
		);
	}

	function safeUnboxNullableBool(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_bool");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(
			tmp,
			expr,
			OcamlExpr.EIf(
				OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
				OcamlExpr.EConst(OcamlConst.CBool(false)),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [OcamlExpr.EIdent(tmp)])
			),
			false
		);
	}

	function coerceForAssignment(lhsType:Type, rhs:TypedExpr):OcamlExpr {
		final lhsKind = nullablePrimitiveKind(lhsType);
		final rhsKind = nullablePrimitiveKind(rhs.t);

		// Dynamic / anonymous slots: represent arbitrary values as `Obj.t`.
		//
		// This is required for patterns like:
		//   `final d:Dynamic = new Child();`
		//
		// Without boxing (`Obj.repr`), OCaml infers `d` as `child_t`, which then fails when
		// passed to runtime APIs expecting `Obj.t` (e.g. `Type.getClass(d)`).
		//
		// Important: anonymous structures already use the `HxAnon` runtime representation (`Obj.t`),
		// so we must *not* double-box those.
		final lhsUnwrapped = unwrapNullType(lhsType);
		switch (followNoAbstracts(lhsUnwrapped)) {
			case TDynamic(_):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				// Enums stored as `Obj.t` must be boxed to preserve enum identity at runtime.
				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]
					);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]
					);
				}
				// Booleans stored as `Obj.t` must be boxed to avoid int/bool ambiguity.
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case TAbstract(_, _) if (isStdAnyAbstract(lhsUnwrapped)):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]
					);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]
					);
				}
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case TAnonymous(_) if (shouldAnonUseHxAnon(lhsUnwrapped)):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]
					);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]
					);
				}
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case _:
		}

		// Non-null primitive slot <- nullable primitive value.
		if (lhsKind == null && rhsKind != null) {
			return switch (rhsKind) {
				case "int" if (isIntType(lhsType)):
					safeUnboxNullableInt(buildExpr(rhs));
				case "float" if (isFloatType(lhsType)):
					safeUnboxNullableFloat(buildExpr(rhs));
				case "bool" if (isBoolType(lhsType)):
					safeUnboxNullableBool(buildExpr(rhs));
				case _:
					buildExpr(rhs);
			}
		}

		// Nullable primitive slot <- non-null primitive value.
		if (lhsKind != null && rhsKind == null) {
			return switch (lhsKind) {
				case "int" if (isIntType(rhs.t)):
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				case "float" if (isFloatType(rhs.t)):
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				case "float" if (isIntType(rhs.t)):
					OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
						[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(rhs)])]
					);
				case "bool" if (isBoolType(rhs.t)):
					// Box bools to avoid int/bool ambiguity when carried as `Obj.t`.
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				case _:
					buildExpr(rhs);
			}
		}

			// Float slots can accept Int values (promote).
			if (isFloatType(lhsType) && isIntType(rhs.t)) {
				return OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(rhs)]);
			}

			// Nullable enum slot (Obj.t) <- enum value
			//
			// We represent `Null<Enum>` as `Obj.t` so we can carry the `hx_null` sentinel.
			// Passing an enum value to a parameter typed as `Null<Enum>` should therefore
			// box with `Obj.repr` (unless the value is literally `null`).
			final lhsNullEnumName:Null<String> = switch (followNoAbstracts(lhsType)) {
				case TAbstract(aRef, [inner]) if ((aRef.get().pack ?? []).length == 0 && aRef.get().name == "Null"):
					switch (TypeTools.follow(inner)) {
						case TEnum(eRef, _):
							final e = eRef.get();
							(e.pack ?? []).concat([e.name]).join(".");
						case _:
							null;
					}
				case _:
					null;
			}
			if (lhsNullEnumName != null) {
				// Only box when RHS is a *non-null* enum value.
				// If RHS is already `Null<Enum>` (i.e. already `Obj.t`), boxing would double-wrap.
				final rhsWasNullable = unwrapNullType(rhs.t) != rhs.t;
				final rhsEnumName:Null<String> = (!rhsWasNullable) ? switch (TypeTools.follow(rhs.t)) {
					case TEnum(eRef, _):
						final e = eRef.get();
						(e.pack ?? []).concat([e.name]).join(".");
					case _:
						null;
				} : null;
				if (rhsEnumName != null) {
					final rhsUnwrapped = unwrap(rhs);
					final rhsIsNull = switch (rhsUnwrapped.expr) {
						case TConst(TNull): true;
						case _: false;
					}
					if (rhsIsNull) {
						return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
					}
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(
						OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]
					);
				}
			}

			// Nullable enum (Obj.t) -> enum value
			//
			// We represent `Null<Enum>` as `Obj.t` to carry the `hx_null` sentinel safely.
			// When Haxe flow-typing refines a nullable enum to a non-null enum (e.g. after
		// `if (e != null)`), it often passes that value to functions expecting `Enum`,
		// without inserting an explicit cast expression.
		//
		// At those callsites we must unbox (`Obj.obj`) to satisfy OCaml typing.
		final lhsEnumName:Null<String> = switch (TypeTools.follow(lhsType)) {
			case TEnum(eRef, _):
				final e = eRef.get();
				(e.pack ?? []).concat([e.name]).join(".");
			case _:
				null;
		}
		if (lhsEnumName != null) {
			final rhsU = unwrapNullType(rhs.t);
			final rhsEnumName:Null<String> = switch (TypeTools.follow(rhsU)) {
				case TEnum(eRef, _):
					final e = eRef.get();
					(e.pack ?? []).concat([e.name]).join(".");
				case _:
					null;
			}
			if (rhsEnumName != null && rhsEnumName == lhsEnumName && rhsU != rhs.t) {
				final unboxed = OcamlExpr.EApp(
					OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
					[OcamlExpr.EConst(OcamlConst.CString(lhsEnumName)), buildExpr(rhs)]
				);
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [unboxed]);
			}
		}

		// Class upcasts (inheritance + interfaces): Derived -> Base or Impl -> IFace
		// requires an explicit cast at the OCaml type level.
		final lhsCls = classTypeFromType(lhsType);
		final rhsCls = classTypeFromType(rhs.t);
		if (lhsCls != null && rhsCls != null) {
			final lhsName = (lhsCls.pack ?? []).concat([lhsCls.name]).join(".");
			final rhsName = (rhsCls.pack ?? []).concat([rhsCls.name]).join(".");
			if (lhsName != rhsName) {
				if (isSubclassOf(rhsCls, lhsCls)) {
					return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
				}
				if (lhsCls.isInterface && implementsInterface(rhsCls, lhsCls)) {
					return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
				}
			}
		}

		return buildExpr(rhs);
	}

		function buildUnop(op:Unop, postFix:Bool, e:TypedExpr, resultType:Type):OcamlExpr {
			return switch (op) {
				case OpNot:
					OcamlExpr.EUnop(OcamlUnop.Not, buildExpr(e));
				case OpNegBits:
					final kind = nullablePrimitiveKind(e.t);
					final v = kind == "int" ? safeUnboxNullableInt(buildExpr(e)) : buildExpr(e);
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "lognot"), [v]);
				case OpNeg:
					if (isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float") {
						OcamlExpr.EUnop(OcamlUnop.Neg, buildExpr(e));
					} else {
						final kind = nullablePrimitiveKind(e.t);
						final v = kind == "int" ? safeUnboxNullableInt(buildExpr(e)) : buildExpr(e);
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "neg"), [v]);
					}
				case OpIncrement, OpDecrement:
				// ++x / x++ / --x / x--:
				//
				// Haxe semantics:
				// - prefix: ++x returns the updated value
				// - postfix: x++ returns the old value
				//
				// We support:
				// - ref locals (`let x = ref ...`)
				// - instance var fields (record fields on `t`)
				// - array elements (`HxArray.get/set`)
				final lvalueNullableKind = nullablePrimitiveKind(e.t);
				final kind = if (isIntType(e.t)) {
					"int";
				} else if (isFloatType(e.t)) {
					"float";
				} else if (lvalueNullableKind != null) {
					lvalueNullableKind;
				} else {
					null;
				}

				final resultNullableKind = nullablePrimitiveKind(resultType);
				final resultIsNullable = resultNullableKind != null;

				if (kind == null || kind == "bool") {
					#if macro
					guardrailError("reflaxe.ocaml (M10): ++/-- is only supported for Int/Float (and their nullable forms) for now.", e.pos);
					#end
					OcamlExpr.EConst(OcamlConst.CUnit);
				} else {
					final lvalueIsNullable = lvalueNullableKind != null;
					final deltaInt = op == OpIncrement ? 1 : -1;
					final deltaFloatLiteral = op == OpIncrement ? "1." : "-1.";
					final deltaPrimExpr = kind == "float"
						? OcamlExpr.EConst(OcamlConst.CFloat(deltaFloatLiteral))
						: OcamlExpr.EConst(OcamlConst.CInt(deltaInt));

					inline function incDec(getOldRep:OcamlExpr, setNewRep:OcamlExpr->OcamlExpr):OcamlExpr {
						// Fast path: non-null primitive lvalue with non-null primitive result.
						// Keep generated OCaml compact and stable for existing Int-only code.
						if (!lvalueIsNullable && !resultIsNullable) {
							final oldName = freshTmp("old");
							final newName = freshTmp("new");
							final updated = kind == "float"
								? OcamlExpr.EBinop(OcamlBinop.AddF, OcamlExpr.EIdent(oldName), deltaPrimExpr)
								: OcamlExpr.EApp(
									OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"),
									[OcamlExpr.EIdent(oldName), deltaPrimExpr]
								);
							final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNewRep(OcamlExpr.EIdent(newName))]);
							final resultName = postFix ? oldName : newName;
							return OcamlExpr.ELet(
								oldName,
								getOldRep,
								OcamlExpr.ELet(
									newName,
									updated,
									OcamlExpr.ESeq([setExpr, OcamlExpr.EIdent(resultName)]),
									false
								),
								false
							);
						}

						final oldRepName = freshTmp("old");
						final oldPrimName = freshTmp("oldp");
						final newPrimName = freshTmp("newp");
						final newRepName = freshTmp("new");

						final oldPrimExpr:OcamlExpr = if (lvalueIsNullable) {
							kind == "float"
								? safeUnboxNullableFloat(OcamlExpr.EIdent(oldRepName))
								: safeUnboxNullableInt(OcamlExpr.EIdent(oldRepName));
						} else {
							OcamlExpr.EIdent(oldRepName);
						}

						final newPrimExpr = kind == "float"
							? OcamlExpr.EBinop(OcamlBinop.AddF, OcamlExpr.EIdent(oldPrimName), deltaPrimExpr)
							: OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"),
								[OcamlExpr.EIdent(oldPrimName), deltaPrimExpr]
							);
						final newRepExpr:OcamlExpr = lvalueIsNullable
							? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(newPrimName)])
							: OcamlExpr.EIdent(newPrimName);

						final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNewRep(OcamlExpr.EIdent(newRepName))]);

						final resultExpr:OcamlExpr = resultIsNullable
							? (postFix ? OcamlExpr.EIdent(oldRepName) : OcamlExpr.EIdent(newRepName))
							: (postFix ? OcamlExpr.EIdent(oldPrimName) : OcamlExpr.EIdent(newPrimName));

						return OcamlExpr.ELet(
							oldRepName,
							getOldRep,
							OcamlExpr.ELet(
								oldPrimName,
								oldPrimExpr,
								OcamlExpr.ELet(
									newPrimName,
									newPrimExpr,
									OcamlExpr.ELet(
										newRepName,
										newRepExpr,
										OcamlExpr.ESeq([setExpr, resultExpr]),
										false
									),
									false
								),
								false
							),
							false
						);
					}

						switch (e.expr) {
							case TLocal(v) if (isRefLocalId(v.id)):
								incDec(
									buildLocal(v),
									(newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), newVal)
								);
							case TField(_, FStatic(clsRef, cfRef)):
								final cls = clsRef.get();
								final cf = cfRef.get();
								final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
								final isMutableStatic = switch (cf.kind) {
									case FVar(_, _): ctx.mutableStaticFields.exists(key) && ctx.mutableStaticFields.get(key) == true;
									case _: false;
								}
								if (!isMutableStatic) {
									#if macro
									guardrailError("reflaxe.ocaml (M10): ++/-- on immutable static field '" + key + "' is not supported yet.", e.pos);
									#end
									OcamlExpr.EConst(OcamlConst.CUnit);
								} else {
									final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
									final modName = moduleIdToOcamlModuleName(cls.module);
									final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
									final lhsCell = (selfMod != null && selfMod == modName)
										? OcamlExpr.EIdent(scoped)
										: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
									incDec(
										OcamlExpr.EUnop(OcamlUnop.Deref, lhsCell),
										(newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, newVal)
									);
								}
							case TField(obj, FInstance(_, _, cfRef)):
								final cf = cfRef.get();
								switch (cf.kind) {
									case FVar(_, _):
									final objName = freshTmp("obj");
									OcamlExpr.ELet(
										objName,
										buildExpr(obj),
										incDec(
											OcamlExpr.EField(OcamlExpr.EIdent(objName), cf.name),
											(newVal) -> OcamlExpr.EAssign(
												OcamlAssignOp.FieldSet,
												OcamlExpr.EField(OcamlExpr.EIdent(objName), cf.name),
												newVal
											)
										),
										false
									);
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
							case TArray(arr, idx):
								final arrName = freshTmp("arr");
								final idxName = freshTmp("idx");
								OcamlExpr.ELet(
									arrName,
								buildExpr(arr),
								OcamlExpr.ELet(
									idxName,
									buildExpr(idx),
									incDec(
										OcamlExpr.EApp(
											OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"),
											[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName)]
										),
										(newVal) -> OcamlExpr.EApp(
											OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
											[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName), newVal]
										)
									),
									false
								),
								false
							);
						case _:
							OcamlExpr.EConst(OcamlConst.CUnit);
					}
				}
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildBlock(exprs:Array<TypedExpr>):OcamlExpr {
		// Mutability inference: decide which locals become `ref` (as opposed to `let`-shadowed)
		// by scanning for assignments and closure-capture requirements.
		final refIds = collectRefLocalIdsFromExprs(exprs);
		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = refIds;
		final usedIds = collectUsedLocalIdsFromExprs(exprs);
		final prevUsed = currentUsedLocalIds;
		currentUsedLocalIds = usedIds;
		final result = buildBlockFromIndex(exprs, 0, false);
		currentMutatedLocalIds = prev;
		currentUsedLocalIds = prevUsed;
		return result;
	}

		function buildBlockFromIndex(exprs:Array<TypedExpr>, index:Int, allowDirectReturn:Bool):OcamlExpr {
			if (index >= exprs.length) return OcamlExpr.EConst(OcamlConst.CUnit);

			final e = exprs[index];
			return switch (e.expr) {
				case TVar(v, init):
				final isUsed = currentUsedLocalIds != null
					&& currentUsedLocalIds.exists(v.id)
					&& currentUsedLocalIds.get(v.id) == true;

				if (!isUsed) {
					final rest = buildBlockFromIndex(exprs, index + 1, allowDirectReturn);
					if (init == null) return rest;
					final initUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(init)]);
					return switch (rest) {
						case ESeq(items): OcamlExpr.ESeq([initUnit].concat(items));
						case _: OcamlExpr.ESeq([initUnit, rest]);
					}
				}

				// Variable declarations are the primary place Haxe inserts implicit conversions
				// (notably between `Null<primitive>` and `primitive`, and also Int->Float).
				//
				// If we ignore those coercions here, we can end up binding a value with a
				// different OCaml representation than the variable's declared Haxe type,
				// leading to downstream type errors (e.g. `String.charCodeAt` flows).
				final initExpr = init != null ? coerceForAssignment(v.t, init) : defaultValueForType(v.t);
				final isMutable = currentMutatedLocalIds != null
					&& currentMutatedLocalIds.exists(v.id)
					&& currentMutatedLocalIds.get(v.id) == true;

				// If this local is immutable (let-bound) and its initial value is never read before
				// the next write, binding it is a dead-store and can trigger OCaml's unused-var warning
				// if it is immediately shadowed (a common pattern in the typed AST).
				if (!isMutable) {
					final shouldBind = isLocalReadBeforeNextWrite(exprs, index + 1, v.id);
					if (!shouldBind) {
						final rest = buildBlockFromIndex(exprs, index + 1, allowDirectReturn);
						if (init == null) return rest;
						final initUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [initExpr]);
						return switch (rest) {
							case ESeq(items): OcamlExpr.ESeq([initUnit].concat(items));
							case _: OcamlExpr.ESeq([initUnit, rest]);
						}
					}
				}

				final rhs = if (isMutable) {
					refLocals.set(v.id, true);
					OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
				} else {
					refLocals.remove(v.id);
					initExpr;
					}
					OcamlExpr.ELet(renameVar(v.name), rhs, buildBlockFromIndex(exprs, index + 1, allowDirectReturn), false);
				case TBinop(OpAssign, lhs, rhs):
					switch (lhs.expr) {
						case TLocal(v) if (!isRefLocalId(v.id)):
							// Optimization (M14.5.1): avoid `ref` for straight-line local assignments when safe.
							//
							// Instead of allocating `let x = ref ...` and emitting `x := v`, we "rebind" with
							// `let x = v in ...`, which is idiomatic in OCaml and avoids mutable cells.
							//
							// Safety note:
							// This path only runs for locals that were *not* classified as needing `ref` by
							// `collectRefLocalIdsFromExprs` (loops, nested-block mutations, closure capture, and
							// non-statement assignment expressions keep using `ref`).
							final rhsExpr = coerceForAssignment(v.t, rhs);
							final shouldBind = isLocalReadBeforeNextWrite(exprs, index + 1, v.id);
							if (index == exprs.length - 1) {
								rhsExpr;
							} else {
								if (shouldBind) {
									OcamlExpr.ELet(renameVar(v.name), rhsExpr, buildBlockFromIndex(exprs, index + 1, allowDirectReturn), false);
								} else {
									// Dead-store in this block: preserve RHS side effects but don't bind an unused `let`,
									// since dune/warn-error treats unused vars as errors.
									final currentUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [rhsExpr]);
									final rest = buildBlockFromIndex(exprs, index + 1, allowDirectReturn);
									switch (rest) {
										case ESeq(items):
											OcamlExpr.ESeq([currentUnit].concat(items));
										case _:
											OcamlExpr.ESeq([currentUnit, rest]);
									}
								}
							}
						case _:
							final current = buildExpr(e);
							if (index == exprs.length - 1) {
								current;
							} else {
								final currentUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [current]);
								final rest = buildBlockFromIndex(exprs, index + 1, allowDirectReturn);
								switch (rest) {
									case ESeq(items):
										OcamlExpr.ESeq([currentUnit].concat(items));
									case _:
										OcamlExpr.ESeq([currentUnit, rest]);
								}
							}
					}
				case TReturn(ret):
					if (allowDirectReturn) {
						ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
					} else {
					final valueExpr = ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
					final payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [valueExpr]);
					OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_return"), [payload]));
				}
			case _:
				final current = buildExpr(e);
				if (index == exprs.length - 1) {
					current;
				} else {
					final currentUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [current]);
					final rest = buildBlockFromIndex(exprs, index + 1, allowDirectReturn);
					switch (rest) {
						case ESeq(items):
							OcamlExpr.ESeq([currentUnit].concat(items));
						case _:
							OcamlExpr.ESeq([currentUnit, rest]);
					}
				}
		}
	}

	function buildFunctionBodyBlock(exprs:Array<TypedExpr>):OcamlExpr {
		final refIds = collectRefLocalIdsFromExprs(exprs);
		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = refIds;
		final usedIds = collectUsedLocalIdsFromExprs(exprs);
		final prevUsed = currentUsedLocalIds;
		currentUsedLocalIds = usedIds;
		final result = buildBlockFromIndex(exprs, 0, true);
		currentMutatedLocalIds = prev;
		currentUsedLocalIds = prevUsed;
		return result;
	}

	static function containsNestedReturnInFunctionBody(bodyExpr:TypedExpr):Bool {
		var found = false;

		function visit(e:TypedExpr, isDirectTopLevelStmt:Bool):Void {
			if (found) return;
			switch (e.expr) {
				case TReturn(_):
					if (!isDirectTopLevelStmt) found = true;
				case TFunction(_):
					// Skip nested functions: `return` inside them is handled by their own boundary.
				case TBlock(exprs):
					// Any block encountered here is nested (function-body block is handled at the root).
					for (x in exprs) visit(x, false);
				case _:
					TypedExprTools.iter(e, (x) -> visit(x, false));
			}
		}

		switch (bodyExpr.expr) {
			case TBlock(exprs):
				for (x in exprs) visit(x, true);
			case _:
				visit(bodyExpr, true);
		}

		return found;
	}

	public function buildFunctionFromArgsAndExpr(args:Array<{id:Int, name:String}>, bodyExpr:TypedExpr):OcamlExpr {
		final refIds = collectRefLocalIds(bodyExpr);

		final params = args.length == 0
			? [OcamlPat.PConst(OcamlConst.CUnit)]
			: args.map(a -> OcamlPat.PVar(renameVar(a.name)));

		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = refIds;
		for (a in args) {
			if (refIds.exists(a.id) && refIds.get(a.id) == true) {
				refLocals.set(a.id, true);
			}
		}

		final needsReturnCatch = containsNestedReturnInFunctionBody(bodyExpr);

		var body:OcamlExpr = switch (unwrap(bodyExpr).expr) {
			case TReturn(ret):
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case TBlock(exprs):
				buildFunctionBodyBlock(exprs);
			case _:
				buildExpr(bodyExpr);
		}

		if (needsReturnCatch) {
			final returnVar = freshTmp("ret");
			final returnCase:OcamlMatchCase = {
				pat: OcamlPat.PConstructor("HxRuntime.Hx_return", [OcamlPat.PVar(returnVar)]),
				guard: null,
				expr: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(returnVar)])
			};
			body = OcamlExpr.ETry(body, [returnCase]);
		}

		for (a in args) {
			if (refIds.exists(a.id) && refIds.get(a.id) == true) {
				final n = renameVar(a.name);
				body = OcamlExpr.ELet(n, OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EIdent(n)]), body, false);
			}
		}

		currentMutatedLocalIds = prev;
		return OcamlExpr.EFun(params, body);
	}

	public function buildFunction(tfunc:haxe.macro.Type.TFunc):OcamlExpr {
		final refIds = collectRefLocalIds(tfunc.expr);

		// Determine parameters and wrap mutated parameters as refs inside the body.
		final params = tfunc.args.length == 0
			? [OcamlPat.PConst(OcamlConst.CUnit)]
			: tfunc.args.map(a -> OcamlPat.PVar(renameVar(a.v.name)));

		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = refIds;
		for (a in tfunc.args) {
			if (refIds.exists(a.v.id) && refIds.get(a.v.id) == true) {
				refLocals.set(a.v.id, true);
			}
		}

		final needsReturnCatch = containsNestedReturnInFunctionBody(tfunc.expr);

		var body:OcamlExpr = switch (unwrap(tfunc.expr).expr) {
			case TReturn(ret):
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case TBlock(exprs):
				buildFunctionBodyBlock(exprs);
			case _:
				buildExpr(tfunc.expr);
		}

		if (needsReturnCatch) {
			final returnVar = freshTmp("ret");
			final returnCase:OcamlMatchCase = {
				pat: OcamlPat.PConstructor("HxRuntime.Hx_return", [OcamlPat.PVar(returnVar)]),
				guard: null,
				expr: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(returnVar)])
			};
			body = OcamlExpr.ETry(body, [returnCase]);
		}

		// Shadow mutated params as refs (`let x = ref x in ...`).
		for (a in tfunc.args) {
			if (refIds.exists(a.v.id) && refIds.get(a.v.id) == true) {
				final n = renameVar(a.v.name);
				body = OcamlExpr.ELet(n, OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EIdent(n)]), body, false);
			}
		}

		currentMutatedLocalIds = prev;
		return OcamlExpr.EFun(params, body);
	}

	static function collectMutatedLocalIdsFromExprs(exprs:Array<TypedExpr>):Map<Int, Bool> {
		final mutated:Map<Int, Bool> = [];
		for (e in exprs) {
			collectMutatedLocalIdsInto(e, mutated);
		}
		return mutated;
	}

	static function collectMutatedLocalIds(e:TypedExpr):Map<Int, Bool> {
		final mutated:Map<Int, Bool> = [];
		collectMutatedLocalIdsInto(e, mutated);
		return mutated;
	}

	static function collectMutatedLocalIdsInto(e:TypedExpr, mutated:Map<Int, Bool>):Void {
		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function visit(e:TypedExpr):Void {
			if (visited.exists(e)) return;
			visited.set(e, true);

			switch (e.expr) {
				case TBinop(OpAssign, lhs, _):
					switch (lhs.expr) {
						case TLocal(v):
							mutated.set(v.id, true);
						case _:
					}
				case TBinop(OpAssignOp(_), lhs, _):
					switch (lhs.expr) {
						case TLocal(v):
							mutated.set(v.id, true);
						case _:
					}
				case TUnop(OpIncrement, _, inner) | TUnop(OpDecrement, _, inner):
					switch (inner.expr) {
						case TLocal(v):
							mutated.set(v.id, true);
						case _:
					}
				case _:
			}

			TypedExprTools.iter(e, visit);
		}

		visit(e);
	}

	/**
		Collects the set of local ids that must be represented as `ref`.

		Why:
		- Haxe is imperative; the typed AST frequently uses assignment even for straight-line
		  control flow (temporary variables, compiler-lowered patterns, etc).
		- Emitting `ref` for every mutated local is correct but unnecessarily slow and unidiomatic.

		What:
		- Returns a set of local ids that require **cell semantics** in OCaml.
		- Locals not in this set can be updated via **`let`-shadowing** in straight-line blocks.

		How (conservative rules):
		- Any mutation (assignment / assign-op / ++/--) that occurs:
		  - inside a loop,
		  - inside a nested function,
		  - inside a nested block (relative to the current block),
		  - or in a non-statement expression position,
		  requires `ref`.
		- Additionally, if a local is **captured by a nested function** and is mutated anywhere
		  in the current block, it requires `ref` so closures observe updates (Haxe semantics).

		This intentionally leaves more-advanced SSA-style rewrites for later milestones; the goal
		is a simple, predictable win for common straight-line assignment patterns.
	**/
	static function collectRefLocalIdsFromExprs(exprs:Array<TypedExpr>):Map<Int, Bool> {
		final mutatedAny:Map<Int, Bool> = [];
		final needsRef:Map<Int, Bool> = [];

		final captured:Map<Int, Bool> = [];
		for (e in exprs) collectCapturedOuterLocalIdsInto(e, captured);

		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function markMutated(id:Int, isShadowableStmt:Bool):Void {
			mutatedAny.set(id, true);
			if (!isShadowableStmt) needsRef.set(id, true);
		}

		function visit(e:TypedExpr, depth:Int, inLoop:Bool, inFn:Bool, isStmt:Bool):Void {
			if (visited.exists(e)) return;
			visited.set(e, true);

			switch (e.expr) {
				case TFunction(tfunc):
					// Any mutations inside nested functions require refs for the mutated locals.
					visit(tfunc.expr, depth + 1, inLoop, true, false);
					return;
					case TWhile(cond, body, _):
						visit(cond, depth + 1, true, inFn, false);
						visit(body, depth + 1, true, inFn, false);
						return;
					case TBlock(items):
						// Nested blocks (relative to this block) are treated conservatively: mutations in them
						// require refs for the mutated locals, since `let`-shadowing would not propagate out.
						for (x in items) visit(x, depth + 1, inLoop, inFn, true);
						return;
				case _:
			}

			switch (e.expr) {
				case TBinop(OpAssign, lhs, _):
					switch (lhs.expr) {
						case TLocal(v):
							final shadowable = isStmt && depth == 0 && !inLoop && !inFn;
							markMutated(v.id, shadowable);
						case _:
					}
				case TBinop(OpAssignOp(_), lhs, _):
					switch (lhs.expr) {
						case TLocal(v):
							markMutated(v.id, false);
						case _:
					}
				case TUnop(OpIncrement, _, inner) | TUnop(OpDecrement, _, inner):
					switch (inner.expr) {
						case TLocal(v):
							markMutated(v.id, false);
						case _:
					}
				case _:
			}

			TypedExprTools.iter(e, (x) -> visit(x, depth + 1, inLoop, inFn, false));
		}

		for (e in exprs) visit(e, 0, false, false, true);

		// Closure semantics: if a local is captured by any nested function and is mutated anywhere
		// in this block, it must be a ref so closures observe updates.
		for (id in captured.keys()) {
			if (mutatedAny.exists(id) && mutatedAny.get(id) == true) needsRef.set(id, true);
		}

		return needsRef;
	}

	static function collectRefLocalIds(e:TypedExpr):Map<Int, Bool> {
		return switch (e.expr) {
			case TBlock(exprs):
				collectRefLocalIdsFromExprs(exprs);
			case _:
				collectRefLocalIdsFromExprs([e]);
		}
	}

	static function collectCapturedOuterLocalIdsInto(e:TypedExpr, out:Map<Int, Bool>):Void {
		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function collectDeclaredLocalIdsShallow(e:TypedExpr, declared:Map<Int, Bool>):Void {
			switch (e.expr) {
				case TVar(v, _):
					declared.set(v.id, true);
				case TFunction(_):
					// Stop: nested function defines its own scope.
				case _:
					TypedExprTools.iter(e, (x) -> collectDeclaredLocalIdsShallow(x, declared));
			}
		}

		function collectUsedLocalIdsShallow(e:TypedExpr, used:Map<Int, Bool>):Void {
			switch (e.expr) {
				case TLocal(v):
					used.set(v.id, true);
				case TFunction(_):
					// Stop: nested function defines its own scope.
				case _:
					TypedExprTools.iter(e, (x) -> collectUsedLocalIdsShallow(x, used));
			}
		}

		function capturedOuterLocalsForFunction(tfunc:haxe.macro.Type.TFunc):Map<Int, Bool> {
			final declared:Map<Int, Bool> = [];
			final used:Map<Int, Bool> = [];
			for (a in tfunc.args) declared.set(a.v.id, true);
			collectDeclaredLocalIdsShallow(tfunc.expr, declared);
			collectUsedLocalIdsShallow(tfunc.expr, used);

			final captured:Map<Int, Bool> = [];
			for (id in used.keys()) {
				if (!declared.exists(id)) captured.set(id, true);
			}
			return captured;
		}

		function visit(e:TypedExpr):Void {
			if (visited.exists(e)) return;
			visited.set(e, true);

			switch (e.expr) {
				case TFunction(tfunc):
					final captured = capturedOuterLocalsForFunction(tfunc);
					for (id in captured.keys()) out.set(id, true);
					TypedExprTools.iter(tfunc.expr, visit);
				case _:
					TypedExprTools.iter(e, visit);
			}
		}

		visit(e);
	}

	function collectUsedLocalIdsFromExprs(exprs:Array<TypedExpr>):Map<Int, Bool> {
		final used:Map<Int, Bool> = [];
		for (e in exprs) {
			final u = collectUsedLocalIds(e);
			for (k in u.keys()) used.set(k, true);
		}
		return used;
	}

	function collectUsedLocalIds(e:TypedExpr):Map<Int, Bool> {
		final used:Map<Int, Bool> = [];
		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function visit(e:TypedExpr):Void {
			if (visited.exists(e)) return;
			visited.set(e, true);

			switch (e.expr) {
				case TLocal(v):
					used.set(v.id, true);
				case _:
			}

			TypedExprTools.iter(e, visit);
		}

		visit(e);
		return used;
	}

	/**
		Returns true if the given local is *read* before it is *written* again in the suffix
		of the current straight-line block.

		Why:
		- The M14.5.1 "let-shadowing" optimization replaces `x := rhs` with `let x = rhs in ...`.
		- If `x` is never read before the next write, binding `let x = rhs` is a dead-store and
		  triggers OCaml's "unused var" warning (which is an error under dune's warn-error).

		How:
		- Scan forward:
		  - If we see a read of `id`, return true.
		  - If we see a write to `id` first, return false (this assignment's value will never be observed).
		  - If we reach the end, return false.
	**/
	static function isLocalReadBeforeNextWrite(exprs:Array<TypedExpr>, startIndex:Int, id:Int):Bool {
		for (i in startIndex...exprs.length) {
			final e = exprs[i];
			if (exprReadsLocalId(e, id)) return true;
			if (exprWritesLocalId(e, id)) return false;
		}
		return false;
	}

	static function exprWritesLocalId(e:TypedExpr, id:Int):Bool {
		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function visit(e:TypedExpr):Bool {
			if (visited.exists(e)) return false;
			visited.set(e, true);

			switch (e.expr) {
				case TBinop(OpAssign, lhs, _):
					switch (lhs.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case TBinop(OpAssignOp(_), lhs, _):
					switch (lhs.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case TUnop(OpIncrement, _, inner) | TUnop(OpDecrement, _, inner):
					switch (inner.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case _:
			}

			var found = false;
			TypedExprTools.iter(e, (x) -> {
				if (!found && visit(x)) found = true;
			});
			return found;
		}

		return visit(e);
	}

	static function exprReadsLocalId(e:TypedExpr, id:Int):Bool {
		final visited = new haxe.ds.ObjectMap<TypedExpr, Bool>();

		function visit(e:TypedExpr, writeOnly:Bool):Bool {
			if (visited.exists(e)) return false;
			visited.set(e, true);

			switch (e.expr) {
				case TLocal(v) if (!writeOnly && v.id == id):
					return true;
				case TBinop(OpAssign, lhs, rhs):
					// LHS is write-only for simple assignment; RHS is read-context.
					if (visit(lhs, true)) return true;
					if (visit(rhs, false)) return true;
					return false;
				case _:
			}

			var found = false;
			TypedExprTools.iter(e, (x) -> {
				if (!found && visit(x, false)) found = true;
			});
			return found;
		}

		return visit(e, false);
	}

	function buildSwitch(
		scrutinee:TypedExpr,
		cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>,
		edef:Null<TypedExpr>,
		switchType:Type
	):OcamlExpr {
		final wantUnit = isVoidType(switchType);

			inline function wrapCaseExpr(expr:OcamlExpr):OcamlExpr {
				return wantUnit ? exprAsStatement(expr) : expr;
			}

		final defaultExpr:OcamlExpr = edef != null
			? buildExpr(edef)
			: (wantUnit
				? OcamlExpr.EConst(OcamlConst.CUnit)
				: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))]));

		// Enum pattern matching: Haxe's pattern matcher often lowers enum switches to:
		// switch (TEnumIndex(e)) { case 0: ...; case 1: ... }
		// Reconstruct a direct OCaml match on the enum value.
		final scrutineeUnwrapped = unwrap(scrutinee);
		switch (scrutineeUnwrapped.expr) {
				case TEnumIndex(enumValueExpr):
					switch (enumValueExpr.t) {
						case TEnum(eRef, _):
							final enumType = eRef.get();
							final scrut = buildExpr(enumValueExpr);
							final arms:Array<OcamlMatchCase> = [];
							final isExhaustive = enumIndexSwitchIsExhaustive(enumType, cases);
	
							for (c in cases) {
								// Only support a single constructor index per case for now.
								final patRes = (c.values.length == 1) ? buildEnumIndexCasePat(enumType, c.values[0]) : null;
								final pat = patRes != null ? patRes.pat : OcamlPat.PAny;
	
								final prev = currentEnumParamNames;
								currentEnumParamNames = patRes != null ? patRes.enumParams : null;
								final expr = wrapCaseExpr(buildExpr(c.expr));
								currentEnumParamNames = prev;
	
								arms.push({ pat: pat, guard: null, expr: expr });
							}

						if (!isExhaustive) {
							arms.push({
								pat: OcamlPat.PAny,
								guard: null,
								expr: wrapCaseExpr(defaultExpr)
							});
						}

						return OcamlExpr.EMatch(scrut, arms);
					case _:
				}
			case _:
		}

		final arms:Array<OcamlMatchCase> = [];
		for (c in cases) {
			// NOTE: For now, only support enum-parameter binding for a single pattern.
			final patRes = c.values.length == 1 ? buildSwitchValuePatAndEnumParams(c.values[0]) : null;
			final pat = if (patRes != null) {
				patRes.pat;
			} else {
				final pats = c.values.map(buildSwitchValuePat);
				pats.length == 1 ? pats[0] : OcamlPat.POr(pats);
			}

			final prev = currentEnumParamNames;
			currentEnumParamNames = patRes != null ? patRes.enumParams : null;
			final expr = wrapCaseExpr(buildExpr(c.expr));
			currentEnumParamNames = prev;

			arms.push({ pat: pat, guard: null, expr: expr });
		}
		arms.push({
			pat: OcamlPat.PAny,
			guard: null,
			expr: wrapCaseExpr(defaultExpr)
		});

		// Nullable primitive switches (notably `Null<Int>` lowered by the compiler in
		// dynamic-target mode) frequently appear with integer constant patterns.
		//
		// We represent nullable primitives as `Obj.t`, so we must guard against `null`
		// before unboxing for an OCaml `match`.
		switch (nullablePrimitiveKind(scrutinee.t)) {
			case "int", "float", "bool":
				inline function isNullCaseValue(v:TypedExpr):Bool {
					return switch (unwrap(v).expr) {
						case TConst(TNull): true;
						case _: false;
					}
				}

				final tmp = freshTmp("switch");
				final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				final defaultBranch = wrapCaseExpr(defaultExpr);

				// Support `case null`: for nullable primitives the scrutinee is `Obj.t`, so
				// the `null` case must be handled *before* unboxing to a primitive.
				var firstNullCaseExpr:Null<OcamlExpr> = null;
				for (c in cases) {
					var hasNull = false;
					for (v in c.values) {
						if (isNullCaseValue(v)) {
							hasNull = true;
							break;
						}
					}
					if (hasNull) {
						firstNullCaseExpr = wrapCaseExpr(buildExpr(c.expr));
						break;
					}
				}

				final nullBranch = firstNullCaseExpr != null ? firstNullCaseExpr : defaultBranch;

				// Rebuild match arms, excluding `null` literals (handled by the guard).
				final nonNullArms:Array<OcamlMatchCase> = [];
				for (c in cases) {
					final valuesNonNull = c.values.filter(v -> !isNullCaseValue(v));
					if (valuesNonNull.length == 0) continue;

					final patRes = valuesNonNull.length == 1 ? buildSwitchValuePatAndEnumParams(valuesNonNull[0]) : null;
					final pat = if (patRes != null) {
						patRes.pat;
					} else {
						final pats = valuesNonNull.map(buildSwitchValuePat);
						pats.length == 1 ? pats[0] : OcamlPat.POr(pats);
					}

					final prev = currentEnumParamNames;
					currentEnumParamNames = patRes != null ? patRes.enumParams : null;
					final expr = wrapCaseExpr(buildExpr(c.expr));
					currentEnumParamNames = prev;

					nonNullArms.push({ pat: pat, guard: null, expr: expr });
				}
				nonNullArms.push({ pat: OcamlPat.PAny, guard: null, expr: defaultBranch });

				final unboxed = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]);
				return OcamlExpr.ELet(
					tmp,
					buildExpr(scrutinee),
					OcamlExpr.EIf(
						OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
						nullBranch,
						OcamlExpr.EMatch(unboxed, nonNullArms)
					),
					false
				);
			case _:
		}

		return OcamlExpr.EMatch(buildExpr(scrutinee), arms);
	}

	function enumIndexSwitchIsExhaustive(enumType:EnumType, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>):Bool {
		final allIndices:Map<Int, Bool> = [];
		for (name in enumType.names) {
			final ef = enumType.constructs.get(name);
			if (ef != null) allIndices.set(ef.index, true);
		}
		if (enumType.names.length == 0) return false;

		final covered:Map<Int, Bool> = [];
		for (c in cases) {
			for (v in c.values) {
				switch (v.expr) {
					case TConst(TInt(i)):
						covered.set(i, true);
					case _:
						return false;
				}
			}
		}

		for (idx in allIndices.keys()) {
			if (!(covered.exists(idx) && covered.get(idx) == true)) return false;
		}
		return true;
	}

	function buildEnumIndexCasePat(enumType:EnumType, indexExpr:TypedExpr):Null<{pat:OcamlPat, enumParams:Map<String, String>}> {
		final idx:Null<Int> = switch (indexExpr.expr) {
			case TConst(TInt(v)): v;
			case _: null;
		}
		if (idx == null) return null;

		var field:Null<EnumField> = null;
		for (name in enumType.names) {
			final ef = enumType.constructs.get(name);
			if (ef != null && ef.index == idx) {
				field = ef;
				break;
			}
		}
		if (field == null) return null;

		final modName = moduleIdToOcamlModuleName(enumType.module);
		final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;
		final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
			field.name;
		} else if (isOcamlNativeEnumType(enumType, "List")) {
			field.name == "Nil" ? "[]" : (field.name == "Cons" ? "::" : field.name);
		} else {
			isSameModule ? field.name : (modName + "." + field.name);
		}

		final argCount = switch (field.type) {
			case TFun(args, _): args.length;
			case _: 0;
		}

		final enumParams:Map<String, String> = [];
		final patArgs:Array<OcamlPat> = [];
		for (i in 0...argCount) {
			final n = "_p" + i;
			patArgs.push(OcamlPat.PVar(n));
			enumParams.set(field.name + ":" + i, n);
		}

		return { pat: OcamlPat.PConstructor(ctorName, patArgs), enumParams: enumParams };
	}

	function buildSwitchValuePat(v:TypedExpr):OcamlPat {
		return switch (v.expr) {
			case TConst(c):
				OcamlPat.PConst(buildConst(c));
			case TField(_, FEnum(eRef, ef)):
				final e = eRef.get();
				if (isOcamlNativeEnumType(e, "List") && ef.name == "Nil") {
					OcamlPat.PConstructor("[]", []);
				} else if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
					OcamlPat.PConstructor(ef.name, []);
				} else {
					final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
					final ctorName = isSameModule ? ef.name : (moduleIdToOcamlModuleName(e.module) + "." + ef.name);
					OcamlPat.PConstructor(ctorName, []);
				}
			case _:
				OcamlPat.PAny;
		}
	}

	function buildSwitchValuePatAndEnumParams(v:TypedExpr):{pat:OcamlPat, enumParams:Null<Map<String, String>>} {
		return switch (v.expr) {
			case TCall(fn, args):
				switch (fn.expr) {
					case TField(_, FEnum(eRef, ef)):
						final e = eRef.get();
						final ctorName = if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
							ef.name;
						} else if (isOcamlNativeEnumType(e, "List") && ef.name == "Cons") {
							"::";
						} else {
							final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
							isSameModule ? ef.name : (moduleIdToOcamlModuleName(e.module) + "." + ef.name);
						}

						final enumParams:Map<String, String> = [];
						final patArgs:Array<OcamlPat> = [];
						for (i in 0...args.length) {
							final a = args[i];
							switch (a.expr) {
								case TLocal(v):
									final n = renameVar(v.name);
									patArgs.push(OcamlPat.PVar(n));
									enumParams.set(ef.name + ":" + i, n);
								case TConst(c):
									patArgs.push(OcamlPat.PConst(buildConst(c)));
								case TIdent("_"):
									patArgs.push(OcamlPat.PAny);
								case _:
									patArgs.push(OcamlPat.PAny);
							}
						}
						{ pat: OcamlPat.PConstructor(ctorName, patArgs), enumParams: enumParams };
					case _:
						{ pat: buildSwitchValuePat(v), enumParams: null };
				}
			case _:
				{ pat: buildSwitchValuePat(v), enumParams: null };
		}
	}

	function buildField(obj:TypedExpr, fa:FieldAccess, pos:Position):OcamlExpr {
		return switch (fa) {
			case FEnum(eRef, ef):
				final e = eRef.get();
				if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
					OcamlExpr.EIdent(ef.name);
				} else if (isOcamlNativeEnumType(e, "List")) {
					switch (ef.name) {
						case "Nil": OcamlExpr.EList([]);
						case "Cons": OcamlExpr.EIdent("::");
						case _: OcamlExpr.EConst(OcamlConst.CUnit);
					}
				} else {
					final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
					if (isSameModule) {
						OcamlExpr.EIdent(ef.name);
					} else {
						final modName = moduleIdToOcamlModuleName(e.module);
						OcamlExpr.EField(OcamlExpr.EIdent(modName), ef.name);
					}
				}
			case FStatic(clsRef, cfRef):
				final cls = clsRef.get();
				final cf = cfRef.get();
				if (isStdStringClass(cls) && cf.name == "fromCharCode") {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "fromCharCode");
				}
				#if macro
				if (!ctx.currentIsHaxeStd && cls.pack != null && cls.pack.length == 0 && cls.name == "Type") {
					guardrailError(
						"reflaxe.ocaml (M5): Haxe reflection is not supported yet (Type." + cfRef.get().name + "). "
						+ "Avoid Type for now, or add an OCaml extern and call native APIs. (bd: haxe.ocaml-eli)",
						pos
					);
				}
				#end
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);

				// Extern OCaml interop: allow `@:native("PMap") extern class PMap { ... }` to map
				// to the actual OCaml module path, and allow `@:native("add")` (or a full
				// `@:native("ExtLib.PMap.add")`) on the field to map to the native identifier.
				//
				// This is intentionally conservative for now: we only apply @:native mapping for extern classes.
				// (bd: haxe.ocaml-28t.8.1)
				if (cls.isExtern) {
					final nativeClassPath = extractNativeString(cls.meta);
					final nativeFieldPath = extractNativeString(cf.meta);

					// OCaml-native functor instantiations (M12): if user code references our
					// defunctorized `Map`/`Set` modules (emitted as standalone `.ml` files),
					// record that so `OcamlCompiler.onOutputComplete()` can emit them.
					if (nativeClassPath != null) {
						switch (nativeClassPath) {
							case "OcamlNativeStringMap", "OcamlNativeIntMap", "OcamlNativeStringSet", "OcamlNativeIntSet":
								ctx.needsOcamlNativeMapSet = true;
							case _:
						}
					}

					final resolved = resolveNativeStaticPath(
						moduleIdToOcamlModuleName(cls.module),
						cf.name,
						nativeClassPath,
						nativeFieldPath
					);

					return OcamlExpr.EField(resolved.moduleExpr, resolved.fieldName);
					} else {
						final modName = moduleIdToOcamlModuleName(cls.module);
						final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
						final baseExpr = (selfMod != null && selfMod == modName)
							? OcamlExpr.EIdent(scoped)
							: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
						final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
						final isMutableStatic = switch (cf.kind) {
							case FVar(_, _): ctx.mutableStaticFields.exists(key) && ctx.mutableStaticFields.get(key) == true;
							case _: false;
						}
						return isMutableStatic ? OcamlExpr.EUnop(OcamlUnop.Deref, baseExpr) : baseExpr;
					}
					case FInstance(clsRef, _, cfRef):
						final cls = clsRef.get();
						final cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _):
							if (isStdArrayClass(cls) && cf.name == "length") {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(obj)]);
							} else if (isStdStringClass(cls) && cf.name == "length") {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"), [buildExpr(obj)]);
							} else if (isStdBytesClass(cls) && cf.name == "length") {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "length"), [buildExpr(obj)]);
							} else {
								OcamlExpr.EField(buildExpr(obj), cf.name);
							}
						case FMethod(_):
							buildBoundMethodClosure(obj, cls, cf, pos);
							case _:
								// Methods/properties are handled at callsites; as values, we only support real methods for now.
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
				case FClosure(c, cfRef):
					final cf = cfRef.get();
					final owner:Null<ClassType> = c != null ? c.c.get() : classTypeFromType(obj.t);
					if (owner == null) {
						#if macro
						guardrailError("reflaxe.ocaml (M10): unsupported method-closure without owner class metadata ('" + cf.name + "').", pos);
						#end
						OcamlExpr.EConst(OcamlConst.CUnit);
					} else {
						buildBoundMethodClosure(obj, owner, cf, pos);
					}
					case FDynamic(name):
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"),
						[
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
							[
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(obj)]),
								OcamlExpr.EConst(OcamlConst.CString(name))
							]
						)
					]
				);
			case FAnon(cfRef):
				// Minimal anonymous-structure support: KeyValueIterator elements are represented as OCaml tuples.
				// `{ key:K, value:V }` lowers to `(key, value)`, so `.key` maps to `fst`, `.value` maps to `snd`.
				//
				// For iterator values (`Iterator<T>`), we represent them as OCaml records with fields
				// `hasNext` and `next`, so field access becomes `it.hasNext` / `it.next`.
				final cf = cfRef.get();
				switch (cf.name) {
					case "key":
						OcamlExpr.EApp(OcamlExpr.EIdent("fst"), [buildExpr(obj)]);
					case "value":
						OcamlExpr.EApp(OcamlExpr.EIdent("snd"), [buildExpr(obj)]);
					case "hasNext", "next":
						OcamlExpr.EField(buildExpr(obj), cf.name);
					case _:
						// Some typedef-backed anonymous structures are represented as real OCaml records
						// for better performance/ergonomics (e.g. `sys.FileStat`).
						// For those, anonymous-field access should lower to record field access.
						if (isSysFileStatTypedef(obj.t) || isSysFileStatAnon(obj.t)) {
							OcamlExpr.EField(buildExpr(obj), cf.name);
						} else {
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"),
								[
									OcamlExpr.EApp(
										OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
										[buildExpr(obj), OcamlExpr.EConst(OcamlConst.CString(cf.name))]
									)
								]
							);
						}
				}
			case _:
					// For now, treat unknown field access as unit.
					OcamlExpr.EConst(OcamlConst.CUnit);
			}
		}

		/**
		 * Build a bound-closure value for an instance method access (`obj.method`).
		 *
		 * Why:
		 * - In Haxe, taking an instance method as a value produces a closure which captures
		 *   the receiver (`this`) and can be called later: `var f = obj.foo; f(1);`.
		 * - In OCaml, our generated instance methods are top-level functions that take an
		 *   explicit receiver parameter (and, for 0-arg methods, an extra `unit` arg).
		 * - For interface/virtual dispatch (M10), the receiver may be a “dispatch record”
		 *   that stores method fields; the call must go through that record field to
		 *   preserve dynamic dispatch semantics.
		 *
		 * What this returns:
		 * - An OCaml `fun ... -> ...` that evaluates the receiver once and forwards calls
		 *   to the appropriate implementation (`Module.foo recv ...` or `recv.foo (Obj.magic recv) ...`).
		 *
		 * Notes:
		 * - This does not currently implement bound-closures for stdlib “magic” methods
		 *   (e.g. `Array.push` lowered to `HxArray.push`). If upstream suites rely on that,
		 *   add explicit mappings. (bd: haxe.ocaml-d3c)
		 */
		function buildBoundMethodClosure(objExpr:TypedExpr, cls:ClassType, cf:ClassField, pos:Position):OcamlExpr {
			final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (cf.type) {
				case TFun(fargs, _): fargs;
				case _: null;
			}
			final argCount = expectedArgs != null ? expectedArgs.length : 0;

			final paramNames:Array<String> = [];
			final params:Array<OcamlPat> = argCount == 0
				? [OcamlPat.PConst(OcamlConst.CUnit)]
				: {
					final out:Array<OcamlPat> = [];
					for (i in 0...argCount) {
						final n = "a" + Std.string(i);
						paramNames.push(n);
						out.push(OcamlPat.PVar(n));
					}
					out;
				};

			final recvExpr = buildExpr(objExpr);
			final tmpName = switch (recvExpr) {
				case EIdent(_): null;
				case _: freshTmp("obj");
			}
			final recvVar = tmpName == null ? recvExpr : OcamlExpr.EIdent(tmpName);

			final argExprs:Array<OcamlExpr> = [];
			for (n in paramNames) argExprs.push(OcamlExpr.EIdent(n));

			final unwrappedObj = unwrap(objExpr);
			final isSuperReceiver = switch (unwrappedObj.expr) {
				case TConst(TSuper): true;
				case _: false;
			}

			final recvFullName = classFullNameFromType(objExpr.t);
			final isDispatchRecv = recvFullName != null && (ctx.dispatchTypes.exists(recvFullName) || ctx.interfaceTypes.exists(recvFullName));
			final allowSuperCall = !ctx.currentIsHaxeStd && ctx.currentTypeFullName != null && ctx.dispatchTypes.exists(ctx.currentTypeFullName);

			final call:OcamlExpr = if (isSuperReceiver && allowSuperCall) {
				// `super.foo` as a value: bind to the base implementation (no virtual dispatch).
				final modName = moduleIdToOcamlModuleName(cls.module);
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
				final implName = ctx.scopedValueName(cls.module, cls.name, cf.name + "__impl");
				final callFn = (selfMod != null && selfMod == modName)
					? OcamlExpr.EIdent(implName)
					: OcamlExpr.EField(OcamlExpr.EIdent(modName), implName);

				final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("self")])].concat(argExprs);
				if (argCount == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
				OcamlExpr.EApp(callFn, callArgs);
			} else if (isDispatchRecv) {
				final methodField = OcamlExpr.EField(recvVar, cf.name);
				final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar])].concat(argExprs);
				if (argCount == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
				OcamlExpr.EApp(methodField, callArgs);
			} else {
				final modName = moduleIdToOcamlModuleName(cls.module);
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
				final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
				final callFn = (selfMod != null && selfMod == modName)
					? OcamlExpr.EIdent(scoped)
					: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);

				final callArgs = [recvVar].concat(argExprs);
				if (argCount == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
				OcamlExpr.EApp(callFn, callArgs);
			}

			final body = tmpName == null ? call : OcamlExpr.ELet(tmpName, recvExpr, call, false);
			return OcamlExpr.EFun(params, body);
		}

			static function moduleIdToOcamlModuleName(moduleId:String):String {
				if (moduleId == null || moduleId.length == 0) return "Main";
				final flat = moduleId.split(".").join("_");
				return flat.substr(0, 1).toUpperCase() + flat.substr(1);
		}

		static function classFullNameFromType(t:Type):Null<String> {
			return switch (TypeTools.follow(t)) {
				case TInst(cRef, _):
					final c = cRef.get();
					(c.pack ?? []).concat([c.name]).join(".");
				case _:
					null;
			}
		}

		static function classTypeFromType(t:Type):Null<ClassType> {
			return switch (TypeTools.follow(t)) {
				case TInst(cRef, _):
					cRef.get();
				case _:
					null;
			}
		}

			static function isSubclassOf(child:ClassType, parent:ClassType):Bool {
				inline function fullNameOf(c:ClassType):String return (c.pack ?? []).concat([c.name]).join(".");
				final parentName = fullNameOf(parent);

				var cur:Null<ClassType> = child;
				var guard = 0;
				while (cur != null && guard++ < 64) {
					if (fullNameOf(cur) == parentName) return true;
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
				return false;
			}

			static function implementsInterface(child:ClassType, iface:ClassType):Bool {
				inline function fullNameOf(c:ClassType):String return (c.pack ?? []).concat([c.name]).join(".");
				final ifaceName = fullNameOf(iface);

				final seen:Map<String, Bool> = [];
				function ifaceMatchesOrExtends(i:ClassType):Bool {
					final n = fullNameOf(i);
					if (seen.exists(n)) return false;
					seen.set(n, true);
					if (n == ifaceName) return true;
					if (i.interfaces != null) {
						for (x in i.interfaces) {
							final it = x.t.get();
							if (ifaceMatchesOrExtends(it)) return true;
						}
					}
					return false;
				}

				var cur:Null<ClassType> = child;
				var guard = 0;
				while (cur != null && guard++ < 64) {
					if (cur.interfaces != null) {
						for (x in cur.interfaces) {
							final it = x.t.get();
							if (ifaceMatchesOrExtends(it)) return true;
						}
					}
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
				return false;
			}

		/**
		 * Extracts the string argument from a `@:native("...")` metadata entry, if present.
	 *
	 * Why:
	 * - Haxe uses `@:native` for target name mapping.
	 * - For the OCaml backend, this is especially important for **extern interop**: Haxe names
	 *   should map onto existing OCaml module paths / values.
	 *
	 * What:
	 * - Returns the raw string given to `@:native`, or `null` if absent/invalid.
	 *
	 * How:
	 * - Only supports constant-string params for now (non-string params are ignored).
	 */
	static function extractNativeString(meta:MetaAccess):Null<String> {
		for (m in meta.get()) {
			if (m.name != ":native") continue;
			if (m.params == null || m.params.length == 0) continue;
			return switch (m.params[0].expr) {
				case EConst(CString(s)): s;
				case _: null;
			}
		}
		return null;
	}

	static function buildOcamlModulePathExpr(path:String):Null<OcamlExpr> {
		if (path == null) return null;
		final parts = path.split(".").filter(p -> p != null && p.length > 0);
		if (parts.length == 0) return null;
		var expr:OcamlExpr = OcamlExpr.EIdent(parts[0]);
		for (i in 1...parts.length) {
			expr = OcamlExpr.EField(expr, parts[i]);
		}
		return expr;
	}

	/**
	 * Resolves an extern static callsite path from `@:native` metadata.
	 *
	 * Rules:
	 * - `nativeFieldPath` may be:
	 *   - `foo` (rename only) -> `<module>.<foo>`
	 *   - `A.B.foo` (full path) -> `A.B.foo` (overrides module too)
	 * - If `nativeFieldPath` doesn't specify a module, `nativeClassPath` (module) is used.
	 * - If no native metadata exists, falls back to `<defaultModuleName>.<defaultFieldName>`.
	 */
	static function resolveNativeStaticPath(
		defaultModuleName:String,
		defaultFieldName:String,
		nativeClassPath:Null<String>,
		nativeFieldPath:Null<String>
	):{ moduleExpr:OcamlExpr, fieldName:String } {
		var modulePath:Null<String> = nativeClassPath;
		var fieldName:String = defaultFieldName;

		if (nativeFieldPath != null) {
			final parts = nativeFieldPath.split(".").filter(p -> p != null && p.length > 0);
			if (parts.length >= 2) {
				fieldName = parts[parts.length - 1];
				modulePath = parts.slice(0, parts.length - 1).join(".");
			} else if (parts.length == 1) {
				fieldName = parts[0];
			}
		}

		final moduleExpr = if (modulePath != null) {
			final expr = buildOcamlModulePathExpr(modulePath);
			expr == null ? OcamlExpr.EIdent(defaultModuleName) : expr;
		} else {
			OcamlExpr.EIdent(defaultModuleName);
		}

		return { moduleExpr: moduleExpr, fieldName: fieldName };
	}

	/**
	 * Extract per-parameter `@:ocamlLabel("...")` metadata for a class field.
	 *
	 * Why:
	 * - Haxe doesn't have labelled arguments, but OCaml does. For extern interop we need a way
	 *   to map positional Haxe arguments to labelled OCaml callsites.
	 *
	 * How:
	 * - Haxe stores argument metadata in a synthetic `:haxe.arguments` entry on the field's meta.
	 *   We parse that AST and build a map from parameter name → label string.
	 *
	 * Returns:
	 * - `null` if no relevant metadata exists.
	 * - Otherwise, a map from argument name to OCaml label string.
	 */
	static function extractOcamlLabelByArgName(field:ClassField):Null<Map<String, String>> {
		final meta = field.meta.get();
		var out:Null<Map<String, String>> = null;

		for (m in meta) {
			if (m.name != ":haxe.arguments") continue;
			if (m.params == null || m.params.length == 0) continue;

			switch (m.params[0].expr) {
				case EFunction(_, f):
					for (a in f.args) {
						if (a.meta == null) continue;
						for (am in a.meta) {
							if (am.name != ":ocamlLabel") continue;
							if (am.params == null || am.params.length != 1) continue;
							final label = switch (am.params[0].expr) {
								case EConst(CString(s)): s;
								case _: null;
							}
							if (label == null) continue;
							if (out == null) out = [];
							out.set(a.name, label);
						}
					}
				case _:
			}
		}

		return out;
	}

	/**
	 * Builds the value passed to an OCaml **optional labelled argument** (`?label:`) at a callsite.
	 *
	 * Why:
	 * - OCaml optional labelled parameters have type `'a option`.
	 * - For extern interop we want Haxe callsites to feel natural, so we allow passing:
	 *   - an actual value (`Some v`)
	 *   - `null` as "omit" (`None`)
	 * - reflaxe.ocaml represents nullable primitives (`Null<Int>`, etc.) as `Obj.t` carrying the
	 *   `HxRuntime.hx_null` sentinel. If we unbox too early, we lose that sentinel and can no
	 *   longer distinguish "null means None" from "a real value".
	 *
	 * What:
	 * - Returns an OCaml expression of type `'a option`:
	 *   - literal `null` -> `None`
	 *   - nullable primitive `Obj.t` -> `let tmp = <expr> in if tmp == hx_null then None else Some <unboxed>`
	 *   - non-null value -> `Some (<coerced>)`
	 *
	 * How:
	 * - Uses physical equality (`==`) against `HxRuntime.hx_null` to detect null-sentinel values.
	 * - Avoids producing invalid double-boxing patterns like `Obj.repr (Obj.repr 2)` when Haxe
	 *   inserts redundant casts around `Null<T>` flows.
	 */
	function buildOptionalArgOptionExprForInterop(arg:TypedExpr, expectedType:Type):OcamlExpr {
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

		inline function stripDoubleObjRepr(e:OcamlExpr):OcamlExpr {
			function peelAnnot(x:OcamlExpr):OcamlExpr {
				var cur = x;
				while (true) {
					switch (cur) {
						case OcamlExpr.EAnnot(inner, _):
							cur = inner;
						case _:
							return cur;
					}
				}
				return cur;
			}

			function peelObjReprApp(x:OcamlExpr):Null<OcamlExpr> {
				final p = peelAnnot(x);
				return switch (p) {
					case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]): inner;
					case _: null;
				}
			}

			final inner1 = peelObjReprApp(e);
			if (inner1 == null) return e;
			final inner2 = peelObjReprApp(inner1);
			return inner2 == null ? e : inner1;
		}

		// Fast-path literal null.
		final unwrapped = unwrap(arg);
		final isLiteralNull = switch (unwrapped.expr) {
			case TConst(TNull): true;
			case _: false;
		}
		if (isLiteralNull) return OcamlExpr.EIdent("None");

		final tmp = freshTmp("optarg");

		// Optional labelled args in OCaml are `'a option`. For Haxe interop we accept:
		// - `null` (meaning "omit" / None)
		// - a value
		//
		// For primitive optional args, Haxe will often type arguments as `Null<T>`, which in
		// reflaxe.ocaml is represented as `Obj.t` with the `HxRuntime.hx_null` sentinel.
		//
		// If we eagerly coerce `Null<Int>` to `Int` here (unboxing), we lose the null sentinel
		// and cannot correctly produce `None`. So we build the option wrapper directly.
		if (isIntType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "int":
					final v0 = switch (unwrapped.expr) {
						// Haxe can insert redundant casts around `Null<T>` flows, e.g. `cast (cast 2 : Null<Int>)`.
						// Avoid double-boxing (`Obj.repr (Obj.repr 2)`) by stripping casts where the inner
						// expression is already represented as `Obj.t`.
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])]);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		if (isFloatType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "float":
					final v0 = switch (unwrapped.expr) {
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])]);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		if (isBoolType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "bool":
					final v0 = switch (unwrapped.expr) {
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(
						OcamlExpr.EIdent("Some"),
						[
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"),
								[OcamlExpr.EIdent(tmp)]
							)
						]
					);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		// Non-primitive optional arg: compare via `Obj.repr` so the null sentinel can be detected
		// consistently even when null is represented as `Obj.magic hx_null : t`.
		final coerced = coerceForAssignment(expectedType, arg);
		final objVal = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [coerced]);
		final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
		final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])]);
		return OcamlExpr.ELet(tmp, objVal, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
	}
}

#end
