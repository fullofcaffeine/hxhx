package sys.thread;

/**
	Native OCaml runtime bridge for `sys.thread.*` overrides.

	`Dynamic` appears only at unavoidable runtime-boundary surfaces:
	- cross-thread message payloads (`Thread.sendMessage/readMessage`)
	- generic deque payloads (`Deque<T>`)
	- thread-local storage payloads (`Tls<T>`)
	- event-loop attachment handles (`Thread.events`)

	Each emitted operation declares the checked `haxe-thread` runtime
	capability before packaging, so `HxThread` is selected from typed Haxe
	behavior instead of inferred only from generated OCaml module names.
**/
@:ocamlRuntime("haxe-thread")
@:native("HxThread")
extern class NativeHxThread {
	static function lock_create():Int;
	static function lock_wait(handle:Int):Bool;
	static function lock_wait_timeout(handle:Int, timeout:Float):Bool;
	static function lock_release(handle:Int):Void;

	static function mutex_create():Int;
	static function mutex_acquire(handle:Int):Void;
	static function mutex_try_acquire(handle:Int):Bool;
	static function mutex_release(handle:Int):Void;

	static function condition_create():Int;
	static function condition_acquire(handle:Int):Void;
	static function condition_try_acquire(handle:Int):Bool;
	static function condition_release(handle:Int):Void;
	static function condition_wait(handle:Int):Void;
	static function condition_signal(handle:Int):Void;
	static function condition_broadcast(handle:Int):Void;

	static function semaphore_create(value:Int):Int;
	static function semaphore_acquire(handle:Int):Void;
	static function semaphore_try_acquire(handle:Int):Bool;
	static function semaphore_try_acquire_timeout(handle:Int, timeout:Float):Bool;
	static function semaphore_release(handle:Int):Void;

	static function deque_create():Int;
	static function deque_add(handle:Int, value:Dynamic):Void;
	static function deque_push(handle:Int, value:Dynamic):Void;
	static function deque_pop(handle:Int, block:Bool):Dynamic;

	static function tls_create():Int;
	static function tls_get(handle:Int):Dynamic;
	static function tls_set(handle:Int, value:Dynamic):Void;

	static function thread_current():Int;
	static function thread_create(job:() -> Void):Int;
	static function thread_send_message(targetHandle:Int, message:Dynamic):Void;
	static function thread_read_message(block:Bool):Dynamic;
	static function thread_get_events(handle:Int):Dynamic;
	static function thread_set_events(handle:Int, eventLoop:Dynamic):Void;
}
