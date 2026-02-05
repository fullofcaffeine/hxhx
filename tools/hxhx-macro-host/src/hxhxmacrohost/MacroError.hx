package hxhxmacrohost;

/**
	Small helper for raising macro-host errors with a position payload.

	Why
	- We want `file:line` in protocol errors (`p` field) in a way that:
	  - is deterministic and portable across targets,
	  - does not depend on runtime stack traces.

	What
	- `raise(message, ?pos)` throws a small tagged payload when `pos` is available,
	  otherwise throws the raw message.

	How
	- The optional `pos:haxe.PosInfos` parameter is automatically filled by the
	  Haxe compiler at the call site, so callers just write:
	  - `MacroError.raise("boom");`
**/
class MacroError {
	public static inline final TAG:String = "hxhx_macro_host_error_v1";

	public static function raise<T>(message:String, ?pos:haxe.PosInfos):T {
		if (pos != null) {
			// Use an anonymous payload so `Reflect.field` works reliably on the OCaml target.
			// (Custom class instances may be represented as records, which are awkward to reflect on.)
			throw {__hxhx_tag: TAG, message: message, pos: pos};
		}
		throw message;
	}
}
