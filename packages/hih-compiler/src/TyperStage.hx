/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
	static inline function isStrict():Bool {
		final v = Sys.getEnv("HXHX_TYPER_STRICT");
		return v == "1" || v == "true" || v == "yes";
	}

	static function arrayElementType(t:TyType):Null<TyType> {
		if (t == null) return null;
		final d = t.getDisplay();
		if (d == null) return null;
		if (!StringTools.startsWith(d, "Array<")) return null;
		if (!StringTools.endsWith(d, ">")) return null;
		final inner = StringTools.trim(d.substr("Array<".length, d.length - "Array<".length - 1));
		return inner.length == 0 ? TyType.unknown() : TyType.fromHintText(inner);
	}

	static function typeFromHintInContext(hint:String, ctx:TyperContext):TyType {
		final raw = hint == null ? "" : StringTools.trim(hint);
		if (raw.length == 0) return TyType.unknown();
		// Keep primitive-like names stable.
		switch (raw) {
			case "Int", "Float", "Bool", "String", "Void", "Dynamic", "Null":
				return TyType.fromHintText(raw);
			case _:
		}

		// Best-effort: resolve short names against the current module context.
		final c = ctx == null ? null : ctx.resolveType(raw);
		return c != null ? TyType.fromHintText(c.getFullName()) : TyType.fromHintText(raw);
	}

	/**
		Type a parsed module into a minimal `TypedModule`.

		Why:
		- Later stages (macro expansion + backend codegen) need a stable typed
		  surface, even before we implement the full Haxe type system.
		- For `hih-compiler` acceptance, we care about determinism and basic type
		  inference for literals and simple `return` expressions.

		What:
		- Builds a `TyModuleEnv` containing:
		  - package/import summary
		  - a `TyClassEnv` with per-function environments

		How:
		- Stage 3: we build a real local scope per function (params + locals) and
		  infer return types when no explicit return hint exists.
	**/
	public static function typeModule(m:ParsedModule):TypedModule {
		final decl = m.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final className = HxClassDecl.getName(cls);
		final classFullName = (pkg == null || pkg.length == 0) ? className : (pkg + "." + className);
		final ctx = new TyperContext(null, m.getFilePath(), "", pkg, imports, classFullName);

		final typedFns = new Array<TyFunctionEnv>();
		for (fn in HxClassDecl.getFunctions(cls)) {
			typedFns.push(typeFunction(fn, ctx));
		}

		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), typedFns);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(m, env);
	}

	/**
		Type a resolved module using a shared program index.

		Why
		- Stage 3.3 needs cross-module knowledge (imports, class fields, statics)
		  to type `Util.ping()` and `this.x` in upstream-shaped code.
	**/
	public static function typeResolvedModule(m:ResolvedModule, index:TyperIndex, ?loader:ModuleLoader):TypedModule {
		final pm = ResolvedModule.getParsed(m);
		final decl = pm.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final className = HxClassDecl.getName(cls);
		final classFullName = (pkg == null || pkg.length == 0) ? className : (pkg + "." + className);
		final ctx = new TyperContext(index, pm.getFilePath(), ResolvedModule.getModulePath(m), pkg, imports, classFullName, loader);

		final typedFns = new Array<TyFunctionEnv>();
		for (fn in HxClassDecl.getFunctions(cls)) typedFns.push(typeFunction(fn, ctx));
		final classEnv = new TyClassEnv(className, typedFns);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(pm, env);
	}

	static function typeFunction(fn:HxFunctionDecl, ctx:TyperContext):TyFunctionEnv {
		// Stage 3 local scope:
		// - parameters (type hints, if any)
		// - locals (not parsed yet; reserved for later)
		final params = new Array<TySymbol>();
		for (arg in HxFunctionDecl.getArgs(fn)) {
			final name = HxFunctionArg.getName(arg);
			final ty = typeFromHintInContext(HxFunctionArg.getTypeHint(arg), ctx);
			params.push(new TySymbol(name, ty));
		}

			final locals = new Array<TySymbol>();
			final scope = new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, TyType.unknown(), TyType.unknown());

			final returnExprTy = inferReturnType(fn, scope, ctx);
			final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
			final retTy = if (retHintText != null && retHintText.length > 0) {
				final hinted = typeFromHintInContext(retHintText, ctx);
				// If we couldn't infer a concrete return type (e.g. because the parser produced an
				// empty/unsupported body), keep bring-up moving by trusting the explicit hint.
				if (!returnExprTy.isUnknown()) {
					final unified = TyType.unify(hinted, returnExprTy);
					if (unified == null) {
						if (isStrict()) {
							throw new TyperError(ctx.getFilePath(), HxPos.unknown(),
								"return type hint " + hinted + " conflicts with inferred return " + returnExprTy
							);
						}
						// Bring-up default: trust the explicit hint and continue.
					}
				}
				hinted;
				} else {
					// No explicit hint:
					// - If we inferred a return type from `return` statements, use it.
					// - Otherwise, default to `Void` to match the common `function f() { ... }` / `static function main()` shape.
					//
					// Bring-up heuristic:
					// - The native frontend protocol can capture a "first return string literal" even when
					//   we can't parse a complex body (e.g. a `switch` with returns in cases).
					// - If present, treat the function as returning `String` instead of collapsing to `Void`.
					if (!returnExprTy.isUnknown()) {
						returnExprTy;
					} else {
						final retStr = HxFunctionDecl.getReturnStringLiteral(fn);
						(retStr != null && retStr.length > 0) ? TyType.fromHintText("String") : TyType.fromHintText("Void");
					}
				}

			return new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, retTy, returnExprTy);
		}

	static function inferReturnType(fn:HxFunctionDecl, scope:TyFunctionEnv, ctx:TyperContext):TyType {
		var out:Null<TyType> = null;

		function unifyInto(t:TyType, pos:HxPos):Void {
			if (out == null) {
				out = t;
				return;
			}
			final u = TyType.unify(out, t);
			if (u == null) {
				if (isStrict()) {
					throw new TyperError(
						ctx.getFilePath(),
						pos,
						"incompatible return types: " + out + " vs " + t
					);
				}
				// Bring-up default: collapse to Dynamic to keep typing moving.
				out = TyType.fromHintText("Dynamic");
				return;
			}
			out = u;
		}

			function typeStmt(s:HxStmt):Void {
				switch (s) {
				case SBlock(stmts, _pos):
					for (ss in stmts) typeStmt(ss);
				case SIf(cond, thenBranch, elseBranch, pos):
					// Best-effort: ensure the condition is at least type-checked for locals.
					inferExprType(cond, scope, ctx, pos);
					typeStmt(thenBranch);
					if (elseBranch != null) typeStmt(elseBranch);
					case SForIn(name, iterable, body, pos):
						// Bring-up: type-check the iterable expression and bind the loop variable.
						//
						// We intentionally model the loop variable as a function-local symbol for now
						// (not a nested scope) so later statements can still reference it during bring-up.
						final iterableTy = inferExprType(iterable, scope, ctx, pos);
						final loopTy = switch (iterable) {
							case ERange(_, _):
								TyType.fromHintText("Int");
							case _:
								// Best-effort: if we can see an `Array<T>` element type, propagate it
								// to the loop variable so string/number-heavy harness code can emit.
								final elem = arrayElementType(iterableTy);
								(elem != null && !elem.isUnknown()) ? elem : TyType.fromHintText("Dynamic");
						}
						scope.declareLocal(name, loopTy);
						typeStmt(body);
						case SVar(name, typeHint, init, pos):
						// Declare first so subsequent statements can reference the symbol deterministically.
						final hinted = typeFromHintInContext(typeHint, ctx);
						final sym = scope.declareLocal(name, hinted);
						if (init != null) {
							final initTy = inferExprType(init, scope, ctx, pos);
							final u = TyType.unify(sym.getType(), initTy);
						if (u == null) {
							if (isStrict()) {
								throw new TyperError(
									ctx.getFilePath(),
									pos,
									"initializer type " + initTy + " is not compatible with local " + name + ":" + sym.getType()
								);
							}
							// Bring-up default: widen locals to Dynamic when inference disagrees.
							sym.setType(TyType.fromHintText("Dynamic"));
							return;
						}
						sym.setType(u);
					}
				case SReturnVoid(pos):
					unifyInto(TyType.fromHintText("Void"), pos);
				case SReturn(e, pos):
					final t = inferExprType(e, scope, ctx, pos);
					unifyInto(t, pos);
				case SExpr(e, pos):
					inferExprType(e, scope, ctx, pos);
			}
		}

			for (s in HxFunctionDecl.getBody(fn)) typeStmt(s);
			// If we saw no explicit returns, the true return type depends on surrounding typing rules.
			// For bootstrap bring-up we return `Unknown` here so `typeFunction` can:
			// - trust an explicit return type hint, or
			// - default to `Void` when no hint is provided.
			return out == null ? TyType.unknown() : out;
		}

	static function inferExprType(expr:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyType {
		return switch (expr) {
			case ENull:
				TyType.fromHintText("Null");
			case EBool(_):
				TyType.fromHintText("Bool");
			case EString(_):
				TyType.fromHintText("String");
			case EInt(_):
				TyType.fromHintText("Int");
			case EFloat(_):
				TyType.fromHintText("Float");
			case EThis:
				{
					final full = ctx.getClassFullName();
					full.length == 0 ? TyType.unknown() : TyType.fromHintText(full);
				}
			case ESuper:
				// Stage 3: `super` typing requires class hierarchy (future stage).
				TyType.unknown();
			case EIdent(name):
				final sym = scope.resolveSymbol(name);
				if (sym != null) {
					sym.getType();
				} else {
					final t = ctx.resolveType(name);
					t != null ? TyType.fromHintText(t.getFullName()) : TyType.unknown();
				}
			case EField(obj, _field):
				switch (obj) {
					case EThis:
						final c = ctx.currentClass();
						if (c != null) {
							final ft = c.fieldType(_field);
							ft != null ? ft : TyType.unknown();
						} else {
							TyType.unknown();
						}
					case _:
						// Best-effort: infer child for locals; actual field typing depends on the index.
						final objTy = inferExprType(obj, scope, ctx, pos);
						final idx = ctx.getIndex();
						final c = idx == null ? null : idx.getByFullName(objTy.getDisplay());
						if (c != null) {
							final ft = c.fieldType(_field);
							ft != null ? ft : TyType.unknown();
						} else {
							TyType.unknown();
						}
				}
				case ECall(callee, args):
					// Best-effort: type children for local inference, and use the index when we can.
					switch (callee) {
					case EField(obj, field):
						// Static call through a type name (imported or same-package): `Util.ping()`.
						switch (obj) {
							case EIdent(typeName):
								final c = ctx.resolveType(typeName);
								if (c != null) {
									for (a in args) inferExprType(a, scope, ctx, pos);
									final sig = c.staticMethod(field);
									sig != null ? sig.getReturnType() : TyType.unknown();
								} else {
									// `obj` is a value identifier (local/param), not a type name.
									final objTy = inferExprType(obj, scope, ctx, pos);
									for (a in args) inferExprType(a, scope, ctx, pos);
									final idx = ctx.getIndex();
									final c2 = idx == null ? null : idx.getByFullName(objTy.getDisplay());
									if (c2 != null) {
										final sig = c2.instanceMethod(field);
										sig != null ? sig.getReturnType() : TyType.unknown();
									} else {
										TyType.unknown();
									}
								}
							case EThis:
								final c = ctx.currentClass();
								for (a in args) inferExprType(a, scope, ctx, pos);
								if (c != null) {
									final sig = c.instanceMethod(field);
									sig != null ? sig.getReturnType() : TyType.unknown();
								} else {
									TyType.unknown();
								}
							case _:
								final objTy = inferExprType(obj, scope, ctx, pos);
								for (a in args) inferExprType(a, scope, ctx, pos);
								final idx = ctx.getIndex();
								final c = idx == null ? null : idx.getByFullName(objTy.getDisplay());
								if (c != null) {
									final sig = c.instanceMethod(field);
									sig != null ? sig.getReturnType() : TyType.unknown();
								} else {
									TyType.unknown();
								}
						}
					case _:
						inferExprType(callee, scope, ctx, pos);
						for (a in args) inferExprType(a, scope, ctx, pos);
						TyType.unknown();
					}
				case ELambda(argNames, body):
					// Stage 3 bring-up: type the body in a nested scope that:
					// - introduces lambda args (shadowing outer locals/params),
					// - but preserves visibility of outer locals/params for capture.
					//
					// We intentionally return `Dynamic` as the lambda value type for now.
					final lambdaArgs = new Array<TySymbol>();
					for (n in argNames) lambdaArgs.push(new TySymbol(n, TyType.fromHintText("Dynamic")));
					final combinedParams = lambdaArgs.concat(scope.getParams().copy());
					final combinedLocals = scope.getLocals().copy();
					final nested = new TyFunctionEnv("<lambda>", combinedParams, combinedLocals, TyType.unknown(), TyType.unknown());
					inferExprType(body, nested, ctx, pos);
					TyType.fromHintText("Dynamic");
				case ETryCatchRaw(_raw):
					// Stage 3 bring-up: we only preserve the shape of `try/catch` in the expression tree.
					// Correct semantics are Stage 4+ work, so we type it as `Dynamic` here.
					TyType.fromHintText("Dynamic");
				case ESwitchRaw(_raw):
					// Stage 3 bring-up: we only preserve the shape of `switch` expressions so parsing/typing
					// can proceed deterministically through upstream-shaped code (notably runci).
					// Correct semantics (pattern matching + guards + value typing) are Stage 4+ work.
					TyType.fromHintText("Dynamic");
				case ENew(_typePath, args):
					for (a in args) inferExprType(a, scope, ctx, pos);
					final c = ctx.resolveType(_typePath);
					c != null ? TyType.fromHintText(c.getFullName()) : TyType.fromHintText(_typePath);
			case EUnop(_op, e):
				switch (_op) {
					case "!":
						inferExprType(e, scope, ctx, pos);
						TyType.fromHintText("Bool");
					case "-" | "+":
						final inner = inferExprType(e, scope, ctx, pos);
						inner.isNumeric() ? inner : TyType.unknown();
					case _:
						inferExprType(e, scope, ctx, pos);
						TyType.unknown();
				}
			case EBinop(op, a, b):
				switch (op) {
					case "=":
						// Assignment as expression.
								final rhs = inferExprType(b, scope, ctx, pos);
								switch (a) {
								case EIdent(name):
									final sym = scope.resolveSymbol(name);
									if (sym != null) {
										final u = TyType.unify(sym.getType(), rhs);
										if (u == null) {
											// Bootstrap: don't fail hard on complex types (generics, abstracts, etc.).
											// Keep typing moving by widening to Dynamic.
											sym.setType(TyType.fromHintText("Dynamic"));
											rhs;
										} else {
											sym.setType(u);
											rhs;
										}
									} else {
										rhs;
									}
							case _:
								// Field assignment typing needs class env (future stage).
								inferExprType(a, scope, ctx, pos);
								rhs;
						}
					case "==" | "!=" | "<" | "<=" | ">" | ">=":
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.fromHintText("Bool");
					case "&&" | "||":
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.fromHintText("Bool");
					case "&" | "|" | "^" | "<<" | ">>" | ">>>":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						// Best-effort: treat as Bool if both operands are Bool; otherwise Int.
						(ta.getDisplay() == "Bool" && tb.getDisplay() == "Bool")
							? TyType.fromHintText("Bool")
							: TyType.fromHintText("Int");
					case "+":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						if (ta.getDisplay() == "String" || tb.getDisplay() == "String") {
							TyType.fromHintText("String");
						} else {
							final u = TyType.unify(ta, tb);
							u != null && u.isNumeric() ? u : TyType.unknown();
						}
					case "-" | "*" | "/" | "%":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final u = TyType.unify(ta, tb);
						u != null && u.isNumeric() ? u : TyType.unknown();
					case _:
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.unknown();
				}
				case ETernary(cond, thenExpr, elseExpr):
					inferExprType(cond, scope, ctx, pos);
					final t1 = inferExprType(thenExpr, scope, ctx, pos);
					final t2 = inferExprType(elseExpr, scope, ctx, pos);
					final u = TyType.unify(t1, t2);
					u == null ? TyType.fromHintText("Dynamic") : u;
				case EAnon(_names, values):
					for (v in values) inferExprType(v, scope, ctx, pos);
					TyType.fromHintText("Dynamic");
					case EArrayDecl(values):
						var elem:TyType = TyType.unknown();
						var saw = false;
						for (v in values) {
							final vt = inferExprType(v, scope, ctx, pos);
							if (!saw) {
								saw = true;
								elem = vt;
								continue;
							}
							final u = TyType.unify(elem, vt);
							if (u == null) {
								elem = TyType.fromHintText("Dynamic");
								break;
							}
							elem = u;
						}
						if (!saw) elem = TyType.fromHintText("Dynamic");
						TyType.fromHintText("Array<" + elem.getDisplay() + ">");
					case EArrayAccess(array, index):
						inferExprType(array, scope, ctx, pos);
						inferExprType(index, scope, ctx, pos);
						// Stage3: indexing semantics depend on the concrete container type (Array/Bytes/String/etc).
					TyType.fromHintText("Dynamic");
				case ERange(start, end):
					inferExprType(start, scope, ctx, pos);
					inferExprType(end, scope, ctx, pos);
					// Bring-up: `start...end` is primarily used as a loop iterable; model it as Dynamic.
					TyType.fromHintText("Dynamic");
				case ECast(expr, typeHint):
					final inner = inferExprType(expr, scope, ctx, pos);
					final hinted = typeFromHintInContext(typeHint, ctx);
					hinted.isUnknown() ? inner : hinted;
				case EUntyped(expr):
					inferExprType(expr, scope, ctx, pos);
					TyType.fromHintText("Dynamic");
				case EUnsupported(_):
					TyType.unknown();
			}
		}
	}
