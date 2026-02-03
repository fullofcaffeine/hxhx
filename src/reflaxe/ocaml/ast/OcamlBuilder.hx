package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)

import haxe.macro.Expr.Binop;
import haxe.macro.Expr;
import haxe.macro.Expr.Unop;
import haxe.macro.Expr.Position;
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

/**
 * Milestone 2: minimal TypedExpr -> OcamlExpr lowering for expressions and function bodies.
 *
 * Notes:
 * - This pass is intentionally conservative: unsupported constructs emit `()` with a comment where possible.
 * - Local vars declared with `TVar` are treated as `ref` (mutable-by-default) for now; M3 will infer mutability.
 */
class OcamlBuilder {
	public final ctx:CompilationContext;

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

	public function new(ctx:CompilationContext) {
		this.ctx = ctx;
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

	public function buildExpr(e:TypedExpr):OcamlExpr {
		return switch (e.expr) {
			case TTypeExpr(_):
				#if macro
				guardrailError(
					"reflaxe.ocaml (M5): type expressions (class values) are not supported yet (reflection). (bd: haxe.ocaml-28t.6.4)",
					e.pos
				);
				#end
				OcamlExpr.EConst(OcamlConst.CUnit);
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
				buildUnop(op, postFix, inner);
				case TFunction(tfunc):
					buildFunction(tfunc);
				case TIf(cond, eif, eelse):
					if (eelse == null) {
						// Haxe `if (cond) stmt;` is statement-typed (Void). Ensure both branches are `unit`
						// so the OCaml `if` is well-typed, even if `stmt` returns a value (e.g. Array.push).
						OcamlExpr.EIf(
							buildCondition(cond),
							OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(eif)]),
							OcamlExpr.EConst(OcamlConst.CUnit)
						);
					} else {
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
						final expected = e.t;

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
					final builtArgs = args.map(buildExpr);
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
								final allowSuperCtor = !ctx.currentIsHaxeStd && curFull != null && ctx.virtualTypes.exists(curFull);
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

								final builtArgs = args.map(buildExpr);
								final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("self")])].concat(builtArgs);
								// Calling convention: `super()` supplies `unit` when there are no args.
								if (args.length == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
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
													expr: buildOptionalArgOptionExpr(coerced, ea.t)
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
								case _:
									#if macro
									guardrailError("reflaxe.ocaml (M6): Sys." + cf.name + " is not implemented yet.", e.pos);
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
						} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "string" && args.length == 1) {
							buildStdString(args[0]);
						} else {
							final builtArgs = args.map(buildExpr);
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
														buildExpr(args[1]);
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
														buildExpr(args[1]);
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
														buildExpr(args[1]);
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
														buildExpr(args[1]);
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
									final coercedArgs:Array<OcamlExpr> = [];
									if (expectedArgs != null) {
										for (i in 0...args.length) {
											coercedArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
										}
									} else {
										for (a in args) coercedArgs.push(buildExpr(a));
									}

									final unwrappedObj = unwrap(objExpr);
									final isSuperReceiver = switch (unwrappedObj.expr) {
										case TConst(TSuper): true;
										case _: false;
									}

									// Virtual dispatch subset (M10): if the receiver's static type participates in
									// inheritance, call through the record-stored method function (`obj.foo obj ...`).
									final recvFullName = classFullNameFromType(objExpr.t);
									final isVirtualRecv = recvFullName != null && ctx.virtualTypes.exists(recvFullName);

									final allowSuperCall = !ctx.currentIsHaxeStd
										&& ctx.currentTypeFullName != null
										&& ctx.virtualTypes.exists(ctx.currentTypeFullName);

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
										if (args.length == 0) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
										OcamlExpr.EApp(callFn, builtArgs);
									} else if (isVirtualRecv) {
										final recvExpr = buildExpr(objExpr);
										final tmpName = switch (recvExpr) {
											case EIdent(_): null;
											case _: freshTmp("obj");
										}
										final recvVar = tmpName == null ? recvExpr : OcamlExpr.EIdent(tmpName);
										final methodField = OcamlExpr.EField(recvVar, cf.name);
										final callArgs = [recvVar].concat(coercedArgs);
										// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
										if (args.length == 0) callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
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
										if (args.length == 0) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
										OcamlExpr.EApp(callFn, builtArgs);
									}
									}
								case _:
									final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (fn.t) {
										case TFun(fargs, _): fargs;
										case _: null;
									}
									final builtArgs:Array<OcamlExpr> = [];
									if (expectedArgs != null) {
										for (i in 0...args.length) {
											builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
										}
									} else {
										for (a in args) builtArgs.push(buildExpr(a));
									}
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
							final expectedArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (fn.t) {
								case TFun(fargs, _): fargs;
								case _: null;
							}
							final builtArgs:Array<OcamlExpr> = [];
							if (expectedArgs != null) {
								for (i in 0...args.length) {
									builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t, args[i]) : buildExpr(args[i]));
								}
							} else {
								for (a in args) builtArgs.push(buildExpr(a));
							}
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
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]);
					case { from: null, to: "float" } if (isFloatType(e1.t)):
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]);
					case { from: null, to: "float" } if (isIntType(e1.t)):
						OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
							[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(e1)])]
						);
					case { from: null, to: "bool" } if (isBoolType(e1.t)):
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]);
					case { from: "int", to: null } if (isIntType(e.t)):
						safeUnboxNullableInt(buildExpr(e1));
					case { from: "float", to: null } if (isFloatType(e.t)):
						safeUnboxNullableFloat(buildExpr(e1));
					case { from: "bool", to: null } if (isBoolType(e.t)):
						safeUnboxNullableBool(buildExpr(e1));
					case _:
						buildExpr(e1);
				}
			case TEnumParameter(enumValueExpr, ef, index):
				final key = ef.name + ":" + index;
				if (currentEnumParamNames != null && currentEnumParamNames.exists(key)) {
					OcamlExpr.EIdent(currentEnumParamNames.get(key));
				} else {
					final enumType:Null<EnumType> = switch (enumValueExpr.t) {
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
							OcamlExpr.EMatch(buildExpr(enumValueExpr), [
								{ pat: OcamlPat.PConstructor(ctorName, patArgs), guard: null, expr: OcamlExpr.EIdent(wanted) },
								{
									pat: OcamlPat.PAny,
									guard: null,
									expr: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))])
								}
							]);
						}
					}
				}
			case TEnumIndex(_):
				switch (e.expr) {
					case TEnumIndex(enumValueExpr):
						switch (enumValueExpr.t) {
							case TEnum(eRef, _):
								final enumType = eRef.get();
								final scrut = buildExpr(enumValueExpr);
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
								// If the enum has constructors, the match is exhaustive: no default arm
								// (avoid redundant-case warnings under -warn-error).
								if (arms.length == 0) {
									OcamlExpr.EConst(OcamlConst.CInt(-1));
								} else {
									OcamlExpr.EMatch(scrut, arms);
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
							// do {body} while(cond) not supported yet; lower as while for now.
							return OcamlExpr.ETry(OcamlExpr.ESeq([bodyWithContinue, whileExpr]), [breakCase]);
						}

						return loopExpr;
					}

					// do {body} while(cond) not supported yet; lower as while for now
					if (!normalWhile) {
						OcamlExpr.ESeq([
							builtBody,
							OcamlExpr.EWhile(condExpr, builtBody)
						]);
					} else {
						OcamlExpr.EWhile(condExpr, builtBody);
					}
			case TSwitch(scrutinee, cases, edef):
				buildSwitch(scrutinee, cases, edef);
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
			case TObjectDecl(_):
				// Placeholder until class/anon-struct strategy lands.
				OcamlExpr.EConst(OcamlConst.CUnit);
			case TThrow(expr):
				final repr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(expr)]);
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_throw"), [repr]);
			case TTry(tryExpr, catches):
				if (catches.length == 0) {
					buildExpr(tryExpr);
				} else {
					// For now, only support `catch (e:Dynamic)` (M6).
					if (catches.length != 1) {
						#if macro
						guardrailError(
							"reflaxe.ocaml (M6): only `try {..} catch (e:Dynamic) {..}` is supported for now (multiple catches unsupported).",
							e.pos
						);
						#end
						OcamlExpr.EConst(OcamlConst.CUnit);
					} else {
						final c = catches[0];
						final isDynamicCatch = switch (c.v.t) {
							case TDynamic(_): true;
							case _: false;
						}
						if (!isDynamicCatch) {
							#if macro
							guardrailError(
								"reflaxe.ocaml (M6): only `catch (e:Dynamic)` is supported for now (typed catches unsupported).",
								e.pos
							);
							#end
							OcamlExpr.EConst(OcamlConst.CUnit);
						} else {
							final tryFn = OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], buildExpr(tryExpr));
							final catchName = renameVar(c.v.name);
							final handlerFn = OcamlExpr.EFun([OcamlPat.PVar(catchName)], buildExpr(c.expr));
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_try"), [tryFn, handlerFn]);
						}
					}
				}
			case TReturn(ret):
				final valueExpr = ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
				final payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [valueExpr]);
				OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_return"), [payload]));
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildStdString(inner:TypedExpr):OcamlExpr {
		final e = unwrap(inner);
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
						OcamlExpr.EConst(OcamlConst.CString("<object>"));
					}
				}
			case _:
				OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
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
							OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), coerceForAssignment(v.t, e2));
						case TField(obj, FInstance(_, _, cfRef)):
							final cf = cfRef.get();
							switch (cf.kind) {
								case FVar(_, _):
									OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(buildExpr(obj), cf.name), coerceForAssignment(e1.t, e2));
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
						case TArray(arr, idx):
							OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
								[buildExpr(arr), buildExpr(idx), coerceForAssignment(e1.t, e2)]
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
									OcamlExpr.EBinop(OcamlBinop.Add, lhs, toIntExpr(e2));
								}
							case OpSub:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.SubF, lhs, toFloatExpr(e2))
									: OcamlExpr.EBinop(OcamlBinop.Sub, lhs, toIntExpr(e2));
							case OpMult:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.MulF, lhs, toFloatExpr(e2))
									: OcamlExpr.EBinop(OcamlBinop.Mul, lhs, toIntExpr(e2));
							case OpDiv:
								floatMode
									? OcamlExpr.EBinop(OcamlBinop.DivF, lhs, toFloatExpr(e2))
									: OcamlExpr.EBinop(OcamlBinop.Div, lhs, toIntExpr(e2));
							case OpMod:
								floatMode
									? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [lhs, toFloatExpr(e2)])
									: OcamlExpr.EBinop(OcamlBinop.Mod, lhs, toIntExpr(e2));
							case _: OcamlExpr.EConst(OcamlConst.CUnit);
						}
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), rhs);
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
						OcamlExpr.EBinop(OcamlBinop.Add, toIntExpr(e1), toIntExpr(e2));
					}
				}
			case OpSub:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.SubF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EBinop(OcamlBinop.Sub, toIntExpr(e1), toIntExpr(e2));
				}
			case OpMult:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.MulF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EBinop(OcamlBinop.Mul, toIntExpr(e1), toIntExpr(e2));
				}
			case OpDiv:
				// Haxe `/` always produces Float (Int/Int => Float). OCaml needs `/.` with
				// float operands, so we promote ints as needed.
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.DivF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EBinop(OcamlBinop.Div, toIntExpr(e1), toIntExpr(e2));
				}
			case OpMod:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [toFloatExpr(e1), toFloatExpr(e2)]);
				} else {
					OcamlExpr.EBinop(OcamlBinop.Mod, toIntExpr(e1), toIntExpr(e2));
				}
			case OpEq:
				// Null checks must use physical equality (==) so we don't accidentally invoke
				// specialized structural equality (notably for strings).
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysEq, buildExpr(e1), buildExpr(e2));
				} else {
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
					} else {
						OcamlExpr.EBinop(OcamlBinop.Eq, buildExpr(e1), buildExpr(e2));
					}
				}
			case OpNotEq:
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysNeq, buildExpr(e1), buildExpr(e2));
				} else {
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
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
			),
			false
		);
	}

	function coerceForAssignment(lhsType:Type, rhs:TypedExpr):OcamlExpr {
		final lhsKind = nullablePrimitiveKind(lhsType);
		final rhsKind = nullablePrimitiveKind(rhs.t);

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
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				case _:
					buildExpr(rhs);
			}
		}

		// Float slots can accept Int values (promote).
		if (isFloatType(lhsType) && isIntType(rhs.t)) {
			return OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(rhs)]);
		}

		// Class upcasts (inheritance): Derived -> Base requires an explicit cast at the OCaml type level.
		final lhsCls = classTypeFromType(lhsType);
		final rhsCls = classTypeFromType(rhs.t);
		if (lhsCls != null && rhsCls != null) {
			final lhsName = (lhsCls.pack ?? []).concat([lhsCls.name]).join(".");
			final rhsName = (rhsCls.pack ?? []).concat([rhsCls.name]).join(".");
			if (lhsName != rhsName && isSubclassOf(rhsCls, lhsCls)) {
			return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
			}
		}

		return buildExpr(rhs);
	}

	function buildUnop(op:Unop, postFix:Bool, e:TypedExpr):OcamlExpr {
		return switch (op) {
			case OpNot:
				OcamlExpr.EUnop(OcamlUnop.Not, buildExpr(e));
			case OpNeg:
				OcamlExpr.EUnop(OcamlUnop.Neg, buildExpr(e));
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
				//
				// NOTE: This currently assumes `Int` arithmetic (`+`). Supporting `Float`
				// properly requires float operators (`+.`) which we have not modeled yet.
				if (!isIntType(e.t)) {
					#if macro
					guardrailError("reflaxe.ocaml (M6): ++/-- currently supports Int only.", e.pos);
					#end
					OcamlExpr.EConst(OcamlConst.CUnit);
				} else {
					final delta = op == OpIncrement ? 1 : -1;
					final deltaExpr = OcamlExpr.EConst(OcamlConst.CInt(delta));

					inline function incDec(getOld:OcamlExpr, setNew:OcamlExpr->OcamlExpr):OcamlExpr {
						final oldName = freshTmp("old");
						final newName = freshTmp("new");
						final updated = OcamlExpr.EBinop(OcamlBinop.Add, OcamlExpr.EIdent(oldName), deltaExpr);
						final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNew(OcamlExpr.EIdent(newName))]);
						final resultName = postFix ? oldName : newName;
						return OcamlExpr.ELet(
							oldName,
							getOld,
							OcamlExpr.ELet(
								newName,
								updated,
								OcamlExpr.ESeq([setExpr, OcamlExpr.EIdent(resultName)]),
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
		// Mutability inference: decide which locals become `ref` by scanning for assignments.
		final mutatedIds = collectMutatedLocalIdsFromExprs(exprs);
		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = mutatedIds;
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
				final rhs = if (isMutable) {
					refLocals.set(v.id, true);
					OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
				} else {
					refLocals.remove(v.id);
					initExpr;
				}
				OcamlExpr.ELet(renameVar(v.name), rhs, buildBlockFromIndex(exprs, index + 1, allowDirectReturn), false);
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
		final mutatedIds = collectMutatedLocalIdsFromExprs(exprs);
		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = mutatedIds;
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
		final mutatedIds = collectMutatedLocalIds(bodyExpr);

		final params = args.length == 0
			? [OcamlPat.PConst(OcamlConst.CUnit)]
			: args.map(a -> OcamlPat.PVar(renameVar(a.name)));

		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = mutatedIds;
		for (a in args) {
			if (mutatedIds.exists(a.id) && mutatedIds.get(a.id) == true) {
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
			if (mutatedIds.exists(a.id) && mutatedIds.get(a.id) == true) {
				final n = renameVar(a.name);
				body = OcamlExpr.ELet(n, OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EIdent(n)]), body, false);
			}
		}

		currentMutatedLocalIds = prev;
		return OcamlExpr.EFun(params, body);
	}

	public function buildFunction(tfunc:haxe.macro.Type.TFunc):OcamlExpr {
		final mutatedIds = collectMutatedLocalIds(tfunc.expr);

		// Determine parameters and wrap mutated parameters as refs inside the body.
		final params = tfunc.args.length == 0
			? [OcamlPat.PConst(OcamlConst.CUnit)]
			: tfunc.args.map(a -> OcamlPat.PVar(renameVar(a.v.name)));

		final prev = currentMutatedLocalIds;
		currentMutatedLocalIds = mutatedIds;
		for (a in tfunc.args) {
			if (mutatedIds.exists(a.v.id) && mutatedIds.get(a.v.id) == true) {
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
			if (mutatedIds.exists(a.v.id) && mutatedIds.get(a.v.id) == true) {
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

	function buildSwitch(
		scrutinee:TypedExpr,
		cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>,
		edef:Null<TypedExpr>
	):OcamlExpr {
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
								final expr = buildExpr(c.expr);
								currentEnumParamNames = prev;
	
								arms.push({ pat: pat, guard: null, expr: expr });
							}

						if (!isExhaustive) {
							arms.push({
								pat: OcamlPat.PAny,
								guard: null,
								expr: edef != null ? buildExpr(edef) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))])
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
			final expr = buildExpr(c.expr);
			currentEnumParamNames = prev;

			arms.push({ pat: pat, guard: null, expr: expr });
		}
		arms.push({
			pat: OcamlPat.PAny,
			guard: null,
			expr: edef != null ? buildExpr(edef) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))])
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
				final defaultBranch = edef != null
					? buildExpr(edef)
					: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))]);

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
						firstNullCaseExpr = buildExpr(c.expr);
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
					final expr = buildExpr(c.expr);
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
				if (!ctx.currentIsHaxeStd && cls.pack != null && cls.pack.length == 0 && (cls.name == "Type" || cls.name == "Reflect")) {
					guardrailError(
						"reflaxe.ocaml (M5): Haxe reflection is not supported yet (" + cls.name + "." + cfRef.get().name + "). "
						+ "Avoid Type/Reflect for now, or add an OCaml extern and call native APIs. (bd: haxe.ocaml-28t.6.4)",
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
					return (selfMod != null && selfMod == modName)
						? OcamlExpr.EIdent(scoped)
						: OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
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
					case _:
						#if macro
						guardrailError(
							"reflaxe.ocaml (M5): taking a method as a value (bound closure) is not supported yet ('" + cf.name + "'). "
							+ "Call it directly (obj." + cf.name + "(...)) or wrap it in a lambda. (bd: haxe.ocaml-28t.6.4)",
							pos
						);
						#end
						// Methods are handled at the callsite; as a value, we currently can't represent them.
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case FDynamic(name):
				#if macro
				guardrailError(
					"reflaxe.ocaml (M5): dynamic field access is not supported yet ('" + name + "'). "
					+ "Avoid Reflect/dynamic objects for now. (bd: haxe.ocaml-28t.6.4)",
					pos
				);
				#end
				OcamlExpr.EConst(OcamlConst.CUnit);
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
					case _:
						OcamlExpr.EField(buildExpr(obj), cf.name);
				}
			case _:
				// For now, treat unknown field access as unit.
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
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

	function buildOptionalArgOptionExpr(coerced:OcamlExpr, expectedType:Type):OcamlExpr {
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		final tmp = freshTmp("optarg");

		// For `Null<Int>/Null<Float>/Null<Bool>` we represent values as Obj.t already.
		// For everything else, compare via `Obj.repr` so the null sentinel can be detected consistently.
		final objVal = (nullablePrimitiveKind(expectedType) != null)
			? coerced
			: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [coerced]);

		final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
		final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])]);

		return OcamlExpr.ELet(tmp, objVal, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
	}
}

#end
