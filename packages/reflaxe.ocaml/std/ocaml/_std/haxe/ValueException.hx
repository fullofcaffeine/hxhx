package haxe;

/**
	`haxe.ValueException` (OCaml target).

	Why
	- Typed catches such as `catch (e:haxe.Exception)` can wrap non-Exception throws
	  as `haxe.ValueException` in generated OCaml code.
	- If the target stdlib only provides extern declarations, the generated OCaml
	  reference (`Haxe_ValueException.create`) has no backing module and stage0
	  bootstrap builds fail at link time.

	What
	- Provides a concrete OCaml-target implementation of `haxe.ValueException`
	  that extends our local `haxe.Exception` implementation.
	- Preserves the thrown value via `value` and `unwrap()`.
	- Lives in `std/ocaml/_std` so source checkouts follow Reflaxe's generated
	  target layout; Reflaxe packaging flattens it to
	  `src/haxe/ValueException.cross.hx`.

	How
	- Under `#if ocaml_output`, emit a real class.
	- On other targets, expose only an extern signature so this file does not pull
	  OCaml-only runtime behavior into non-OCaml builds.
**/
@:coreApi
#if ocaml_output
class ValueException extends Exception {
	public var value(default, null):Any;

	public function new(value:Any, ?previous:Exception, ?native:Any):Void {
		super(Std.string(value), previous, native);
		this.value = value;
	}

	override function unwrap():Any {
		return value;
	}
}
#else
extern class ValueException extends Exception {
	public var value(default, null):Any;
	public function new(value:Any, ?previous:Exception, ?native:Any):Void;
	private function unwrap():Any;
}
#end
