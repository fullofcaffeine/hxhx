/** Abstract factories must return their backing value without inventing a runtime class descriptor. */
class M14NekoAbstractConstructionTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("abstract_construction", 'abstract Count(Int) to Int {
public function new(value:Int, stop:Bool=false) {
Main.events=Main.events+"body;";
this=value;
if(stop)return;
this=this+1;
}
}
class Cell {public var value:Int;public function new(value:Int){this.value=value;}}
abstract Wrapped(Cell) to Cell {public function new(value:Cell){this=value;}}
abstract Failing(Int) {public function new(){this=1;throw "stop";}}
class Main {
public static var events="";
static function argument():Int {events=events+"argument;";return 7;}
static function main():Void {
var first:Int=new Count(argument());Sys.println(events);Sys.println(first);
events="";var second:Int=new Count(argument(),true);Sys.println(events);Sys.println(second);
var cell=new Cell(12);var same:Cell=new Wrapped(cell);Sys.println(same==cell);Sys.println(same.value);
try {new Failing();} catch(error:Dynamic) {Sys.println(error);}
}
}', "argument;body;\n8\nargument;body;\n7\ntrue\n12\nstop\n");
	}
}
