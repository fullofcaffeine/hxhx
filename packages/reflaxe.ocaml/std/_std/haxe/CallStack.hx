package haxe;

private typedef NativeTrace = {
	final skip:Int;
	final stack:Array<String>;
}

/**
	OCaml target override for `haxe.CallStack`.

	Why
	- Upstream Haxe routes `haxe.CallStack` through `haxe.NativeStackTrace`.
	- In `reflaxe.ocaml`, `haxe.NativeStackTrace` is already target-owned and
	  implemented early under `src/haxe/NativeStackTrace.cross.hx`.
	- Letting the upstream `haxe.CallStack` source emit directly creates a cycle in
	  generated OCaml (`CallStack -> NativeStackTrace -> CallStack`) on real
	  compile/build paths.

	What
	- Provides the public `StackItem` / `CallStack` surface for OCaml builds.
	- Keeps runtime behavior aligned with Haxe 4.3.7 intent:
	  best-effort captured stacks plus deterministic string rendering.

	How
	- Runtime capture talks to the repo-owned `HxBacktrace` OCaml module through
	  `@:native` externs instead of routing back through `haxe.NativeStackTrace`.
	- `subtract` and `itemToString` follow upstream `haxe.CallStack` behavior
	  closely enough for current declared target scope.
	- In macro context we keep a harmless host-safe fallback surface so target-only
	  OCaml runtime bindings are not required during macro execution.
**/
enum StackItem {
	CFunction;
	Module(m:String);
	FilePos(s:Null<StackItem>, file:String, line:Int, ?column:Int);
	Method(classname:Null<String>, method:String);
	LocalFunction(?v:Int);
}

@:allow(haxe.Exception)
@:using(haxe.CallStack)
abstract CallStack(Array<StackItem>) from Array<StackItem> {
	public var length(get, never):Int;

	inline function get_length():Int {
		return this.length;
	}

	#if macro
	public static function callStack():Array<StackItem> {
		return [];
	}

	public static function exceptionStack(fullStack = false):Array<StackItem> {
		return [];
	}
	#else
	static function parseFileLine(line:String):Null<{file:String, line:Int}> {
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
		for (k in i...j)
			ln = ln * 10 + (line.charCodeAt(k) - "0".code);
		return {file: file, line: ln};
	}

	static function nativeToHaxe(native:NativeTrace, skip:Int = 0):Array<StackItem> {
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

	public static function callStack():Array<StackItem> {
		return nativeToHaxe({
			skip: 1,
			stack: NativeHxBacktrace.callstack_lines(64)
		});
	}

	public static function exceptionStack(fullStack = false):Array<StackItem> {
		final eStack:CallStack = nativeToHaxe({
			skip: 0,
			stack: NativeHxBacktrace.exceptionstack_lines()
		});
		return (fullStack ? eStack : eStack.subtract(callStack())).asArray();
	}
	#end

	public static function toString(stack:CallStack):String {
		final b = new StringBuf();
		for (s in stack.asArray()) {
			b.add("\nCalled from ");
			itemToString(b, s);
		}
		return b.toString();
	}

	public function subtract(stack:CallStack):CallStack {
		var startIndex = -1;
		var i = -1;
		while (++i < this.length) {
			for (j in 0...stack.length) {
				if (equalItems(this[i], stack[j])) {
					if (startIndex < 0)
						startIndex = i;
					++i;
					if (i >= this.length)
						break;
				} else {
					startIndex = -1;
				}
			}
			if (startIndex >= 0)
				break;
		}
		return startIndex >= 0 ? this.slice(0, startIndex) : this;
	}

	public inline function copy():CallStack {
		return this.copy();
	}

	@:arrayAccess public inline function get(index:Int):StackItem {
		return this[index];
	}

	inline function asArray():Array<StackItem> {
		return this;
	}

	static function equalItems(item1:Null<StackItem>, item2:Null<StackItem>):Bool {
		return switch ([item1, item2]) {
			case [null, null]:
				true;
			case [CFunction, CFunction]:
				true;
			case [Module(m1), Module(m2)]:
				m1 == m2;
			case [FilePos(item1, file1, line1, col1), FilePos(item2, file2, line2, col2)]: file1 == file2 && line1 == line2 && col1 == col2 && equalItems(item1,
					item2);
			case [Method(class1, method1), Method(class2, method2)]: class1 == class2 && method1 == method2;
			case [LocalFunction(v1), LocalFunction(v2)]:
				v1 == v2;
			case _:
				false;
		}
	}

	static function itemToString(b:StringBuf, s:StackItem):Void {
		switch (s) {
			case CFunction:
				b.add("a C function");
			case Module(m):
				b.add("module ");
				b.add(m);
			case FilePos(inner, file, line, col):
				if (inner != null) {
					itemToString(b, inner);
					b.add(" (");
				}
				b.add(file);
				b.add(" line ");
				b.add(line);
				if (col != null) {
					b.add(" column ");
					b.add(col);
				}
				if (inner != null)
					b.add(")");
			case Method(classname, method):
				b.add(classname == null ? "<unknown>" : classname);
				b.add(".");
				b.add(method);
			case LocalFunction(v):
				b.add("local function #");
				b.add(v);
		}
	}
}

@:native("HxBacktrace")
private extern class NativeHxBacktrace {
	static function callstack_lines(depth:Int):Array<String>;
	static function exceptionstack_lines():Array<String>;
}
