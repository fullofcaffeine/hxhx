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
		final classPaths = ["examples/hih-compiler/fixtures/src"];
		final mainModule = "demo.A";
		final resolved = ResolverStage.parseProject(classPaths, mainModule);

		// Bootstrap quirk (OCaml): record field labels are only known once the defining module
		// has been referenced during typechecking. Because this compiler skeleton still erases
		// many generic types, the OCaml compiler may not "see" `ResolvedModule` as a dependency
		// at this point unless we reference it explicitly.
		//
		// We do that with a zero-cost reference via the `__ocaml__` escape hatch (no allocation).
		untyped __ocaml__("(ResolvedModule.create)");

		final root:ResolvedModule = resolved[0];
		final ast = ResolvedModule.getParsed(root);
		final decl = ast.getDecl();
		Sys.println("parse=ok");
		Sys.println("modules=" + resolved.length);
		Sys.println("main=" + mainModule);
		Sys.println("mainFile=" + ResolvedModule.getFilePath(root));
		Sys.println("package=" + (decl.packagePath.length == 0 ? "<none>" : decl.packagePath));
		Sys.println("imports=" + decl.imports.length);
		Sys.println("class=" + decl.mainClass.name);
		Sys.println("hasStaticMain=" + (decl.mainClass.hasStaticMain ? "yes" : "no"));
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
			final parsed = ParserStage.parse(src).getDecl();
			if (parsed.packagePath != case_.getExpectPackagePath()) {
				throw new HxParseError('Fixture ' + label + ': package mismatch', new HxPos(0, 0, 0));
			}
			if (parsed.mainClass.name != case_.getExpectMainClassName()) {
				throw new HxParseError('Fixture ' + label + ': class mismatch', new HxPos(0, 0, 0));
			}
			if (parsed.mainClass.hasStaticMain != case_.getExpectHasStaticMain()) {
				throw new HxParseError('Fixture ' + label + ': static main mismatch', new HxPos(0, 0, 0));
			}

			#if hih_native_parser
			// Compare against the pure-Haxe frontend for this subset.
			final haxeDecl = new HxParser(src).parseModule();
			if (haxeDecl.packagePath != parsed.packagePath) throw new HxParseError('Fixture ' + label + ': package differs (native vs haxe)', new HxPos(0, 0, 0));
			if (haxeDecl.imports.length != parsed.imports.length) throw new HxParseError('Fixture ' + label + ': import count differs (native vs haxe)', new HxPos(0, 0, 0));
			for (i in 0...haxeDecl.imports.length) {
				if (haxeDecl.imports[i] != parsed.imports[i]) throw new HxParseError('Fixture ' + label + ': import differs (native vs haxe)', new HxPos(0, 0, 0));
			}
			if (haxeDecl.mainClass.name != parsed.mainClass.name) throw new HxParseError('Fixture ' + label + ': class differs (native vs haxe)', new HxPos(0, 0, 0));
			if (haxeDecl.mainClass.hasStaticMain != parsed.mainClass.hasStaticMain) throw new HxParseError('Fixture ' + label + ': static main differs (native vs haxe)', new HxPos(0, 0, 0));
			#end
		}

		final typed = TyperStage.typeModule(ast);
		Sys.println("typer=ok");

		final expanded = MacroStage.expand(typed);
		Sys.println("macros=stub");

		EmitterStage.emit(expanded);
		Sys.println("emit=stub");
	}
}
