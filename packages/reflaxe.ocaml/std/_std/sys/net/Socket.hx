package sys.net;

import haxe.io.Input;
import haxe.io.Output;
import haxe.io.Eof;

/**
	OCaml target override for `sys.net.Socket`.

	Why
	- Upstream declares `Socket` as extern.
	- The OCaml portable lane needs a concrete class/module so generated code can type-check
	  and run fixture-level constructor/close paths without unresolved extern modules.

	What
	- Preserves the upstream API surface.
	- Provides a deterministic fallback implementation:
	  - constructor + `close()` succeed,
	  - network operations throw "Not available on this platform".

	Notes
	- This is a compatibility scaffold, not a full socket implementation.
**/
class Socket {
	public var input(default, null):Input;
	public var output(default, null):Output;
	public var custom:Dynamic;

	@:ifFeature("sys.net.Socket.select") var socket:Dynamic;

	public function new():Void {
		init(null);
	}

	function init(socket:Dynamic):Void {
		this.socket = socket;
		input = new UnavailableSocketInput();
		output = new UnavailableSocketOutput();
		custom = null;
	}

	public function close():Void {}

	public function read():String {
		throw "Not available on this platform";
	}

	public function write(content:String):Void {
		throw "Not available on this platform";
	}

	public function connect(host:Host, port:Int):Void {
		throw "Not available on this platform";
	}

	public function listen(connections:Int):Void {
		throw "Not available on this platform";
	}

	public function shutdown(read:Bool, write:Bool):Void {
		throw "Not available on this platform";
	}

	public function bind(host:Host, port:Int):Void {
		throw "Not available on this platform";
	}

	public function accept():Socket {
		throw "Not available on this platform";
	}

	public function peer():{host:Host, port:Int} {
		throw "Not available on this platform";
	}

	public function host():{host:Host, port:Int} {
		throw "Not available on this platform";
	}

	public function setTimeout(timeout:Float):Void {
		throw "Not available on this platform";
	}

	public function waitForRead():Void {
		throw "Not available on this platform";
	}

	public function setBlocking(b:Bool):Void {
		throw "Not available on this platform";
	}

	public function setFastSend(b:Bool):Void {
		throw "Not available on this platform";
	}

	public static function select(read:Array<Socket>, write:Array<Socket>, others:Array<Socket>,
			?timeout:Float):{read:Array<Socket>, write:Array<Socket>, others:Array<Socket>} {
		throw "Not available on this platform";
	}
}

private class UnavailableSocketInput extends Input {
	public function new() {}

	public override function readByte():Int {
		throw new Eof();
	}
}

private class UnavailableSocketOutput extends Output {
	public function new() {}

	public override function writeByte(c:Int):Void {
		throw new Eof();
	}
}
