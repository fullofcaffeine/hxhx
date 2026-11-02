package backend.ocaml;

/**
	Read and write the two 32-bit words inside one `haxe.Int64` object.

	Why
	- Haxe 4.3.7 implements `haxe.Int64` as an abstract over the private class
	  `___Int64` declared in the `haxe.Int64` module (canonical name
	  `haxe.Int64.___Int64`), which stores the signed `high` and `low` words.
	  Inline operator bodies such as `++`/`--` copy the value and then update
	  `this.low` and `this.high` directly on that class.
	- Stage3 represents that class with the record type `Haxe_Int64.t` from the
	  `packages/hxhx-core/shims/Haxe_Int64.ml` provider. A record has no
	  anonymous-object slots, so the generic `HxAnon.get`/`HxAnon.set` field
	  lookup read null and ignored the write: `i64++` printed the old value.

	What
	- `isWordField` is true only when the typed field occurrence selects the
	  `high` or `low` field of the exact private Int64 storage class through a
	  value receiver (`value.low`, not an implicit `low` inside that class).
	- `read` and `write` call the provider's typed accessors. `write` yields the
	  stored word, like a Haxe assignment expression.
**/
inline final INT64_STORAGE_CLASS = "haxe.Int64.___Int64";

function isWordField(occurrence:Null<TypedBackendFieldOccurrence>):Bool {
	if (occurrence == null || occurrence.getReceiver() != ValueReceiver)
		return false;
	final field = occurrence.getField();
	return !field.getIsStatic()
		&& field.getOwner().getCanonicalName() == INT64_STORAGE_CLASS
		&& (field.getName() == "high" || field.getName() == "low");
}

function read(field:String, receiver:String):String {
	return "(Haxe_Int64.get_" + field + " (" + receiver + "))";
}

function write(field:String, receiver:String, value:String):String {
	return "(Haxe_Int64.set_" + field + " (" + receiver + ") (" + value + "))";
}
