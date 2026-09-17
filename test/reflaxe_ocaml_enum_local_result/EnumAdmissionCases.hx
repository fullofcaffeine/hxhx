/** Small independent source shapes for enum-result admission classification. */
class EnumAdmissionCases {
	public function new() {}

	public function direct():Payload
		return Text("direct");

	public function forwarded():Payload
		return direct();

	public function alternateForwarded():Payload
		return constructedLocal();

	public static function freshReceiverForwarded():Payload
		return new EnumAdmissionCases().direct();

	public function foreign(receiver:EnumAdmissionCases):Payload
		return receiver.direct();

	public function nullable():Null<Payload>
		return Empty;

	public function generic():AdmissionGeneric<Int>
		return Item(1);

	public function retained():Payload {
		final value = forwarded();
		Sys.println("effect");
		return value;
	}

	public function retainedAfterPriorEffect():Payload {
		Sys.println("prior effect");
		final value = forwarded();
		Sys.println("later effect");
		return value;
	}

	public function retainedAcrossGuard(flag:Bool):Payload {
		final value = forwarded();
		if (flag)
			Sys.println("guard");
		return value;
	}

	public function controlledDependencies(flag:Bool):Payload {
		if (flag)
			return forwarded();
		return constructedLocal();
	}

	public function controlledThrow(flag:Bool):Payload {
		if (flag)
			return direct();
		throw "expected fixture throw";
	}

	public function constructedLocal():Payload {
		final value = Payload.Text("local");
		Sys.println("effect");
		return value;
	}

	/** Deliberate unsafe input: its annotation must never authorize a native carrier. */
	public function castValue(value:Dynamic):Payload
		return cast value;

	public function replaced():Payload {
		var value = direct();
		value = Empty;
		return value;
	}

	public function captured():Payload {
		final value = direct();
		final read = () -> value;
		read();
		return value;
	}

	public function selfCycle():Payload
		return selfCycle();

	public function cycleLeft():Payload
		return cycleRight();

	public function cycleRight():Payload
		return cycleLeft();

	public function dependsOnCycle():Payload
		return cycleLeft();

	public function alternative(flag:Bool):Payload
		return flag ? Empty : direct();
}

/** Generic variants remain outside the first native result contract. */
enum AdmissionGeneric<T> {
	Item(value:T);
}
