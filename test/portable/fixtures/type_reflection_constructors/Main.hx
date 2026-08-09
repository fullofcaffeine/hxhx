/** Values created through Haxe's runtime enum-construction API. */
enum ReflectedChoice {
	Empty;
	Pair(enabled:Bool, label:String);
}

/** A class whose omitted arguments exercise each reflected null representation. */
class ReflectedConstructor {
	public final enabled:Bool;
	public final label:Null<String>;
	public final payload:Dynamic;
	public final count:Null<Int>;

	public function new(enabled:Bool, ?label:String, ?payload:Dynamic, ?count:Int) {
		this.enabled = enabled;
		this.label = label;
		this.payload = payload;
		this.count = count;
	}
}

/** Proves reflected class and enum construction through generated OCaml and its runtime. */
class Main {
	static function main():Void {
		final created:ReflectedConstructor = Type.createInstance(ReflectedConstructor, [true]);
		Sys.println(created.enabled);
		Sys.println(created.label == null);
		Sys.println(created.payload == null);
		Sys.println(created.count == null);

		final choice:ReflectedChoice = Type.createEnum(ReflectedChoice, "Pair", [true, "made"]);
		switch (choice) {
			case Pair(enabled, label):
				Sys.println(enabled && label == "made" ? label : "wrong");
			case Empty:
				Sys.println("wrong");
		}
	}
}
