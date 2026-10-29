/** Observe key/value types, values, and mutation behavior in authored loops. */
class Main {
	static function main():Void {
		Extractors.run();
		if (!Std.isOfType("word", String) || Std.isOfType(7, String) || !Std.isOfType([1], Array) || Std.isOfType("word", Array))
			throw "runtime type checks after Std.string initialization";
		final data = ["left" => [1], "right" => [2]];
		var labels = "";
		for (label => stacks in data)
			labels += label + ":" + stacks.length + ";";
		if (labels != "left:1;right:1;")
			throw "map pair values";
		final objectData = ["01" => 2, "alpha" => 3];
		var keys = "";
		var count = 0;
		for (key => value in objectData) {
			if (!Std.isOfType(key, String))
				throw "object key type";
			keys += key + ";";
			count++;
			objectData.set("later", 9);
		}
		if (keys != "01;alpha;" || count != 2)
			throw "object key snapshot";
		final values = [3, 2];
		var seen = "";
		var numericKeys = 0;
		for (key => value in values) {
			numericKeys += key + 1;
			seen += key + ":" + value + ";";
			if (key == 0)
				values.push(5);
		}
		if (seen != "0:3;1:2;2:5;" || numericKeys != 6)
			throw "live array length or numeric keys";
	}
}
