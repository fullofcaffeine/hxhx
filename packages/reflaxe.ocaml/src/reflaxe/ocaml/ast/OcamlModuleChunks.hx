package reflaxe.ocaml.ast;

private typedef RecordedModuleChunk = {
	final header:String;
	final items:Array<OcamlModuleItem>;
}

/**
	Keeps target declarations available until the compiler assembles output files.

	Each source type owns one chunk, identified by its module and type name. The
	compiler transfers the completed syntax tree here and must not mutate it later.
	Only the outer array is copied: expressions retain their checked runtime IDs.
	Clear this request-owned catalog before compiling another program.
**/
class OcamlModuleChunks {
	final chunks:Map<String, RecordedModuleChunk> = [];

	public function new() {}

	public function clear():Void {
		chunks.clear();
	}

	/** Retains completed syntax without rendering or observing runtime uses again. */
	public function record(moduleId:String, typeName:String, items:Array<OcamlModuleItem>, header:String):Void {
		chunks.set(key(moduleId, typeName), {items: items.copy(), header: header});
	}

	/** Reads completed declarations without transferring ownership of the item list. */
	public function itemsFor(moduleId:String, typeName:String):Null<Array<OcamlModuleItem>> {
		final chunk = chunks.get(key(moduleId, typeName));
		return chunk == null ? null : chunk.items.copy();
	}

	/** A changed framework prefix cannot borrow the original declarations' safety facts. */
	public function itemsForOutput(moduleId:String, typeName:String, header:String):Null<Array<OcamlModuleItem>> {
		final chunk = chunks.get(key(moduleId, typeName));
		return chunk == null || chunk.header != header ? null : chunk.items.copy();
	}

	/**
		Appends retained declarations to the original source-type header.
		Types supplied as text by a framework hook have no retained chunk; their
		output passes through unchanged. Rendering does not consume the catalog,
		so repeated output iteration has the same result.
	**/
	public function render(moduleId:String, typeName:String, prefix:String, printer:OcamlASTPrinter):String {
		final chunk = chunks.get(key(moduleId, typeName));
		return chunk == null ? prefix : prefix + printer.printModule(chunk.items);
	}

	static inline function key(moduleId:String, typeName:String):String {
		return moduleId + "\n" + typeName;
	}
}
