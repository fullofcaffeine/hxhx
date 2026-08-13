class Holder {
	public final value:ReferenceValue;

	public function new(value:ReferenceValue) {
		this.value = value;
	}
}

class ReferenceValue {
	public final label:String;

	public function new(label:String) {
		this.label = label;
	}
}

class Main {
	static function main() {
		final holder = new Holder(new ReferenceValue("later declaration"));
		Sys.println(holder.value.label);
		final separate = new SeparateHolder(new SeparateValue("separate module"));
		Sys.println(separate.value.label);
	}
}
