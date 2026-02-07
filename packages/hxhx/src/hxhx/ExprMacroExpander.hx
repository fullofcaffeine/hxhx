package hxhx;

import hxhx.macro.MacroHostClient.MacroHostSession;

/**
	Expression macro expansion (Gate1 bring-up).

	Why
	- Upstream Haxe supports “expression macros”: a call in normal code (e.g. `Foo.bar()`) can be a macro
	  call which is executed at compile time, and its returned expression AST is spliced into the program.
	- During `hxhx` Stage3/Stage4 bring-up we do not have a full upstream macro/typer integration yet, but
	  we still want an incremental rung that proves the *pipeline shape*:
	  - detect eligible call sites
	  - ask the macro host to expand them
	  - parse the returned expression text into `HxExpr`
	  - continue typing/emitting on the expanded program

	What
	- This stage rewrites the bootstrap AST in-place (via replacement of nodes):
	  - Supports only a conservative call subset:
	    - `pack.Class.meth()` / `Class.meth()`
	    - `pack.Class.meth("literal")` (single String literal arg)
	  - Only expands expressions explicitly allowlisted by exact call text.

	How
	- The macro host implements `macro.expandExpr`, which returns a Haxe expression text snippet.
	- We parse that snippet with `HxParser.parseExprText` (small grammar) and splice it into the AST.

	Gotchas
	- This is **not** full upstream semantics:
	  - We do not detect real `macro function` declarations yet.
	  - The returned expression grammar is limited to what `HxParser.parseExprText` can parse.
	- This rung exists to unblock Gate bring-up; extend only when a gate/test requires it.
**/
class ExprMacroExpander {
	public static function expandResolvedModules(
		modules:Array<ResolvedModule>,
		session:MacroHostSession,
		allowlist:Array<String>
	):{modules:Array<ResolvedModule>, expandedCount:Int} {
		if (modules == null || modules.length == 0) return {modules: modules == null ? [] : modules, expandedCount: 0};
		if (session == null) return {modules: modules, expandedCount: 0};
		if (allowlist == null || allowlist.length == 0) return {modules: modules, expandedCount: 0};

		final allowed:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
		final allowKeys = new Array<String>();
		var anyAllowed = false;
		for (raw in allowlist) {
			if (raw == null) continue;
			final s = StringTools.trim(raw);
			if (s.length == 0) continue;
			allowed.set(s, true);
			allowKeys.push(s);
			anyAllowed = true;
		}
		if (!anyAllowed) return {modules: modules, expandedCount: 0};

		var expandedCount = 0;
		final out = new Array<ResolvedModule>();

		final trace = isTrueEnv("HXHX_TRACE_EXPR_MACROS");

		for (m in modules) {
			final pm = ResolvedModule.getParsed(m);
			final decl = pm.getDecl();
			final modulePkg = HxModuleDecl.getPackagePath(decl);
			final importMap = buildImportMap(HxModuleDecl.getImports(decl), modulePkg);
			final cls = HxModuleDecl.getMainClass(decl);

			var changed = false;

			// Rewrite fields.
			final newFields = new Array<HxFieldDecl>();
			for (f in HxClassDecl.getFields(cls)) {
				final init = HxFieldDecl.getInit(f);
				final rewritten = rewriteExprOrNull(init, session, allowed, allowKeys, importMap, modulePkg, trace, 0, () -> expandedCount++);
				if (rewritten != init) changed = true;
				newFields.push(new HxFieldDecl(
					HxFieldDecl.getName(f),
					HxFieldDecl.getVisibility(f),
					HxFieldDecl.getIsStatic(f),
					HxFieldDecl.getTypeHint(f),
					rewritten
				));
			}

			// Rewrite function bodies.
			final newFns = new Array<HxFunctionDecl>();
			for (fn in HxClassDecl.getFunctions(cls)) {
				final body = HxFunctionDecl.getBody(fn);
				final newBody = new Array<HxStmt>();
				var bodyChanged = false;
				for (s in body) {
					final rs = rewriteStmt(s, session, allowed, allowKeys, importMap, modulePkg, trace, () -> expandedCount++);
					if (rs != s) bodyChanged = true;
					newBody.push(rs);
				}
				if (bodyChanged) changed = true;
				newFns.push(new HxFunctionDecl(
					HxFunctionDecl.getName(fn),
					HxFunctionDecl.getVisibility(fn),
					HxFunctionDecl.getIsStatic(fn),
					HxFunctionDecl.getArgs(fn),
					HxFunctionDecl.getReturnTypeHint(fn),
					newBody,
					HxFunctionDecl.getReturnStringLiteral(fn)
				));
			}

			if (!changed) {
				out.push(m);
				continue;
			}

			final newCls = new HxClassDecl(
				HxClassDecl.getName(cls),
				HxClassDecl.getHasStaticMain(cls),
				newFns,
				newFields
			);
			final newDecl = new HxModuleDecl(
				HxModuleDecl.getPackagePath(decl),
				HxModuleDecl.getImports(decl),
				newCls,
				HxModuleDecl.getHeaderOnly(decl),
				HxModuleDecl.getHasToplevelMain(decl)
			);
			final newParsed = new ParsedModule(pm.getSource(), newDecl, pm.getFilePath());
			final updated = new ResolvedModule(ResolvedModule.getModulePath(m), ResolvedModule.getFilePath(m), newParsed);
			out.push(updated);

			if (trace) {
				Sys.println("expr_macro_module=" + ResolvedModule.getModulePath(m) + " file=" + ResolvedModule.getFilePath(m));
			}
		}

		return {modules: out, expandedCount: expandedCount};
	}

	static function isTrueEnv(name:String):Bool {
		final v = Sys.getEnv(name);
		final t = v == null ? "" : StringTools.trim(v);
		return t == "1" || t == "true" || t == "yes";
	}

	static function rewriteStmt(
		s:HxStmt,
		session:MacroHostSession,
		allowed:haxe.ds.StringMap<Bool>,
		allowKeys:Array<String>,
		importMap:haxe.ds.StringMap<String>,
		modulePkg:String,
		trace:Bool,
		onExpand:()->Void
	):HxStmt {
		return switch (s) {
			case SBlock(stmts, pos):
				final out = new Array<HxStmt>();
				var changed = false;
				for (ss in stmts) {
					final rs = rewriteStmt(ss, session, allowed, allowKeys, importMap, modulePkg, trace, onExpand);
					if (rs != ss) changed = true;
					out.push(rs);
				}
				changed ? SBlock(out, pos) : s;
			case SVar(name, typeHint, init, pos):
				final rInit = rewriteExprOrNull(init, session, allowed, allowKeys, importMap, modulePkg, trace, 0, onExpand);
				rInit != init ? SVar(name, typeHint, rInit, pos) : s;
			case SIf(cond, thenBranch, elseBranch, pos):
				final rCond = rewriteExpr(cond, session, allowed, allowKeys, importMap, modulePkg, trace, 0, onExpand);
				final rThen = rewriteStmt(thenBranch, session, allowed, allowKeys, importMap, modulePkg, trace, onExpand);
				final rElse = elseBranch == null ? null : rewriteStmt(elseBranch, session, allowed, allowKeys, importMap, modulePkg, trace, onExpand);
				(rCond != cond || rThen != thenBranch || rElse != elseBranch) ? SIf(rCond, rThen, rElse, pos) : s;
			case SReturnVoid(_):
				s;
			case SReturn(e, pos):
				final re = rewriteExpr(e, session, allowed, allowKeys, importMap, modulePkg, trace, 0, onExpand);
				re != e ? SReturn(re, pos) : s;
			case SExpr(e, pos):
				final re = rewriteExpr(e, session, allowed, allowKeys, importMap, modulePkg, trace, 0, onExpand);
				re != e ? SExpr(re, pos) : s;
		}
	}

	static function rewriteExprOrNull(
		e:Null<HxExpr>,
		session:MacroHostSession,
		allowed:haxe.ds.StringMap<Bool>,
		allowKeys:Array<String>,
		importMap:haxe.ds.StringMap<String>,
		modulePkg:String,
		trace:Bool,
		depth:Int,
		onExpand:()->Void
	):Null<HxExpr> {
		return e == null ? null : rewriteExpr(e, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
	}

	static function rewriteExpr(
		e:HxExpr,
		session:MacroHostSession,
		allowed:haxe.ds.StringMap<Bool>,
		allowKeys:Array<String>,
		importMap:haxe.ds.StringMap<String>,
		modulePkg:String,
		trace:Bool,
		depth:Int,
		onExpand:()->Void
	):HxExpr {
		if (depth > 4) return e; // prevent runaway recursion in bring-up

		return switch (e) {
			case EField(obj, field):
				final ro = rewriteExpr(obj, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				ro != obj ? EField(ro, field) : e;
			case ECall(callee, args):
				final rc = rewriteExpr(callee, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				final rargs = new Array<HxExpr>();
				var argsChanged = false;
				for (a in args) {
					final ra = rewriteExpr(a, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					if (ra != a) argsChanged = true;
					rargs.push(ra);
				}

				if (trace) {
					final calleePath = renderCalleePath(rc);
					final argKinds = rargs.map(a -> exprKind(a)).join(",");
					Sys.println("expr_macro_visit callee=" + (calleePath == null ? exprKind(rc) : calleePath) + " args=[" + argKinds + "]");
				}

				final candidate = renderSimpleCall(rc, rargs);
				if (trace && candidate != null) {
					Sys.println("expr_macro_candidate raw=" + candidate);
				}
				final matched = candidate == null ? null : matchAllowlistedCall(candidate, allowed, allowKeys, importMap, modulePkg);
				if (matched != null) {
					if (trace) Sys.println("expr_macro_expand call=" + matched);
					final expandedText = session.expandExpr(matched);
					final parsed = HxParser.parseExprText(expandedText);
					onExpand();
					// Allow nested expansions in the returned expression (bounded).
					final nested = rewriteExpr(parsed, session, allowed, allowKeys, importMap, modulePkg, trace, depth + 1, onExpand);
					nested;
				} else {
					(argsChanged || rc != callee) ? ECall(rc, rargs) : e;
				}
			case ENew(typePath, args):
				final out = new Array<HxExpr>();
				var changed = false;
				for (a in args) {
					final ra = rewriteExpr(a, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					if (ra != a) changed = true;
					out.push(ra);
				}
				changed ? ENew(typePath, out) : e;
			case EUnop(op, expr):
				final re = rewriteExpr(expr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				re != expr ? EUnop(op, re) : e;
			case EBinop(op, left, right):
				final rl = rewriteExpr(left, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				final rr = rewriteExpr(right, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				(rl != left || rr != right) ? EBinop(op, rl, rr) : e;
			case ETernary(cond, thenExpr, elseExpr):
				final rc = rewriteExpr(cond, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				final rt = rewriteExpr(thenExpr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				final re = rewriteExpr(elseExpr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
				(rc != cond || rt != thenExpr || re != elseExpr) ? ETernary(rc, rt, re) : e;
				case EAnon(fieldNames, fieldValues):
					var changed = false;
					final outNames = new Array<String>();
					final outValues = new Array<HxExpr>();
					for (i in 0...fieldValues.length) {
					final v = fieldValues[i];
					final rv = rewriteExpr(v, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					if (rv != v) changed = true;
					outNames.push(fieldNames[i]);
					outValues.push(rv);
					}
					changed ? EAnon(outNames, outValues) : e;
				case EArrayDecl(values):
					final out = new Array<HxExpr>();
					var changed = false;
					for (v in values) {
						final rv = rewriteExpr(v, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
						if (rv != v) changed = true;
						out.push(rv);
					}
					changed ? EArrayDecl(out) : e;
				case EArrayAccess(arr, idx):
					final ra = rewriteExpr(arr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					final ri = rewriteExpr(idx, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					(ra != arr || ri != idx) ? EArrayAccess(ra, ri) : e;
				case ECast(expr, hint):
					final re = rewriteExpr(expr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					re != expr ? ECast(re, hint) : e;
				case EUntyped(expr):
					final re = rewriteExpr(expr, session, allowed, allowKeys, importMap, modulePkg, trace, depth, onExpand);
					re != expr ? EUntyped(re) : e;
				case _:
					e;
			}
		}

	static function exprKind(e:HxExpr):String {
		return switch (e) {
			case EBool(_): "Bool";
			case EInt(_): "Int";
			case EFloat(_): "Float";
			case EString(_): "String";
			case EIdent(_): "Ident";
			case EThis: "This";
			case ESuper: "Super";
			case ENull: "Null";
			case ENew(_, _): "New";
			case EField(_, _): "Field";
			case ECall(_, _): "Call";
			case EUnop(_, _): "Unop";
			case EBinop(_, _, _): "Binop";
				case ETernary(_, _, _): "Ternary";
				case EAnon(_, _): "Anon";
				case EArrayDecl(_): "ArrayDecl";
				case EArrayAccess(_, _): "ArrayAccess";
				case ECast(_, _): "Cast";
				case EUntyped(_): "Untyped";
				case EUnsupported(_): "Unsupported";
			}
		}

	static function buildImportMap(imports:Array<String>, modulePkg:String):haxe.ds.StringMap<String> {
		final map = new haxe.ds.StringMap<String>();
		if (imports == null) return map;

		for (raw in imports) {
			if (raw == null) continue;
			final trimmed = StringTools.trim(raw);
			if (trimmed.length == 0) continue;
			if (StringTools.endsWith(trimmed, ".*")) continue;

			final full = {
				// Bring-up approximation: allow `import Foo;` inside `package unit;` to mean `unit.Foo`.
				if (modulePkg != null && modulePkg.length > 0 && trimmed.indexOf(".") == -1) {
					final c0 = trimmed.charCodeAt(0);
					final isUpper = c0 >= "A".code && c0 <= "Z".code;
					isUpper ? (modulePkg + "." + trimmed) : trimmed;
				} else {
					trimmed;
				}
			};

			final dot = full.lastIndexOf(".");
			final shortName = dot == -1 ? full : full.substr(dot + 1);
			if (shortName.length == 0) continue;
			if (!map.exists(shortName)) map.set(shortName, full);
		}
		return map;
	}

	static function matchAllowlistedCall(
		renderedCall:String,
		allowed:haxe.ds.StringMap<Bool>,
		allowKeys:Array<String>,
		importMap:haxe.ds.StringMap<String>,
		modulePkg:String
	):Null<String> {
		if (renderedCall == null || renderedCall.length == 0) return null;
		if (allowed.exists(renderedCall)) return renderedCall;

		final firstDot = renderedCall.indexOf(".");
		if (firstDot != -1) {
			final head = renderedCall.substr(0, firstDot);
			final rest = renderedCall.substr(firstDot); // includes dot
			if (importMap != null && importMap.exists(head)) {
				final fullHead = importMap.get(head);
				if (fullHead != null && fullHead.length > 0) {
					final qualified = fullHead + rest;
					if (allowed.exists(qualified)) return qualified;
				}
			}
		}

		// Same-package qualification: `Foo.bar()` inside `package unit;` can be `unit.Foo.bar()`.
		if (modulePkg != null && modulePkg.length > 0 && !StringTools.startsWith(renderedCall, modulePkg + ".")) {
			final headDot = renderedCall.indexOf(".");
			final head = headDot == -1 ? renderedCall : renderedCall.substr(0, headDot);
			if (head.length > 0) {
				final c0 = head.charCodeAt(0);
				final isUpper = c0 >= "A".code && c0 <= "Z".code;
				if (isUpper) {
					final qualified = modulePkg + "." + renderedCall;
					if (allowed.exists(qualified)) return qualified;
				}
			}
		}

		// Last-resort bring-up fallback: if allowlist uses a fully-qualified type path but the code
		// calls it via imports (`ExprMacroShim.hello()`), match by `Class.method(...)` suffix.
		//
		// We only accept an unambiguous match (exactly one allowlisted key with the same suffix).
		final renderedShort = shortenCall(renderedCall);
		var found:Null<String> = null;
		var matches = 0;
		for (k in allowKeys) {
			if (k == null) continue;
			if (shortenCall(k) == renderedShort) {
				found = k;
				matches += 1;
				if (matches > 1) break;
			}
		}
		if (matches == 1) return found;

		return null;
	}

	static function shortenCall(callText:String):String {
		if (callText == null) return "";
		final open = callText.indexOf("(");
		final head = open == -1 ? callText : callText.substr(0, open);
		final tail = open == -1 ? "" : callText.substr(open);
		final parts = head.split(".");
		if (parts.length <= 2) return callText;
		return parts[parts.length - 2] + "." + parts[parts.length - 1] + tail;
	}

	static function renderCalleePath(e:HxExpr):Null<String> {
		return switch (e) {
			case EIdent(name):
				name;
			case EField(obj, field):
				final base = renderCalleePath(obj);
				base == null ? null : (base + "." + field);
			case _:
				null;
		}
	}

	static function escapeStringLiteral(s:String):String {
		if (s == null) return "";
		// Avoid repeated local rebinding (`out = replace(out, ...)`) because Stage3 brings
		// `hxhx` up through our OCaml backend, and conservative codegen can drop those
		// intermediate assignments.
		return StringTools.replace(
			StringTools.replace(
				StringTools.replace(
					StringTools.replace(
						StringTools.replace(s, "\\", "\\\\"),
						"\"",
						"\\\""
					),
					"\n",
					"\\n"
				),
				"\r",
				"\\r"
			),
			"\t",
			"\\t"
		);
	}

	static function renderSimpleCall(callee:HxExpr, args:Array<HxExpr>):Null<String> {
		// Supported shapes:
		// - TypePath.meth()
		// - TypePath.meth("literal")
		if (callee == null) return null;
		final path = renderCalleePath(callee);
		if (path == null || path.length == 0) return null;

		if (args == null || args.length == 0) return path + "()";
		if (args.length == 1) {
			return switch (args[0]) {
				case EString(s):
					path + "(\"" + escapeStringLiteral(s) + "\")";
				case _:
					null;
			}
		}
		return null;
	}
}
