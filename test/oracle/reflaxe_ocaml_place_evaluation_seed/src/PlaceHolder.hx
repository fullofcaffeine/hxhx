/** Mutable receiver used to expose field and property evaluation behavior. */
class PlaceHolder {
	public var field:Int;
	public var property(get, set):Int;

	var storedProperty:Int;

	public function new() {
		field = 0;
		storedProperty = 0;
	}

	/** Resets storage without invoking the observable property setter. */
	public function reset(fieldValue:Int, propertyValue:Int):Void {
		field = fieldValue;
		storedProperty = propertyValue;
	}

	/** Reads the stored property value without adding a getter event. */
	public function rawProperty():Int {
		return storedProperty;
	}

	function get_property():Int {
		EventLog.record("get");
		return storedProperty;
	}

	function set_property(value:Int):Int {
		EventLog.record("set:" + value);
		storedProperty = value + 100;
		return value + 1000;
	}
}
