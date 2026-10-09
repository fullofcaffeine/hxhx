/** Backend-only scope nodes must never enter source macro expansion or source diagnostics. */
@:access(hxhx.ExprMacroExpander)
@:access(hxhx.Stage3DiagnosticsSupport)
class M14SourceTargetScopeBoundaryTest {
	public static function run():Void {
		final position = HxPos.unknown();
		final body = HxStmt.SBlock([], position);
		final scope = HxStmt.STargetScope(CsUnsafe, body, position);
		final allowed = new haxe.ds.StringMap<Bool>();
		final imports = new haxe.ds.StringMap<String>();
		// Neither rejection nor an unchanged empty block may contact a macro runtime.
		final checks:Array<Void->Void> = [
			() -> {
				hxhx.ExprMacroExpander.rewriteStmt(scope, null, allowed, [], imports, "", false, () -> {});
			},
			() -> {
				hxhx.Stage3DiagnosticsSupport.collectUnsupportedExprRawInStmt(scope, [], 10);
			},
			() -> {
				hxhx.Stage3DiagnosticsSupport.countUnsupportedExprsInStmt(scope);
			}
		];
		for (check in checks) {
			var rejected = false;
			try {
				check();
			} catch (error:haxe.Exception) {
				if (error.message != "native target scope is not valid in this source or target phase")
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "backend scope passed a source-phase boundary";
		}
		if (hxhx.ExprMacroExpander.rewriteStmt(body, null, allowed, [], imports, "", false, () -> {}) != body)
			throw "empty source block lost unchanged-node identity";
		final unsupported = HxStmt.SExpr(EUnsupported("source-boundary-probe"), position);
		final observed = new Array<String>();
		hxhx.Stage3DiagnosticsSupport.collectUnsupportedExprRawInStmt(unsupported, observed, 10);
		if (observed.join(",") != "source-boundary-probe" || hxhx.Stage3DiagnosticsSupport.countUnsupportedExprsInStmt(unsupported) != 1)
			throw "ordinary unsupported source diagnostic was lost";
		Sys.println("SOURCE_TARGET_SCOPE_BOUNDARY:PASS");
	}

	static function main():Void
		run();
}
