package contract;

/** Public generic surface retained by the pre-DCE fixture snapshot. */
class ContractBox<T> extends ContractBase<T> implements ContractReadable<T> {
	public final envelope:ContractEnvelope<T>;

	public function new(value:T) {
		super(value);
		this.envelope = {value: value};
	}

	public function read():T {
		return value;
	}

	@:overload(function(value:Int):String {})
	public function format(value:String):String {
		return value;
	}

	public function unusedRuntimeMember():String {
		return "unused";
	}
}

/** Generic parent used to retain the authored superclass parameter. */
class ContractBase<T> {
	final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/** Public interface used to verify generic parent facts. */
interface ContractReadable<T> {
	function read():T;
}

/** Authored alias used to verify that source-level typedef identity survives. */
typedef ContractEnvelope<T> = {
	final value:T;
	final ?label:String;
}

/** Enum abstract used to verify source-level literal-union facts. */
enum abstract ContractMode(String) from String to String {
	var Ready = "ready";
	var Waiting = "waiting";
}
