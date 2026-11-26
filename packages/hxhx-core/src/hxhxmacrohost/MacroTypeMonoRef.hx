package hxhxmacrohost;

import haxe.macro.Type;

/**
	The `get` of a monomorph's `Ref` in a project-macro plugin (`MacroTypeWire`): the type the
	compiler bound it to, or null. A class method, so the plugin passes it as a method value: the
	Stage3 emitter's closures cannot return a nullable value. It holds the decoder's bound method,
	not the decoder, so the two OCaml modules do not depend on each other.
**/
class MacroTypeMonoRef {
	final read:Int->Null<Type>;
	final handle:Int;

	public function new(read:Int->Null<Type>, handle:Int) {
		this.read = read;
		this.handle = handle;
	}

	public function get():Null<Type>
		return read(handle);
}
