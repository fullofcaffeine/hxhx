package haxe;

import haxe.CallStack.StackItem;

private typedef NativeTrace = {
	final skip:Int;
	final stack:Array<String>;
}

/**
	`haxe.NativeStackTrace` (OCaml target).

	WHY
	- The upstream Haxe stdlib declares `haxe.NativeStackTrace` as `extern`.
	  For Reflaxe custom targets that means no implementation is emitted unless we
	  provide one.
	- `haxe.CallStack.*` and `haxe.Exception.stack` are implemented on top of this.

	WHY THIS LIVES UNDER `std/ocaml/_std`
	- This is a normal OCaml stdlib override in the Reflaxe-generated source
	  layout: `std` contains target APIs, and `std/ocaml/_std` contains target
	  replacements for upstream stdlib modules.
	- Local source builds receive this directory through explicit dev/test
	  classpaths, matching Reflaxe's generated-compiler workflow.
	- Published haxelib packages are flattened by `haxelib run reflaxe build`;
	  this source file becomes `src/haxe/NativeStackTrace.cross.hx` in that
	  package.
	- The internal `#if ocaml_output` keeps the real implementation target-gated
	  even in flattened packages where `.cross.hx` is visible to custom targets.
**/
@:dox(hide)
@:noCompletion
#if ocaml_output
class NativeStackTrace {
	/**
		No-op for now.

		Some targets store stack information directly on a native exception object.
		For OCaml we query `Printexc` in `exceptionStack()`.
	**/
	@:ifFeature('haxe.NativeStackTrace.exceptionStack')
	static public inline function saveStack(_exception:Any):Void {}

	static public inline function callStack():NativeTrace {
		return {
			skip: 1,
			stack: untyped __ocaml__("(HxBacktrace.callstack_lines 64)")
		};
	}

	static public inline function exceptionStack():NativeTrace {
		return {
			skip: 0,
			stack: untyped __ocaml__("(HxBacktrace.exceptionstack_lines ())")
		};
	}

	static function parseFileLine(line:String):Null<{file:String, line:Int}> {
		// We avoid using `EReg` here on purpose:
		// - it's unnecessary for this “best effort” parsing,
		// - and it keeps `haxe.NativeStackTrace` independent from regex lowering details.
		final fileNeedle = 'file "';
		final fileStart0 = line.indexOf(fileNeedle);
		if (fileStart0 < 0)
			return null;
		final fileStart = fileStart0 + fileNeedle.length;
		final fileEnd = line.indexOf('"', fileStart);
		if (fileEnd < 0)
			return null;
		final file = line.substr(fileStart, fileEnd - fileStart);

		final lineNeedle = "line ";
		final lineStart0 = line.indexOf(lineNeedle, fileEnd);
		if (lineStart0 < 0)
			return null;
		var i = lineStart0 + lineNeedle.length;
		var j = i;
		while (j < line.length) {
			final c = line.charCodeAt(j);
			if (c < "0".code || c > "9".code)
				break;
			j++;
		}
		if (j == i)
			return null;
		var ln = 0;
		for (k in i...j) {
			ln = ln * 10 + (line.charCodeAt(k) - "0".code);
		}
		return {file: file, line: ln};
	}

	static public function toHaxe(nativeStackTrace:Any, skip:Int = 0):Array<StackItem> {
		final native:NativeTrace = cast nativeStackTrace;
		var toSkip = skip + native.skip;

		final out = new Array<StackItem>();
		for (line in native.stack) {
			if (toSkip > 0) {
				toSkip--;
				continue;
			}

			final loc = parseFileLine(line);
			if (loc != null) {
				out.push(FilePos(null, loc.file, loc.line, null));
			} else {
				out.push(Module(line));
			}
		}
		return out;
	}
}
#else

/**
	Do not use manually.
**/
@:dox(hide)
@:noCompletion
extern class NativeStackTrace {
	static public function saveStack(exception:Any):Void;
	static public function callStack():Any;
	static public function exceptionStack():Any;
	static public function toHaxe(nativeStackTrace:Any, skip:Int = 0):Array<StackItem>;
}
#end
