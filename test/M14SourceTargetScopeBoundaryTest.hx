/** Backend-only statements must never enter source macro expansion or source diagnostics. */
@:access(hxhx.ExprMacroExpander)
@:access(hxhx.Stage3DiagnosticsSupport)
class M14SourceTargetScopeBoundaryTest {
	public static function run():Void {
		final position = HxPos.unknown();
		final body = HxStmt.SBlock([], position);
		final scope = HxStmt.STargetScope(CsUnsafe, body, position);
		final plan = new TypedGuardedPatternPlan([PWildcard], _ -> throw "wildcard has no named declaration", true, true, [true]);
		final guarded = HxStmt.SGuardedSwitch(EInt(1), EBool(true), plan, [body], position);
		final allowed = new haxe.ds.StringMap<Bool>();
		final imports = new haxe.ds.StringMap<String>();
		// Neither rejection nor an unchanged empty block may contact a macro runtime.
		for (entry in [
			{statement: scope, diagnostic: "native target scope is not valid in this source or target phase"},
			{statement: guarded, diagnostic: "backend guarded switch is not source syntax"}
		]) {
			final checks:Array<Void->Void> = [
				() -> {
					hxhx.ExprMacroExpander.rewriteStmt(entry.statement, null, allowed, [], imports, "", false, () -> {});
				},
				() -> {
					hxhx.Stage3DiagnosticsSupport.collectUnsupportedExprRawInStmt(entry.statement, [], 10);
				},
				() -> {
					hxhx.Stage3DiagnosticsSupport.countUnsupportedExprsInStmt(entry.statement);
				}
			];
			for (check in checks) {
				var rejected = false;
				try {
					check();
				} catch (error:haxe.Exception) {
					if (error.message != entry.diagnostic)
						throw error;
					rejected = true;
				}
				if (!rejected)
					throw "backend statement passed a source-phase boundary";
			}
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
