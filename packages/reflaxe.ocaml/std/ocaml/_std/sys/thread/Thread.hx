package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target implementation of `sys.thread.Thread`.

	`Dynamic` usage is restricted to message/event payload boundaries mandated by
	the upstream API surface (`sendMessage/readMessage`, event-loop storage).
**/
class Thread {
	public var events(get, never):EventLoop;

	final handle:Int;

	private function new(handle:Int) {
		this.handle = handle;
	}

	function get_events():EventLoop {
		final currentLoop:Null<EventLoop> = cast NativeHxThread.thread_get_events(handle);
		if (currentLoop == null)
			throw new NoEventLoopException();
		return currentLoop;
	}

	public function sendMessage(msg:Dynamic):Void {
		NativeHxThread.thread_send_message(handle, msg);
	}

	public static function current():Thread {
		return new Thread(NativeHxThread.thread_current());
	}

	@:native("spawn")
	public static function create(job:() -> Void):Thread {
		return new Thread(NativeHxThread.thread_create(job));
	}

	public static function runWithEventLoop(job:() -> Void):Void {
		final thread = current();
		final existingLoop:Null<EventLoop> = cast NativeHxThread.thread_get_events(thread.handle);
		if (existingLoop != null) {
			job();
			return;
		}

		final created = new EventLoop();
		NativeHxThread.thread_set_events(thread.handle, created);
		job();
		created.loop();
		NativeHxThread.thread_set_events(thread.handle, null);
	}

	public static function createWithEventLoop(job:() -> Void):Thread {
		return create(() -> runWithEventLoop(job));
	}

	public static function readMessage(block:Bool):Dynamic {
		return NativeHxThread.thread_read_message(block);
	}

	static function processEvents():Void {
		current().events.loop();
	}
}
