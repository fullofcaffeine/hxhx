/** Checks enum payload identity, null preservation, and single evaluation. */
class Main {
	static function main() {
		final values = [7];
		final holder = new Holder(Payload(values));
		final result = holder.project().get();
		switch (result) {
			case Payload(items):
				items.push(9);
			case Empty:
				throw "missing payload";
		}
		Sys.println(values.join(","));
		Sys.println('reads=${holder.reads}');
		final absent = new Holder(null);
		final missing = absent.project().get();
		Sys.println('null=${missing == null}');
		Sys.println('nullReads=${absent.reads}');
	}
}
