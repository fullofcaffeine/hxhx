/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
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
			final ty = TyType.fromHintText(HxFunctionArg.getTypeHint(arg));
			params.push(new TySymbol(name, ty));
		}

		final locals = new Array<TySymbol>();
		final scope = new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, TyType.unknown(), TyType.unknown());

		final returnExprTy = inferReturnType(fn, scope, ctx);
		final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
		final retTy = if (retHintText != null && retHintText.length > 0) {
			final hinted = TyType.fromHintText(retHintText);
			final unified = TyType.unify(hinted, returnExprTy);
			if (unified == null) {
				throw new TyperError(ctx.getFilePath(), HxPos.unknown(), "return type hint " + hinted + " conflicts with inferred return " + returnExprTy);
			}
			hinted;
		} else {
			returnExprTy;
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
				throw new TyperError(
					ctx.getFilePath(),
					pos,
					"incompatible return types: " + out + " vs " + t
				);
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
					final hinted = TyType.fromHintText(typeHint);
					final sym = scope.declareLocal(name, hinted);
					if (init != null) {
						final initTy = inferExprType(init, scope, ctx, pos);
						final u = TyType.unify(sym.getType(), initTy);
						if (u == null) {
							throw new TyperError(
								ctx.getFilePath(),
								pos,
								"initializer type " + initTy + " is not compatible with local " + name + ":" + sym.getType()
							);
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
		return out == null ? TyType.fromHintText("Void") : out;
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
											throw new TyperError(
												ctx.getFilePath(),
												pos,
												"cannot assign " + rhs + " to " + name + ":" + sym.getType()
											);
										}
									sym.setType(u);
									u;
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
