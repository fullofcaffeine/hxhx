typedef Real = Float;

enum Color {
	Red;
	Green;
}

class Main {
	static final ratio:Real = 0.5;
	static final maybeRatio:Null<Float> = 0.25;
	static final count:Null<Int> = 3;
	static final color:Color = Red;
	static final point = {y: 2, x: 1};
	static final anything:Dynamic = 1;
	static final names:Array<String> = ["a"];

	static function half():Float
		return 0.5;

	static function scale(value:Float, ?times:Int):Float
		return value * (times == null ? 1 : times);

	static function main():Void {
		Sys.println("isFloat 1.5 " + TypeProbe.isFloat("1.5"));
		Sys.println("isFloat 1 " + TypeProbe.isFloat("1"));
		Sys.println("isFloat text " + TypeProbe.isFloat('"x"'));
		Sys.println("isFloat typedef " + TypeProbe.isFloat("Main.ratio"));
		Sys.println("isFloat null float " + TypeProbe.isFloat("Main.maybeRatio"));
		Sys.println("isFloat call " + TypeProbe.isFloat("Main.half()"));
		Sys.println("isFloat sqrt " + TypeProbe.isFloat("Math.sqrt(2)"));
		Sys.println("isFloat unknown " + TypeProbe.isFloat("missingName"));
		Sys.println(TypeProbe.describe('"text"'));
		Sys.println(TypeProbe.describe("1.5"));
		Sys.println(TypeProbe.describe("Main.count"));
		Sys.println(TypeProbe.describe("Main.color"));
		Sys.println(TypeProbe.describe("Main.point"));
		Sys.println(TypeProbe.describe("Main.anything"));
		Sys.println(TypeProbe.describe("Main.names"));
		Sys.println(TypeProbe.describe("Main.scale"));
	}
}
