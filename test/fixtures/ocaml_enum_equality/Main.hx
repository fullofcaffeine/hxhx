enum Choice {
	First;
	Last;
	Number(value:Int);
	Text(value:String);
	Nested(value:Choice);

	/** Dynamic is the public payload boundary under test; values must retain their runtime kind and identity. */
	Value(value:Dynamic);
}

class Main {
	static function pair(left:Int, right:Int):Int {
		return left * 10 + right;
	}

	static function number(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	static function operand(label:String, value:Int):Choice {
		Sys.println(label);
		return Choice.Number(value);
	}

	static function main():Void {
		Sys.println(Type.enumEq(Choice.First, Choice.First));
		Sys.println(Type.enumEq(Choice.First, Choice.Last));
		Sys.println(Type.enumEq(Choice.Number(3), Choice.Number(3)));
		Sys.println(Type.enumEq(Choice.Number(3), Choice.Number(4)));
		Sys.println(Type.enumEq(Choice.Text("same"), Choice.Text("same")));
		Sys.println(Type.enumEq(Choice.Text("same"), Choice.Text("different")));
		Sys.println(Type.enumEq(Choice.Nested(Choice.Number(3)), Choice.Nested(Choice.Number(3))));
		Sys.println(Type.enumEq(Choice.Nested(Choice.Number(3)), Choice.Nested(Choice.Number(4))));
		Sys.println(Type.enumEq(Choice.Value(true), Choice.Value(true)));
		Sys.println(Type.enumEq(Choice.Value(true), Choice.Value(1)));
		Sys.println(Type.enumEq(Choice.Value(null), Choice.Value(null)));
		Sys.println(Type.enumEq(Choice.Value(null), Choice.Value(0)));
		final object = {value: 3};
		Sys.println(Type.enumEq(Choice.Value(object), Choice.Value(object)));
		Sys.println(Type.enumEq(Choice.Value(object), Choice.Value({value: 3})));
		Sys.println(Type.enumEq(operand("left", 7), operand("right", 7)));
		final __hx_call_function = 8;
		final __hx_call_argument_0 = 9;
		Sys.println(pair(number("plain-left", __hx_call_function), number("plain-right", __hx_call_argument_0)));
	}
}
