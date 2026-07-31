package backend.source;

/**
	Required state boundary for recursive source-target function rendering.

	A program frame supports the non-PHP source targets and PHP syntax emitted
	outside typed executable units. Typed PHP function bodies and field
	initializers use a PHP function frame carrying both the target-owned renderer
	and the exact immutable lexical scope. Keeping the two cases distinct
	prevents a missed argument from silently falling back to an empty PHP scope.
**/
enum SourceFunctionRenderFrame {
	Program(target:SourceNativeTarget);
	PhpFunction(renderer:PhpFunctionBodyRenderer, scope:PhpLexicalRenderScope);
}

class SourceFunctionRenderFrameTools {
	public static function target(frame:SourceFunctionRenderFrame):SourceNativeTarget {
		if (frame == null)
			throw "source function rendering requires an explicit render frame";
		return switch (frame) {
			case Program(target): target;
			case PhpFunction(_, _): Php;
		};
	}

	public static function requirePhpRenderer(frame:SourceFunctionRenderFrame):PhpFunctionBodyRenderer {
		return switch (frame) {
			case PhpFunction(renderer, _): renderer;
			case Program(target):
				throw "source " + targetLabel(target) + " program frame cannot answer PHP function-state queries";
		};
	}

	/** Return the request-owned program renderer shared by the exact function facts. **/
	public static function requirePhpProgramRenderer(frame:SourceFunctionRenderFrame):PhpProgramBodyRenderer
		return requirePhpRenderer(frame).getProgramRenderer();

	public static function requirePhpScope(frame:SourceFunctionRenderFrame):PhpLexicalRenderScope {
		return switch (frame) {
			case PhpFunction(_, scope): scope;
			case Program(target):
				throw "source " + targetLabel(target) + " program frame cannot answer PHP lexical-scope queries";
		};
	}

	public static function withPhpScope(frame:SourceFunctionRenderFrame, scope:PhpLexicalRenderScope):SourceFunctionRenderFrame {
		if (scope == null)
			throw "PHP function rendering requires an explicit lexical scope";
		return switch (frame) {
			case PhpFunction(renderer, _): PhpFunction(renderer, scope);
			case Program(target):
				throw "source " + targetLabel(target) + " program frame cannot derive a PHP lexical scope";
		};
	}

	/** Create the exact root frame for one request-owned PHP renderer. **/
	public static function forPhpRenderer(renderer:PhpFunctionBodyRenderer):SourceFunctionRenderFrame {
		if (renderer == null)
			throw "PHP function rendering requires a request-owned renderer";
		final plan = renderer.getPlan();
		final scope = PhpLexicalRenderScope.forFunction(plan);
		return PhpFunction(renderer, plan.usesThisValueSlot() ? scope.withThisValueSlot(true) : scope);
	}

	static function targetLabel(target:SourceNativeTarget):String
		return switch (target) {
			case Python: "Python";
			case Java: "Java";
			case Cs: "C#";
			case Php: "PHP";
			case Lua: "Lua";
		};
}
