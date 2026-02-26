package sys.thread;

/**
	When an event loop has an available event to execute.
**/
enum NextEventTime {
	Now;
	Never;
	AnyTime(time:Null<Float>);
	At(time:Float);
}

class RegularEvent {
	public final callback:() -> Void;
	public final intervalSeconds:Float;
	public var nextRunAt:Float;
	public var cancelled:Bool;

	public function new(callback:() -> Void, nextRunAt:Float, intervalSeconds:Float) {
		this.callback = callback;
		this.intervalSeconds = intervalSeconds;
		this.nextRunAt = nextRunAt;
		this.cancelled = false;
	}
}

/**
	Handle returned by `EventLoop.repeat(...)`.
**/
class EventHandler {
	public final regular:RegularEvent;

	public function new(regular:RegularEvent) {
		this.regular = regular;
	}
}

/**
	Minimal OCaml-target event loop compatible with `sys.thread.Thread.events`.
**/
class EventLoop {
	final mutex = new Mutex();
	final wakeLock = new Lock();
	final oneTimeEvents:Array<() -> Void>;
	final regularEvents:Array<RegularEvent>;
	var promisedEvents:Int = 0;

	public function new():Void {
		oneTimeEvents = [];
		regularEvents = [];
	}

	static function invokeCallback(callback:() -> Void):Void {
		Reflect.callMethod(null, cast callback, []);
	}

	public function repeat(event:() -> Void, intervalMs:Int):EventHandler {
		final intervalSeconds = intervalMs <= 0 ? 0.001 : (intervalMs / 1000.0);
		final regular = new RegularEvent(event, Sys.time() + intervalSeconds, intervalSeconds);
		mutex.acquire();
		regularEvents.push(regular);
		mutex.release();
		wakeLock.release();
		return new EventHandler(regular);
	}

	public function cancel(eventHandler:EventHandler):Void {
		final regular = eventHandler.regular;
		regular.cancelled = true;
		wakeLock.release();
	}

	public function promise():Void {
		mutex.acquire();
		promisedEvents++;
		mutex.release();
		wakeLock.release();
	}

	public function run(event:() -> Void):Void {
		mutex.acquire();
		oneTimeEvents.push(event);
		mutex.release();
		wakeLock.release();
	}

	public function runPromised(event:() -> Void):Void {
		mutex.acquire();
		if (promisedEvents > 0)
			promisedEvents--;
		oneTimeEvents.push(event);
		mutex.release();
		wakeLock.release();
	}

	public function progress():NextEventTime {
		final ready:Array<() -> Void> = [];
		var hasAnyTime = false;
		var nextAt:Null<Float> = null;

		mutex.acquire();
		while (oneTimeEvents.length > 0) {
			final event = oneTimeEvents.shift();
			if (event != null)
				ready.push(event);
		}

		final now = Sys.time();
		for (regular in regularEvents) {
			if (regular == null || regular.cancelled)
				continue;
			if (regular.nextRunAt <= now) {
				ready.push(regular.callback);
				regular.nextRunAt = now + regular.intervalSeconds;
			}
			if (nextAt == null || regular.nextRunAt < nextAt) {
				nextAt = regular.nextRunAt;
			}
		}
		if (promisedEvents > 0) {
			hasAnyTime = true;
		}
		mutex.release();

		for (event in ready) {
			invokeCallback(event);
		}

		if (ready.length > 0)
			return Now;
		if (nextAt == null) {
			return hasAnyTime ? AnyTime(null) : Never;
		}
		return hasAnyTime ? AnyTime(nextAt) : At(nextAt);
	}

	function waitForNext(next:NextEventTime, ?timeout:Float):Void {
		switch (next) {
			case Never:
			case Now:
			case AnyTime(nextTime):
				if (timeout == null) {
					if (nextTime == null) {
						wakeLock.wait();
					} else {
						wakeLock.wait(Math.max(0.0, nextTime - Sys.time()));
					}
				} else if (nextTime == null) {
					wakeLock.wait(Math.max(0.0, timeout));
				} else {
					wakeLock.wait(Math.min(Math.max(0.0, timeout), Math.max(0.0, nextTime - Sys.time())));
				}
			case At(nextTime):
				final delay = Math.max(0.0, nextTime - Sys.time());
				if (timeout == null) {
					wakeLock.wait(delay);
				} else {
					wakeLock.wait(Math.min(delay, Math.max(0.0, timeout)));
				}
		}
	}

	public function wait(?timeout:Float):Bool {
		final next = progress();
		switch (next) {
			case Never:
				return false;
			case Now:
				return true;
			case AnyTime(_) | At(_):
				waitForNext(next, timeout);
				return switch (progress()) {
					case Never: false;
					case _: true;
				};
		}
	}

	public function loop():Void {
		while (true) {
			final next = progress();
			switch (next) {
				case Never:
					return;
				case Now:
				case AnyTime(_) | At(_):
					waitForNext(next);
			}
		}
	}
}
