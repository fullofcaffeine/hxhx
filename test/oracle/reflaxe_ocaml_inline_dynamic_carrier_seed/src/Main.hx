private class SampleValue {
	public final label:String;

	public function new(label:String) {
		this.label = label;
	}

	public function toString():String {
		return "SampleValue(" + label + ")";
	}
}

#if ocaml
@:native("HxDynamic")
private extern class NativeDynamicText {
	static function toStdString(value:Dynamic):String;
}
#end

/**
	Exercises one inlined `Dynamic` parameter through three independent users.

	The ordinary Haxe call, typed native call, and direct `Std.string` call must
	all observe the same value. Inlining must not specialize the temporary into a
	target carrier that is incompatible with its declared `Dynamic` type.
**/
class Main {
	static function output(value:String):Void {
		#if js
		js.Syntax.code("process.stdout.write({0} + '\\n')", value);
		#else
		Sys.println(value);
		#end
	}

	static function ordinaryText(value:Dynamic):String {
		return Std.string(value);
	}

	static function nativeText(value:Dynamic):String {
		#if ocaml
		return NativeDynamicText.toStdString(value);
		#else
		return Std.string(value);
		#end
	}

	static inline function inspect(value:Dynamic):String {
		return ordinaryText(value) + "|" + nativeText(value) + "|" + Std.string(value);
	}

	static function main():Void {
		output("string=" + inspect("text"));
		output("int=" + inspect(7));
		output("float=" + inspect(1.5));
		output("bool=" + inspect(true));
		output("null=" + inspect(null));
		output("class=" + inspect(new SampleValue("class")));
		output("anonymous=" + inspect({label: "anonymous"}));
	}
}
