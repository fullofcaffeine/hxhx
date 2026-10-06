/** Initializers own their locals even when a constructor uses the same source name. */
class Holder {
	public var number:Int = {
		var int = 3;
		var int_ = 4;
		int + int_;
	};
	public var word:String = {
		var int = "left";
		var int_ = "right";
		int + ":" + int_;
	};

	public function new(int:Int) {
		Sys.println(int);
	}
}

/** Observe each initializer and the constructor through ordinary Haxe field reads. */
class Main {
	static function main():Void {
		var holder = new Holder(99);
		Sys.println(holder.number);
		Sys.println(holder.word);
	}
}
