class EmitterStageDebug {
	/**
		Emit a debug trace of computed call signatures.

		Why
		- Rest-arg bring-up depends on a signature map (`callSigByCallee`) built from parsed
		  declarations. When it is wrong, the emitter can accidentally pack *all* call arguments
		  into the rest array (or fail to pack any), which then shows up as confusing OCaml type
		  errors at build time.

		How
		- Gated by `HXHX_TRACE_CALLSIG=1`.
		- Written to stderr so it doesn't perturb tests that assert stdout output.
	**/
	public static function traceCallSig(modName:String, fnName:String, args:Array<HxFunctionArg>, required:Int, fixed:Int, hasRest:Bool,
			needsReceiver:Bool):Void {
		final enabled = Sys.getEnv("HXHX_TRACE_CALLSIG");
		if (enabled != "1" && enabled != "true" && enabled != "yes")
			return;
		try {
			final parts = new Array<String>();
			if (args != null) {
				for (a in args) {
					final nm = HxFunctionArg.getName(a);
					final kind = HxFunctionArg.getIsRest(a) ? "rest" : "fixed";
					final hint = StringTools.trim(HxFunctionArg.getTypeHint(a));
					parts.push(nm + ":" + kind + (hint.length == 0 ? "" : (":" + hint)));
				}
			}
			Sys.stderr()
				.writeString("callsig " + modName + "." + fnName + " required=" + required + " fixed=" + fixed + " hasRest=" + (hasRest ? "1" : "0")
					+ " needsReceiver=" + (needsReceiver ? "1" : "0") + " args=[" + parts.join(",") + "]\n");
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	/**
		Emit a debug trace for Stage3 module emission progress.

		Why
		- Some Stage3 bring-up failures currently surface as hard crashes during module emission.
		- A narrow per-module trace lets us identify the last module reached without perturbing
		  normal stdout-based gate markers.

		How
		- Gated by `HXHX_TRACE_STAGE3_MODULE_EMIT=1`.
		- Written to stderr so the existing stdout markers remain stable.
	**/
	static inline function traceStage3Enabled():Bool {
		final enabled = Sys.getEnv("HXHX_TRACE_STAGE3_MODULE_EMIT");
		return enabled == "1" || enabled == "true" || enabled == "yes";
	}

	public static function traceStage3Phase(label:String):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final stderr = Sys.stderr();
			stderr.writeString("stage3_emit_phase=" + label + "\n");
			stderr.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3Module(label:String, moduleName:String, filePath:Null<String>):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final fileTag = filePath == null ? "<unknown>" : filePath;
			final stderr = Sys.stderr();
			stderr.writeString("stage3_emit[" + label + "]=" + moduleName + " file=" + fileTag + "\n");
			stderr.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3StmtList(phase:String, functionName:Null<String>, idx:Int, total:Int, stmt:HxStmt):Void {
		if (!traceStage3Enabled())
			return;
		final fn = functionName == null ? "" : functionName;
		final traceEnv = Sys.getEnv("HXHX_TRACE_STAGE3_STMT_LIST");
		final traceAll = traceEnv == "1" || traceEnv == "true" || traceEnv == "yes";
		if (!traceAll && fn != "emitToDir")
			return;
		final kindAndPos = switch (stmt) {
			case SBlock(_, pos): {kind: "SBlock", pos: pos};
			case SVar(_, _, _, pos): {kind: "SVar", pos: pos};
			case SIf(_, _, _, pos): {kind: "SIf", pos: pos};
			case SWhile(_, _, pos): {kind: "SWhile", pos: pos};
			case SDoWhile(_, _, pos): {kind: "SDoWhile", pos: pos};
			case SForIn(_, _, _, pos): {kind: "SForIn", pos: pos};
			case SForKeyValue(_, _, _, _, pos): {kind: "SForKeyValue", pos: pos};
			case STry(_, _, pos): {kind: "STry", pos: pos};
			case SThrow(_, pos): {kind: "SThrow", pos: pos};
			case SBreak(pos): {kind: "SBreak", pos: pos};
			case SContinue(pos): {kind: "SContinue", pos: pos};
			case SSwitch(_, _, _, pos): {kind: "SSwitch", pos: pos};
			case SReturnVoid(pos): {kind: "SReturnVoid", pos: pos};
			case SReturn(_, pos): {kind: "SReturn", pos: pos};
			case SExpr(_, pos): {kind: "SExpr", pos: pos};
		}
		final pos = kindAndPos.pos;
		final line = pos == null ? 0 : pos.getLine();
		final col = pos == null ? 0 : pos.getColumn();
		final detail = switch (stmt) {
			case SVar(name, typeHint, _init, _):
				":name=" + name + ":type=" + (typeHint == null ? "" : typeHint);
			case SIf(_cond, _thenBranch, elseBranch, _):
				":hasElse=" + (elseBranch == null ? "0" : "1");
			case SForIn(name, _iterable, _body, _):
				":name=" + name;
			case SForKeyValue(keyName, valueName, _iterable, _body, _):
				":key=" + keyName + ":value=" + valueName;
			case SSwitch(_scrutinee, patterns, bodies, _):
				":patterns="
				+ (patterns == null ? "0" : Std.string(patterns.length))
				+ ":bodies="
				+ (bodies == null ? "0" : Std.string(bodies.length));
			case SBlock(stmts, _):
				":stmts=" + (stmts == null ? "0" : Std.string(stmts.length));
			case _:
				"";
		}
		traceStage3Phase("stmt_list_"
			+ phase
			+ ":"
			+ fn
			+ ":"
			+ idx
			+ "/"
			+ total
			+ ":"
			+ kindAndPos.kind
			+ ":line="
			+ line
			+ ":col="
			+ col
			+ detail);
	}
}
