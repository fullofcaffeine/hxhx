import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterSwitchExprIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final simple = HxParser.parseExprText('switch (mode) { case "a": 1; case "b" | "c": 2; default: 9; }');
		final simpleJs = JsExprEmitter.emit(simple, exprScope);
		assertContains(simpleJs, "(function () {", "switch expression should lower via IIFE");
		assertContains(simpleJs, "if (__sw === \"a\")", "first case should lower to condition");
		assertContains(simpleJs, "else if ((__sw === \"b\") || (__sw === \"c\"))", "OR pattern should lower to disjunction");
		assertContains(simpleJs, "return 9;", "default branch should return fallback value");

		final bind = HxParser.parseExprText("switch (mode) { case value: value + 1; }");
		final bindJs = JsExprEmitter.emit(bind, exprScope);
		assertContains(bindJs, "var __sw_bind_value = __sw;", "bind pattern should define branch-local alias");
		assertContains(bindJs, "return (__sw_bind_value + 1);", "bind alias should be used in emitted expression");

		final throwExpr = HxParser.parseExprText("switch (value) { case label: throw 'unknown value $label'; }");
		final throwJs = JsExprEmitter.emit(throwExpr, exprScope);
		assertContains(throwJs, "(function(){ throw", "switch expression throw branch should lower to throwing IIFE");
		assertContains(throwJs, "unknown value", "switch expression throw branch should keep message text");

		final objectPattern = HxParser.parseExprText("switch (payload.expr) { case Wrap(Text(s)): s; case Group({ value : Wrap(Text(s)) }) | Raw({ value : Wrap(Text(s)) }): s; case Pick(_, name): name; case At(_, { value : Wrap(IntText(i) | FloatText(i)) }): Std.string(i); case InOp(In, _, { value : inner, pos : _ }): Std.string(inner); case _: \"none\"; }");
		final objectPatternJs = JsExprEmitter.emit(objectPattern, exprScope);
		assertContains(objectPatternJs, "__sw.__hx_ctor === \"Group\"", "expression switch should test structural OR first constructor");
		assertContains(objectPatternJs, "__sw.__hx_params[0].value.__hx_ctor === \"Wrap\"", "expression switch should match object field nested constructor");
		assertContains(objectPatternJs, "var __sw_bind_s = __sw.__hx_params[0].value.__hx_params[0].__hx_params[0];",
			"expression OR alternatives with matching bind paths should bind shared value");
		assertContains(objectPatternJs, "__sw.__hx_params[1].value.__hx_params[0].__hx_ctor === \"IntText\"",
			"expression switch should test first nested numeric OR constructor");
		assertContains(objectPatternJs, "__sw.__hx_params[1].value.__hx_params[0].__hx_ctor === \"FloatText\"",
			"expression switch should test second nested numeric OR constructor");
		assertContains(objectPatternJs, "var __sw_bind_i = __sw.__hx_params[1].value.__hx_params[0].__hx_params[0];",
			"expression switch should bind nested OR value");

		final capturePattern = HxParser.parseExprText('switch payload { case Wrap(captured = (Text("hello") | IntText("9"))): Std.string(captured); case _: "none"; }');
		final capturePatternJs = JsExprEmitter.emit(capturePattern, exprScope);
		assertContains(capturePatternJs, "__sw.__hx_params[0].__hx_ctor === \"Text\"", "capture pattern should test first inner constructor");
		assertContains(capturePatternJs, "__sw.__hx_params[0].__hx_params[0] === \"hello\"", "capture pattern should test first literal value");
		assertContains(capturePatternJs, "__sw.__hx_params[0].__hx_ctor === \"IntText\"", "capture pattern should test second inner constructor");
		assertContains(capturePatternJs, "var __sw_bind_captured = __sw.__hx_params[0];", "capture pattern should bind matched value");

		final arrayPattern = HxParser.parseExprText('switch values { case []: "empty"; case [one]: one; case [left, right]: left + right; case _: "many"; }');
		final arrayPatternJs = JsExprEmitter.emit(arrayPattern, exprScope);
		assertContains(arrayPatternJs, "Array.isArray(__sw) && __sw.length === 0", "empty array pattern should test array length");
		assertContains(arrayPatternJs, "Array.isArray(__sw) && __sw.length === 1", "single-item array pattern should test array length");
		assertContains(arrayPatternJs, "var __sw_bind_one = __sw[0];", "single-item array pattern should bind item");
		assertContains(arrayPatternJs, "Array.isArray(__sw) && __sw.length === 2", "two-item array pattern should test array length");
		assertContains(arrayPatternJs, "var __sw_bind_left = __sw[0];", "two-item array pattern should bind first item");
		assertContains(arrayPatternJs, "var __sw_bind_right = __sw[1];", "two-item array pattern should bind second item");

		final guardedPattern = HxParser.parseExprText('switch values { case var rest if (rest.length == 3): Std.string(rest.length); case _: "other"; }');
		final guardedPatternJs = JsExprEmitter.emit(guardedPattern, exprScope);
		assertContains(guardedPatternJs, "if ((true) && (__sw.length === 3))", "guarded bind pattern should lower length guard");
		assertContains(guardedPatternJs, "var __sw_bind_rest = __sw;", "guarded bind pattern should bind scrutinee");

		final groupedPattern = HxParser.parseExprText('switch v { case 1, 2, 3: "small"; case val = (4 | 5 | 6) if (val == 5): "middle"; case var x: "_"; }');
		final groupedPatternJs = JsExprEmitter.emit(groupedPattern, exprScope);
		assertContains(groupedPatternJs, "(__sw === 1) || (__sw === 2) || (__sw === 3)", "comma-separated case groups should lower as OR conditions");
		assertContains(groupedPatternJs, "(__sw === 4) || (__sw === 5) || (__sw === 6)", "captured OR pattern should lower all alternatives");
		assertContains(groupedPatternJs, "(__sw === 5)", "integer equality guard should use captured scrutinee value");
		assertContains(groupedPatternJs, "var __sw_bind_val = __sw;", "captured guard branch should bind the capture");

		final switchIfElseSemicolon = HxParser.parseExprText('switch v { case A(x): if (x == null) "null"; else "not null"; }');
		final switchIfElseSemicolonJs = JsExprEmitter.emit(switchIfElseSemicolon, exprScope);
		assertContains(switchIfElseSemicolonJs, "__sw.__hx_ctor === \"A\"", "if/else branch switch should match enum constructor");
		assertContains(switchIfElseSemicolonJs, "var __sw_bind_x = __sw.__hx_params[0];", "if/else branch switch should bind enum arg");
		assertContains(switchIfElseSemicolonJs, "((__sw_bind_x === null) ? \"null\" : \"not null\")", "semicolon before else should still lower as ternary");

		final emptyCaseSwitchJs = JsExprEmitter.emit(HxParser.parseExprText('switch true { case true: case false: }'), exprScope);
		assertContains(emptyCaseSwitchJs, "if (__sw === true)", "boolean literal switch pattern should lower true test");
		assertContains(emptyCaseSwitchJs, "else if (__sw === false)", "boolean literal switch pattern should lower false test");
		assertContains(emptyCaseSwitchJs, "return null;", "empty switch case body should return null");

		final macroStringJs = JsExprEmitter.emit(HxParser.parseExprText('macro "bar"'), exprScope);
		assertContains(macroStringJs, "__hx_ctor: \"EConst\"", "macro string quote should emit EConst expression def");
		assertContains(macroStringJs, "__hx_ctor: \"CString\"", "macro string quote should emit CString constant");
		assertContains(macroStringJs, "\"bar\"", "macro string quote should preserve literal");

		final macroFieldJs = JsExprEmitter.emit(HxParser.parseExprText("macro null.foo"), exprScope);
		assertContains(macroFieldJs, "__hx_ctor: \"EField\"", "macro field quote should emit EField expression def");
		assertContains(macroFieldJs, "\"foo\"", "macro field quote should preserve field name");

		final macroInJs = JsExprEmitter.emit(HxParser.parseExprText("macro 1 in 0"), exprScope);
		assertContains(macroInJs, "__hx_ctor: \"EBinop\"", "macro in quote should emit EBinop expression def");
		assertContains(macroInJs, "__hx_ctor: \"OpIn\"", "macro in quote should emit OpIn operator");

		final macroTypeJs = JsExprEmitter.emit(HxParser.parseExprText("macro :X -> Y"), exprScope);
		assertContains(macroTypeJs, "__hx_ctor: \"TFunction\"", "macro type quote should emit function complex type");
		assertContains(macroTypeJs, "__hx_ctor: \"TPath\"", "macro type quote should emit path complex type");
		assertContains(macroTypeJs, "name: \"X\"", "macro type quote should preserve argument type path");
		assertContains(macroTypeJs, "name: \"Y\"", "macro type quote should preserve return type path");

		final enumCtorJs = JsExprEmitter.emit(HxParser.parseExprText('TOptional(TNamed("a", macro :Int))'), exprScope);
		assertContains(enumCtorJs, "__hx_ctor: \"TOptional\"", "enum constructor calls should emit enum objects");
		assertContains(enumCtorJs, "__hx_ctor: \"TNamed\"", "nested enum constructor calls should emit enum objects");
		assertContains(enumCtorJs, "name: \"Int\"", "macro type constructor arg should preserve Int type path");
	}
}
