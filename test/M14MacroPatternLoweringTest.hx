/**
	`case macro <quote>:` binds typed values, as upstream's reified pattern does (haxe_ocaml-ikf1n).

	Upstream reifies a quote in a case pattern like any other (`reify_expr`,
	`src/syntax/grammar.mly` lines 1275-1294 in Haxe 4.3.7): `$v{(s:String)}` is
	`EConst(CString(s))` and `$b{el}` is `EBlock(el)` (`src/syntax/reification.ml` lines 350-368), and
	the matcher skips position fields (`src/typing/matcher.ml` lines 488-499). The shapes are the
	three sites of upstream's `tests/unit/src/unit/HelperMacros.hx`.
**/
class M14MacroPatternLoweringTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function caseOf(source:String):HxSwitchPattern {
		final parsed = ParserStage.parse("class C { static function f(e:haxe.macro.Expr):Dynamic { return switch e { " + source + " case _: null; } } }",
			"C.hx");
		final body = HxFunctionDecl.getBody(HxClassDecl.getFunctions(HxModuleDecl.getMainClass(parsed.getDecl()))[0]);
		return switch body[0] {
			case SReturn(ESwitch(_, patterns, _), _): patterns[0];
			case other: throw "not a switch: " + Std.string(other);
		};
	}

	static function main():Void {
		// The markup site: `@:markup` keeps its colon (haxe_ocaml-1d2zn), the value binds `s`, and no
		// position field is matched.
		switch caseOf("case macro @:markup $v{(s:String)}: s;") {
			case PObject(["expr"], [
				PEnumExtract("EMeta", [
					PObject(["name", "params"], [PString(":markup"), PArray([])]),
					PObject(["expr"], [PEnumExtract("EConst", [PEnumExtract("CString", [PBind("s")], _)], _)])
				], _)
			]):
			case other:
				throw "markup pattern: " + Std.string(other);
		}
		switch caseOf("case macro $b{el}: el;") {
			case PObject(["expr"], [PEnumExtract("EBlock", [PBind("el")], _)]):
			case other:
				throw "block pattern: " + Std.string(other);
		}
		switch caseOf("case macro $e: e;") {
			case PBind("e"):
			case other:
				throw "expression splice pattern: " + Std.string(other);
		}

		// The bindings are typed in the case bodies, which HelperMacros relies on: `$v{s}` needs the
		// static type of `s`, and `$a{el}` an `Array<Expr>`.
		final source = [
			"import haxe.macro.Expr;",
			"class Main {",
			"  static function unprocessed(e:Expr):Expr {",
			"    return switch e { case macro @:markup $v{(s:String)}: macro $v{s}; case _: null; }",
			"  }",
			"  static function joined(e:Expr):Expr {",
			"    return switch e { case macro $b{el}: macro $a{el}.join(\"\"); case _: null; }",
			"  }",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader([
			hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true))
		], HxDefineMap.fromRawDefines(["sys"]), index);
		loader.markResolvedAlready([resolved]);
		TyperStage.typeResolvedModule(resolved, index, loader);

		// `$v{x}` without a written type is `Context.makeExpr(x, ...)` upstream, which its matcher rejects.
		final untypedValue = try {
			caseOf("case macro $v{x}: x;");
			"";
		} catch (error:HxParseError) {
			error.message;
		}
		require(StringTools.startsWith(untypedValue, "Unrecognized pattern"), "an untyped $v{} pattern must be rejected, got `" + untypedValue + "`");
		Sys.println("M14_MACRO_PATTERN_LOWERING:PASS");
	}
}
