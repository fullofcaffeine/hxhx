import hxhx.ExprMacroExpander;
import hxhx.macro.ExprMacroDispatch;
import hxhx.macro.MacroRuntimeSession;

/**
	Production expansion must select a real `macro` declaration by its declaration,
	hand the original argument syntax to the session as one typed request, and
	insert the structured result without reparsing source text. A registered
	exact-text expression keeps the exact-text route even when it is a macro. A
	selected macro whose session has no executor is recorded and continues as an
	ordinary call; it is never silently dropped. This test does not execute a
	macro body.
**/
class M14ExprMacroSelectedDispatchTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function module(path:String, source:String):ResolvedModule {
		final file = path.split(".").join("/") + ".hx";
		return new ResolvedModule(path, file, ParserStage.parse(source, file));
	}

	/** A session that records structured requests and exact-text calls separately. */
	static function session(requests:Array<ExprMacroDispatchRequest>, texts:Array<String>,
			answer:ExprMacroDispatchRequest->ExprMacroDispatchResult):MacroRuntimeSession {
		return {
			run: _ -> throw "string macro run must not be used by selected dispatch",
			runHook: (_, _) -> {},
			runTypeNotFoundHook: (_, _) -> false,
			expandExpr: text -> {
				texts.push(text);
				"[3]";
			},
			expandSelected: request -> {
				requests.push(request);
				answer(request);
			},
			loadProjectMacroPlugin: (_, _) -> throw "unexpected project macro plugin load",
			close: () -> {}
		};
	}

	static function mainLoopIterable(resolved:ResolvedModule):HxExpr {
		final declaration = ResolvedModule.getParsed(resolved).getDecl();
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(declaration)))
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SForIn(_, iterable, _, _):
						return iterable;
					case _:
				}
		throw "fixture main lost its value loop";
	}

	static function main():Void {
		final macros = module("macros.Macros",
			'package macros; class Macros { public static macro function items():haxe.macro.Expr { throw "body must not run during selection"; } }');
		final helpers = module("plain.Helpers", 'package plain; class Helpers { public static function items():Array<Int> return [1, 2]; }');
		final caller = module("Main", 'class Main { static function main():Void { var sum = 0; for (value in macros.Macros.items()) sum += value; } }');
		final ordinary = module("Ordinary",
			'class Ordinary { static function main():Void { var sum = 0; for (value in plain.Helpers.items()) sum += value; } }');
		final inputs = [macros, helpers, caller, ordinary];
		final selection:ExprMacroSelectionContext = {index: TyperIndex.build(inputs), loader: null};

		// A selected declaration receives one structured request and its result replaces the call structurally.
		final requests = new Array<ExprMacroDispatchRequest>();
		final texts = new Array<String>();
		final expanded = ExprMacroExpander.expandResolvedModules(inputs, session(requests, texts, _ -> Expanded(EArrayDecl([EInt(1), EInt(2)]))), [],
			selection);
		require(expanded.expandedCount == 1 && requests.length == 1 && texts.length == 0, "selected macro call was not dispatched exactly once");
		final request = requests[0];
		require(request.getDeclaration().getOwner().getCanonicalName() == "macros.Macros"
			&& request.getDeclaration().getSignature().getName() == "items",
			"request lost its declaration identity: " + request.describe());
		require(request.getArguments().length == 0 && request.getFilePath() == "Main.hx", "request lost its call facts");
		require(expanded.modules[3] == ordinary, "ordinary static call was rewritten");
		require(expanded.unexecuted.length == 0 && expanded.lexicalGaps.length == 0, "complete fixture reported gaps or unexecuted calls");
		switch mainLoopIterable(expanded.modules[2]) {
			case EArrayDecl([EInt(1), EInt(2)]):
			case other:
				throw "structured result was not inserted: " + Std.string(other);
		}
		require(mainLoopIterable(caller).match(ECall(_, _)), "input module was mutated");

		// A selected declaration without an executor is recorded and continues as an ordinary call.
		final unexecuted = ExprMacroExpander.expandResolvedModules(inputs, session([], [], _ -> Unavailable("no executor registered")), [], selection);
		require(unexecuted.expandedCount == 0 && unexecuted.modules[2] == caller, "missing executor changed the call instead of recording it");
		require(unexecuted.unexecuted.length == 1
			&& unexecuted.unexecuted[0].filePath == "Main.hx"
			&& unexecuted.unexecuted[0].declaration == "macros.Macros.items"
			&& unexecuted.unexecuted[0].reason == "no executor registered",
			"missing executor was not recorded with its call facts");

		// A registered exact-text expression keeps the exact-text route even though its callee is a macro.
		final registeredTexts = new Array<String>();
		final registered = ExprMacroExpander.expandResolvedModules(inputs,
			session([], registeredTexts, _ -> throw "must not dispatch a registered expression"), ["macros.Macros.items()"], selection);
		require(registered.expandedCount == 1 && registeredTexts.length == 1 && registeredTexts[0] == "macros.Macros.items()",
			"registered exact-text expression lost precedence over selection");
		switch mainLoopIterable(registered.modules[2]) {
			case EArrayDecl([EInt(3)]):
			case other:
				throw "exact-text result was not inserted: " + Std.string(other);
		}

		// Without a selection context the previous string route is unchanged: nothing is selected or dispatched.
		final untouched = ExprMacroExpander.expandResolvedModules(inputs, session([], [], _ -> throw "must not dispatch"), []);
		require(untouched.expandedCount == 0 && untouched.modules[2] == caller, "string route changed without a selection context");

		Sys.println("M14_EXPR_MACRO_SELECTED_DISPATCH:PASS");
	}
}
