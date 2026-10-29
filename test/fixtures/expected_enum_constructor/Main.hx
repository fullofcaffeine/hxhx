import First;
import Second;

/** Observe selected constructor ownership, optional records, and enclosing switch context. */
class Main {
	static function first(value:First):String {
		return switch value {
			case First.Build(text, record): text + (record == null ? ":absent" : ":" + record.name);
		};
	}

	static function main():Void {
		final expected:First = Build("expected", {name: "record"});
		final absent:First = Build("optional");
		final qualified:First = First.Build("qualified", null);
		final branch:First = switch true {
			case true: Build("switch", null);
			case false: Build("wrong", null);
		};
		final fallback = Build(7, false);
		Sys.println(first(expected));
		Sys.println(first(absent));
		Sys.println(first(qualified));
		Sys.println(first(branch));
		Sys.println(switch fallback {
			case Second.Build(value, flag): Std.string(value) + ":" + Std.string(flag);
		});
	}
}
