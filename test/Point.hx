class Point {
	public var x:Int;
	public var y:Int;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}

	public function incX():Void {
		this.x = this.x + 1;
	}

	public function add(dx:Int, dy:Int):Void {
		this.x = this.x + dx;
		this.y = this.y + dy;
	}

	public function sum():Int {
		return this.x + this.y;
	}
}

