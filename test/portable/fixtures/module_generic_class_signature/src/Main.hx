import model.Payload;
import model.OtherPayload;
import model.EmptyPayload;

/** Observes identity, mutations, null, callback effects and state after failure. */
class Main {
	static function main():Void {
		final scope = new Scope();
		final original = new Payload(7);
		scope.values.push(original);
		scope.retained = {value: original};
		original.children.push(original);
		original.parent = original;
		var calls = 0;
		final returned:Payload = scope.within(() -> {
			calls++;
			if (!scope.active)
				throw "inactive callback";
			return original;
		});
		returned.count = 9;
		Sys.println(returned == original);
		Sys.println(original.count);
		Sys.println(calls);
		Sys.println(scope.active);
		final absent:Null<Payload> = scope.within(() -> (null : Null<Payload>));
		Sys.println(absent == null);
		final present:Null<Payload> = scope.within(() -> (original : Null<Payload>));
		Sys.println(present == original);
		final mapped = scope.map(original, value -> {
			value.count++;
			return value;
		});
		Sys.println(mapped == original);
		Sys.println(original.count);
		final other = new OtherPayload(12);
		Sys.println(scope.within(() -> other) == other);
		var caught = false;
		try {
			scope.within(() -> {
				if (scope.active)
					throw "class failure";
				return original;
			});
		} catch (error:Dynamic) {
			// Compare the expected String immediately at the arbitrary exception boundary.
			caught = error == "class failure";
		}
		Sys.println(caught);
		Sys.println(scope.active);
		Sys.println(scope.values[0] == returned);
		Sys.println(scope.retained.value == returned);
		Sys.println(returned.children[0] == returned && returned.parent == returned);
		final empty = new EmptyPayload();
		final otherEmpty = new EmptyPayload();
		Sys.println(scope.within(() -> empty) == empty);
		Sys.println(scope.within(() -> otherEmpty) != empty);
	}
}
