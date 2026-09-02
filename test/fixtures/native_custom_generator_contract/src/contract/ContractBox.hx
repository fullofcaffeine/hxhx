package contract;

/** Public generic surface retained by the pre-DCE fixture snapshot. */
class ContractBox<T> implements ContractReadable<T> {
	final value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function read():T {
		return value;
	}
}

/** Public interface used to verify generic parent facts. */
interface ContractReadable<T> {
	function read():T;
}

/** Authored alias used to verify that source-level typedef identity survives. */
typedef ContractEnvelope<T> = {
	final value:T;
}

/** Enum abstract used to verify source-level literal-union facts. */
enum abstract ContractMode(String) from String to String {
	var Ready = "ready";
	var Waiting = "waiting";
}
