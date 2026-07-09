package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Deque<T>` backed by `HxThread` runtime primitives.
**/
@:coreApi
class Deque<T> {
	final handle:Int;

	public function new():Void {
		handle = NativeHxThread.deque_create();
	}

	public function add(i:T):Void {
		NativeHxThread.deque_add(handle, i);
	}

	public function push(i:T):Void {
		NativeHxThread.deque_push(handle, i);
	}

	public function pop(block:Bool):Null<T> {
		return cast NativeHxThread.deque_pop(handle, block);
	}
}
