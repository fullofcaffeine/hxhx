/** Independent upstream observation of the same source methods used by the native heap test. */
class Main {
	static function main():Void {
		Sys.println(GuardedSwitch.scalar(1));
		Sys.println(GuardedSwitch.scalar(2));
		final values = [1, 2];
		Sys.println(GuardedSwitch.observed(values));
		Sys.println(values[1]);
		final escaped = new Array<Void->Int>();
		final selected = GuardedSwitch.capture([1, 7], callback -> {
			escaped.push(callback);
			return false;
		});
		Sys.println(escaped[0]());
		Sys.println(selected());
		final nested = [[23]];
		final retained = GuardedSwitch.retained(nested, () -> {
			nested[0] = null;
			return false;
		});
		Sys.println(retained[0]);
		Sys.println(GuardedSwitch.nested(1)());
		Sys.println(GuardedSwitch.loops());
		Sys.println(GuardedSwitch.record({items: [1, 2]}));
		var effects = 0;
		Sys.println(GuardedSwitch.enumSelect(GuardedSwitch.enumValue(), value -> {
			effects = effects * 10 + value;
			return value == 2;
		}));
		Sys.println(effects);
		final alternatives = new Array<Void->Int>();
		Sys.println(GuardedSwitch.alternatives([1, 2], callback -> {
			alternatives.push(callback);
			return false;
		}));
		Sys.println(alternatives[0]());
		Sys.println(alternatives[1]());
		var calls = 0;
		final effect = (value:Int) -> {
			calls += value;
			return false;
		};
		Sys.println(GuardedSwitch.effectfulTrue(1, effect));
		Sys.println(GuardedSwitch.effectfulTrue(2, effect));
		Sys.println(calls);
		calls = 0;
		final runtimeEffect = (value:Int) -> {
			calls = calls * 10 + value;
			return value >= 2;
		};
		Sys.println(GuardedSwitch.runtimeGuard(1, runtimeEffect));
		Sys.println(GuardedSwitch.runtimeGuard(2, runtimeEffect));
		Sys.println(GuardedSwitch.runtimeGuard(3, runtimeEffect));
		Sys.println(calls);
		calls = 0;
		Sys.println(GuardedSwitch.guardThenFallback(1, runtimeEffect));
		Sys.println(GuardedSwitch.guardThenFallback(2, runtimeEffect));
		Sys.println(calls);
	}
}
