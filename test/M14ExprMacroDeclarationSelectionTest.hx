import hxhx.ExprMacroDeclarationSelector.capture;
import hxhx.ExprMacroDeclarationSelector.select;
import hxhx.ExprMacroDeclarationSelector.ExprMacroSelectionScope;

/** Header selection and source capture only; this does not execute a project macro. */
class M14ExprMacroDeclarationSelectionTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function module(path:String, source:String):ResolvedModule {
		final file = path.split(".").join("/") + ".hx";
		return new ResolvedModule(path, file, ParserStage.parse(source, file));
	}

	static function rejects(action:Void->Void, expected:String):Void {
		var diagnostic = "";
		try
			action()
		catch (error:String)
			diagnostic = error;
		require(diagnostic == expected, "selector accepted an unsupported declaration or failed elsewhere: " + diagnostic);
	}

	static function main():Void {
		final inputs = [
			module("one.Identity",
				'package one; class Identity { public static macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr { throw "body must not run"; } }'),
			module("two.Identity",
				'package two; class Identity { public static macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr { throw "body must not run"; } }'),
			module("plain.Identity", 'package plain; class Identity { @:macroLike public static function preserve(value:String):String return value; }'),
			module("callers.Aliased", 'package callers; import one.Identity as Chosen; class Aliased { public static function main():Void {} }'),
			module("callers.Later",
				'package callers; import two.Identity as Chosen; import one.Identity as Chosen; class Later { public static function main():Void {} }'),
			module("callers.Imported", 'package callers; import one.Identity.preserve as keep; class Imported { public static function main():Void {} }'),
			module("callers.Ordinary",
				'package callers; import one.Identity.preserve; class Ordinary { public static function preserve(value:String):String return value; }'),
			module("callers.Fields", 'package callers; import one.Identity.preserve; class Fields { public static var preserve:Int->Int = value -> value; }'),
			module("callers.Instance",
				'package callers; import one.Identity.preserve; class Instance { public function preserve(value:String):String return value; }'),
			module("callers.Parameters",
				'package callers; import one.Identity as Chosen; import one.Identity.preserve as keep; class Parameters { public static function run(Chosen:String, keep:String):Void { var local:String = "local"; } }'),
			module("values.Api", 'package values; class Api { public static var preserve:String->String = value -> value; }'),
			module("callers.FieldLast", 'package callers; import one.Identity.preserve as keep; import values.Api.preserve as keep; class FieldLast {}'),
			module("callers.MacroLast", 'package callers; import values.Api.preserve as keep; import one.Identity.preserve as keep; class MacroLast {}'),
			module("tools.Bundle",
				'package tools; class Bundle {} class Extra { public static macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr { throw "body must not run"; } }'),
			module("callers.Secondary", 'package callers; import tools.Bundle.Extra as Chosen; class Secondary {}'),
			module("callers.Wildcard", 'package callers; import one.Identity.*; class Wildcard {}'),
			module("base.Parent", 'package base; class Parent { public var preserve:String->String; }'),
			module("callers.InheritedField", 'package callers; import one.Identity.preserve; class InheritedField extends base.Parent {}'),
			module("callers.ValueTypeRoot",
				'package callers; import one.Identity as Chosen; class ValueTypeRoot { public static var Chosen:{preserve:String->String}; }'),
			module("callers.ValuePackageRoot", 'package callers; class ValuePackageRoot { public static var one:{Identity:{preserve:String->String}}; }'),
			module("callers.MethodRoot",
				'package callers; import one.Identity as Chosen; class MethodRoot { public static function Chosen():String return "value"; }'),
			module("values.Root", 'package values; class Root { public static var Chosen:{preserve:String->String}; }'),
			module("callers.ImportedValueRoot", 'package callers; import one.Identity as Chosen; import values.Root.Chosen; class ImportedValueRoot {}'),
			module("negative.Hidden",
				'package negative; class Hidden { private static macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr return value; }'),
			module("negative.Instance",
				'package negative; class Instance { public macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr return value; }'),
			module("negative.Ambiguous",
				'package negative; class Ambiguous { public static macro function preserve(value:haxe.macro.Expr):haxe.macro.Expr return value; public static macro function preserve(value:String):haxe.macro.Expr { throw "unused"; } }')
		];
		final index = TyperIndex.build(inputs);
		function context(name:String):TyperContext {
			final input = inputs.filter(value -> ResolvedModule.getModulePath(value) == "callers." + name)[0];
			final parsed = ResolvedModule.getParsed(input);
			final declaration = parsed.getDecl();
			final directives = HxModuleDecl.getDirectives(declaration);
			return new TyperContext(index, parsed.getFilePath(), "callers." + name, "callers", directives, "callers." + name, null,
				TyperStage.resolveModuleDirectives(directives, "callers", "callers." + name, index, null));
		}
		final scope:ExprMacroSelectionScope = {visibleNames: new Array<String>(), isStaticContext: true};
		function selected(text:String, owner:String, caller:String):Void {
			final call = HxParser.parseExprText(text);
			final captured = capture(call, context(caller), scope);
			require(captured != null, "macro declaration was not selected: " + text);
			require(captured.getDeclaration().getOwner().getCanonicalName() == owner, "wrong macro provider: " + text);
			require(captured.getCall() == call, "capture replaced its source call");
		}
		selected('one.Identity.preserve(undefined)', "one.Identity", "Aliased");
		selected('Chosen.preserve(undefined)', "one.Identity", "Aliased");
		selected('Chosen.preserve(undefined)', "one.Identity", "Later");
		selected('keep(undefined)', "one.Identity", "Imported");
		selected('preserve(undefined)', "one.Identity", "Wildcard");
		selected('Chosen.preserve(undefined)', "tools.Bundle.Extra", "Secondary");
		final secondary = capture(HxParser.parseExprText('Chosen.preserve(undefined)'), context("Secondary"), scope);
		require(secondary.getDeclaration().getModulePath() == "tools.Bundle", "secondary type lost its containing module identity");
		for (caller in ["FieldLast", "MacroLast"])
			rejects(() -> {
				capture(HxParser.parseExprText('keep(undefined)'), context(caller), scope);
			},
				"expression macro selection does not yet resolve mixed field and method imports");
		for (caller in ["ValueTypeRoot", "MethodRoot", "ImportedValueRoot"])
			require(capture(HxParser.parseExprText('Chosen.preserve(undefined)'), context(caller), scope) == null,
				"value-bound type root selected a macro: " + caller);
		require(capture(HxParser.parseExprText('one.Identity.preserve(undefined)'), context("ValuePackageRoot"), scope) == null,
			"value-bound package root selected a macro");
		rejects(() -> {
			capture(HxParser.parseExprText('negative.Hidden.preserve(undefined)'), context("Aliased"), scope);
		}, "expression macro selection requires a public static declaration");
		rejects(() -> {
			capture(HxParser.parseExprText('negative.Ambiguous.preserve(undefined)'), context("Aliased"), scope);
		},
			"expression macro selection requires one exact declaration before argument typing");
		require(capture(HxParser.parseExprText('negative.Instance.preserve(undefined)'), context("Aliased"), scope) == null,
			"instance macro was admitted as a static declaration");
		require(capture(HxParser.parseExprText('plain.Identity.preserve("ordinary")'), context("Aliased"), scope) == null,
			"ordinary same-name method or metadata substring became a macro");
		require(capture(HxParser.parseExprText('preserve("ordinary")'), context("Ordinary"), scope) == null, "ordinary current-class method lost precedence");
		require(capture(HxParser.parseExprText('preserve(1)'), context("Fields"), scope) == null, "callable current-class field lost precedence");
		require(capture(HxParser.parseExprText('preserve("ordinary")'), context("Instance"), {visibleNames: [], isStaticContext: false}) == null,
			"ordinary instance method lost precedence");
		require(capture(HxParser.parseExprText('preserve("ordinary")'), context("InheritedField"), {visibleNames: [], isStaticContext: false}) == null,
			"inherited callable field lost precedence");
		final parameters = inputs[9];
		final fn = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(ResolvedModule.getParsed(parameters).getDecl()))[0];
		final parameterNames = HxFunctionDecl.getArgs(fn).map(HxFunctionArg.getName);
		for (text in ['Chosen.preserve(undefined)', 'keep(undefined)'])
			require(capture(HxParser.parseExprText(text), context("Parameters"), {visibleNames: parameterNames, isStaticContext: true}) == null,
				"parameter shadowing was ignored");
		// The caller owns these exact point-in-source snapshots until production lexical traversal is integrated.
		require(capture(HxParser.parseExprText('Chosen.preserve(undefined)'), context("Aliased"), {visibleNames: ["Chosen"], isStaticContext: true}) == null,
			"local value did not shadow an imported type");
		require(capture(HxParser.parseExprText('one.Identity.preserve(undefined)'), context("Aliased"), {visibleNames: ["one"], isStaticContext: true}) == null,
			"local root did not shadow a qualified path");
		require(capture(HxParser.parseExprText('missing.Identity.preserve(undefined)'), context("Aliased"), scope) == null,
			"missing provider borrowed a same-suffix declaration");
		require(select(EField(ECall(EIdent("receiverMustNotRun"), []), "preserve"), context("Aliased"), scope) == null,
			"indirect receiver was inferred as a static macro provider");
		final outer = HxParser.parseExprText('one.Identity.preserve(two.Identity.preserve(undefined))');
		final before = TypedBodyFingerprint.exactExpression(outer);
		final originalArguments = switch outer {
			case ECall(_, arguments): arguments;
			case _: throw "expected call";
		};
		final captured = capture(outer, context("Aliased"), scope);
		require(captured != null
			&& captured.getDeclaration().getOwner().getCanonicalName() == "one.Identity", "outer macro was not selected first");
		require(captured.getArguments()[0] == originalArguments[0], "outer capture rewrote or copied its nested syntax");
		require(TypedBodyFingerprint.exactExpression(outer) == before, "selection mutated original syntax");
		final returned = captured.getArguments();
		returned[0] = ENull;
		require(captured.getArguments()[0] == originalArguments[0], "capture exposed its argument collection");
		final noArguments = capture(HxParser.parseExprText('one.Identity.preserve()'), context("Aliased"), scope);
		require(noArguments.getDeclaration() == captured.getDeclaration(), "argument count influenced declaration lookup");
		Sys.println("M14_EXPR_MACRO_DECLARATION_SELECTION:PASS");
	}
}
