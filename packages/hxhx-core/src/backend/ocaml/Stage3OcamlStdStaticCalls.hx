package backend.ocaml;

/**
	Native adapters for bodiless static methods of standard extern classes:
	`sys.io.File`, `sys.FileSystem`, and `String.fromCharCode`.

	These standard classes are `extern`: their methods have no Haxe body and
	each target supplies the implementation. Stage3 still emits generated OCaml
	modules (`Sys_io_File`, `Sys_FileSystem`, `String`) for them, and each
	bodiless method there is an empty placeholder. A call that reached such a placeholder
	compiled, then returned a value that was not a real string, Bool, or array,
	so the native program printed garbage or crashed.

	This adapter selects the call by the typed owner and method, never by the
	spelling in the source. `File.getContent(p)`, `sys.io.File.getContent(p)`,
	and an import alias all reach the same `HxFile.getContent` runtime function
	from `packages/reflaxe.ocaml/std/runtime`. A method that is missing from
	this table, such as `File.getBytes` or `FileSystem.stat`, stays unrouted;
	the emitter then rejects the bodiless call instead of reaching the
	placeholder.

	Every listed method uses only `Int`, `String`, `Bool`, `Array<String>`, and `Void`,
	which have the same representation in Stage3 output and in the runtime.
	Results that need a converted carrier (`haxe.io.Bytes`, `sys.FileStat`)
	are not listed until the adapter can build that carrier.
 */
private typedef RuntimeOperation = {
	final reference:String;
	final arity:Int;
}

private function operation(owner:String, method:String):Null<RuntimeOperation> {
	return switch [owner, method] {
		case ["String", "fromCharCode"]: {reference: "HxString.fromCharCode", arity: 1};
		case ["sys.io.File", "getContent"]: {reference: "HxFile.getContent", arity: 1};
		case ["sys.io.File", "saveContent"]: {reference: "HxFile.saveContent", arity: 2};
		case ["sys.io.File", "copy"]: {reference: "HxFile.copy", arity: 2};
		case ["sys.FileSystem", "exists"]: {reference: "HxFileSystem.exists", arity: 1};
		case ["sys.FileSystem", "rename"]: {reference: "HxFileSystem.rename", arity: 2};
		case ["sys.FileSystem", "fullPath"]: {reference: "HxFileSystem.fullPath", arity: 1};
		case ["sys.FileSystem", "absolutePath"]: {reference: "HxFileSystem.absolutePath", arity: 1};
		case ["sys.FileSystem", "isDirectory"]: {reference: "HxFileSystem.isDirectory", arity: 1};
		case ["sys.FileSystem", "createDirectory"]: {reference: "HxFileSystem.createDirectory", arity: 1};
		case ["sys.FileSystem", "deleteFile"]: {reference: "HxFileSystem.deleteFile", arity: 1};
		case ["sys.FileSystem", "deleteDirectory"]: {reference: "HxFileSystem.deleteDirectory", arity: 1};
		case ["sys.FileSystem", "readDirectory"]: {reference: "HxFileSystem.readDirectory", arity: 1};
		case _: null;
	};
}

/**
	Render a typed standard extern static call through the runtime, or return
	null when this adapter does not own the call.

	Arguments are evaluated left to right, as in Haxe, before the runtime
	function is applied. OCaml application alone may evaluate them right to left.
 */
function render(input:{
	call:TypedExactStaticCallSource.TypedExactStaticCall,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames
}):Null<String> {
	final selected = operation(input.call.owner, input.call.method);
	if (selected == null)
		return null;
	if (input.call.arguments.length != selected.arity)
		throw "stage3 emitter: " + input.call.owner + "." + input.call.method + " requires " + selected.arity + " argument(s)";
	final arguments = [for (argument in input.call.arguments) input.emit(argument)];
	if (arguments.length == 1)
		return "(" + selected.reference + " (" + arguments[0] + "))";
	if (input.names == null)
		throw "stage3 emitter: " + input.call.owner + "." + input.call.method + " requires its local naming owner";
	return Stage3OcamlCallOrder.render({callee: selected.reference, arguments: arguments, names: input.names});
}
