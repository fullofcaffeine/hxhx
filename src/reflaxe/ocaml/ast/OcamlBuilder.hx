package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)

import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TConstant;
import haxe.macro.TypedExprTools;

import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
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

	static function isStringType(t:Type):Bool {
		return switch (t) {
			case TInst(cRef, _):
				final c = cRef.get();
				isStdStringClass(c);
			case _:
				false;
		}
	}

	static function unwrap(e:TypedExpr):TypedExpr {
		var current = e;
		while (true) {
			switch (current.expr) {
				case TParenthesis(inner):
					current = inner;
				case TMeta(_, inner):
					current = inner;
				case TCast(inner, _):
					current = inner;
				case _:
					return current;
			}
		}
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
				// Inheritance isn't supported yet; treat as `self` for now.
				OcamlExpr.EIdent("self");
			case TConst(c):
				OcamlExpr.EConst(buildConst(c));
			case TLocal(v):
				buildLocal(v);
			case TIdent(s):
				OcamlExpr.EIdent(s);
			case TParenthesis(inner):
				buildExpr(inner);
			case TBinop(op, e1, e2):
				buildBinop(op, e1, e2);
			case TUnop(op, postFix, inner):
				buildUnop(op, postFix, inner);
			case TFunction(tfunc):
				buildFunction(tfunc);
			case TIf(cond, eif, eelse):
				OcamlExpr.EIf(buildExpr(cond), buildExpr(eif), eelse != null ? buildExpr(eelse) : OcamlExpr.EConst(OcamlConst.CUnit));
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
				} else {
					final modName = moduleIdToOcamlModuleName(cls.module);
					final fn = OcamlExpr.EField(OcamlExpr.EIdent(modName), "create");
					final builtArgs = args.map(buildExpr);
					OcamlExpr.EApp(fn, builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
				}
			case TCall(fn, args):
				switch (fn.expr) {
					case TField(_, FStatic(clsRef, cfRef)):
						final cls = clsRef.get();
						final cf = cfRef.get();
						if (isStdStringClass(cls) && cf.name == "fromCharCode" && args.length == 1) {
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "fromCharCode"), [buildExpr(args[0])]);
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
											OcamlExpr.EApp(
												OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "charCodeAt"),
												[self, buildExpr(args[0])]
											);
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
								} else {
									final modName = moduleIdToOcamlModuleName(cls.module);
									final callFn = OcamlExpr.EField(OcamlExpr.EIdent(modName), cf.name);
									final builtArgs = [buildExpr(objExpr)].concat(args.map(buildExpr));
									// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
									if (args.length == 0) builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
									OcamlExpr.EApp(callFn, builtArgs);
								}
							case _:
								final builtArgs = args.map(buildExpr);
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
						final builtArgs = args.map(buildExpr);
						OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
				}
			case TField(obj, fa):
				buildField(obj, fa, e.pos);
			case TMeta(_, e1):
				buildExpr(e1);
			case TCast(e1, _):
				buildExpr(e1);
			case TEnumParameter(_, ef, index):
				final key = ef.name + ":" + index;
				currentEnumParamNames != null && currentEnumParamNames.exists(key)
					? OcamlExpr.EIdent(currentEnumParamNames.get(key))
					: OcamlExpr.EConst(OcamlConst.CUnit);
			case TEnumIndex(_):
				// TODO: implement enum index support (used by pattern matcher internals).
				OcamlExpr.EConst(OcamlConst.CUnit);
			case TWhile(cond, body, normalWhile):
				// do {body} while(cond) not supported yet; lower as while for now
				if (!normalWhile) {
					OcamlExpr.ESeq([
						OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(body)]),
						OcamlExpr.EWhile(buildExpr(cond), buildExpr(body))
					]);
				} else {
					OcamlExpr.EWhile(buildExpr(cond), buildExpr(body));
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
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildStdString(inner:TypedExpr):OcamlExpr {
		final e = unwrap(inner);
		switch (e.expr) {
			case TConst(TNull):
				return OcamlExpr.EConst(OcamlConst.CString("null"));
			case _:
		}

		return switch (e.t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_int"), [buildExpr(e)]);
					case "Float":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_float"), [buildExpr(e)]);
					case "Bool":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_bool"), [buildExpr(e)]);
					default:
						OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
				}
			case TInst(cRef, _):
				final c = cRef.get();
				if (isStdStringClass(c)) {
					buildExpr(e);
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
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(modName), "toString"), [buildExpr(e), OcamlExpr.EConst(OcamlConst.CUnit)]);
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

		// reserved words are handled by Reflaxe reservedVarNames; keep deterministic suffix as backup.
		final renamed = name;
		ctx.variableRenameMap.set(name, renamed);
		return renamed;
	}

	function buildVarDecl(v:TVar, init:Null<TypedExpr>):OcamlExpr {
		// Kept for compatibility when TVar occurs outside of a block (rare in typed output).
		// Prefer `buildBlock` handling for correct scoping.
		final initExpr = init != null ? buildExpr(init) : defaultValueForType(v.t);
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
		return switch (t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					default: OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case TInst(cRef, _):
				final c = cRef.get();
				switch (c.name) {
					case "String": OcamlExpr.EConst(OcamlConst.CString(""));
					case _: OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildBinop(op:Binop, e1:TypedExpr, e2:TypedExpr):OcamlExpr {
		return switch (op) {
			case OpAssign:
				// Handle local ref assignment: x = v  ->  x := v
				switch (e1.expr) {
					case TLocal(v) if (isRefLocalId(v.id)):
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), buildExpr(e2));
					case TField(obj, FInstance(_, _, cfRef)):
						final cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _):
								OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(buildExpr(obj), cf.name), buildExpr(e2));
							case _:
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
					case TArray(arr, idx):
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"), [buildExpr(arr), buildExpr(idx), buildExpr(e2)]);
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case OpAssignOp(inner):
				// Handle compound assignment for ref locals:
				// x += v  ->  x := (!x) + v
				switch (e1.expr) {
					case TLocal(v) if (isRefLocalId(v.id)):
						final lhs = buildLocal(v);
						final rhs = switch (inner) {
							case OpAdd:
								if (isStringType(v.t) || isStringType(e2.t)) {
									final r = isStringType(e2.t) ? buildExpr(e2) : buildStdString(e2);
									OcamlExpr.EBinop(OcamlBinop.Concat, lhs, r);
								} else {
									OcamlExpr.EBinop(OcamlBinop.Add, lhs, buildExpr(e2));
								}
							case OpSub: OcamlExpr.EBinop(OcamlBinop.Sub, lhs, buildExpr(e2));
							case OpMult: OcamlExpr.EBinop(OcamlBinop.Mul, lhs, buildExpr(e2));
							case OpDiv: OcamlExpr.EBinop(OcamlBinop.Div, lhs, buildExpr(e2));
							case OpMod: OcamlExpr.EBinop(OcamlBinop.Mod, lhs, buildExpr(e2));
							case _: OcamlExpr.EConst(OcamlConst.CUnit);
						}
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), rhs);
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case OpAdd:
				if (isStringType(e1.t) || isStringType(e2.t)) {
					final lhs = isStringType(e1.t) ? buildExpr(e1) : buildStdString(e1);
					final rhs = isStringType(e2.t) ? buildExpr(e2) : buildStdString(e2);
					OcamlExpr.EBinop(OcamlBinop.Concat, lhs, rhs);
				} else {
					OcamlExpr.EBinop(OcamlBinop.Add, buildExpr(e1), buildExpr(e2));
				}
			case OpSub: OcamlExpr.EBinop(OcamlBinop.Sub, buildExpr(e1), buildExpr(e2));
			case OpMult: OcamlExpr.EBinop(OcamlBinop.Mul, buildExpr(e1), buildExpr(e2));
			case OpDiv: OcamlExpr.EBinop(OcamlBinop.Div, buildExpr(e1), buildExpr(e2));
			case OpMod: OcamlExpr.EBinop(OcamlBinop.Mod, buildExpr(e1), buildExpr(e2));
			case OpEq: OcamlExpr.EBinop(OcamlBinop.Eq, buildExpr(e1), buildExpr(e2));
			case OpNotEq: OcamlExpr.EBinop(OcamlBinop.Neq, buildExpr(e1), buildExpr(e2));
			case OpLt: OcamlExpr.EBinop(OcamlBinop.Lt, buildExpr(e1), buildExpr(e2));
			case OpLte: OcamlExpr.EBinop(OcamlBinop.Lte, buildExpr(e1), buildExpr(e2));
			case OpGt: OcamlExpr.EBinop(OcamlBinop.Gt, buildExpr(e1), buildExpr(e2));
			case OpGte: OcamlExpr.EBinop(OcamlBinop.Gte, buildExpr(e1), buildExpr(e2));
			case OpBoolAnd: OcamlExpr.EBinop(OcamlBinop.And, buildExpr(e1), buildExpr(e2));
			case OpBoolOr: OcamlExpr.EBinop(OcamlBinop.Or, buildExpr(e1), buildExpr(e2));
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildUnop(op:Unop, postFix:Bool, e:TypedExpr):OcamlExpr {
		return switch (op) {
			case OpNot:
				OcamlExpr.EUnop(OcamlUnop.Not, buildExpr(e));
			case OpNeg:
				OcamlExpr.EUnop(OcamlUnop.Neg, buildExpr(e));
			case OpIncrement, OpDecrement:
				// ++x / x++ / --x / x--: support for ref locals only (M3).
				switch (e.expr) {
					case TLocal(v) if (isRefLocalId(v.id)):
						final delta = op == OpIncrement ? 1 : -1;
						final next = OcamlExpr.EBinop(
							OcamlBinop.Add,
							buildLocal(v),
							OcamlExpr.EConst(OcamlConst.CInt(delta))
						);
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), next);
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
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
		final result = buildBlockFromIndex(exprs, 0);
		currentMutatedLocalIds = prev;
		currentUsedLocalIds = prevUsed;
		return result;
	}

	function buildBlockFromIndex(exprs:Array<TypedExpr>, index:Int):OcamlExpr {
		if (index >= exprs.length) return OcamlExpr.EConst(OcamlConst.CUnit);

		final e = exprs[index];
		return switch (e.expr) {
			case TVar(v, init):
				final isUsed = currentUsedLocalIds != null
					&& currentUsedLocalIds.exists(v.id)
					&& currentUsedLocalIds.get(v.id) == true;

				if (!isUsed) {
					final rest = buildBlockFromIndex(exprs, index + 1);
					if (init == null) return rest;
					final initUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(init)]);
					return switch (rest) {
						case ESeq(items): OcamlExpr.ESeq([initUnit].concat(items));
						case _: OcamlExpr.ESeq([initUnit, rest]);
					}
				}

				final initExpr = init != null ? buildExpr(init) : defaultValueForType(v.t);
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
				OcamlExpr.ELet(renameVar(v.name), rhs, buildBlockFromIndex(exprs, index + 1), false);
			case TReturn(ret):
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case _:
				final current = buildExpr(e);
				if (index == exprs.length - 1) {
					current;
				} else {
					final currentUnit = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [current]);
					final rest = buildBlockFromIndex(exprs, index + 1);
					switch (rest) {
						case ESeq(items):
							OcamlExpr.ESeq([currentUnit].concat(items));
						case _:
							OcamlExpr.ESeq([currentUnit, rest]);
					}
				}
		}
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

		var body = buildExpr(bodyExpr);

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

		var body = buildExpr(tfunc.expr);

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
		function visit(e:TypedExpr):TypedExpr {
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
			return TypedExprTools.map(e, visit);
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
		function visit(e:TypedExpr):TypedExpr {
			switch (e.expr) {
				case TLocal(v):
					used.set(v.id, true);
				case _:
			}
			return TypedExprTools.map(e, visit);
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
				final modName = moduleIdToOcamlModuleName(cls.module);
				OcamlExpr.EField(OcamlExpr.EIdent(modName), cf.name);
			case FInstance(clsRef, _, cfRef):
				final cls = clsRef.get();
				final cf = cfRef.get();
				switch (cf.kind) {
					case FVar(_, _):
						if (isStdArrayClass(cls) && cf.name == "length") {
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(obj)]);
						} else if (isStdStringClass(cls) && cf.name == "length") {
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"), [buildExpr(obj)]);
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
}

#end
