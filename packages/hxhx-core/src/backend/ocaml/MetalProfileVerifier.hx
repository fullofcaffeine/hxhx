package backend.ocaml;

import backend.GenIrProgram;

typedef MetalViolationSummary = {
	final filePath:String;
	final context:String;
	final code:String;
	final construct:String;
	final reason:String;
}

private typedef MetalViolation = {
	final filePath:String;
	final line:Int;
	final column:Int;
	final code:String;
	final construct:String;
	final context:String;
	final reason:String;
	final migrationHint:String;
}

/**
	Fail-fast verifier for the OCaml `metal` profile.

	Why
	- `metal` is the native-performance lane. It must reject constructs that currently
	  depend on broad dynamic/reflection behavior or bootstrap placeholders.
	- Failing before emit keeps errors deterministic and avoids generating output that
	  appears valid but silently falls back to non-metal semantics.

	What
	- Scans the typed module graph (`GenIrProgram` / `MacroExpandedProgram`) and reports
	  disallowed constructs with actionable diagnostics.
	- Current blocked constructs:
	  - `untyped` expressions
	  - bootstrap placeholder expressions (`EUnsupported`, `ETryCatchRaw`, `ESwitchRaw`)
	  - reflection-heavy calls (`Reflect.*`, `Type.*`)
	  - explicit `Dynamic` type hints on fields/args/locals/casts/catches

	How
	- Traverses modules, classes, fields, functions, statements, and expressions in
	  source order for deterministic output.
	- Collects violations and throws one formatted error string.

	Notes
	- This pass is intentionally conservative for the first metal verifier rung.
	- Richer migration hints and allowlists are tracked by follow-up tasks.
**/
class MetalProfileVerifier {
	static inline final CODE_UNTYPED = "untyped_expr";
	static inline final CODE_UNSUPPORTED_EXPR = "unsupported_expr";
	static inline final CODE_UNSUPPORTED_SEMANTIC = "unsupported_semantic";
	static inline final CODE_REFLECTION_CALL = "reflection_call";
	static inline final CODE_DYNAMIC_TYPE_HINT = "dynamic_type_hint";

	public static function verifyProgram(program:GenIrProgram):Void {
		final violations = collectViolations(program);
		if (violations.length > 0)
			throw formatViolations(violations);
	}

	public static function collectViolationSummaries(program:GenIrProgram):Array<MetalViolationSummary> {
		final summaries = new Array<MetalViolationSummary>();
		for (violation in collectViolations(program)) {
			summaries.push({
				filePath: violation.filePath,
				context: violation.context,
				code: violation.code,
				construct: violation.construct,
				reason: violation.reason
			});
		}
		return summaries;
	}

	static function collectViolations(program:GenIrProgram):Array<MetalViolation> {
		final typedModules = program.getTypedModules();
		final violations = new Array<MetalViolation>();
		for (typedModule in typedModules) {
			verifyTypedModule(typedModule, violations);
		}
		return violations;
	}

	static function verifyTypedModule(typedModule:TypedModule, violations:Array<MetalViolation>):Void {
		final parsed = typedModule.getParsed();
		final filePath = parsed.getFilePath();
		final moduleDecl = typedModule.getBackendDeclaration();
		for (cls in HxModuleDecl.getClasses(moduleDecl)) {
			final className = HxClassDecl.getName(cls);
			for (field in HxClassDecl.getFields(cls)) {
				final fieldName = HxFieldDecl.getName(field);
				verifyExplicitDynamicTypeHint(filePath, className, null, null, "field `" + fieldName + "` type", HxFieldDecl.getTypeHint(field), violations);
				final fieldInit = HxFieldDecl.getInit(field);
				if (fieldInit != null)
					verifyExpr(filePath, className, null, null, fieldInit, violations);
			}
			for (fn in HxClassDecl.getFunctions(cls)) {
				final fnName = HxFunctionDecl.getName(fn);
				verifyExplicitDynamicTypeHint(filePath, className, fnName, null, "return type", HxFunctionDecl.getReturnTypeHint(fn), violations);
				for (arg in HxFunctionDecl.getArgs(fn)) {
					final argName = HxFunctionArg.getName(arg);
					verifyExplicitDynamicTypeHint(filePath, className, fnName, null, "argument `" + argName + "` type", HxFunctionArg.getTypeHint(arg),
						violations);
				}
				for (stmt in HxFunctionDecl.getBody(fn)) {
					verifyStmt(filePath, className, fnName, stmt, violations);
				}
			}
		}
	}

	static function verifyStmt(filePath:String, className:String, fnName:String, stmt:HxStmt, violations:Array<MetalViolation>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (inner in stmts)
					verifyStmt(filePath, className, fnName, inner, violations);
			case SVar(name, typeHint, init, pos):
				verifyExplicitDynamicTypeHint(filePath, className, fnName, pos, "local `" + name + "` type", typeHint, violations);
				if (init != null)
					verifyExpr(filePath, className, fnName, pos, init, violations);
			case SIf(cond, thenBranch, elseBranch, pos):
				verifyExpr(filePath, className, fnName, pos, cond, violations);
				verifyStmt(filePath, className, fnName, thenBranch, violations);
				if (elseBranch != null)
					verifyStmt(filePath, className, fnName, elseBranch, violations);
			case SForIn(_, iterable, body, pos):
				verifyExpr(filePath, className, fnName, pos, iterable, violations);
				verifyStmt(filePath, className, fnName, body, violations);
			case SForKeyValue(_, _, iterable, body, pos):
				verifyExpr(filePath, className, fnName, pos, iterable, violations);
				verifyStmt(filePath, className, fnName, body, violations);
			case SWhile(cond, body, pos):
				verifyExpr(filePath, className, fnName, pos, cond, violations);
				verifyStmt(filePath, className, fnName, body, violations);
			case SDoWhile(body, cond, pos):
				verifyStmt(filePath, className, fnName, body, violations);
				verifyExpr(filePath, className, fnName, pos, cond, violations);
			case SSwitch(scrutinee, _patterns, bodies, pos):
				verifyExpr(filePath, className, fnName, pos, scrutinee, violations);
				for (body in bodies)
					verifyStmt(filePath, className, fnName, body, violations);
			case STry(tryBody, catches, _):
				verifyStmt(filePath, className, fnName, tryBody, violations);
				for (c in catches) {
					final catchHint = normalizeTypeHint(c.typeHint);
					if (catchHint.length == 0 || isDynamicTypeHint(c.typeHint)) {
						addViolation(violations, filePath, className, fnName, HxPos.unknown(), CODE_DYNAMIC_TYPE_HINT, "catch variable `" + c.name + "` type",
							"metal catch typing must stay concrete to preserve deterministic native exception matching",
							"use a concrete catch type in metal profile (for example, `haxe.Exception` or a specific error type)");
					}
					verifyStmt(filePath, className, fnName, c.body, violations);
				}
			case SThrow(expr, pos):
				verifyExpr(filePath, className, fnName, pos, expr, violations);
			case SReturn(expr, pos):
				verifyExpr(filePath, className, fnName, pos, expr, violations);
			case SExpr(expr, pos):
				verifyExpr(filePath, className, fnName, pos, expr, violations);
			case SBreak(_):
			case SContinue(_):
			case SReturnVoid(_):
		}
	}

	static function verifyExpr(filePath:String, className:String, fnName:String, stmtPos:Null<HxPos>, expr:HxExpr, violations:Array<MetalViolation>):Void {
		switch (expr) {
			case EUntyped(inner):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNTYPED, "`untyped` expression",
					"metal profile forbids `untyped` because it bypasses typed lowering and native guarantees",
					"replace `untyped` with typed target abstractions or portable equivalents");
				verifyExpr(filePath, className, fnName, stmtPos, inner, violations);
			case EUnsupported(raw):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_EXPR, "EUnsupported(" + summarizeRaw(raw) + ")",
					"bootstrap fallback nodes are not valid in metal mode", "rewrite the expression to a supported typed form before using metal profile");
			case ETryCatchRaw(raw):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "ETryCatchRaw(" + summarizeRaw(raw) + ")",
					"raw try/catch fallback nodes cannot guarantee native metal semantics", "use statement-level try/catch with concrete catch types");
			case ESwitchRaw(raw):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "ESwitchRaw(" + summarizeRaw(raw) + ")",
					"raw switch fallback nodes cannot guarantee native metal semantics", "use structured switch forms that type-check without fallback nodes");
			case ECall(callee, args):
				final reflectionCall = reflectionCallName(callee);
				if (reflectionCall != null) {
					addViolation(violations, filePath, className, fnName, stmtPos, CODE_REFLECTION_CALL, reflectionCall,
						"reflection-driven calls prevent static specialization in metal mode", "replace reflection calls with static/typed APIs");
				}
				verifyExpr(filePath, className, fnName, stmtPos, callee, violations);
				for (arg in args)
					verifyExpr(filePath, className, fnName, stmtPos, arg, violations);
			case EReturn(value):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "expression-position return",
					"a return nested inside another expression must be handled by macro expansion before metal emission",
					"expand the macro or move the return to statement position before selecting metal profile");
				if (value != null)
					verifyExpr(filePath, className, fnName, stmtPos, value, violations);
			case EWhile(condition, body, _, _):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "expression-position while",
					"a while loop nested inside another expression must be handled by macro expansion before metal emission",
					"expand the macro or move the loop to statement position before selecting metal profile");
				verifyExpr(filePath, className, fnName, stmtPos, condition, violations);
				for (entry in body)
					verifyExpr(filePath, className, fnName, stmtPos, entry, violations);
			case EVars(declarations):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "expression-position variable declaration",
					"a variable declaration passed as source syntax must be handled by macro expansion before metal emission",
					"expand the macro or move the declaration to statement position before selecting metal profile");
				for (declaration in declarations) {
					final initializer = HxExprVarDecl.getInitializer(declaration);
					if (initializer != null)
						verifyExpr(filePath, className, fnName, stmtPos, initializer, violations);
				}
			case EVariableDeclaration(_, _, initializer, _, _, _):
				addViolation(violations, filePath, className, fnName, stmtPos, CODE_UNSUPPORTED_SEMANTIC, "detached expression variable declaration",
					"an expression variable declaration must remain inside its declaration list",
					"report the compiler invariant failure before selecting metal profile");
				if (initializer != null)
					verifyExpr(filePath, className, fnName, stmtPos, initializer, violations);
			case EMacroExpr(inner, _wrappers):
				verifyExpr(filePath, className, fnName, stmtPos, inner, violations);
			case EMacroType(_):
			case EField(obj, _) | ENullSafeField(obj, _):
				verifyExpr(filePath, className, fnName, stmtPos, obj, violations);
			case EUnop(_, _, inner):
				verifyExpr(filePath, className, fnName, stmtPos, inner, violations);
			case EBinop(_, left, right):
				verifyExpr(filePath, className, fnName, stmtPos, left, violations);
				verifyExpr(filePath, className, fnName, stmtPos, right, violations);
			case ETernary(cond, thenExpr, elseExpr):
				verifyExpr(filePath, className, fnName, stmtPos, cond, violations);
				verifyExpr(filePath, className, fnName, stmtPos, thenExpr, violations);
				verifyExpr(filePath, className, fnName, stmtPos, elseExpr, violations);
			case EAnon(_, fieldValues):
				for (fieldExpr in fieldValues)
					verifyExpr(filePath, className, fnName, stmtPos, fieldExpr, violations);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr):
				verifyExpr(filePath, className, fnName, stmtPos, iterable, violations);
				if (guardExpr != null)
					verifyExpr(filePath, className, fnName, stmtPos, guardExpr, violations);
				verifyExpr(filePath, className, fnName, stmtPos, yieldExpr, violations);
			case EArrayDecl(values):
				for (valueExpr in values)
					verifyExpr(filePath, className, fnName, stmtPos, valueExpr, violations);
			case EArrayAccess(array, index):
				verifyExpr(filePath, className, fnName, stmtPos, array, violations);
				verifyExpr(filePath, className, fnName, stmtPos, index, violations);
			case ERange(start, end):
				verifyExpr(filePath, className, fnName, stmtPos, start, violations);
				verifyExpr(filePath, className, fnName, stmtPos, end, violations);
			case ECast(inner, typeHint):
				verifyExplicitDynamicTypeHint(filePath, className, fnName, stmtPos, "cast target type", typeHint, violations);
				verifyExpr(filePath, className, fnName, stmtPos, inner, violations);
			case ELambda(_, body):
				verifyExpr(filePath, className, fnName, stmtPos, body, violations);
			case ESwitch(scrutinee, _patterns, exprs):
				verifyExpr(filePath, className, fnName, stmtPos, scrutinee, violations);
				for (branchExpr in exprs)
					verifyExpr(filePath, className, fnName, stmtPos, branchExpr, violations);
			case ENew(_, args):
				for (arg in args)
					verifyExpr(filePath, className, fnName, stmtPos, arg, violations);
			case ENull:
			case EBool(_):
			case EString(_):
			case EInt(_):
			case EFloat(_):
			case EEnumValue(_):
			case EThis:
			case ESuper:
			case EIdent(_):
		}
	}

	static function verifyExplicitDynamicTypeHint(filePath:String, className:String, fnName:Null<String>, pos:Null<HxPos>, label:String, rawTypeHint:String,
			violations:Array<MetalViolation>):Void {
		if (!isDynamicTypeHint(rawTypeHint))
			return;
		addViolation(violations, filePath, className, fnName, pos, CODE_DYNAMIC_TYPE_HINT, label,
			"`Dynamic` type hints disable metal-profile specialization and deterministic native typing", "replace `Dynamic` with a concrete type");
	}

	static function isDynamicTypeHint(rawTypeHint:String):Bool {
		final normalized = normalizeTypeHint(rawTypeHint).toLowerCase();
		return normalized == "dynamic" || normalized == "null<dynamic>" || normalized == "array<dynamic>";
	}

	static function normalizeTypeHint(rawTypeHint:String):String {
		if (rawTypeHint == null)
			return "";
		return StringTools.replace(StringTools.replace(StringTools.replace(StringTools.trim(rawTypeHint), " ", ""), "\t", ""), "\n", "");
	}

	static function reflectionCallName(callee:HxExpr):Null<String> {
		return switch (callee) {
			case EField(EIdent("Reflect"), field): "Reflect." + field;
			case EField(EIdent("Type"), field): "Type." + field;
			case _: null;
		}
	}

	static function summarizeRaw(raw:String):String {
		if (raw == null)
			return "<unknown>";
		final oneLine = StringTools.replace(StringTools.replace(StringTools.replace(raw, "\r", " "), "\n", " "), "\t", " ");
		final trimmed = StringTools.trim(oneLine);
		return trimmed.length > 80 ? trimmed.substr(0, 80) + "..." : trimmed;
	}

	static function formatContext(className:String, fnName:Null<String>):String {
		return fnName == null ? className : className + "." + fnName;
	}

	static function addViolation(violations:Array<MetalViolation>, filePath:String, className:String, fnName:Null<String>, pos:Null<HxPos>, code:String,
			construct:String, reason:String, migrationHint:String):Void {
		final line = pos == null ? 0 : pos.getLine();
		final column = pos == null ? 0 : pos.getColumn();
		violations.push({
			filePath: (filePath == null || filePath.length == 0) ? "<unknown>" : filePath,
			line: line,
			column: column,
			code: code,
			construct: construct,
			context: formatContext(className, fnName),
			reason: reason,
			migrationHint: migrationHint
		});
	}

	static function formatViolations(violations:Array<MetalViolation>):String {
		final lines = new Array<String>();
		lines.push("metal profile verification failed: " + violations.length + " issue(s)");
		for (v in violations) {
			final lineCol = (v.line > 0 && v.column > 0) ? ":" + v.line + ":" + v.column : "";
			lines.push("- " + v.filePath + lineCol + " [" + v.code + "] construct: " + v.construct + " (context: " + v.context + ")");
			lines.push("  reason: " + v.reason);
			lines.push("  migration: " + v.migrationHint);
		}
		lines.push("next: keep metal by applying the migrations above, or explicitly switch lanes with -D ocaml_profile=portable.");
		lines.push("policy: no implicit metal->portable fallback is performed.");
		return lines.join("\n");
	}
}
