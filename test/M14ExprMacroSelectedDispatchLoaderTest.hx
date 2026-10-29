import hxhx.Stage3ExprMacroPass;
import hxhx.macro.ExprMacroDispatch;
import hxhx.macro.MacroRuntimeSession;

/**
	Run the production expression macro pass over on-disk modules with a real
	`ModuleLoader`, exactly as `Stage3Compiler` does: header index first, resolved
	modules marked before any lookup, lazily discovered modules walked too, and
	the index and loader rebuilt after a rewrite. Fixture:
	`test/fixtures/expr_macro_selected_dispatch`.
**/
class M14ExprMacroSelectedDispatchLoaderTest {
	static final root = "test/fixtures/expr_macro_selected_dispatch";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function module(path:String):ResolvedModule {
		final file = root + "/" + path.split(".").join("/") + ".hx";
		return new ResolvedModule(path, file, ParserStage.parse(sys.io.File.getContent(file), file));
	}

	static function session(requests:Array<ExprMacroDispatchRequest>, texts:Array<String>,
			answer:ExprMacroDispatchRequest->ExprMacroDispatchResult):MacroRuntimeSession {
		return {
			run: _ -> throw "string macro run must not be used here",
			runHook: (_, _) -> {},
			runTypeNotFoundHook: (_, _) -> false,
			expandExpr: text -> {
				texts.push(text);
				"[9]";
			},
			expandSelected: request -> {
				requests.push(request);
				answer(request);
			},
			close: () -> {}
		};
	}

	/** Mirror the driver: a loader over the fixture class path whose missing-type hook counts its calls. */
	static function pass(roots:Array<ResolvedModule>, macroSession:MacroRuntimeSession, allowlist:Array<String>,
			missing:Array<String>):Stage3ExprMacroPassResult {
		return Stage3ExprMacroPass.run(roots, macroSession, allowlist, index -> new ModuleLoader([root], new haxe.ds.StringMap<String>(), index, path -> {
			missing.push(path);
			false;
		}));
	}

	static function firstBodyCall(resolved:ResolvedModule, functionName:String):HxExpr {
		final declaration = ResolvedModule.getParsed(resolved).getDecl();
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(declaration))) {
			if (HxFunctionDecl.getName(functionDecl) != functionName)
				continue;
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SReturn(value, _):
						return value;
					case SForIn(_, iterable, _, _):
						return iterable;
					case _:
				}
		}
		throw "fixture lost function " + functionName;
	}

	static function describeAll(requests:Array<ExprMacroDispatchRequest>):Array<String> {
		final out = requests.map(request -> request.describe());
		out.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return out;
	}

	static function main():Void {
		// Selection, alias and bare-import calls, a shadowed package root, a registered exact-text call,
		// a lazily discovered module that itself contains a macro call, and a missing type, in one pass.
		final direct = module("callers.Direct");
		final shadowed = module("callers.Shadowed");
		final ordinary = module("callers.Ordinary");
		final roots = [
			module("macros.Macros"),
			module("plain.Helpers"),
			direct,
			module("callers.Aliased"),
			shadowed,
			ordinary,
			module("callers.Lazy"),
			module("callers.Missing")
		];
		final requests = new Array<ExprMacroDispatchRequest>();
		final texts = new Array<String>();
		final missing = new Array<String>();
		final result = pass(roots, session(requests, texts, _ -> Expanded(EArrayDecl([EInt(1), EInt(2)]))), ["plain.Helpers.items()"], missing);
		// Direct, two Aliased calls, the lazily discovered module's own call, Lazy's call, and Macros' own private call.
		require(describeAll(requests)
			.join(";") == "lazy.LazyMacros.lazyItems;macros.Macros.hidden;macros.Macros.items;macros.Macros.items;macros.Macros.items;macros.Macros.items",
			"selected declarations differ: "
			+ describeAll(requests).join(";"));
		require(result.expandedCount == 7
			&& texts.join(";") == "plain.Helpers.items()", "exact-text route and selection did not both expand");
		require(result.unexecuted.length == 0 && result.lexicalGaps.length == 0, "complete fixture reported gaps or unexecuted calls");
		require(result.modules.length == roots.length + 1
			&& ResolvedModule.getModulePath(result.modules[roots.length]) == "lazy.LazyMacros",
			"lazily discovered module was not appended after the roots");
		require(result.discovered.length == 1 && result.discovered[0] == result.modules[roots.length],
			"pass did not report the module it discovered (rewritten form) to the driver");
		require(result.modules[4] == shadowed, "value-shadowed package root was selected");
		switch firstBodyCall(result.modules[2], "main") {
			case EArrayDecl([EInt(1), EInt(2)]):
			case other:
				throw "direct call was not replaced structurally: " + Std.string(other);
		}
		switch firstBodyCall(result.modules[roots.length], "viaLazy") {
			case EArrayDecl([EInt(1), EInt(2)]):
			case other:
				throw "macro call inside the lazily discovered module was not expanded: " + Std.string(other);
		}
		switch firstBodyCall(result.modules[5], "run") {
			case EField(EArrayDecl([EInt(9)]), "length"):
			case other:
				throw "registered exact-text call was not served by its route: " + Std.string(other);
		}
		final rebound = result.index.getForSourceClass(HxModuleDecl.getMainClass(ResolvedModule.getParsed(result.modules[2]).getDecl()));
		require(rebound != null && rebound.getFullName() == "callers.Direct", "rebuilt index does not bind the rewritten source class");
		// The fixture loader has no standard library class path, so std names also reach the hook; only the
		// absent project type must be asked exactly once across the pass and the rebuilt loader.
		function askedForAbsent():Int
			return missing.filter(path -> path == "absent.Missing").length;
		require(askedForAbsent() == 1, "missing-type hook calls during selection: " + missing.join(","));
		final missingModule = result.modules[7];
		final directives = HxModuleDecl.getDirectives(ResolvedModule.getParsed(missingModule).getDecl());
		final retry = new TyperContext(result.index, ResolvedModule.getFilePath(missingModule), "callers.Missing", "callers", directives, "callers.Missing",
			result.loader, TyperStage.resolveModuleDirectives(directives, "callers", "callers.Missing", result.index, result.loader));
		require(retry.resolveType("absent.Missing") == null && askedForAbsent() == 1, "rebuilt loader asked the missing-type hook again");

		// A call inside an unprovable switch scope is not selected; the gap is reported instead. The only
		// request is the macro module's own legal private call, never the call inside the guarded case.
		final gappedRequests = new Array<ExprMacroDispatchRequest>();
		final gapped = module("callers.Gapped");
		final gapResult = pass([module("macros.Macros"), gapped], session(gappedRequests, [], request -> {
			if (request.describe() != "macros.Macros.hidden")
				throw "must not dispatch in a gap: " + request.describe();
			Expanded(EInt(0));
		}), [], []);
		require(gapResult.lexicalGaps.length == 1 && gappedRequests.length == 1 && gapResult.modules[1] == gapped && gapResult.expandedCount == 1,
			"gap scope changed selection or rewrote the module");

		// Overloaded macro declarations fail explicitly with the calling file and callee.
		var diagnostic = "";
		try
			pass([module("macros.Overloaded"), module("callers.Ambiguous")], session([], [], _ -> throw "must not dispatch"), [], [])
		catch (error:String)
			diagnostic = error;
		require(diagnostic.indexOf("callers/Ambiguous.hx") >= 0
			&& diagnostic.indexOf("macros.Overloaded.pick") >= 0
			&& diagnostic.indexOf("one exact declaration") >= 0,
			"overload rejection lacks file or callee: "
			+ diagnostic);

		// A private static macro is selectable from its own class; without an executor it is recorded, not rewritten.
		final ownRequests = new Array<ExprMacroDispatchRequest>();
		final macrosModule = module("macros.Macros");
		final own = pass([macrosModule], session(ownRequests, [], _ -> Unavailable("no executor")), [], []);
		require(ownRequests.length == 1
			&& ownRequests[0].describe() == "macros.Macros.hidden", "own-class private macro was not selected");
		require(own.expandedCount == 0
			&& own.modules[0] == macrosModule
			&& own.unexecuted.length == 1
			&& own.unexecuted[0].reason == "no executor",
			"unexecuted private macro was rewritten or not recorded");

		Sys.println("M14_EXPR_MACRO_SELECTED_DISPATCH_LOADER:PASS");
	}
}
