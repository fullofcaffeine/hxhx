package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Tls<T>` backed by `HxThread` runtime primitives.
**/
class Tls<T> {
	public var value(get, set):T;

	final handle:Int;

	public function new():Void {
		handle = NativeHxThread.tls_create();
	}

	function get_value():T {
		return cast NativeHxThread.tls_get(handle);
	}

	function set_value(next:T):T {
		NativeHxThread.tls_set(handle, next);
		return next;
	}
}
