import hxhx.ExprMacroExpander;
import hxhx.macro.ExprMacroDispatch;
import hxhx.macro.MacroRuntimeSession;

/**
	Production expansion must select a real `macro` declaration by its declaration,
	hand the original argument syntax to the session as one typed request, and
	insert the structured result without reparsing source text. A selected macro
	whose session has no executor is a compile error at the call site; it must
	never continue into ordinary typing as a call that returns `haxe.macro.Expr`.
	This test does not execute a macro body.
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

	/** A session that records structured requests; the string route must stay unused here. */
	static function session(requests:Array<ExprMacroDispatchRequest>, answer:ExprMacroDispatchRequest->ExprMacroDispatchResult):MacroRuntimeSession {
		return {
			run: _ -> throw "string macro run must not be used by selected dispatch",
			runHook: (_, _) -> {},
			runTypeNotFoundHook: (_, _) -> false,
			expandExpr: _ -> throw "string expansion must not be used by selected dispatch",
			expandSelected: request -> {
				requests.push(request);
				answer(request);
			},
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
		final expanded = ExprMacroExpander.expandResolvedModules(inputs, session(requests, _ -> Expanded(EArrayDecl([EInt(1), EInt(2)]))), [], selection);
		require(expanded.expandedCount == 1 && requests.length == 1, "selected macro call was not dispatched exactly once");
		final request = requests[0];
		require(request.getDeclaration().getOwner().getCanonicalName() == "macros.Macros"
			&& request.getDeclaration().getSignature().getName() == "items",
			"request lost its declaration identity: " + request.describe());
		require(request.getArguments().length == 0 && request.getFilePath() == "Main.hx", "request lost its call facts");
		require(expanded.modules[3] == ordinary, "ordinary static call was rewritten");
		switch mainLoopIterable(expanded.modules[2]) {
			case EArrayDecl([EInt(1), EInt(2)]):
			case other:
				throw "structured result was not inserted: " + Std.string(other);
		}
		require(mainLoopIterable(caller).match(ECall(_, _)), "input module was mutated");

		// A selected declaration without an executor is an explicit call-site error, never ordinary typing.
		var diagnostic = "";
		try
			ExprMacroExpander.expandResolvedModules(inputs, session([], _ -> Unavailable("no executor registered")), [], selection)
		catch (error:String)
			diagnostic = error;
		require(diagnostic.indexOf("Main.hx") >= 0
			&& diagnostic.indexOf("macros.Macros.items") >= 0
			&& diagnostic.indexOf("no executor registered") >= 0,
			"missing executor did not fail explicitly at the call site: " + diagnostic);

		// Without a selection context the previous string route is unchanged: nothing is selected or dispatched.
		final untouched = ExprMacroExpander.expandResolvedModules(inputs, session([], _ -> throw "must not dispatch"), []);
		require(untouched.expandedCount == 0 && untouched.modules[2] == caller, "string route changed without a selection context");

		Sys.println("M14_EXPR_MACRO_SELECTED_DISPATCH:PASS");
	}
}
