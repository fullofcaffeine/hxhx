import haxe.exceptions.ArgumentException;
import haxe.exceptions.NotImplementedException;
import haxe.exceptions.PosException;

class Main {
	static function main() {
		final pos = {
			fileName: "Demo.hx",
			lineNumber: 42,
			className: "Demo",
			methodName: "run"
		};

		final arg = new ArgumentException("age", null, null, pos);
		final notImplemented = new NotImplementedException("TODO", arg, pos);
		final posException = new PosException("Boom", notImplemented, pos);

		Sys.println("arg.name=" + arg.argument);
		Sys.println("arg.msg=" + arg.message);
		Sys.println("notimpl.msg=" + notImplemented.message);
		Sys.println("notimpl.prev=" + notImplemented.previous.message);
		Sys.println("pos.msg=" + posException.message);
		Sys.println("pos.loc=" + posException.posInfos.className + "." + posException.posInfos.methodName + "@" + posException.posInfos.fileName + ":"
			+ posException.posInfos.lineNumber);
	}
}
