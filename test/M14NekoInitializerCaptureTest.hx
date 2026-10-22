/** Field-owned closures must retain shared storage without borrowing a method's catalog. */
class M14NekoInitializerCaptureTest {
	/** Initializers retain operand identity and reject foreign owners or function-only exits. */
	static function adapter():Void {
		final position = HxPos.unknown();
		final value:HxExpr = EInt(7);
		final body:HxExpr = ELoweredControl(Initializer(true), "field", [value], position);
		final projected = TypedControlStatements.initializerBody(body, "field");
		if (projected.value != value || projected.statements.length != 0)
			throw "initializer adapter replaced its final operand";
		function rejected(expression:HxExpr):Void {
			try {
				TypedControlStatements.initializerBody(expression, "field");
			} catch (_:String) {
				return;
			}
			throw "invalid initializer control was accepted";
		}
		rejected(ELoweredControl(Initializer(true), "other", [value], position));
		rejected(ELoweredControl(Initializer(true), "field", [], position));
		rejected(ELoweredControl(Initializer(false), "field", [ELoweredControl(Return, "", [], position)], position));
		rejected(ELoweredControl(Initializer(false), "field", [ELoweredControl(Return, "method", [], position)], position));
		rejected(ELoweredControl(Initializer(false), "field", [ELoweredControl(Break, "loop", [], position)], position));
		final abrupt = TypedControlStatements.initializerBody(ELoweredControl(Initializer(false), "field", [ELoweredControl(Throw, "", [value], position)],
			position), "field");
		if (abrupt.value != null || abrupt.statements.length != 1)
			throw "initializer adapter discarded abrupt completion";
	}

	static function main():Void {
		adapter();
		#if neko_capture_initializer_static
		#if neko_capture_initializer_block
		final source = 'class Main {
static var next:Void->Int = { var value = 10; function():Int { value = value + 1; return value; }; };
static function main():Void { Sys.println(next()); Sys.println(next()); }
}';
		final expected = "11\n12\n";
		final name = "initializer_block";
		#else
		final source = 'class Main {
static var make:Int->(Void->Int) = function(value:Int):Void->Int {
return function():Int { value = value + 1; return value; };
};
static function main():Void {
var first = make(10); var second = make(20);
Sys.println(first()); Sys.println(first()); Sys.println(second());
}
}';
		final expected = "11\n12\n21\n";
		final name = "initializer_lambda";
		#end
		#else
		#if neko_capture_initializer_block
		final source = 'class Holder {
public var next:Void->Int = { var value = 10; function():Int { value = value + 1; return value; }; };
public function new() {}
} class Main { static function main():Void { var holder = new Holder(); Sys.println(holder.next()); Sys.println(holder.next()); var other = new Holder(); Sys.println(other.next()); } }';
		final expected = "11\n12\n11\n";
		final name = "instance_initializer_block";
		#else
		final source = 'class Holder {
public var make:Int->(Void->Int) = function(value:Int):Void->Int { return function():Int { value = value + 1; return value; }; };
public function new() {}
} class Main { static function main():Void {
var holder = new Holder(); var first = holder.make(10); var second = holder.make(20);
Sys.println(first()); Sys.println(first()); Sys.println(second());
} }';
		final expected = "11\n12\n21\n";
		final name = "instance_initializer_lambda";
		#end
		#end
		@:privateAccess M14NekoClosureControlTest.assertSource(name, source, expected);
		#if (!neko_capture_initializer_static && neko_capture_initializer_block)
		@:privateAccess M14NekoClosureControlTest.assertSource("instance_initializer_catch", 'class Holder {
public var next:Void->Int = try {throw 10;} catch(value:Dynamic) {function():Int {value=value+1; return value;};};
public function new() {}
} class Main {static function main():Void {var first=new Holder(); var second=new Holder(); Sys.println(first.next()); Sys.println(first.next()); Sys.println(second.next());}}',
			"11\n12\n11\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("instance_initializer_order", 'class Holder {
public var value:Int = {Sys.println("start"); var value=0; while(value<3) {value=value+1;} if(value==3) {value=value+4;} Sys.println("end"); value;};
public function new() {Sys.println("constructor");}
} class Main {static function main():Void {var first=new Holder(); Sys.println(first.value); var second=new Holder(); Sys.println(second.value);}}',
			"start\nend\nconstructor\n7\nstart\nend\nconstructor\n7\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("instance_initializer_throw", 'class Holder {
public var value:Int = {Sys.println("before"); throw "stop";};
public function new() {Sys.println("bad");}
} class Main {static function main():Void {try {var holder=new Holder(); Sys.println("bad");} catch(error:Dynamic) {Sys.println(error);}}}', "before\nstop\n");
		#end

		#if (!neko_capture_initializer_static && !neko_capture_initializer_block)
		@:privateAccess M14NekoClosureControlTest.assertSource("instance_initializer_pair", 'class Holder {
public var make:Int->({read:Void->Int, write:Void->Void}) = function(value:Int):{read:Void->Int, write:Void->Void} {
return {read:function():Int {return value;}, write:function():Void {value = value + 1;}};
};
public function new() {}
} class Main { static function main():Void {
var holder = new Holder(); var first = holder.make(10); var second = holder.make(20);
first.write(); Sys.println(first.read()); first.write(); Sys.println(first.read()); Sys.println(second.read());
} }', "11\n12\n20\n");
		#end
	}
}
