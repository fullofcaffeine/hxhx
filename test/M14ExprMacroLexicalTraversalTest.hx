import hxhx.ExprMacroExpander;
import hxhx.ExprMacroCallRewrite;
import hxhx.ExprMacroDeclarationSelector.capture;
import hxhx.macro.MacroRuntimeSession;

/**
	Full parsed-source visibility and call order; no project macro handler executes here.
	Some ordinary shadowing controls are ill-typed. Selection must leave their
	argument and receiver diagnostics to ordinary typing instead of choosing a macro.
**/
class M14ExprMacroLexicalTraversalTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function module(name:String, source:String):ResolvedModule
		return new ResolvedModule(name, name + ".hx", ParserStage.parse(source, name + ".hx"));

	static function main():Void {
		final provider = module("Provider",
			'class Provider { public static macro function keep(value:haxe.macro.Expr):haxe.macro.Expr { return macro keep("macro-body"); } }');
		final caller = module("Caller", [
			'import Provider.keep; import Provider as Chosen;',
			'class Caller {',
			'  static var field = keep("field");',
			'  var instance = keep("instance-field");',
			'  static function make(value:String):String->String return value -> value;',
			'  static function parameter(keep:String->String):Void { keep("method-parameter"); }',
			'  static function defaulted(keep:String->String, value:String = keep("method-default")):String return value;',
			'  static function main():Void {',
			'    keep("before");',
			'    { var keep = make(keep("initializer")); keep("local"); }',
			'    keep("after");',
			'    if (true) { var keep = make("branch"); keep("branch-local"); }',
			'    keep("after-if");',
			'    for (keep in [make("loop")]) keep("loop-local");',
			'    keep("after-loop");',
			'    for (key => keep in [make("key-loop")]) keep("key-loop-local");',
			'    var comprehension = [for (keep in [make("comprehension")]) keep("comprehension-local")];',
			'    keep("after-comprehension");',
			'    while (false) { var keep = make("while"); keep("while-local"); }',
			'    keep("after-while");',
			'    do { keep("do-body"); } while (keep("do-condition") == "");',
			'    try { keep("try"); } catch(keep:haxe.Exception) { keep("catch-local"); }',
			'    keep("after-catch");',
			'    var caught = try keep("expression-try") catch(keep:haxe.Exception) keep("expression-catch-local");',
			'    keep("after-expression-catch");',
			'    switch (make("switch")) { case keep: keep("switch-local"); }',
			'    keep("after-switch");',
			'    var fn = function(keep:String->String, value:String = keep("function-default")):String { keep("function-parameter"); return value; };',
			'    var before = () -> keep("closure-before");',
			'    { var keep = make("closure"); var after = () -> keep("closure-after"); }',
			'    { var Chosen = {keep: make("chosen")}; Chosen.keep("type-root-local"); }',
			'    { var f = function keep(value:Int):Int return value == 0 ? 0 : keep(value - 1); keep("named-value-local"); }',
			'    keep("after-named-value");',
			'    { var f = function keep(value:String = keep("named-default-local")):String return value; }',
			'    { function keep(value:Int):Int return value == 0 ? 0 : keep(value - 1); keep("named-declaration-local"); }',
			'    keep("after-named-declaration");',
			'    normal(Provider.keep("first"), Provider.keep("second"));',
			'    receiver(Provider.keep("receiver-argument")).call(Provider.keep("last-argument"));',
			'    keep(Provider.keep("unvisited-inner"));',
			'    var quote = macro Provider.keep("quoted");',
			'  }',
			'}',
			'class Extra { static var field = keep("secondary-field"); }'
		].join("\n"));
		final selected = new Array<String>();
		final ordinary = new Array<String>();
		final visited = new Array<String>();
		final unchanged = ExprMacroExpander.rewriteResolvedModules([provider, caller], (call, context, scope) -> {
			final label = switch call {
				case ECall(_, [EString(value)]): value;
				case _: "";
			};
			if (label.length > 0)
				visited.push(label);
			final selection = capture(call, context, scope);
			if (selection == null) {
				if (label.length > 0)
					ordinary.push(label);
				return Recurse(value -> value);
			}
			selected.push(label.length == 0 ? "outer" : label);
			if (label == "secondary-field")
				require(context.getClassFullName() == "Caller.Extra", "secondary source class used the primary class context");
			return Consume(call);
		});
		final expected = [
			"field",
			"instance-field",
			"method-default",
			"before",
			"initializer",
			"after",
			"after-if",
			"after-loop",
			"after-comprehension",
			"after-while",
			"do-body",
			"do-condition",
			"try",
			"after-catch",
			"expression-try",
			"after-expression-catch",
			"after-switch",
			"function-default",
			"closure-before",
			"after-named-value",
			"after-named-declaration",
			"first",
			"second",
			"receiver-argument",
			"last-argument",
			"outer",
			"secondary-field"
		];
		require(selected.join(";") == expected.join(";"), "wrong source selections: " + selected.join(";"));
		for (label in [
			"method-parameter",
			"local",
			"branch-local",
			"loop-local",
			"key-loop-local",
			"comprehension-local",
			"while-local",
			"expression-catch-local",
			"type-root-local",
			"catch-local",
			"function-parameter",
			"closure-after",
			"named-value-local",
			"named-default-local",
			"switch-local",
			"named-declaration-local"
		])
			require(ordinary.indexOf(label) >= 0, "value binding was not kept ordinary: " + label);
		for (label in ["unvisited-inner", "quoted", "macro-body"])
			require(visited.indexOf(label) < 0, "syntax-only argument or compilation domain was visited: " + label);
		require(unchanged.lexicalGaps.length == 0, "complete fixture contains unproven lexical syntax");
		require(unchanged.modules[0] == provider && unchanged.modules[1] == caller, "consuming unchanged source lost module identity");
		final rebuiltSource = module("Rebuilt",
			'typedef Alias = { final name:String; } @:keep class Rebuilt<T> { static var field = Provider.keep("replace"); static function run():Void { Provider.keep("replace-body"); } }');
		final rebuilt = ExprMacroExpander.rewriteResolvedModules([provider, rebuiltSource], (call, context, scope) -> {
			return capture(call, context, scope) == null ? Recurse(value -> value) : Consume(EString("replaced"));
		}).modules[1];
		final originalDecl = ResolvedModule.getParsed(rebuiltSource).getDecl();
		final rebuiltDecl = ResolvedModule.getParsed(rebuilt).getDecl();
		final originalClass = HxModuleDecl.getMainClass(originalDecl);
		final rebuiltClass = HxModuleDecl.getMainClass(rebuiltDecl);
		require(rebuilt != rebuiltSource
			&& HxClassDecl.getTypeParameters(rebuiltClass).length == 1, "replacement lost its class type parameters");
		require(HxModuleDecl.getTypedefs(rebuiltDecl)[0] == HxModuleDecl.getTypedefs(originalDecl)[0], "replacement lost typedef syntax");
		require(HxClassDecl.getMetadata(rebuiltClass).join(";") == HxClassDecl.getMetadata(originalClass).join(";"), "replacement lost class metadata");
		final originalRange = HxClassDecl.getSourceRange(originalClass);
		final rebuiltRange = HxClassDecl.getSourceRange(rebuiltClass);
		require(originalRange != null
			&& rebuiltRange != null
			&& originalRange.start == rebuiltRange.start
			&& originalRange.end == rebuiltRange.end,
			"replacement lost authored class source range");

		final nominal = module("T", 'class T { public static macro function keep(value:haxe.macro.Expr):haxe.macro.Expr return value; }');
		final genericQualifier = module("GenericQualifier", 'class GenericQualifier<T> { public function run():String return T.keep("generic-qualifier"); }');
		final genericValue = module("GenericValue",
			'import Provider.keep as T; class GenericValue<T> { public function run():String return T("generic-value"); }');
		final genericCalls = new Array<String>();
		final generics = ExprMacroExpander.rewriteResolvedModules([provider, nominal, genericQualifier, genericValue], (call, context, scope) -> {
			final selected = capture(call, context, scope);
			if (selected == null)
				return Recurse(value -> value);
			genericCalls.push(selected.getDeclaration().getOwner().getCanonicalName());
			return Consume(call);
		});
		require(generics.lexicalGaps.length == 0 && genericCalls.join(";") == "T;Provider", "generic scope changed upstream declaration precedence");

		final unsupported = module("Unsupported", 'class Unsupported { static function main():Void { switch (1) { case value if(true): normal(); } } }');
		final incomplete = ExprMacroExpander.rewriteResolvedModules([unsupported], (_, _, _) -> Recurse(value -> value));
		require(incomplete.lexicalGaps.length == 1 && incomplete.modules[0] == unsupported, "unmodeled syntax lost explicit incomplete-scope evidence");
		final opaque = module("Opaque", 'class Opaque { static function main():Void { var value = switch (1) { case 1: Provider.keep("hidden"); }; } }');
		var opaqueCalls = 0;
		final opaqueResult = ExprMacroExpander.rewriteResolvedModules([opaque], (_, _, _) -> {
			opaqueCalls++;
			return Recurse(value -> value);
		});
		require(opaqueCalls == 0 && opaqueResult.lexicalGaps.length == 1 && opaqueResult.modules[0] == opaque,
			"opaque syntax without visited calls masqueraded as complete lexical coverage");
		var diagnostic = "";
		try
			ExprMacroExpander.rewriteResolvedModules([unsupported], (call, context, scope) -> {
				capture(call, context, scope);
				return Recurse(value -> value);
			})
		catch (error:String)
			diagnostic = error;
		require(diagnostic == "source macro traversal cannot prove this switch pattern scope",
			"unmodeled bindings did not stop declaration selection: " + diagnostic);

		final calls = new Array<String>();
		final session:MacroRuntimeSession = {
			run: _ -> throw "unexpected run",
			runHook: (_, _) -> throw "unexpected hook",
			runTypeNotFoundHook: (_, _) -> throw "unexpected type hook",
			expandExpr: expression -> {
				calls.push(expression);
				return expression == "Second.expand()" ? '"second"' : '"first"';
			},
			close: () -> {}
		};
		final legacy = module("Legacy",
			'class Legacy { static function main():Void { switch (1) { case 1: normal(); } var opaque = switch (1) { case 1: normal(); }; normal(First.expand(Second.expand())); } }');
		final result = ExprMacroExpander.expandResolvedModules([legacy], session, ["Second.expand()", 'First.expand("second")']);
		require(calls.join(";") == 'Second.expand();First.expand("second")' && result.expandedCount == 2,
			"existing adapter lost its single post-child transformation: " + calls.join(";"));
		switch HxFunctionDecl.getBody(HxClassDecl.getFunctions(HxModuleDecl.getMainClass(ResolvedModule.getParsed(result.modules[0]).getDecl()))[0]) {
			case [
				SSwitch(_, _, _, _),
				SVar(_, _, _, _),
				SExpr(ECall(EIdent("normal"), [EString("first")]), _)
			]:
			case _:
				throw "existing nested adapter did not preserve the ordinary enclosing call";
		}
		Sys.println("M14_EXPR_MACRO_LEXICAL_TRAVERSAL:PASS");
	}
}
