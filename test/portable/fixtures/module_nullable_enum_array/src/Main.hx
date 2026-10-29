/** Independent runtime observer for payload identity and producer evaluation. */
class Main {
	static function main() {
		final payload = [7];
		final holder = new Holder(Payload(payload));
		final out:Array<Choice> = [];
		Collector.from(holder, out);
		switch out[0] {
			case Payload(values):
				values.push(9);
			case Empty:
				throw "missing payload";
		}
		final absent = new Holder(null);
		Collector.from(absent, out);
		Sys.println(payload.join(","));
		Sys.println('length=${out.length}');
		Sys.println('reads=${holder.reads},${absent.reads}');
		ElementOperations.run(holder.value);
	}
}
