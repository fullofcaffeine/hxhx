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
	public static function typeResolvedModule(m:ResolvedModule, index:TyperIndex):TypedModule {
		final pm = ResolvedModule.getParsed(m);
		final decl = pm.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final className = HxClassDecl.getName(cls);
		final classFullName = (pkg == null || pkg.length == 0) ? className : (pkg + "." + className);
		final ctx = new TyperContext(index, pm.getFilePath(), ResolvedModule.getModulePath(m), pkg, imports, classFullName);

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
				// No explicit hint: if we couldn't infer anything from the body, default to `Void` to
				// match the common `function f() { ... }` / `static function main()` shape.
				returnExprTy.isUnknown() ? TyType.fromHintText("Void") : returnExprTy;
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
					case "&&" | "||" | "&" | "|":
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.fromHintText("Bool");
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
			case EUnsupported(_):
				TyType.unknown();
		}
	}
}
