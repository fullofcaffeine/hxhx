/** Observe lazy creation, repeated identity, reset, and retained old values. */
class CacheFixture {
	static function main():Void {
		final first = Cache.get();
		Sys.println(Peer.calculate(4));
		Sys.println(first == Cache.get());
		Cache.clear();
		final second = Cache.get();
		Sys.println(first == second);
		Sys.println(second.apply(5));
		Sys.println(first.apply(6));
		final state = Cache.getState();
		Sys.println(state.value);
		Sys.println(state.apply(4));
		Sys.println(state == Cache.getState());
		Cache.clear();
		Sys.println(state == Cache.getState());
		Sys.println(state.value);
		Sys.println(state.apply(6));
	}
}
