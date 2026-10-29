package hxhx;

import hxhx.ExprMacroExpander.ExprMacroUnexecutedCall;
import hxhx.ExprMacroLexicalScope.ExprMacroLexicalGap;
import hxhx.macro.MacroRuntimeSession;

/** Everything the driver needs after the pre-typing expression macro pass. */
typedef Stage3ExprMacroPassResult = {
	/** Modules to type, in request order; lazily discovered modules follow the roots. */
	final modules:Array<ResolvedModule>;

	/**
		Modules the loader first loaded while calls were being selected, in discovery
		order; they are also the tail of `modules`. The loader already counts them as
		resolved, so it never yields them again: a driver that types only its roots
		(the no-emit lane) must add these itself, exactly as it would add a module the
		loader discovers during typing.
	**/
	final discovered:Array<ResolvedModule>;

	/** Header index bound to `modules`; rebuilt when a module was rewritten. */
	final index:TyperIndex;

	/** Request loader bound to `index`, with resolved modules already marked. */
	final loader:ModuleLoader;

	final expandedCount:Int;

	/** Selected macro calls no executor could run; they continue through ordinary typing. */
	final unexecuted:Array<ExprMacroUnexecutedCall>;

	/** Call sites whose visible names the walker could not prove; no selection happened there. */
	final lexicalGaps:Array<ExprMacroLexicalGap>;
}

/** The header index and loader a request types with, before any expansion. */
typedef Stage3ExprMacroPassSetup = {
	final index:TyperIndex;
	final loader:ModuleLoader;
}

/**
	Run expression macro expansion with the request's own header index and loader.

	Why
	- Selecting a call by its `macro` declaration needs the same index and lazy
	  loader body typing uses, and the loader must already know the resolved
	  modules; otherwise a lookup re-prepares a root module and the index rejects
	  the duplicate registration.
	- Selection can load modules on demand. Those modules may contain macro
	  calls too, so the walk repeats over drained modules until nothing new appears.
	- A rewrite replaces parsed source classes. The index binds declarations to
	  those classes, so after any rewrite the index and loader are rebuilt once
	  over the final module list; the rebuilt loader keeps the previous loader's
	  record of missing-type hooks already attempted.

	What
	- Returns the modules to type, the index and loader to type them with, and
	  the counts and records the driver prints.
**/
class Stage3ExprMacroPass {
	/**
		Build the request's header index and loader and mark `resolved` as already known.

		This is ordinary request setup, not macro expansion: a driver calls it outside
		its expansion error handling so an index failure keeps its own diagnostic.
	**/
	public static function prepare(resolved:Array<ResolvedModule>, openLoader:TyperIndex->ModuleLoader):Stage3ExprMacroPassSetup {
		final index = TyperIndex.buildHeaders(resolved);
		final loader = openLoader(index);
		loader.markResolvedAlready(resolved);
		return {index: index, loader: loader};
	}

	/** `prepare` followed by `expand`. */
	public static function run(resolved:Array<ResolvedModule>, session:Null<MacroRuntimeSession>, allowlist:Array<String>,
			openLoader:TyperIndex->ModuleLoader):Stage3ExprMacroPassResult {
		return expand(resolved, prepare(resolved, openLoader), session, allowlist, openLoader);
	}

	/** Expand over a `prepare`d index and loader; with no session the setup is returned unchanged. */
	public static function expand(resolved:Array<ResolvedModule>, setup:Stage3ExprMacroPassSetup, session:Null<MacroRuntimeSession>, allowlist:Array<String>,
			openLoader:TyperIndex->ModuleLoader):Stage3ExprMacroPassResult {
		var index = setup.index;
		var loader = setup.loader;
		final modules = resolved.copy();
		final unexecuted = new Array<ExprMacroUnexecutedCall>();
		final lexicalGaps = new Array<ExprMacroLexicalGap>();
		var expandedCount = 0;
		if (session == null)
			return {
				modules: modules,
				discovered: [],
				index: index,
				loader: loader,
				expandedCount: 0,
				unexecuted: unexecuted,
				lexicalGaps: lexicalGaps
			};

		var work = modules.copy();
		var offset = 0;
		while (work.length > 0) {
			final pass = ExprMacroExpander.expandResolvedModules(work, session, allowlist, {index: index, loader: loader});
			for (position in 0...pass.modules.length)
				modules[offset + position] = pass.modules[position];
			expandedCount += pass.expandedCount;
			for (entry in pass.unexecuted)
				unexecuted.push(entry);
			for (gap in pass.lexicalGaps)
				lexicalGaps.push(gap);
			offset = modules.length;
			work = loader.drainNewModules();
			for (module in work)
				modules.push(module);
		}

		if (expandedCount > 0) {
			index = TyperIndex.buildHeaders(modules);
			final rebuilt = openLoader(index);
			rebuilt.inheritTypeNotFoundAttempts(loader);
			rebuilt.markResolvedAlready(modules);
			loader = rebuilt;
		}
		return {
			modules: modules,
			discovered: modules.slice(resolved.length),
			index: index,
			loader: loader,
			expandedCount: expandedCount,
			unexecuted: unexecuted,
			lexicalGaps: lexicalGaps
		};
	}
}
