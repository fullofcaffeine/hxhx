/** Dynamic is confined to the erased value boundary whose runtime tag controls formatting. */
class DynamicConcat {
	static var order:String = "";
	static var calls:Int = 0;

	static function erased(value:Dynamic):Dynamic {
		calls++;
		return value;
	}

	static function left():String {
		order += "L";
		return "value:";
	}

	static function right():Dynamic {
		order += "R";
		return true;
	}

	static function main():Void {
		if ("bool:" + erased(true) != "bool:true"
			|| erased(false) + ":bool" != "false:bool"
			|| "int:" + erased(7) != "int:7"
			|| erased(-3) + ":int" != "-3:int"
			|| "null:" + erased(null) != "null:null"
			|| erased("hé\x00z") + ":text" != "hé\x00z:text")
			throw "Dynamic concatenation changed its runtime value";
		if (calls != 6)
			throw "Dynamic concatenation repeated an operand";
		if (left() + right() != "value:true" || order != "LR")
			throw "Dynamic concatenation changed operand order";
		var compound = "start:";
		compound += erased(true);
		if (compound != "start:true" || calls != 7)
			throw "Dynamic compound concatenation changed value or effects";
	}
}
