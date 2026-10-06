/** A reference field preserves null through constructor arguments and later writes. */
class Box {
	public var value:String;

	public function new(value:String) {
		this.value = value;
	}
}

/** Assertions distinguish null storage from empty strings and nullable scalar values. */
class Main {
	public static var completed:Bool = false;
	static var initial:String = null;
	static var wrappedText:Text<String> = null;

	static function echo(value:String):String {
		return value;
	}

	static function main():Void {
		var text:String = null;
		if (text != null)
			throw 'null local changed';
		text = '';
		if (null == text)
			throw 'empty string became null';
		text = null;
		if (text != null)
			throw 'null assignment changed';
		var number:Null<Int> = null;
		if (number != null)
			throw 'nullable scalar lost null';
		number = 2;
		if (number == null)
			throw 'nullable scalar lost value';
		var box:Box = null;
		if (box != null)
			throw 'null instance changed';
		box = new Box(null);
		if (box.value != null)
			throw 'constructor argument changed';
		box.value = 'value';
		box.value = null;
		if (box.value != null)
			throw 'null field write changed';
		if (echo(null) != null)
			throw 'null call argument changed';
		final read = function():String {
			return null;
		};
		if (read() != null)
			throw 'null closure result changed';
		if (initial != null)
			throw 'null static initializer changed';
		if (wrappedText != null)
			throw 'abstract backing lost null';
		initial = 'present';
		initial = null;
		if (initial != null)
			throw 'null static write changed';
		if (('x' + null) != 'xnull')
			throw 'null text conversion changed';
		final values:Array<String> = [null, ''];
		var count = 0;
		for (value in values)
			if (value == null)
				count++;
		if (count != 1)
			throw 'array literal lost its null element';
		final copied:Array<String> = [for (value in values) value];
		var copiedCount = 0;
		for (value in copied)
			if (value == null)
				copiedCount++;
		if (copiedCount != 1)
			throw 'array append lost its null element';
		completed = true;
	}
}

/** Nullability follows substituted backing storage without granting an implicit conversion. */
abstract Text<T>(T) {}
