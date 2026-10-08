#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/** Checks whole-method callback selection against authored producers and unsupported consumers. */
class OcamlCallableProgramSelectionTest {
	static function main():Void {
		verify();
		Sys.println("OCAML_CALLABLE_PROGRAM_SELECTION:PASS");
	}

	/** The real failing source remains the positive contract; negative programs test rejection propagation. */
	static macro function verify():Expr {
		function check(name:String, expected:Array<String>):Void {
			final owner = switch (Context.getType(name)) {
				case TInst(reference, []): reference.get();
				case _: throw "callback selection fixture is not an ordinary class";
			};
			final selected = reflaxe.ocaml.lowered.OcamlCallableProgramSelection.select([owner]);
			final actual = selected.map(method -> method.fieldName);
			actual.sort(Reflect.compare);
			expected.sort(Reflect.compare);
			if (actual.join(",") != expected.join(","))
				throw 'callback program $name: expected $expected, got $actual';
		}
		check("Main", [
			"relay",
			"literal",
			"captured",
			"preserve",
			"staticCallback",
			"forwarded",
			"main"
		]);
		check("OcamlCallableProgramSelectionTest.CallbackParameterAndReturn", ["factory", "preserve", "run"]);
		check("OcamlCallableProgramSelectionTest.CallbackEscapes", []);
		check("OcamlCallableProgramSelectionTest.CallbackMutation", []);
		check("OcamlCallableProgramSelectionTest.CallbackCapture", []);
		check("OcamlCallableProgramSelectionTest.CallbackStaticEscape", []);
		check("OcamlCallableProgramSelectionTest.CallbackConstructorEscape", []);
		check("OcamlCallableProgramSelectionTest.CallbackReflectiveEscape", []);
		check("OcamlCallableProgramSelectionTest.CallbackStringReflectiveEscape", []);
		return macro null;
	}
}

/** A returned callback flows through a parameter and remains immediately callable. */
private class CallbackParameterAndReturn {
	static function factory():Int->Int
		return value -> value + 1;

	static function preserve(callback:Int->Int):Int->Int
		return callback;

	static function run():Void {
		var callback = factory();
		preserve(callback)(7);
	}
}

/** Dynamic erasure in one consumer must also reject the factory declaration. */
private class CallbackEscapes {
	static function factory():Int->Int
		return value -> value + 1;

	static function run():Void {
		var erased:Dynamic = factory();
		Sys.println(erased);
	}
}

/** Reassignment needs a separate storage plan even when both factories have the same signature. */
private class CallbackMutation {
	static function factory():Int->Int
		return value -> value + 1;

	static function run():Void {
		var callback = factory();
		callback = factory();
		callback(7);
	}
}

/** A callback captured by another closure cannot be admitted as ordinary immutable local storage. */
private class CallbackCapture {
	static function factory():Int->Int
		return value -> value + 1;

	static function run():Void {
		var callback = factory();
		var captured = () -> callback(7);
		captured();
	}
}

/** Static initializers consume callback results even though they have no eligible method boundary. */
private class CallbackStaticEscape {
	static var stored:Dynamic = factory();

	static function factory():Int->Int
		return value -> value + 1;
}

/** Constructor bodies must participate in rejection even while constructor callback boundaries are unsupported. */
private class CallbackConstructorEscape {
	static function factory():Int->Int
		return value -> value + 1;

	public function new() {
		var stored:Dynamic = factory();
		Sys.println(stored);
	}
}

/** Reading a class value can expose its callback-producing methods to reflection. */
private class CallbackReflectiveEscape {
	static function factory():Int->Int
		return value -> value + 1;

	static function run():Void {
		Reflect.field(CallbackReflectiveEscape, "factory");
	}
}

/** Runtime class lookup can expose a producer without a typed reference to its declaration. */
@:keep
private class CallbackStringReflectiveEscape {
	public static function factory():Int->Int
		return value -> value + 1;

	static function run(name:String):Void {
		final owner = Type.resolveClass(name);
		if (owner != null)
			Reflect.field(owner, "factory");
	}
}
