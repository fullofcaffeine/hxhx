import backend.cpp.CppMacroExpr;
import backend.cpp.CppTargetCore;
import backend.js.JsExprEmitter;
import backend.source.SourceTargetCommon;
import backend.vm.NekoMacroExprLowering;
import haxe.macro.Expr;
import hxhxmacrohost.api.RuntimeMacroExprs;

/** Source braces survive parsing; semantic sequences cannot fabricate macro block syntax. */
class M14SequencingMacroBoundaryTest {
	static function reject(action:Void->Void, label:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("source brace grouping was lost") >= 0)
				return;
			throw label + " failed for another reason: " + error.message;
		}
		throw label + " fabricated a macro expression without source groups";
	}

	static function shape(value:Expr):String {
		return switch (value.expr) {
			case EBlock(entries): "block(" + [for (entry in entries) shape(entry)].join(",") + ")";
			case EConst(CInt(value, _)): value;
			case _: throw "unexpected function-body macro shape";
		};
	}

	/** The `block(...)`/integer shape of a lowered `{expr: <ExprDef>, pos: <Position>}` construction. */
	static function loweredShape(record:TypedExpr):String {
		if (record.getTag() != Anonymous || record.getTexts().join(",") != "expr,pos")
			throw "quotation was not lowered to an Expr record";
		final definition = record.getExpressions()[0];
		return switch constructorName(definition) {
			case "EBlock": "block(" + [for (item in definition.getExpressions()[1].getExpressions()) loweredShape(item)].join(",") + ")";
			case "EConst":
				final constant = definition.getExpressions()[1];
				if (constructorName(constant) != "CInt")
					throw "lowered constant is not an integer";
				constant.getExpressions()[1].getTexts()[0];
			case name: throw "unexpected lowered constructor `" + name + "`";
		};
	}

	/** The constructor a lowered call names; `typeModule` loads no `haxe.macro.Expr`, so read the callee's last segment. */
	static function constructorName(call:TypedExpr):String {
		final callee = call.getTag() == Call ? call.getExpressions()[0] : null;
		return callee != null && callee.getTag() == FieldRead ? callee.getTexts()[0] : "";
	}

	static function main():Void {
		final sources = ["{ 1; 2; }", "{ { 1; 2; } 3; }", "{ 1; { 2; 3; } }"];
		final expected = ["block(1,2)", "block(block(1,2),3)", "block(1,block(2,3))"];
		for (index in 0...sources.length) {
			final source = sources[index];
			if (shape(RuntimeMacroExprs.parse(source, null)) != expected[index])
				throw "runtime expression parser changed source brace grouping";
			if (shape(RuntimeMacroExprs.parseFunctionBodyText(source, null)) != "block(" + expected[index] + ")")
				throw "function-body parser lost an existing source brace group";
			final text = "class Main { static function main() { var quoted = macro " + source + "; } }";
			// The typer lowers the quote to the construction of its `Expr` value; that construction
			// keeps the authored grouping.
			final module = TyperStage.typeModule(ParserStage.parse(text));
			module.getBackendProjection();
			if (loweredShape(module.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0]) != expected[index])
				throw "typed quotation lowering changed source brace grouping";
			// The runtime converter reads quote syntax, which only a module built without the typer
			// still carries (`TypedBodyBuilder.buildFallbackModule`).
			final quote = TypedBodyBuilder.buildFallbackModule(ParserStage.parse(text),
				null)[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
			if (quote.getTag() != MacroExpr)
				throw "fallback module lost its quotation node";
			final projected = TypedSourceSyntax.expression(quote.getExpressions()[0]);
			final macroValue = @:privateAccess RuntimeMacroExprs.convert(projected, null);
			if (shape(macroValue) != expected[index])
				throw "typed quote projection changed source brace grouping";
		}
		// A generated evaluation sequence has no authored braces, even after parser cutover.
		final inner = HxExpr.EDiscardThen(EInt(1), EInt(2));
		final control = HxExpr.ELoweredControl(Scope, "", [EInt(1)], HxPos.unknown());
		reject(() -> @:privateAccess RuntimeMacroExprs.convert(control, null), "runtime executable control adapter");
		reject(() -> TypedSourceSyntax.expression(TypedExpr.controlRegion([], TyType.fromHintText("Void"), null)), "typed executable control adapter");
		final quoted = HxExpr.EMacroExpr(inner, []);
		reject(() -> @:privateAccess RuntimeMacroExprs.convert(inner, null), "runtime semantic sequence adapter");
		reject(() -> JsExprEmitter.emit(quoted, null), "JavaScript macro adapter");
		reject(() -> @:privateAccess EmitterStage.exprToOcaml(quoted), "OCaml unexpanded macro boundary");
		reject(() -> CppMacroExpr.macroExpr(inner, []), "C++ macro object adapter");
		reject(() -> @:privateAccess CppTargetCore.macroExprText(inner, []), "C++ macro text adapter");
		reject(() -> NekoMacroExprLowering.render(inner, [], _ -> "unused", null), "Neko macro adapter");
		reject(() -> @:privateAccess SourceTargetCommon.pythonMacroExpr(inner, []), "Python macro adapter");
		reject(() -> @:privateAccess SourceTargetCommon.phpMacroExpr(inner, []), "PHP macro adapter");
		Sys.println("SEQUENCING_MACRO_BOUNDARY:PASS");
	}
}
