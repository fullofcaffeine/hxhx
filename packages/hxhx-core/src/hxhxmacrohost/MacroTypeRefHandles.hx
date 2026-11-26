package hxhxmacrohost;

import haxe.macro.Type.Ref;

/**
	The compiler's handles for one kind of `Ref` that `MacroTypeWire` built.

	A ref is found by identity. `Ref` is a structure, and `==` on structures is physical equality,
	in the interpreter and in a Stage3 plugin (`Stage3OcamlClassStorage.usesIdentity`). A `Ref` that
	the macro built itself is not found, so it cannot be sent back to the compiler.
**/
class MacroTypeRefHandles<T> {
	final refs:Array<Ref<T>> = [];
	final handles:Array<Int> = [];

	public function new() {}

	/** Remember `ref` with its handle, and return it. */
	public function remember(ref:Ref<T>, handle:Int):Ref<T> {
		refs.push(ref);
		handles.push(handle);
		return ref;
	}

	/** The handle of `ref`; a ref this store did not remember is `invalid`. */
	public function handleOf(ref:Ref<T>):Int {
		for (index in 0...refs.length)
			if (refs[index] == ref)
				return handles[index];
		throw "macro context: invalid: this Ref was not given by the compiler, so it cannot be sent back";
	}
}
