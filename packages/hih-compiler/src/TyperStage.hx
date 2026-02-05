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

		final typedFns = new Array<TyFunctionEnv>();
		for (fn in HxClassDecl.getFunctions(cls)) {
			typedFns.push(typeFunction(fn));
		}

		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), typedFns);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(m, env);
	}

	static function typeFunction(fn:HxFunctionDecl):TyFunctionEnv {
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

		final returnExprTy = inferFirstReturnExprType(fn, scope);
		final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
		final retTy = retHintText != null && retHintText.length > 0
			? TyType.fromHintText(retHintText)
			: returnExprTy;

		return new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, retTy, returnExprTy);
	}

	static function inferFirstReturnExprType(fn:HxFunctionDecl, scope:TyFunctionEnv):TyType {
		function find(stmts:Array<HxStmt>):Null<TyType> {
			for (s in stmts) {
				switch (s) {
					case SReturnVoid:
						return TyType.fromHintText("Void");
					case SReturn(e):
						return inferExprType(e, scope);
					case SBlock(ss):
						final r = find(ss);
						if (r != null) return r;
					case SIf(_cond, thenBranch, elseBranch):
						final r1 = find([thenBranch]);
						if (r1 != null) return r1;
						if (elseBranch != null) {
							final r2 = find([elseBranch]);
							if (r2 != null) return r2;
						}
					case _:
				}
			}
			return null;
		}

		final r = find(HxFunctionDecl.getBody(fn));
		return r == null ? TyType.fromHintText("Void") : r;
	}

	static function inferExprType(expr:HxExpr, scope:TyFunctionEnv):TyType {
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
				inferExprType(obj, scope);
				TyType.unknown();
			case ECall(callee, args):
				// Best-effort: type children for future diagnostics; call return typing
				// requires function resolution (future stage).
				inferExprType(callee, scope);
				for (a in args) inferExprType(a, scope);
				TyType.unknown();
			case EUnop(_op, e):
				inferExprType(e, scope);
				TyType.unknown();
			case EBinop(_op, a, b):
				inferExprType(a, scope);
				inferExprType(b, scope);
				TyType.unknown();
			case EUnsupported(_):
				TyType.unknown();
		}
	}
}
