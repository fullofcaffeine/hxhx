#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallableOrigin.classify;
#end

/** Checks that only real creation or declaration reads select an origin identity. */
class CheckOcamlCallableOrigins {
	#if macro
	public static function verify(main:TypedExpr):Void {
		check(main, [
			"source" => "StaticDeclaration(Main|Main::consume)",
			"higherSource" => "StaticDeclaration(Main|Main::relay)",
			"number" => "FreshLiteral",
			"first" => "null",
			"second" => "null",
			"alias" => "null",
			"higherView" => "null",
			"returned" => "null",
			"firstLiteral" => "null",
			"secondLiteral" => "null",
			"firstCapture" => "null",
			"secondCapture" => "null"
		]);
		final cases = switch (Context.getType("CheckOcamlCallableOrigins.CallableOriginCases")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing callback origin boundaries";
		};
		final boundaries = cases.statics.get().filter(field -> field.name == "probe")[0].expr();
		if (boundaries == null)
			throw "missing callback origin boundary body";
		check(boundaries, [
			"variable" => "null",
			"dynamicMethod" => "null",
			"nativeMethod" => "null",
			"nativeOwner" => "null",
			"foreign" => "null",
			"generic" => "null",
			"bound" => "null",
			"missing" => "null",
			"fresh" => "FreshLiteral",
			"annotated" => "FreshLiteral",
			"read" => "null",
			"castRead" => "null"
		]);
		Sys.println("OCAML_CALLABLE_ORIGIN:PASS");
	}

	/** Assert coverage as well as decisions, so a removed source occurrence cannot pass silently. */
	static function check(body:TypedExpr, expected:Map<String, String>):Void {
		final seen:Map<String, Bool> = [];
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (value != null && expected.exists(local.name)):
					final actual = Std.string(classify(value));
					if (actual != expected.get(local.name))
						throw 'callback origin for ${local.name}: expected ${expected.get(local.name)}, got $actual';
					seen.set(local.name, true);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		for (name in expected.keys())
			if (!seen.exists(name))
				throw "missing callback origin case: " + name;
	}
	#end
}

/** Typed-only boundaries that must not acquire an ordinary static declaration identity. */
class CallableOriginCases {
	/** These expressions are typed but never executed; Sys supplies a real extern boundary. */
	public static function probe():Void {
		var variable = CallableOriginCases.variable;
		var dynamicMethod = CallableOriginCases.replaceable;
		var nativeMethod = CallableOriginCases.nativeMethod;
		var nativeOwner = CallableNativeOwner.method;
		var foreign = Sys.systemName;
		var generic:Int->Int = CallableOriginCases.generic;
		var instance = new CallableOriginCases();
		var bound = instance.method;
		var missing:Null<Int->Int> = null;
		var fresh = (value:Int) -> value + 1;
		var annotated = @:keep (value:Int) -> value + 2;
		var read = fresh;
		var castRead:Int->Int = cast fresh;
	}

	public static var variable:Int->Int = value -> value;

	public static dynamic function replaceable(value:Int):Int
		return value;

	@:native("foreign_method") public static function nativeMethod(value:Int):Int
		return value;

	public static function generic<T>(value:T):T
		return value;

	public function new() {}

	public function method(value:Int):Int
		return value;
}

/** A native mapping can replace the emitted declaration even when the Haxe body exists. */
@:native("ForeignOwner")
class CallableNativeOwner {
	public static function method(value:Int):Int
		return value;
}
