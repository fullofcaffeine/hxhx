#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shape as genericShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shapeId;
#end

/** Checks ordinary callback conversion direction on the retained, upstream-typed source fixture. */
class CheckOcamlCallableViewConversions {
	/** Supplies the exact fixture assignment's selected conversion to the native syntax test. */
	public static macro function selectedView(localName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final body = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		var selected:Null<reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion> = null;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == localName && value != null):
					final source = callableShape(value.t);
					final destination = callableShape(local.t);
					if (source != null && destination != null)
						selected = crossing(source, destination);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		if (body != null)
			visit(body);
		if (selected == null)
			throw "fixture callback conversion was not selected";
		return Context.makeExpr(selected, Context.currentPos());
	}

	#if macro
	public static function install():Void {
		Context.getType("Main");
		Context.onAfterTyping(_ -> verify());
	}

	static function verify():Void {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final main = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		if (main == null)
			throw "missing stored callback body";
		final expected:Map<String, String> = [
			"source" => "Identity",
			"first" => "AdaptFunction([BoxValue],Identity)",
			"second" => "AdaptFunction([BoxValue],Identity)",
			"alias" => "Identity",
			"higherSource" => "Identity",
			"higherView" => "AdaptFunction([AdaptFunction([UnboxValue],BoxValue)],AdaptFunction([BoxValue],UnboxValue))"
		];
		var count = 0;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (value != null && expected.exists(local.name)):
					final source = callableShape(value.t);
					final destination = callableShape(local.t);
					if (source == null || destination == null || Std.string(crossing(source, destination)) != expected.get(local.name))
						throw "wrong callable storage conversion for " + local.name;
					count++;
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(main);
		if (count != 6)
			throw "stored callback conversion coverage changed";

		final dynamicType = Context.resolveType(macro :Dynamic, Context.currentPos());
		final dynamicShape = callableShape(dynamicType);
		if (dynamicShape == null || shapeId(dynamicShape) != "Dynamic" || genericShape(dynamicType) != null)
			throw "ordinary Dynamic changed generic declaration admission";
		for (unsupported in [
			Context.makeMonomorph(),
			Context.resolveType(macro :Dynamic<Int>, Context.currentPos()),
			Context.resolveType(macro :(?value:Int) -> Int, Context.currentPos()),
			Context.resolveType(macro :Null<Int->Int>, Context.currentPos()),
			Context.resolveType(macro :Array<Dynamic>, Context.currentPos())
		])
			if (callableShape(unsupported) != null)
				throw "unproved callable storage acquired a representation";
		final unresolvedCallback:Type = TFun([{name: "value", opt: false, t: Context.makeMonomorph()}], dynamicType);
		if (callableShape(unresolvedCallback) != null)
			throw "unresolved callback input was replaced with Dynamic";
		checkConversion(macro :Dynamic->Dynamic, macro :Int->Dynamic, "AdaptFunction([BoxValue],Identity)");
		checkConversion(macro :Int->Int, macro :Dynamic->Dynamic, "AdaptFunction([UnboxValue],BoxValue)");
		checkConversion(macro :Dynamic->Dynamic, macro :Bool->Bool, "AdaptFunction([BoxBoolean],UnboxBoolean)");
		checkConversion(macro :Dynamic->Dynamic, macro :Null<Bool>->Null<Bool>, "AdaptFunction([BoxNullableBoolean],UnboxNullableBoolean)");
		checkConversion(macro :Int->Int, macro :String->Int, "null");
		checkConversion(macro :Int->Int, macro :Int->Int->Int, "null");
		Sys.println("OCAML_CALLABLE_VIEW_CONVERSION:PASS");
	}

	/** Function arguments reverse direction while the result keeps source-to-destination direction. */
	static function checkConversion(source:haxe.macro.Expr.ComplexType, destination:haxe.macro.Expr.ComplexType, expected:String):Void {
		final from = callableShape(Context.resolveType(source, Context.currentPos()));
		final to = callableShape(Context.resolveType(destination, Context.currentPos()));
		if (from == null || to == null || Std.string(crossing(from, to)) != expected)
			throw "wrong callback conversion direction: " + expected;
	}
	#end
}
