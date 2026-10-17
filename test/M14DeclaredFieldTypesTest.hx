import backend.cpp.CppManagedStaticStorage;
import backend.cpp.CppTypedProgramProjection;

/** Completed declaration types must preserve exact ownership and survive backend projection. */
class M14DeclaredFieldTypesTest {
	static function typeSources(sources:Array<{name:String, source:String}>):Array<TypedModule> {
		final modules = [
			for (entry in sources)
				new ResolvedModule(entry.name, entry.name + ".hx", ParserStage.parse(entry.source, entry.name + ".hx"))
		];
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(["."], HxDefineMap.fromRawDefines([]), index, _ -> false);
		loader.markResolvedAlready(modules);
		return [for (module in modules) TyperStage.typeResolvedModule(module, index, loader)];
	}

	static function rejects(fragment:String, action:Void->Void):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) < 0)
				throw failure;
			return;
		}
		throw "expected rejection: " + fragment;
	}

	static function main():Void {
		final sources = [
			{name: "Provider", source: 'class Provider {public static var value=7;}'},
			{
				name: "Main",
				source: 'import Provider as Alias;
class Main {
 public static var count=1;
 public static var annotated:Int=3;
 public static var copied=Alias.value;
 public static var callback=function(value:Int):Int {return value+1;};
 public var label="instance";
 public var values=[1];
 public var written:Int=2;
 public function new() {}
 public static function read():Int {return count+copied+callback(2);}
}
class Box<T> {public var value:T; public var copy=value; public function new(value:T) {this.value=value;}}'
			}
		];
		final typed = typeSources(sources);
		final cls = typed[1].getTypedClasses()[0];
		final header = cls.getSemanticInfo();
		final projected = typed[1].getBackendProjection().getClasses()[0];
		final facts = projected.requireSemanticFacts();
		for (entry in [
			{name: "count", type: "Int"},
			{name: "copied", type: "Int"},
			{name: "label", type: "String"},
			{name: "values", type: "Array<Int>"},
			{name: "written", type: "Int"}
		]) {
			final field = header.fieldInfo(entry.name);
			if (facts.requireField(field).semanticType.getCanonicalDisplay() != entry.type)
				throw "incorrect published type for " + entry.name;
			if (entry.name != "written" && !field.getType().isUnknown())
				throw "publication mutated a header";
		}
		if (facts.requireField(header.fieldInfo("callback")).semanticType.hasUnknownComponent())
			throw "callable publication incomplete";
		final generic = typed[1].getTypedClasses()[1];
		final genericFacts = TypedBodySource.classProjection(generic).requireSemanticFacts();
		if (genericFacts.requireField(generic.getSemanticInfo().fieldInfo("copy"))
			.typeIdentity != generic.getSemanticInfo()
			.fieldInfo("value")
			.getType()
			.getSemanticKey())
			throw "inference lost the class type parameter binder";
		final foreign = typeSources(sources)[1].getTypedClasses()[0];
		final foreignProjection = TypedBodySource.classProjection(foreign);
		rejects("exact declaration", () -> facts.requireField(foreign.getSemanticInfo().fieldInfo("count")));
		rejects("another class header", () -> cls.getDeclaredFieldTypes().assertOwner(foreign.getSemanticInfo()));
		final replacement = cls.withFunctions(cls.getFunctions());
		if (TypedBodySource.classProjection(replacement)
			.requireSemanticFacts()
			.requireField(header.fieldInfo("count"))
			.typeIdentity != "primitive:Int")
			throw "function rewrite discarded completed field facts";
		final program = new CppTypedProgramProjection(new MacroExpandedProgram(typed, false));
		final storage = new CppManagedStaticStorage(program, "hxhx_statics_inferred");
		var reads = 0;
		for (fn in projected.getFunctions())
			for (statement in fn.getBody())
				TypedBackendSourceWalk.statement(statement, expression -> {
					final occurrence = fn.findField(expression);
					if (occurrence != null && occurrence.getField().getIsStatic()) {
						storage.member(occurrence);
						reads++;
					}
				}, _ -> {});
		if (reads != 3)
			throw "static storage observer lost inferred accesses: " + reads;
		for (initializer in projected.getFieldInitializers())
			if (initializer.getField().getIsStatic()) {
				final target = storage.initializerTarget(initializer);
				if (target.type.getSemanticKey() != facts.requireField(initializer.getField()).typeIdentity)
					throw "initializer storage lost its completed declaration type";
			} else {
				rejects("another program or an instance", () -> storage.initializerTarget(initializer));
			}
		for (initializer in foreignProjection.getFieldInitializers())
			rejects("another program or an instance", () -> storage.initializerTarget(initializer));
		// A completed declaration must also authorize storing its initializer result.
		// The header deliberately stays unknown for this unannotated integer field.
		for (initializer in projected.getFieldInitializers())
			if (initializer.getField().getName() == "count" || initializer.getField().getName() == "annotated")
				backend.cpp.CppManagedInitializerEmitter.render({
					projection: initializer,
					statics: storage,
					symbol: "hxhx_initializer_count",
					resolveStatic: _ -> {
						throw "literal initializer unexpectedly selected a call";
					}
				});
		for (field in cls.getFields())
			if (HxFieldDecl.getName(field) == "values")
				switch HxFieldDecl.getInit(field) {
					case EArrayDecl(values):
						values.push(EInt(2));
					case _:
						throw "mutation fixture lost array source";
				}
		rejects("changed initializer", () -> facts.requireField(header.fieldInfo("values")));
		rejects("changed initializer", () -> facts.copyFields());
		for (initializer in projected.getFieldInitializers())
			if (initializer.getField().getName() == "count")
				rejects("changed initializer", () -> storage.initializerTarget(initializer));
		final cyclic = typeSources([
			{name: "Cycle", source: 'class Cycle {public static var first=second; public static var second=first;}'}
		])[0];
		for (field in cyclic.getBackendProjection().getClasses()[0].requireSemanticFacts().copyFields())
			if (!field.semanticType.isUnknown())
				throw "cyclic field acquired invented type";
		Sys.println("DECLARED_FIELD_TYPES:PASS");
	}
}
