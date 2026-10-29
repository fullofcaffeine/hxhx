/** Verifies optional method slots without weakening the concrete callback result type. */
class Main {
	static function main():Void {
		final scope = new Scope();
		final value = new Value([7]);
		var calls = 0;
		final build = () -> {
			calls++;
			return value;
		};
		final supplied = scope.within(() -> Peer.produce(build), value);
		final omitted = scope.within(() -> Peer.produce(build));
		final explicitNull = scope.within(() -> Peer.produce(build), null);
		if (supplied != value || omitted != value || explicitNull != value)
			throw "optional call lost result identity";
		supplied.items.push(9);
		final nested = scope.within(() -> scope.within(() -> Peer.produce(build)));
		if (nested != value || scope.depth != 0)
			throw "nested call lost identity or scope restoration";
		final defaulted = scope.withDefault(() -> Peer.produce(build));
		final selected = scope.withDefault(() -> Peer.produce(build), 5);
		if (defaulted != value || selected != value)
			throw "defaulted call lost result identity";
		if (!scope.within(() -> true) || scope.within(() -> 17) != 17)
			throw "omitted argument changed a primitive callback result";
		final source = Peer.source(value);
		if (scope.withSource(source, value, () -> Peer.produce(build), value) != value
			|| scope.withSource(source, value, () -> Peer.produce(build)) != value)
			throw "enum argument changed callback identity";
		var caught = false;
		try {
			scope.within(() -> {
				throw "expected";
				return Peer.produce(build);
			});
		} catch (error:String) {
			caught = error == "expected";
		}
		Sys.println(value.items.join(","));
		Sys.println("calls=" + calls);
		Sys.println("depth=" + scope.depth);
		Sys.println("optional=" + scope.optional);
		Sys.println("defaults=" + scope.defaults);
		Sys.println("sources=" + scope.sources);
		Sys.println("exception=" + caught);
	}
}
