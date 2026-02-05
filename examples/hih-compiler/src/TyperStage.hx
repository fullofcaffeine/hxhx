/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
	public static function typeModule(m:ParsedModule):TypedModule {
		final decl = m.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);

		final typedFns = new Array<TyFunctionEnv>();
		for (fn in HxClassDecl.getFunctions(cls)) {
			final params = new Array<TySymbol>();
			for (arg in HxFunctionDecl.getArgs(fn)) {
				final name = HxFunctionArg.getName(arg);
				final ty = TyType.fromHintText(HxFunctionArg.getTypeHint(arg));
				params.push(new TySymbol(name, ty));
			}

			final retTy = TyType.fromHintText(HxFunctionDecl.getReturnTypeHint(fn));
			typedFns.push(new TyFunctionEnv(HxFunctionDecl.getName(fn), params, retTy));
		}

		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), typedFns);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(m, env);
	}
}
