/**
	A minimal, staged “compiler driver”.

	Why:
	- The real Haxe compiler is a pipeline (parse → type → macro → generate).
	- Even before we implement the full semantics, we want the *shape* and the
	  “seams” to exist: each stage has an explicit input/output and can be
	  validated independently.
	- This file should stay small and orchestration-only; the real work lives in
	  the dedicated stage modules.
**/
class CompilerDriver {
	public static function run():Void {
		final preferredFixtureRoot = "workloads/hih-compiler/fixtures/src";
		final legacyFixtureRoot = "examples/hih-compiler/fixtures/src";
		final fixtureRoot = sys.FileSystem.exists(preferredFixtureRoot) ? preferredFixtureRoot : legacyFixtureRoot;
		final classPaths = [fixtureRoot];
		final mainModule = "demo.A";
		final resolved = ResolverStage.parseProject(classPaths, mainModule);

		// Bootstrap quirk (OCaml): record field labels are only known once the defining module
		// has been referenced during typechecking. Because this compiler skeleton still erases
		// many generic types, the OCaml compiler may not "see" `ResolvedModule` as a dependency
		// at this point unless we reference it explicitly.
		//
		// We do that with a zero-cost reference via the `__ocaml__` escape hatch (no allocation).
		//
		// Guard it behind the OCaml backend define so regular `haxe --run` smoke checks can still
		// compile this module without the escape symbol being available.
		#if reflaxe_ocaml
		untyped __ocaml__("(ResolvedModule.create)");
		#end

		final root:ResolvedModule = resolved[0];
		final ast = ResolvedModule.getParsed(root);
		final decl = ast.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final mainClass = HxModuleDecl.getMainClass(decl);
		Sys.println("parse=ok");
		Sys.println("modules=" + resolved.length);
		Sys.println("main=" + mainModule);
		Sys.println("mainFile=" + ResolvedModule.getFilePath(root));
		Sys.println("package=" + (pkg.length == 0 ? "<none>" : pkg));
		Sys.println("imports=" + imports.length);
		Sys.println("class=" + HxClassDecl.getName(mainClass));
		Sys.println("hasStaticMain=" + (HxClassDecl.getHasStaticMain(mainClass) ? "yes" : "no"));
		final fns = HxClassDecl.getFunctions(mainClass);
		Sys.println("functions=" + fns.length);
		for (fn in fns) {
			final vis = switch (HxFunctionDecl.getVisibility(fn)) {
				case Public: "public";
				case Private: "private";
			}
			final retHint = HxFunctionDecl.getReturnTypeHint(fn);
			final ret = retHint.length == 0 ? "<none>" : retHint;
			final retStrLit = HxFunctionDecl.getReturnStringLiteral(fn);
			final retStr = retStrLit.length == 0 ? "<none>" : retStrLit;
			final args = HxFunctionDecl.getArgs(fn);
			Sys.println("fn=" + HxFunctionDecl.getName(fn) + " static=" + (HxFunctionDecl.getIsStatic(fn) ? "yes" : "no") + " vis=" + vis + " args=" + args.length + " ret=" + ret + " retStr=" + retStr);
		}
		try {
			ResolverStage.parseProject(classPaths, "demo.B");
			Sys.println("missing_import=fail");
		} catch (_:Dynamic) {
			Sys.println("missing_import=ok");
		}

		// Stage2 bootstrap: keep the native frontend and the Haxe frontend aligned.
		// We use upstream `tests/misc` fixtures as the behavioral oracle and keep a
		// small, deterministic subset embedded here.
		final upstreamShaped = [
			new FrontendFixture(
				"tests/misc/resolution/projects/spec/pack/Mod.hx",
				[
					"package pack;",
					"@:build(Macro.build()) class Mod {}",
					"@:build(Macro.build()) class ModSubType {}",
				].join("\n"),
				"pack",
				"Mod",
				false
			),
			new FrontendFixture(
				"tests/misc/resolution/projects/spec/pack/ModWithStatic.hx",
				[
					"package pack;",
					"",
					"class ModWithStatic {",
					'  public static function TheStatic() return "pack.ModWithStatic.TheStatic function";',
					"}",
					"",
					"@:build(Macro.build())",
					"class TheStatic {}",
				].join("\n"),
				"pack",
				"ModWithStatic",
				false
			),
		];

		for (case_ in upstreamShaped) {
			final label = case_.getLabel();
			final src = case_.getSource();
			final parsed = ParserStage.parse(src, label).getDecl();
			final parsedPkg = HxModuleDecl.getPackagePath(parsed);
			final parsedMain = HxModuleDecl.getMainClass(parsed);
			if (parsedPkg != case_.getExpectPackagePath()) {
				throw new HxParseError('Fixture ' + label + ': package mismatch', new HxPos(0, 0, 0));
			}
			if (HxClassDecl.getName(parsedMain) != case_.getExpectMainClassName()) {
				throw new HxParseError('Fixture ' + label + ': class mismatch', new HxPos(0, 0, 0));
			}
			if (HxClassDecl.getHasStaticMain(parsedMain) != case_.getExpectHasStaticMain()) {
				throw new HxParseError('Fixture ' + label + ': static main mismatch', new HxPos(0, 0, 0));
			}
			if (label.indexOf("ModWithStatic") >= 0) {
				final found = HxClassDecl.getFunctions(parsedMain).filter(f -> HxFunctionDecl.getName(f) == "TheStatic");
				if (found.length != 1) throw new HxParseError('Fixture ' + label + ': expected 1 TheStatic function', new HxPos(0, 0, 0));
				final retStr = HxFunctionDecl.getReturnStringLiteral(found[0]);
				if (retStr != "pack.ModWithStatic.TheStatic function") {
					throw new HxParseError('Fixture ' + label + ': TheStatic return differs', new HxPos(0, 0, 0));
				}
			}

			#if hih_native_parser
			// Compare against the pure-Haxe frontend for this subset.
			final haxeDecl = new HxParser(src).parseModule();
			if (HxModuleDecl.getPackagePath(haxeDecl) != parsedPkg) throw new HxParseError('Fixture ' + label + ': package differs (native vs haxe)', new HxPos(0, 0, 0));
			final haxeImports = HxModuleDecl.getImports(haxeDecl);
			final parsedImports = HxModuleDecl.getImports(parsed);
			if (haxeImports.length != parsedImports.length) throw new HxParseError('Fixture ' + label + ': import count differs (native vs haxe)', new HxPos(0, 0, 0));
			for (i in 0...haxeImports.length) {
				if (haxeImports[i] != parsedImports[i]) throw new HxParseError('Fixture ' + label + ': import differs (native vs haxe)', new HxPos(0, 0, 0));
			}
			final haxeMain = HxModuleDecl.getMainClass(haxeDecl);
			if (HxClassDecl.getName(haxeMain) != HxClassDecl.getName(parsedMain)) throw new HxParseError('Fixture ' + label + ': class differs (native vs haxe)', new HxPos(0, 0, 0));
			if (HxClassDecl.getHasStaticMain(haxeMain) != HxClassDecl.getHasStaticMain(parsedMain)) throw new HxParseError('Fixture ' + label + ': static main differs (native vs haxe)', new HxPos(0, 0, 0));
			final haxeFns = HxClassDecl.getFunctions(haxeMain);
			final parsedFns = HxClassDecl.getFunctions(parsedMain);
			if (haxeFns.length != parsedFns.length) throw new HxParseError('Fixture ' + label + ': function count differs (native vs haxe)', new HxPos(0, 0, 0));
			for (i in 0...haxeFns.length) {
				if (HxFunctionDecl.getName(haxeFns[i]) != HxFunctionDecl.getName(parsedFns[i])) throw new HxParseError('Fixture ' + label + ': function name differs (native vs haxe)', new HxPos(0, 0, 0));
			}
			#end
		}

		final typed = TyperStage.typeModule(ast);
		Sys.println("typer=ok");
		final typedFns = typed.getEnv().getMainClass().getFunctions();
		Sys.println("typed_functions=" + typedFns.length);
		for (tf in typedFns) {
			Sys.println(
				"typed_fn=" + tf.getName()
				+ " args=" + tf.getParams().length
				+ " locals=" + tf.getLocals().length
				+ " ret=" + tf.getReturnType().toString()
				+ " retExpr=" + tf.getReturnExprType().toString()
			);
		}

		final expanded = MacroStage.expand(typed, []);
		Sys.println("macros=stub");

		EmitterStage.emit(expanded);
		Sys.println("emit=stub");
	}
}
