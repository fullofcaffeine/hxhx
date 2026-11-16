/**
	A local initialized with bare `null` has no useful type yet. Assigning an
	Int to it in an argument (`takeInt(n = 2)`) must type the assignment as the
	assigned Int, as upstream Haxe 4.3.7 does, so the call is accepted.
**/
class Main {
	static function takeInt(i:Int):Void {
		Sys.println("int " + i);
	}

	static function main():Void {
		var n = null;
		takeInt(n = 2);
		var m = null;
		m = 1;
		takeInt(m = 2);
	}
}
