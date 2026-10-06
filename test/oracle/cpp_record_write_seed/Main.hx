/** Independently observe evaluation order, assignment results, aliases, and failed operands. */
class Main {
	static function main():Void {
		final args = Sys.args();
		if (args.length > 0 && args[0] == "null") {
			try {
				RecordWrite.assign(() -> {
					Sys.println("receiver");
					return null;
				}, () -> {
					Sys.println("value");
					return true;
				});
				Sys.println("returned");
			} catch (_:Dynamic) {
				Sys.println("caught");
			}
			return;
		}
		for (discard in [false, true]) {
			for (failure in ["none", "receiver", "value"]) {
				var effects = "";
				final record:{item:Dynamic} = {item: false};
				final alias = record;
				final receiver = () -> {
					effects += "R";
					if (failure == "receiver")
						throw "receiver-failure";
					return record;
				};
				final value = () -> {
					effects += "V";
					if (failure == "value")
						throw "value-failure";
					return true;
				};
				var outcome = "discarded";
				try {
					if (discard)
						RecordWrite.discard(receiver, value);
					else
						outcome = Std.string(RecordWrite.assign(receiver, value));
				} catch (caught:Dynamic) {
					outcome = Std.string(caught);
				}
				Sys.println(discard + ":" + failure + ":" + effects + ":" + outcome + ":" + alias.item);
			}
		}
		var effects = "";
		final record = {item: "before"};
		final result = RecordWrite.text(() -> {
			effects += "R";
			return record;
		}, () -> {
			effects += "V";
			return "after";
		});
		Sys.println("text:" + effects + ":" + result + ":" + record.item);
		effects = "";
		final outer = {inner: record};
		final nested = RecordWrite.nested(() -> {
			effects += "R";
			return outer;
		}, () -> {
			effects += "V";
			return "nested";
		});
		Sys.println("nested:" + effects + ":" + nested + ":" + record.item);
		Sys.println("local:" + RecordWrite.local(true) + ":" + RecordWrite.local(false));
		final box:{item:{name:String}} = {item: null};
		final payload = {name: "payload"};
		final assigned = RecordWrite.object(() -> box, () -> payload);
		Sys.println("object:" + (assigned == payload) + ":" + (box.item == payload));
		final optional:RecordWrite.OptionalRecord = {};
		Sys.println("optional:" + RecordWrite.optional(() -> optional, () -> true) + ":" + optional.item);
	}
}
