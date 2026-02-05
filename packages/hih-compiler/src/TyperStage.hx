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
		final filePath = m.getFilePath();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);

		final typedFns = new Array<TyFunctionEnv>();
		for (fn in HxClassDecl.getFunctions(cls)) {
			typedFns.push(typeFunction(fn, filePath));
		}

		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), typedFns);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(m, env);
	}

	static function typeFunction(fn:HxFunctionDecl, filePath:String):TyFunctionEnv {
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

		final returnExprTy = inferReturnType(fn, scope, filePath);
		final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
		final retTy = if (retHintText != null && retHintText.length > 0) {
			final hinted = TyType.fromHintText(retHintText);
			final unified = TyType.unify(hinted, returnExprTy);
			if (unified == null) {
				throw new TyperError(filePath, HxPos.unknown(), "return type hint " + hinted + " conflicts with inferred return " + returnExprTy);
			}
			hinted;
		} else {
			returnExprTy;
		}

		return new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, retTy, returnExprTy);
	}

	static function inferReturnType(fn:HxFunctionDecl, scope:TyFunctionEnv, filePath:String):TyType {
		var out:Null<TyType> = null;

		function unifyInto(t:TyType, pos:HxPos):Void {
			if (out == null) {
				out = t;
				return;
			}
			final u = TyType.unify(out, t);
			if (u == null) {
				throw new TyperError(
					filePath,
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
					inferExprType(cond, scope, filePath, pos);
					typeStmt(thenBranch);
					if (elseBranch != null) typeStmt(elseBranch);
				case SVar(name, typeHint, init, pos):
					// Declare first so subsequent statements can reference the symbol deterministically.
					final hinted = TyType.fromHintText(typeHint);
					final sym = scope.declareLocal(name, hinted);
					if (init != null) {
						final initTy = inferExprType(init, scope, filePath, pos);
						final u = TyType.unify(sym.getType(), initTy);
						if (u == null) {
							throw new TyperError(
								filePath,
								pos,
								"initializer type " + initTy + " is not compatible with local " + name + ":" + sym.getType()
							);
						}
						sym.setType(u);
					}
				case SReturnVoid(pos):
					unifyInto(TyType.fromHintText("Void"), pos);
				case SReturn(e, pos):
					final t = inferExprType(e, scope, filePath, pos);
					unifyInto(t, pos);
				case SExpr(e, pos):
					inferExprType(e, scope, filePath, pos);
			}
		}

		for (s in HxFunctionDecl.getBody(fn)) typeStmt(s);
		return out == null ? TyType.fromHintText("Void") : out;
	}

	static function inferExprType(expr:HxExpr, scope:TyFunctionEnv, filePath:String, pos:HxPos):TyType {
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
			case EIdent(name):
				scope.resolveLocal(name);
			case EField(obj, _field):
				// Best-effort: infer the object expression type, but field typing needs
				// class env + imports (future stage).
				inferExprType(obj, scope, filePath, pos);
				TyType.unknown();
			case ECall(callee, args):
				// Best-effort: type children for future diagnostics; call return typing
				// requires function resolution (future stage).
				inferExprType(callee, scope, filePath, pos);
				for (a in args) inferExprType(a, scope, filePath, pos);
				TyType.unknown();
			case EUnop(_op, e):
				switch (_op) {
					case "!":
						inferExprType(e, scope, filePath, pos);
						TyType.fromHintText("Bool");
					case "-" | "+":
						final inner = inferExprType(e, scope, filePath, pos);
						inner.isNumeric() ? inner : TyType.unknown();
					case _:
						inferExprType(e, scope, filePath, pos);
						TyType.unknown();
				}
			case EBinop(op, a, b):
				switch (op) {
					case "=":
						// Assignment as expression.
						final rhs = inferExprType(b, scope, filePath, pos);
						switch (a) {
							case EIdent(name):
								final sym = scope.resolveSymbol(name);
								if (sym != null) {
									final u = TyType.unify(sym.getType(), rhs);
									if (u == null) {
										throw new TyperError(
											filePath,
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
								inferExprType(a, scope, filePath, pos);
								rhs;
						}
					case "==" | "!=" | "<" | "<=" | ">" | ">=":
						inferExprType(a, scope, filePath, pos);
						inferExprType(b, scope, filePath, pos);
						TyType.fromHintText("Bool");
					case "&&" | "||" | "&" | "|":
						inferExprType(a, scope, filePath, pos);
						inferExprType(b, scope, filePath, pos);
						TyType.fromHintText("Bool");
					case "+":
						final ta = inferExprType(a, scope, filePath, pos);
						final tb = inferExprType(b, scope, filePath, pos);
						if (ta.display == "String" || tb.display == "String") {
							TyType.fromHintText("String");
						} else {
							final u = TyType.unify(ta, tb);
							u != null && u.isNumeric() ? u : TyType.unknown();
						}
					case "-" | "*" | "/" | "%":
						final ta = inferExprType(a, scope, filePath, pos);
						final tb = inferExprType(b, scope, filePath, pos);
						final u = TyType.unify(ta, tb);
						u != null && u.isNumeric() ? u : TyType.unknown();
					case _:
						inferExprType(a, scope, filePath, pos);
						inferExprType(b, scope, filePath, pos);
						TyType.unknown();
				}
			case EUnsupported(_):
				TyType.unknown();
		}
	}
}
