package hxhx;

import hxhx.macro.ExprMacroDispatch;
import hxhx.macro.MacroRuntimeSession;
import hxhx.runtime.NullableRuntimeString;
import hxhx.ExprMacroCallRewrite.ExprMacroCallRewriter;
import hxhx.ExprMacroDeclarationSelector.capture;
import hxhx.ExprMacroDeclarationSelector.ExprMacroSelectionScope;
import hxhx.ExprMacroLexicalScope.ExprMacroLexicalGap;

/**
	Semantic facts a request supplies so calls can be selected by declaration.
	The index holds registered module headers; the loader publishes declarations
	on demand exactly as body typing does. Without this context only the exact
	string route runs.
**/
typedef ExprMacroSelectionContext = {
	final index:TyperIndex;
	final loader:Null<ModuleLoader>;
}

/** A selected macro call that no executor could run; it continued through ordinary typing. */
typedef ExprMacroUnexecutedCall = {
	final filePath:String;
	final declaration:String;
	final reason:String;

	/** The source file of the declaration's module, or empty when the index does not know it. */
	final ownerFilePath:String;
}

/** Result of one expansion pass over a module list. */
typedef ExprMacroExpansion = {
	final modules:Array<ResolvedModule>;
	final expandedCount:Int;
	final unexecuted:Array<ExprMacroUnexecutedCall>;
	final lexicalGaps:Array<ExprMacroLexicalGap>;
}

/**
	Rewrite source macro calls before ordinary body typing.
	One syntax walker owns lexical visibility and ordered children. A typed call
	decision either consumes original syntax or visits children before one final
	transformation.

	Precedence for each call, in order:
	1. A call whose exact text matches a registered executor (the allowlist of
	   builtin and project-registered expressions) takes the exact-text route,
	   even when its callee is a macro declaration. That route is how the
	   no-argument plugin pilot serves promoted macros today.
	2. With a selection context, a callee that selects a `macro` declaration is
	   consumed before its arguments are visited and dispatched as one structured
	   request through `MacroRuntimeSession.expandSelected`; `Expanded` syntax
	   replaces the call.
	3. A selected call the session reports `Unavailable` is recorded in
	   `unexecuted` and then continues exactly as an unselected call would: its
	   children are visited and ordinary typing sees it. The driver prints each
	   record so a later failure is attributable. This fallback stays until a
	   general executor exists; it is not a claim that the call was expanded.
	Calls inside a lexical gap (unprovable visible names) are never selected; the
	walker reports the gap instead of probing the loader with value names.
**/
class ExprMacroExpander {
	public static function expandResolvedModules(modules:Array<ResolvedModule>, session:MacroRuntimeSession, allowlist:Array<String>,
			?selection:ExprMacroSelectionContext):ExprMacroExpansion {
		if (modules == null || modules.length == 0 || session == null)
			return {
				modules: modules == null ? [] : modules,
				expandedCount: 0,
				unexecuted: [],
				lexicalGaps: []
			};
		final allowed = new haxe.ds.StringMap<Bool>();
		final keys = new Array<String>();
		final entries = allowlist == null ? [] : allowlist;
		for (raw in entries) {
			if (raw == null || StringTools.trim(raw).length == 0)
				continue;
			final key = StringTools.trim(raw);
			allowed.set(key, true);
			keys.push(key);
		}
		if (keys.length == 0 && selection == null)
			return {
				modules: modules,
				expandedCount: 0,
				unexecuted: [],
				lexicalGaps: []
			};
		var count = 0;
		final unexecuted = new Array<ExprMacroUnexecutedCall>();
		final trace = isTrueEnv("HXHX_TRACE_EXPR_MACROS");
		final typerContexts = new haxe.ds.ObjectMap<HxClassDecl, TyperContext>();
		final rewritten = rewriteResolvedModules(modules, (original, context, scope) -> {
			final imports = buildImportMap(context.directives, context.packagePath);
			final registered = switch original {
				case ECall(callee, arguments):
					final candidate = renderSimpleCall(callee, arguments);
					candidate == null ? null : matchAllowlistedCall(candidate, allowed, keys, imports, context.packagePath);
				case _: throw "source call continuation received a non-call";
			};
			final selected = registered != null
				|| selection == null ? null : selectDeclaration(original, context, scope, selection, typerContexts);
			if (selected != null) {
				switch dispatchSelected(selected, context, session, trace) {
					case Expanded(expression):
						count++;
						return Consume(expression);
					case Unavailable(reason):
						final owner = selection.index.getRegisteredModule(selected.getDeclaration().getModulePath());
						unexecuted.push({
							filePath: context.filePath,
							declaration: describeDeclaration(selected.getDeclaration()),
							reason: reason,
							ownerFilePath: owner == null ? "" : ResolvedModule.getFilePath(owner)
						});
				}
			}
			return Recurse(call -> {
				return switch call {
					case ECall(callee, arguments):
						if (trace) {
							final path = renderCalleePath(callee);
							Sys.println("expr_macro_visit callee=" + (path.length == 0 ? exprKind(callee) : path) + " args=["
								+ arguments.map(exprKind).join(",") + "]");
						}
						final candidate = renderSimpleCall(callee, arguments);
						if (trace && candidate != null)
							Sys.println("expr_macro_candidate raw=" + candidate);
						final matched = candidate == null ? null : matchAllowlistedCall(candidate, allowed, keys, imports, context.packagePath);
						if (matched == null) call else {
							if (trace)
								Sys.println("expr_macro_expand call=" + matched);
							final replacement = HxParser.parseExprText(session.expandExpr(matched));
							count++;
							replacement;
						}
					case _: throw "source call continuation received a non-call";
				};
			});
		});
		return {
			modules: rewritten.modules,
			expandedCount: count,
			unexecuted: unexecuted,
			lexicalGaps: rewritten.lexicalGaps
		};
	}

	/**
		Select a macro declaration for one call before its children are visited.
		Visible names come from the walker; a value-bound root stays ordinary. In a
		lexical gap nothing is selected: a probe would resolve value names through
		the loader and run missing-type hooks for them. Selector failures carry the
		call's file and callee; an exact call position waits on per-occurrence
		source positions (haxe_ocaml-9sj5p.2).
	**/
	static function selectDeclaration(call:HxExpr, context:ExprMacroSourceContext, scope:ExprMacroSelectionScope, selection:ExprMacroSelectionContext,
			typerContexts:haxe.ds.ObjectMap<HxClassDecl, TyperContext>):Null<SelectedExprMacroCall> {
		return switch scope.visibility {
			case Unavailable(_): null;
			case Known(_):
				final typerContext = typerContextFor(context, selection, typerContexts);
				try {
					capture(call, typerContext, scope);
				} catch (error:String) {
					throw context.filePath + ": expression macro call " + calleeLabel(call) + ": " + error;
				}
		};
	}

	static function calleeLabel(call:HxExpr):String {
		return switch call {
			case ECall(callee, _):
				final path = renderCalleePath(callee);
				path.length == 0 ? exprKind(callee) : path;
			case _: exprKind(call);
		};
	}

	/** One semantic context per source class, bound through the request index like body typing. */
	static function typerContextFor(context:ExprMacroSourceContext, selection:ExprMacroSelectionContext,
			typerContexts:haxe.ds.ObjectMap<HxClassDecl, TyperContext>):TyperContext {
		final existing = typerContexts.get(context.sourceClass);
		if (existing != null)
			return existing;
		final info = selection.index.getForSourceClass(context.sourceClass);
		final className = HxClassDecl.getName(context.sourceClass);
		final fullName = info != null ? info.getFullName() : (context.packagePath.length == 0 ? className : context.packagePath + "." + className);
		final resolvedDirectives = TyperStage.resolveModuleDirectives(context.directives, context.packagePath, context.modulePath, selection.index,
			selection.loader);
		final created = new TyperContext(selection.index, context.filePath, context.modulePath, context.packagePath, context.directives, fullName,
			selection.loader, resolvedDirectives);
		typerContexts.set(context.sourceClass, created);
		return created;
	}

	/** Send the selected call as one typed request; syntax or an explicit reason comes back, never null syntax. */
	static function dispatchSelected(selected:SelectedExprMacroCall, context:ExprMacroSourceContext, session:MacroRuntimeSession,
			trace:Bool):ExprMacroDispatchResult {
		final request = new ExprMacroDispatchRequest(selected.getDeclaration(), selected.getArguments(), context.filePath, context.modulePath);
		if (trace)
			Sys.println("expr_macro_dispatch declaration=" + request.describe() + " args=" + request.getArguments().length);
		final result = session.expandSelected(request);
		switch result {
			case Expanded(expression) if (expression == null):
				throw context.filePath + ": expression macro " + request.describe() + " returned no syntax";
			case _:
		}
		return result;
	}

	static function describeDeclaration(declaration:TyDeclarationInfo):String
		return declaration.getOwner().getCanonicalName() + "." + declaration.getSignature().getName();

	/**
		Visit every source class using source-owned scope without publishing types.
		Consume skips all original call children; Recurse applies its continuation
		once after receiver and arguments. Replacement syntax is visited separately.
		Declaration preparation belongs to callers that select macro declarations;
		the existing text adapter needs only source directives and package names.
		Declaration-aware callers must reject nonempty lexicalGaps before claiming
		complete selection, even when an opaque subtree contains no visited calls.
		The text adapter uses only its prior syntax contract.
	**/
	public static function rewriteResolvedModules(modules:Array<ResolvedModule>,
			rewriter:ExprMacroCallRewriter):{modules:Array<ResolvedModule>, lexicalGaps:Array<ExprMacroLexicalGap>} {
		final lexicalGaps = new Array<ExprMacroLexicalGap>();
		final out = new Array<ResolvedModule>();
		for (module in modules) {
			final parsed = ResolvedModule.getParsed(module);
			final declaration = parsed.getDecl();
			final packagePath = HxModuleDecl.getPackagePath(declaration);
			final modulePath = ResolvedModule.getModulePath(module);
			final directives = HxModuleDecl.getDirectives(declaration);
			var changed = false;
			var main = HxModuleDecl.getMainClass(declaration);
			final classes = new Array<HxClassDecl>();
			for (source in HxModuleDecl.getClasses(declaration)) {
				final context:ExprMacroSourceContext = {
					filePath: parsed.getFilePath(),
					modulePath: modulePath,
					packagePath: packagePath,
					directives: directives.copy(),
					sourceClass: source
				};
				var classChanged = false;
				final fields = new Array<HxFieldDecl>();
				for (field in HxClassDecl.getFields(source)) {
					final init = HxFieldDecl.getInit(field);
					final value = init == null ? null : rewriteExpr(init, rewriter, context,
						new ExprMacroLexicalScope(HxFieldDecl.getIsStatic(field), [], lexicalGaps), 0);
					if (value == init)
						fields.push(field)
					else {
						classChanged = true;
						fields.push(new HxFieldDecl(HxFieldDecl.getName(field), HxFieldDecl.getVisibility(field), HxFieldDecl.getIsStatic(field),
							HxFieldDecl.getTypeHint(field), value, HxFieldDecl.getMetadata(field), HxFieldDecl.getPos(field), HxFieldDecl.getEndPos(field),
							HxFieldDecl.getIsFinal(field), HxFieldDecl.getPropertyGet(field), HxFieldDecl.getPropertySet(field),
							HxFieldDecl.getInitText(field)));
					}
				}
				final functions = new Array<HxFunctionDecl>();
				for (functionDecl in HxClassDecl.getFunctions(source)) {
					// Macro bodies belong to their separate compilation domain, not target-code expansion.
					if (HxFunctionDecl.getMetadata(functionDecl).indexOf("macro") >= 0) {
						functions.push(functionDecl);
						continue;
					}
					final scope = new ExprMacroLexicalScope(HxFunctionDecl.getIsStatic(functionDecl), [], lexicalGaps);
					final arguments = new Array<HxFunctionArg>();
					var functionChanged = false;
					for (argument in HxFunctionDecl.getArgs(functionDecl)) {
						final defaultValue = HxFunctionArg.getDefaultValue(argument);
						final rewrittenDefault = switch defaultValue {
							case NoDefault: defaultValue;
							case Default(value):
								final rewritten = rewriteExpr(value, rewriter, context, scope.child(), 0);
								rewritten == value ? defaultValue : HxDefaultValue.Default(rewritten);
						};
						if (rewrittenDefault == defaultValue)
							arguments.push(argument)
						else {
							functionChanged = true;
							arguments.push(new HxFunctionArg(HxFunctionArg.getName(argument), HxFunctionArg.getTypeHint(argument), rewrittenDefault,
								HxFunctionArg.getIsOptional(argument), HxFunctionArg.getIsRest(argument), HxFunctionArg.getDefaultValueText(argument),
								HxFunctionArg.getMetadata(argument)));
						}
					}
					for (argument in arguments)
						scope.declare(HxFunctionArg.getName(argument));
					final body = new Array<HxStmt>();
					for (statement in HxFunctionDecl.getBody(functionDecl)) {
						final value = rewriteStmt(statement, rewriter, context, scope);
						if (value != statement)
							functionChanged = true;
						body.push(value);
					}
					if (!functionChanged)
						functions.push(functionDecl)
					else {
						classChanged = true;
						functions.push(new HxFunctionDecl(HxFunctionDecl.getName(functionDecl), HxFunctionDecl.getVisibility(functionDecl),
							HxFunctionDecl.getIsStatic(functionDecl), arguments, HxFunctionDecl.getReturnTypeHint(functionDecl), body,
							HxFunctionDecl.getReturnStringLiteral(functionDecl), HxFunctionDecl.getMetadata(functionDecl),
							HxFunctionDecl.getPos(functionDecl), HxFunctionDecl.getEndPos(functionDecl), HxFunctionDecl.getBodyText(functionDecl),
							HxFunctionDecl.getHasBody(functionDecl), HxFunctionDecl.getIsModuleLevel(functionDecl)));
					}
				}
				var rewritten = source;
				if (classChanged) {
					changed = true;
					rewritten = new HxClassDecl(HxClassDecl.getName(source), HxClassDecl.getHasStaticMain(source), functions, fields,
						HxClassDecl.getExtendsPath(source), HxClassDecl.getMetadata(source), HxClassDecl.getIsInterface(source),
						HxClassDecl.getImplementsPaths(source), HxClassDecl.getVisibility(source), HxClassDecl.getInterfaceExtendsPaths(source),
						HxClassDecl.getIsExtern(source), HxClassDecl.getEnumDeclaration(source), HxClassDecl.getTypeParameters(source),
						HxClassDecl.getSourceRange(source));
				}
				classes.push(rewritten);
				if (source == main)
					main = rewritten;
			}
			if (!changed) {
				out.push(module);
				continue;
			}
			final rewritten = new HxModuleDecl(packagePath, directives, main, classes, HxModuleDecl.getHeaderOnly(declaration),
				HxModuleDecl.getHasToplevelMain(declaration), HxModuleDecl.getTypedefs(declaration));
			out.push(new ResolvedModule(modulePath, ResolvedModule.getFilePath(module), new ParsedModule(parsed.getSource(), rewritten, parsed.getFilePath()),
				ResolvedModule.getSourceOrigin(module), ResolvedModule.getConditionalCompilation(module), ResolvedModule.getGeneratedDeclarations(module)));
		}
		return {modules: out, lexicalGaps: lexicalGaps.copy()};
	}

	static function isTrueEnv(name:String):Bool {
		final value = NullableRuntimeString.trimToEmpty(Sys.getEnv(name));
		return value == "1" || value == "true" || value == "yes";
	}

	static function rewriteStmt(s:HxStmt, rewriter:ExprMacroCallRewriter, context:ExprMacroSourceContext, scope:ExprMacroLexicalScope):HxStmt {
		return switch (s) {
			// Typed match decisions belong to emission, after source macro expansion.
			case SGuardedSwitch(_, _, _, _, _):
				throw "backend guarded switch is not source syntax";
			case STargetScope(_, _, _):
				throw "native target scope is not valid in this source or target phase";
			case SBlock(stmts, pos):
				scope = scope.child();
				final out = new Array<HxStmt>();
				var changed = false;
				for (ss in stmts) {
					final rs = rewriteStmt(ss, rewriter, context, scope);
					if (rs != ss)
						changed = true;
					out.push(rs);
				}
				changed ? SBlock(out, pos) : s;
			case SVar(name, typeHint, init, pos, metadata):
				var rInit:Null<HxExpr> = init;
				if (init != null) {
					final rewrittenInit = rewriteExpr(init, rewriter, context, scope, 0);
					if (rewrittenInit != init)
						rInit = true ? rewrittenInit : null;
				}
				scope.declare(name);
				rInit != init ? SVar(name, typeHint, rInit, pos, metadata == null ? [] : metadata.copy()) : s;
			case SIf(cond, thenBranch, elseBranch, pos):
				final rCond = rewriteExpr(cond, rewriter, context, scope, 0);
				final rThen = rewriteStmt(thenBranch, rewriter, context, scope.child());
				var rElse:Null<HxStmt> = null;
				if (elseBranch != null) rElse = true ? rewriteStmt(elseBranch, rewriter, context, scope.child()) : null;
					(rCond != cond || rThen != thenBranch || rElse != elseBranch) ? SIf(rCond, rThen, rElse, pos) : s;
			case SWhile(cond, body, pos):
				final rCond = rewriteExpr(cond, rewriter, context, scope, 0);
				final rBody = rewriteStmt(body, rewriter, context, scope.child());
				(rCond != cond || rBody != body) ? SWhile(rCond, rBody, pos) : s;
			case SDoWhile(body, cond, pos):
				final rBody = rewriteStmt(body, rewriter, context, scope.child());
				final rCond = rewriteExpr(cond, rewriter, context, scope, 0);
				(rBody != body || rCond != cond) ? SDoWhile(rBody, rCond, pos) : s;
			case SForIn(name, iterable, body, pos):
				final rIt = rewriteExpr(iterable, rewriter, context, scope, 0);
				final rBody = rewriteStmt(body, rewriter, context, scope.child([name]));
				(rIt != iterable || rBody != body) ? SForIn(name, rIt, rBody, pos) : s;
			case SForKeyValue(keyName, valueName, iterable, body, pos):
				final rIt = rewriteExpr(iterable, rewriter, context, scope, 0);
				final rBody = rewriteStmt(body, rewriter, context, scope.child([keyName, valueName]));
				(rIt != iterable || rBody != body) ? SForKeyValue(keyName, valueName, rIt, rBody, pos) : s;
			case STry(tryBody, catches, pos):
				final rTry = rewriteStmt(tryBody, rewriter, context, scope.child());
				var changed = rTry != tryBody;
				final outCatches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (c in catches) {
					final rBody = rewriteStmt(c.body, rewriter, context, scope.child([c.name]));
					if (rBody != c.body)
						changed = true;
					outCatches.push({name: c.name, typeHint: c.typeHint, body: rBody});
				}
				changed ? STry(rTry, outCatches, pos) : s;
			case SBreak(_):
				s;
			case SContinue(_):
				s;
			case SSwitch(scrutinee, patterns, bodies, pos, exhaustive):
				final rewrittenScrutinee = rewriteExpr(scrutinee, rewriter, context, scope, 0);
				var changed = rewrittenScrutinee != scrutinee;
				final rewrittenBodies = new Array<HxStmt>();
				for (index in 0...bodies.length) {
					final names = TySwitchPatternBindings.sourceNames(patterns[index]);
					final caseScope = scope.child(names == null ? [] : names);
					if (names == null)
						caseScope.markUnavailable(context.filePath, "source macro traversal cannot prove this switch pattern scope");
					final rewritten = rewriteStmt(bodies[index], rewriter, context, caseScope);
					if (rewritten != bodies[index])
						changed = true;
					rewrittenBodies.push(rewritten);
				}
				changed ? SSwitch(rewrittenScrutinee, patterns.copy(), rewrittenBodies, pos, exhaustive) : s;
			case SReturnVoid(_):
				s;
			case SReturn(e, pos):
				final re = rewriteExpr(e, rewriter, context, scope, 0);
				re != e ? SReturn(re, pos) : s;
			case SThrow(e, pos):
				final re = rewriteExpr(e, rewriter, context, scope, 0);
				re != e ? SThrow(re, pos) : s;
			case SExpr(e, pos):
				final re = rewriteExpr(e, rewriter, context, scope, 0);
				re != e ? SExpr(re, pos) : s;
		}
	}

	/**
		Replace registered calls while preserving their surrounding authored syntax.
		Unchanged children retain node identity; changed containers retain source facts
		and positions. This traversal does not make syntax arguments ordinary values.
	 */
	static function rewriteExpr(e:HxExpr, rewriter:ExprMacroCallRewriter, context:ExprMacroSourceContext, scope:ExprMacroLexicalScope, depth:Int):HxExpr {
		if (depth > 4)
			throw "expression macro replacement exceeded expansion depth";

		return switch (e) {
			case ELoweredControl(_, _, _, _):
				throw "executable control cannot re-enter source macro expansion";
			case EParenthesized(inner, position):
				final rewritten = rewriteExpr(inner, rewriter, context, scope, depth);
				rewritten != inner ? EParenthesized(rewritten, position) : e;
			case EPrivateAccess(inner, position):
				final rewritten = rewriteExpr(inner, rewriter, context, scope, depth);
				rewritten != inner ? EPrivateAccess(rewritten, position) : e;
			case ESourceTry(catches, bodies, position):
				if (bodies.length != catches.length + 1)
					throw "source catch body layout differs from its declarations";
				var changed = false;
				final rewritten = new Array<HxExpr>();
				for (index in 0...bodies.length) {
					final body = bodies[index];
					final bindings = index == 0 ? [] : [catches[index - 1].getName()];
					final value = rewriteExpr(body, rewriter, context, scope.child(bindings), depth);
					if (value != body)
						changed = true;
					rewritten.push(value);
				}
				changed ? ESourceTry(catches.copy(), rewritten, position) : e;
			case ESourceFor(binding, iterable, body, position):
				final rewrittenIterable = rewriteExpr(iterable, rewriter, context, scope, depth);
				final rewrittenBody = rewriteExpr(body, rewriter, context, scope.child(HxForBinding.names(binding)), depth);
				(rewrittenIterable != iterable || rewrittenBody != body) ? ESourceFor(binding, rewrittenIterable, rewrittenBody, position) : e;
			case ESourceGroup(children, position):
				scope = scope.child();
				var changed = false;
				final rewritten = [
					for (child in children) {
						final value = rewriteExpr(child, rewriter, context, scope, depth);
						if (value != child) changed = true;
						value;
					}
				];
				changed ? ESourceGroup(rewritten, position) : e;
			case ESourceFunction(facts, body, defaults, position):
				facts.assertDefaultCount(defaults.length);
				final name = facts.getDeclaredName();
				if (name != null)
					scope.declare(name);
				var changed = false;
				final rewrittenDefaults = [
					for (entry in defaults) {
						final value = rewriteExpr(entry, rewriter, context, scope.child(), depth);
						if (value != entry) changed = true;
						value;
					}
				];
				final rewrittenBody = rewriteExpr(body, rewriter, context, scope.child(facts.getArguments()), depth);
				if (rewrittenBody != body)
					changed = true;
				changed ? ESourceFunction(facts, rewrittenBody, rewrittenDefaults, position) : e;
			case ELambda(arguments, body, signature):
				final rewritten = rewriteExpr(body, rewriter, context, scope.child(arguments), depth);
				rewritten == body ? e : ELambda(arguments.copy(), rewritten, signature);
			case ESourceIf(condition, whenTrue, whenFalse, position):
				final rewrittenCondition = rewriteExpr(condition, rewriter, context, scope, depth);
				final rewrittenTrue = rewriteExpr(whenTrue, rewriter, context, scope.child(), depth);
				final rewrittenFalse = whenFalse == null ? null : rewriteExpr(whenFalse, rewriter, context, scope.child(), depth);
					(rewrittenCondition != condition || rewrittenTrue != whenTrue || rewrittenFalse != whenFalse) ? ESourceIf(rewrittenCondition,
						rewrittenTrue, rewrittenFalse, position) : e;
			case EThrow(value, position):
				final rewritten = rewriteExpr(value, rewriter, context, scope, depth);
				rewritten != value ? EThrow(rewritten, position) : e;
			case EReturn(value):
				if (value == null) {
					e;
				} else {
					final rewritten = rewriteExpr(value, rewriter, context, scope, depth);
					rewritten != value ? EReturn(rewritten) : e;
				}
			case EVars(declarations):
				var changed = false;
				final rewrittenDeclarations = new Array<HxExpr>();
				for (declaration in declarations) {
					final initializer = HxExprVarDecl.getInitializer(declaration);
					final rewritten = initializer == null ? null : rewriteExpr(initializer, rewriter, context, scope, depth);
					if (rewritten != initializer)
						changed = true;
					rewrittenDeclarations.push(HxExprVarDecl.make(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration), rewritten,
						HxExprVarDecl.getPosition(declaration), HxExprVarDecl.getIsFinal(declaration), HxExprVarDecl.getIsStatic(declaration)));
					scope.declare(HxExprVarDecl.getName(declaration));
				}
				changed ? EVars(rewrittenDeclarations) : e;
			case EVariableDeclaration(name, typeHint, initializer, position, isFinal, isStatic):
				final rewritten = initializer == null ? null : rewriteExpr(initializer, rewriter, context, scope, depth);
				scope.declare(name);
				rewritten != initializer ? HxExprVarDecl.make(name, typeHint, rewritten, position, isFinal, isStatic) : e;
			case EWhile(condition, body, bodyIsBlock, position, loopKind):
				var rewrittenCondition = condition;
				if (loopKind == Normal)
					rewrittenCondition = rewriteExpr(condition, rewriter, context, scope, depth);
				var changed = rewrittenCondition != condition;
				final bodyScope = scope.child();
				final rewrittenBody = new Array<HxExpr>();
				for (entry in body) {
					final rewritten = rewriteExpr(entry, rewriter, context, bodyScope, depth);
					if (rewritten != entry)
						changed = true;
					rewrittenBody.push(rewritten);
				}
				if (loopKind == DoWhile)
					rewrittenCondition = rewriteExpr(condition, rewriter, context, scope, depth);
				if (rewrittenCondition != condition)
					changed = true;
				changed ? EWhile(rewrittenCondition, rewrittenBody, bodyIsBlock, position, loopKind) : e;
			case EBreak(_) | EContinue(_): e;
			case EField(obj, field):
				final ro = rewriteExpr(obj, rewriter, context, scope, depth);
				ro != obj ? EField(ro, field) : e;
			case ENullSafeField(obj, field):
				final ro = rewriteExpr(obj, rewriter, context, scope, depth);
				ro != obj ? ENullSafeField(ro, field) : e;
			case ECall(callee, args):
				switch rewriter(e, context, scope.snapshot()) {
					case Consume(replacement):
						replacement == e ? e : rewriteExpr(replacement, rewriter, context, scope, depth + 1);
					case Recurse(afterChildren):
						final receiver = rewriteExpr(callee, rewriter, context, scope, depth);
						final arguments = new Array<HxExpr>();
						var changed = receiver != callee;
						for (argument in args) {
							final rewritten = rewriteExpr(argument, rewriter, context, scope, depth);
							if (rewritten != argument)
								changed = true;
							arguments.push(rewritten);
						}
						final call:HxExpr = changed ? ECall(receiver, arguments) : e;
						final replacement = afterChildren(call);
						replacement == call ? call : rewriteExpr(replacement, rewriter, context, scope, depth + 1);
				}
			case ENew(typePath, args):
				final out = new Array<HxExpr>();
				var changed = false;
				for (a in args) {
					final ra = rewriteExpr(a, rewriter, context, scope, depth);
					if (ra != a)
						changed = true;
					out.push(ra);
				}
				changed ? ENew(typePath, out) : e;
			case EUnop(op, fixity, expr):
				final re = rewriteExpr(expr, rewriter, context, scope, depth);
				re != expr ? EUnop(op, fixity, re) : e;
			case EBinop(op, left, right):
				final rl = rewriteExpr(left, rewriter, context, scope, depth);
				final rr = rewriteExpr(right, rewriter, context, scope, depth);
				(rl != left || rr != right) ? EBinop(op, rl, rr) : e;
			case EDiscardThen(effect, continuation):
				final rewrittenEffect = rewriteExpr(effect, rewriter, context, scope, depth);
				final rewrittenContinuation = rewriteExpr(continuation, rewriter, context, scope, depth);
				(rewrittenEffect != effect || rewrittenContinuation != continuation) ? EDiscardThen(rewrittenEffect, rewrittenContinuation) : e;
			case ETernary(cond, thenExpr, elseExpr):
				final rc = rewriteExpr(cond, rewriter, context, scope, depth);
				final rt = rewriteExpr(thenExpr, rewriter, context, scope.child(), depth);
				final re = rewriteExpr(elseExpr, rewriter, context, scope.child(), depth);
				(rc != cond || rt != thenExpr || re != elseExpr) ? ETernary(rc, rt, re) : e;
			case ETryCatchRaw(_raw):
				scope.markUnavailable(context.filePath, "source macro traversal requires structured catch bindings");
				e;
			case EAnon(fieldNames, fieldValues):
				var changed = false;
				final outNames = new Array<String>();
				final outValues = new Array<HxExpr>();
				for (i in 0...fieldValues.length) {
					final v = fieldValues[i];
					final rv = rewriteExpr(v, rewriter, context, scope, depth);
					if (rv != v)
						changed = true;
					outNames.push(fieldNames[i]);
					outValues.push(rv);
				}
				changed ? EAnon(outNames, outValues) : e;
			case EArrayDecl(values):
				final out = new Array<HxExpr>();
				var changed = false;
				for (v in values) {
					final rv = rewriteExpr(v, rewriter, context, scope, depth);
					if (rv != v)
						changed = true;
					out.push(rv);
				}
				changed ? EArrayDecl(out) : e;
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				final ri = rewriteExpr(iterable, rewriter, context, scope, depth);
				final bindingScope = scope.child([name]);
				final rg = guardExpr == null ? null : rewriteExpr(guardExpr, rewriter, context, bindingScope, depth);
				final ry = rewriteExpr(yieldExpr, rewriter, context, bindingScope, depth);
				(ri != iterable || rg != guardExpr || ry != yieldExpr) ? EArrayComprehension(name, ri, rg, ry) : e;
			case EArrayAccess(arr, idx):
				final ra = rewriteExpr(arr, rewriter, context, scope, depth);
				final ri = rewriteExpr(idx, rewriter, context, scope, depth);
				(ra != arr || ri != idx) ? EArrayAccess(ra, ri) : e;
			case ERange(start, end):
				final rs = rewriteExpr(start, rewriter, context, scope, depth);
				final re = rewriteExpr(end, rewriter, context, scope, depth);
				(rs != start || re != end) ? ERange(rs, re) : e;
			case ECast(expr, hint):
				final re = rewriteExpr(expr, rewriter, context, scope, depth);
				re != expr ? ECast(re, hint) : e;
			case ECheckType(expr, hint):
				final re = rewriteExpr(expr, rewriter, context, scope, depth);
				re != expr ? ECheckType(re, hint) : e;
			case EUntyped(expr):
				final re = rewriteExpr(expr, rewriter, context, scope, depth);
				re != expr ? EUntyped(re) : e;
			case EMacroExpr(expr, wrappers):
				// Quoted syntax is data, not an ordinary call in the enclosing scope.
				e;
			case EMacroType(_):
				e;
			case ESwitch(_, _, _) | ESwitchRaw(_):
				scope.markUnavailable(context.filePath, "source macro traversal cannot prove this switch syntax");
				e;
			case EUnsupported(_):
				scope.markUnavailable(context.filePath, "source macro traversal requires represented source syntax");
				e;
			case ENull | EThis | ESuper | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EEnumValue(_) | EIdent(_):
				e;
		}
	}

	static function exprKind(e:HxExpr):String {
		return switch (e) {
			case EBool(_): "Bool";
			case EInt(_): "Int";
			case EFloat(_): "Float";
			case EString(_): "String";
			case EEnumValue(_): "EnumValue";
			case EMacroExpr(_, _): "MacroExpr";
			case EMacroType(_): "MacroType";
			case ELambda(_, _): "Lambda";
			case ESourceGroup(_, _): "SourceGroup";
			case EParenthesized(_, _): "Parenthesized";
			case EPrivateAccess(_, _): "PrivateAccess";
			case ESourceTry(_, _, _): "SourceTry";
			case ESourceIf(_, _, _, _): "SourceIf";
			case ESourceFor(_, _, _, _): "SourceFor";
			case EThrow(_, _): "Throw";
			case ESourceFunction(_, _, _, _): "SourceFunction";
			case ELoweredControl(_, _, _, _): "LoweredControl";
			case ETryCatchRaw(_): "TryCatch";
			case ESwitchRaw(_): "Switch";
			case ESwitch(_, _, _): "Switch";
			case EIdent(_): "Ident";
			case EThis: "This";
			case ESuper: "Super";
			case ENull: "Null";
			case ENew(_, _): "New";
			case EField(_, _): "Field";
			case ENullSafeField(_, _): "NullSafeField";
			case ECall(_, _): "Call";
			case EDiscardThen(_, _): "DiscardThen";
			case EReturn(_): "Return";
			case EVars(_): "Vars";
			case EVariableDeclaration(_, _, _, _, _, _): "VariableDeclaration";
			case EWhile(_, _, _, _, loopKind): "While";
			case EBreak(_): "Break";
			case EContinue(_): "Continue";
			case EUnop(_, _, _): "Unop";
			case EBinop(_, _, _): "Binop";
			case ETernary(_, _, _): "Ternary";
			case EAnon(_, _): "Anon";
			case EArrayDecl(_): "ArrayDecl";
			case EArrayComprehension(_, _, _, _): "ArrayComprehension";
			case EArrayAccess(_, _): "ArrayAccess";
			case ERange(_, _): "Range";
			case ECast(_, _): "Cast";
			case ECheckType(_, _): "CheckType";
			case EUntyped(_): "Untyped";
			case EUnsupported(_): "Unsupported";
		}
	}

	static function buildImportMap(directives:Array<HxModuleDirective>, modulePkg:String):haxe.ds.StringMap<String> {
		final map = new haxe.ds.StringMap<String>();
		if (directives == null)
			return map;

		for (directive in directives) {
			final localName = HxModuleDirective.getImportedLocalName(directive);
			if (localName == null)
				continue;
			final trimmed = HxModuleDirective.getPath(directive);
			if (trimmed.length == 0)
				continue;

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

			if (localName.length == 0)
				continue;
			// Haxe resolves a repeated local import name to the last directive.
			// Overwriting here keeps macro allowlist qualification aligned with the
			// shared typer instead of preserving the first path by accident.
			map.set(localName, full);
		}
		return map;
	}

	static function matchAllowlistedCall(renderedCall:String, allowed:haxe.ds.StringMap<Bool>, allowKeys:Array<String>, importMap:haxe.ds.StringMap<String>,
			modulePkg:String):Null<String> {
		if (renderedCall == null || renderedCall.length == 0)
			return null;
		if (allowed.exists(renderedCall))
			return renderedCall;

		final firstDot = renderedCall.indexOf(".");
		if (firstDot != -1) {
			final head = renderedCall.substr(0, firstDot);
			final rest = renderedCall.substr(firstDot); // includes dot
			if (importMap != null && importMap.exists(head)) {
				final fullHead = importMap.get(head);
				if (fullHead != null && fullHead.length > 0) {
					final qualified = fullHead + rest;
					if (allowed.exists(qualified))
						return qualified;
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
					if (allowed.exists(qualified))
						return qualified;
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
			if (k == null)
				continue;
			if (shortenCall(k) == renderedShort) {
				found = k;
				matches += 1;
				if (matches > 1)
					break;
			}
		}
		if (matches == 1)
			return found;

		return null;
	}

	static function shortenCall(callText:String):String {
		if (callText == null)
			return "";
		final open = callText.indexOf("(");
		final head = open == -1 ? callText : callText.substr(0, open);
		final tail = open == -1 ? "" : callText.substr(open);
		final parts = head.split(".");
		if (parts.length <= 2)
			return callText;
		return parts[parts.length - 2] + "." + parts[parts.length - 1] + tail;
	}

	static function renderCalleePath(e:HxExpr):String {
		return switch (e) {
			case EIdent(name):
				name;
			case EField(obj, field):
				final base = renderCalleePath(obj);
				base.length == 0 ? "" : (base + "." + field);
			case _:
				"";
		}
	}

	static function escapeStringLiteral(s:String):String {
		if (s == null)
			return "";
		// Avoid repeated local rebinding (`out = replace(out, ...)`) because Stage3 brings
		// `hxhx` up through our OCaml backend, and conservative codegen can drop those
		// intermediate assignments.
		return StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(s, "\\", "\\\\"), "\"", "\\\""), "\n",
			"\\n"), "\r", "\\r"), "\t",
			"\\t");
	}

	static function renderSimpleCall(callee:HxExpr, args:Array<HxExpr>):Null<String> {
		// Supported shapes:
		// - TypePath.meth()
		// - TypePath.meth("literal")
		if (callee == null)
			return null;
		final path = renderCalleePath(callee);
		if (path.length == 0)
			return null;

		if (args == null || args.length == 0)
			return path + "()";
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
