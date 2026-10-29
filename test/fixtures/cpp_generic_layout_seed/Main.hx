/** Retain three real allocations so a native observer can check their declared storage defaults. */
class Main {
	public static var aInt:Box<Int>;
	public static var bString:Box<String>;
	public static var cLeaf:Leaf;

	static function main():Void {
		aInt = new Box<Int>();
		bString = new Box<String>();
		cLeaf = new Leaf();
	}
}

/** T starts null for both applications; the ordinary Int field starts at zero on native C++. */
class Box<T> {
	public var count:Int;
	public var value:T;

	public function new() {}
}

/** Forward the exact binder across an additional constructor-free class. */
class Middle<T> extends Box<T> {}

/** The applied parent prefix remains intact before this child's Boolean slot. */
class Leaf extends Middle<String> {
	public var flag:Bool;
}
