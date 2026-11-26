class Main {
	static function main():Void {
		Sys.println("shift " + Specs.check('([1]:{function shift ():Null<Int>;}).shift() == 1'));
		Sys.println("pop " + Specs.check('([1]:{function pop ():Null<Int>;}).pop() == 1'));
		Sys.println("push " + Specs.check('([]:{function push (x:Int):Int;}).push(1) == 1'));
		Sys.println("join " + Specs.check('([1,2]:{function join (s:String):String;}).join(",") == "1,2"'));
		Sys.println("filter " + Specs.check('([1,2]:{function filter (s:Int->Bool):Array<Int>;}).filter(function (x) return x == 1).length == 1'));
		Sys.println("object " + Specs.check('({name: "spec", count: 2}:{var name:String; final count:Int;}).name'));
	}
}
