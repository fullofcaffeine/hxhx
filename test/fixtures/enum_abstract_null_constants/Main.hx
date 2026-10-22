/** Null members retain their enum declaration and distinct constant value. */
enum abstract State(String) {
	var Ready = "ready";
	var Missing = null;
	var Alias = Missing;
}

enum abstract NumberState(Int) {
	var Missing = null;
	var Zero = 0;
}

enum abstract TruthState(Bool) {
	var Missing = null;
	var Off = false;
	var On = true;
}

enum abstract NullableState(Null<String>) {
	var Missing = null;
}

/** Exercise null constants through parameter passing and named switch patterns. */
class Main {
	static function select(value:State):String {
		return switch (value) {
			case Alias: "missing";
			case Ready: "ready";
		};
	}

	static function literal(value:State):String {
		return switch (value) {
			case null: "null";
			case Ready: "ready";
		};
	}

	static function statement(value:State):Void {
		switch (value) {
			case Alias:
				Sys.println("statement-null");
			case Ready:
				Sys.println("statement-ready");
		}
	}

	static function nested(values:Array<State>):String {
		return switch (values) {
			case [State.Alias]: "nested-null";
			case [State.Ready]: "nested-ready";
			default: "nested-other";
		};
	}

	static function number(value:NumberState):String {
		return switch (value) {
			case Missing: "number-null";
			case Zero: "number-zero";
		};
	}

	static function truth(value:TruthState):String {
		return switch (value) {
			case Missing: "truth-null";
			case Off: "truth-off";
			case On: "truth-on";
		};
	}

	static function main():Void {
		Sys.println(State.Missing == null);
		Sys.println(State.Alias == null);
		Sys.println(NumberState.Missing == null);
		Sys.println(TruthState.Missing == null);
		Sys.println(NullableState.Missing == null);
		Sys.println(select(State.Missing));
		Sys.println(select(State.Ready));
		Sys.println(literal(State.Alias));
		statement(State.Missing);
		statement(State.Ready);
		Sys.println(nested([State.Alias]));
		Sys.println(nested([State.Ready]));
		Sys.println(nested([]));
		Sys.println(number(NumberState.Missing));
		Sys.println(number(NumberState.Zero));
		Sys.println(truth(TruthState.Missing));
		Sys.println(truth(TruthState.Off));
		Sys.println(truth(TruthState.On));
	}
}
