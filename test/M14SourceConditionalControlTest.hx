import haxe.macro.Expr;
import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Preserve the conditional/value-group syntax used by the original macro runtime. */
class M14SourceConditionalControlTest {
	/** Branch-local declarations retain separate identities and cannot replace an outer local. */
	static function checkBranchScopes():Void {
		final source = "class ScopeCase { static function main():Void { var item = \"outer\"; var selected = if (true) { var item = 1; item; } else { var item = 2; item; }; var restored:String = item; } }";
		final resolved = new ResolvedModule("ScopeCase", "ScopeCase.hx", ParserStage.parse(source, "ScopeCase.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final statements = typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements();
		final outer = statements[0].getLocalBindings()[0].getIdentity().getCanonicalKey();
		final selected = statements[1].getExpressions()[0];
		final whenTrue = selected.getExpressions()[1].getExpressions()[0].getExpressions()[0].getLocalBindings()[0].getIdentity().getCanonicalKey();
		final whenFalse = selected.getExpressions()[2].getExpressions()[0].getExpressions()[0].getLocalBindings()[0].getIdentity().getCanonicalKey();
		final restored = statements[2].getExpressions()[0].getLocalBindings()[0].getIdentity().getCanonicalKey();
		if (outer != restored || outer == whenTrue || outer == whenFalse || whenTrue == whenFalse)
			throw "conditional branches leaked or merged local declarations";
	}

	static function checkParserBoundaries():Void {
		final missingElse = HxParser.parseCompleteExprText("if (flag) 1");
		final nullElse = HxParser.parseCompleteExprText("if (flag) 1 else null");
		if (TypedBodyFingerprint.forExpression(missingElse) == TypedBodyFingerprint.forExpression(nullElse))
			throw "an absent else collided with an authored null else";
		switch HxParser.parseCompleteExprText("if (outer) if (inner) 1 else 2") {
			case ESourceIf(_, ESourceIf(_, EInt(1), EInt(2), _), null, _):
			case _:
				throw "else must bind to the nearest conditional";
		}
		for (source in ["if (flag) else 1", "if (flag) 1 else", "throw;"]) {
			var rejected = false;
			try {
				HxParser.parseCompleteExprText(source);
			} catch (_:HxParseError) {
				rejected = true;
			}
			if (!rejected)
				throw "missing control operand was accepted: " + source;
		}
	}

	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, _ -> null);
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EIdent(name): EConst(CIdent(name));
			case EString(value): EConst(CString(value));
			case EInt(value): EConst(CInt(Std.string(value)));
			case EBinop("<", left, right): EBinop(OpLt, convert(left), convert(right));
			case _: throw "unexpected conditional fixture leaf";
		};
		return {expr: definition, pos: null};
	}

	public static function run():Void {
		checkParserBoundaries();
		checkBranchScopes();
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_conditional_control_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final initializer = typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
		if (initializer.getTag() != SourceIf || initializer.getType().getCanonicalDisplay() != "String")
			throw "typed conditional lost its authored form or selected result";
		final guarded = initializer.getExpressions()[2].getExpressions()[0];
		if (guarded.getTag() != SourceIf || guarded.getExpressions().length != 2 || !guarded.getType().isVoid())
			throw "missing else must remain absent and allow ordinary completion";
		final thrown = guarded.getExpressions()[1];
		if (thrown.getTag() != ThrowExpr || !thrown.getType().isNoNormalCompletion())
			throw "throw lost its abrupt completion";
		final syntax = convert(TypedSourceSyntax.expression(initializer));
		switch syntax.expr {
			case EIf(_, {expr: EBlock([{expr: EConst(CString("left", _))}])}, {
				expr: EBlock([
					{expr: EIf(_, {expr: ExprDef.EThrow({expr: EConst(CString("bad", _))})}, null)},
					{expr: EConst(CString("right", _))}
				])
			}):
			case _:
				throw "macro syntax must retain if, missing else, throw, and each authored group";
		}
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final context = new BackendContext(".tmp/source-conditional-control", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), context);
		if (!result.builtExecutable)
			throw "conditional control requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "conditional lowering changed the original typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_conditional_control_seed/expected.stdout"))
			throw "conditional control changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_CONDITIONAL_NATIVE:PASS");
	}

	static function main():Void
		run();
}
