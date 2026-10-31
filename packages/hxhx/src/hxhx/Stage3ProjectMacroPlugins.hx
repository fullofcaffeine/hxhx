package hxhx;

import hxhx.Stage3ExprMacroPass.Stage3ExprMacroPassResult;
import hxhx.Stage3ExprMacroPass.Stage3ExprMacroPassSetup;
import hxhx.macro.ExprMacroDispatch;
import hxhx.macro.MacroRuntimeSession;
import hxhx.macro.ProjectMacroPluginCache;

/** What one request contributes to its project-macro plugin; the declarations come from the call sites. */
typedef Stage3ProjectMacroPluginInputs = {
	final macroClassPaths:Array<String>;
	final classPaths:Array<String>;
	final defines:Array<String>;
	final cwd:String;

	/** `--hxhx-macro-cache <dir>`, or empty for the default cache root. */
	final cacheRoot:String;
}

/**
	Runs the pre-typing expression macro pass so that selected project macros execute.

	Why
	- A call such as `Identity.preserve(function ... )` is selected by its `macro` declaration
	  before typing (`ExprMacroExpander`). Running it needs a native plugin that contains the
	  project's macro classes. Which classes, and so which plugin, is known only after the pass has
	  found the calls.

	What
	- In the in-process macro mode of a one-shot compile, the pass runs twice when project macros
	  are called:
	  1. A recording pass sends every call through ordinary expansion except selected project
		 macros, whose supported declarations it records and leaves in place.
	  2. `ProjectMacroPluginCache.ensure` reuses or builds the plugin for the recorded
		 declarations, the session loads it, and a second pass over the first pass's output runs
		 the macros.
	  With no project macro call, only the first pass runs, at the old cost.
	- Every reason a selected call cannot run becomes that call's `Unavailable` reason, and the
	  driver reports it with the existing `expr_macro_unexecuted[...]` line: an unsupported
	  declaration shape, a plugin that cannot be built (including a missing `dune` or `ocamlopt`),
	  the external macro host, a compilation-server request, or a macro compilation itself.
	- Prints `project_macro_plugin=reused` or `project_macro_plugin=built` (with
	  `project_macro_plugin_reason=` for the rebuild cause) and `project_macro_plugin_receipt=`.

	Gotchas
	- The compilation server does not load plugins in-process: OCaml cannot load the same plugin
	  file twice into one process. The approved plan gives the server one external macro host per
	  plugin digest; until then server requests report the calls as unexecuted.
	- Macro calls inside macro classes (in a plugin compilation) are not executed.
**/
class Stage3ProjectMacroPlugins {
	/** The `Unavailable` reason of a recorded call in the recording pass; never reported. */
	public static inline final RECORDED_REASON:String = "recorded for the project macro plugin";

	public static function expand(resolved:Array<ResolvedModule>, setup:Stage3ExprMacroPassSetup, session:Null<MacroRuntimeSession>, allowlist:Array<String>,
			openLoader:TyperIndex->ModuleLoader, unavailableReason:Null<String>, inputs:Stage3ProjectMacroPluginInputs,
			output:CompilationRequestOutput):Stage3ExprMacroPassResult {
		if (session == null)
			return Stage3ExprMacroPass.expand(resolved, setup, session, allowlist, openLoader);
		final dispatch = new ProjectMacroCallDispatch(session, unavailableReason);
		final first = Stage3ExprMacroPass.expand(resolved, setup, dispatch.session(), allowlist, openLoader);
		if (dispatch.recorded.length == 0)
			return first;

		dispatch.finishRecording(provide(dispatch.recorded, session, inputs, output));
		final second = Stage3ExprMacroPass.expand(first.modules, {index: first.index, loader: first.loader}, dispatch.session(), allowlist, openLoader);
		return {
			modules: second.modules,
			discovered: first.discovered.concat(second.discovered),
			index: second.index,
			loader: second.loader,
			expandedCount: first.expandedCount + second.expandedCount,
			unexecuted: second.unexecuted,
			lexicalGaps: second.lexicalGaps
		};
	}

	/** Why a request cannot build and load project macro plugins, or `null` when it can. */
	public static function unavailableReason(macroRuntimeMode:String, isServerRequest:Bool, isMacroCompilation:Bool):Null<String> {
		if (macroRuntimeMode != hxhx.macro.MacroRuntimeMode.INPROC)
			return "the external macro host has no structured dispatch method for project macro declarations yet";
		if (isServerRequest)
			return "the compilation server does not load project macro plugins yet; compile without --connect";
		if (isMacroCompilation)
			return "macro calls inside a macro compilation are not executed yet";
		return null;
	}

	/** Reuse or build the plugin and load it; returns `null` on success or the reason it failed. */
	static function provide(declarations:Array<String>, session:MacroRuntimeSession, inputs:Stage3ProjectMacroPluginInputs,
			output:CompilationRequestOutput):Null<String> {
		final sorted = declarations.copy();
		sorted.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		try {
			final result = ProjectMacroPluginCache.ensure(request(sorted, inputs));
			switch (result.outcome) {
				case Reused:
					output.stdoutLine("project_macro_plugin=reused");
				case Built(reason):
					output.stdoutLine("project_macro_plugin=built");
					output.stdoutLine("project_macro_plugin_reason=" + StringTools.replace(reason, "\n", " "));
			}
			output.stdoutLine("project_macro_plugin_receipt=" + result.receiptPath);
			final loaded = session.loadProjectMacroPlugin(result.activation.artifactPath, result.activation.pluginId);
			if (loaded.join(",") != sorted.join(","))
				return "the project macro plugin registered `" + loaded.join(",") + "` instead of `" + sorted.join(",") + "`";
			return null;
		} catch (error:String) {
			return error;
		} catch (error:haxe.Exception) {
			return error.message;
		}
	}

	static function request(declarations:Array<String>, inputs:Stage3ProjectMacroPluginInputs):ProjectMacroPluginRequest {
		final repoRoot = Stage3PathSupport.inferRepoRootForScripts();
		if (repoRoot.length == 0)
			throw "cannot locate the hxhx sources that project macro plugins are built with (set HXHX_REPO_ROOT)";
		final cacheRoot = inputs.cacheRoot.length > 0 ? inputs.cacheRoot : ProjectMacroPluginCache.defaultRoot();
		if (cacheRoot == null)
			throw "no cache directory for project macro plugins (set HOME or pass --hxhx-macro-cache <dir>)";
		return {
			declarations: declarations,
			macroClassPaths: inputs.macroClassPaths,
			classPaths: inputs.classPaths,
			defines: inputs.defines,
			cwd: inputs.cwd,
			supportClassPath: haxe.io.Path.join([repoRoot, "packages", "hxhx-core", "src"]),
			runtimeSourceDirectories: EmitterStage.stage3RuntimeSourceDirectories(),
			cacheRoot: cacheRoot,
			compilerIdentity: hxhxmacrohost.NativeMacroModuleHostIdentity.executableDigest(),
			ocamlVersion: hxhxmacrohost.NativeMacroModuleHostIdentity.ocamlVersion(),
			compiler: {
				program: Sys.programPath(),
				leadingArgs: ["--hxhx-stage3"]
			},
			dune: "dune",
			ocamlopt: "ocamlopt",
			artifactKind: hxhx.macro.InProcMacroRuntime.pluginArtifactKind(),
			lockTimeoutSeconds: 900.0
		};
	}
}

/**
	The session the expression macro pass sees while project macros are recorded, then dispatched.

	While recording, a selected call with a supported declaration is recorded and left in place;
	every other request goes to the real session. After `finishRecording`, a declaration with an
	unsupported shape, or every recorded declaration when the plugin could not be provided, gets
	its reason; the rest reach the real session, which runs them through the loaded plugin.
**/
private class ProjectMacroCallDispatch {
	public final recorded = new Array<String>();

	final target:MacroRuntimeSession;
	final unavailableReason:Null<String>;
	var recording = true;
	var failure:Null<String> = null;

	public function new(target:MacroRuntimeSession, unavailableReason:Null<String>) {
		this.target = target;
		this.unavailableReason = unavailableReason;
	}

	public function finishRecording(failure:Null<String>):Void {
		recording = false;
		this.failure = failure;
	}

	public function session():MacroRuntimeSession {
		return {
			run: target.run,
			runHook: target.runHook,
			runTypeNotFoundHook: target.runTypeNotFoundHook,
			expandExpr: target.expandExpr,
			expandSelected: expandSelected,
			loadProjectMacroPlugin: target.loadProjectMacroPlugin,
			close: target.close
		};
	}

	function expandSelected(request:ExprMacroDispatchRequest):ExprMacroDispatchResult {
		final declaration = request.getDeclaration();
		final key = declaration.getOwner().getCanonicalName() + "." + declaration.getSignature().getName();
		final source = declaration.getSourceDeclaration();
		final unsupported = source == null ? "project macro declaration `" + key +
			"` has no source declaration" : backend.ocaml.Stage3OcamlMacroPluginEntry.unsupportedDeclarationShape(key, source);
		if (unsupported != null)
			return Unavailable(unsupported);
		if (unavailableReason != null)
			return Unavailable(unavailableReason);
		if (recording) {
			if (recorded.indexOf(key) < 0)
				recorded.push(key);
			return Unavailable(Stage3ProjectMacroPlugins.RECORDED_REASON);
		}
		if (failure != null && recorded.indexOf(key) >= 0)
			return Unavailable("the project macro plugin is unavailable: " + failure);
		return target.expandSelected(request);
	}
}
