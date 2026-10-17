/** Constructor inputs constrain omitted method parameters before their callers read the published signature. */
class M14ConstructorParameterContextTest {
	static function main():Void {
		final plain = 'class Packet{public var text:String;public function new(text:String){this.text=text;}}';
		final generic = 'class Packet<T>{public var text:T;public function new(text:T){this.text=text;}}';
		for (entry in [
			{
				name: "written",
				declaration: plain,
				allocation: "new Packet(value)",
				hint: ":String"
			},
			{
				name: "omitted",
				declaration: plain,
				allocation: "new Packet(value)",
				hint: ""
			},
			{
				name: "dynamic",
				declaration: plain,
				allocation: "new Packet(value)",
				hint: ":Dynamic"
			},
			{
				name: "generic",
				declaration: generic,
				allocation: "new Packet<String>(value)",
				hint: ""
			},
			{
				name: "alias",
				declaration: plain + 'typedef Alias=Packet;',
				allocation: "new Alias(value)",
				hint: ""
			},
			{
				name: "inherited",
				declaration: plain + 'class Child extends Packet{}',
				allocation: "new Child(value)",
				hint: ""
			},
			{
				name: "optional_explicit",
				declaration: 'class Packet{public var text:String;public function new(?prefix:Int,text:String){this.text=text;}}',
				allocation: "new Packet(null,value)",
				hint: ""
			},
			{
				name: "rest",
				declaration: 'class Packet{public var text:String;public function new(prefix:Int,...values:String){this.text=values[0];}}',
				allocation: "new Packet(7,value)",
				hint: ""
			},
			{
				name: "block_operand",
				declaration: 'class Packet{public var text:String;public function new(text:String,stamp:Int){this.text=text;}}',
				allocation: "new Packet(value,{var marker=7;marker;})",
				hint: ""
			}
		]) {
			final root = ".tmp/constructor-parameter-contract-" + entry.name;
			final source = entry.declaration
				+ 'class Main{static function read(value'
				+ entry.hint
				+ '):String{var packet='
				+ entry.allocation
				+ ';return packet.text;}static function main():Void{Sys.println(read("ok"));}}';
			upstream(root, source, true);
			final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, root + "/Main.hx");
			var found = false;
			for (cls in typed.getTypedClasses())
				for (fn in cls.getFunctions())
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "read") {
						found = true;
						final expected = entry.hint == ":Dynamic" ? "dynamic" : "primitive:String";
						if (fn.getEnvironment().getParams()[0].getType().getSemanticKey() != expected)
							throw "constructor context changed the input contract: " + entry.name;
					}
			if (!found)
				throw "constructor context lost its method";
			JsRuntimeFixture.assertRuntime(typed, "Main", "ok\n");
			if (entry.name == "omitted")
				@:privateAccess M14NekoClosureControlTest.assertSource("constructor_parameter_context", source, "ok\n");
			Sys.println("CONSTRUCTOR_PARAMETER_CONTEXT:PASS " + entry.name);
		}
		final root = ".tmp/constructor-parameter-contract-conflict";
		final source = plain
			+ 'class Main{static function read(value):String{var packet=new Packet(value);var other:Int=value;return packet.text;}'
			+ 'static function main():Void{Sys.println(read("ok"));}}';
		upstream(root, source, false);
		var rejected = false;
		try {
			@:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, root + "/Main.hx");
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("conflict") < 0 && error.message.indexOf("not compatible") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "constructor context erased a later incompatible use";
		Sys.println("CONSTRUCTOR_PARAMETER_CONTEXT:PASS conflict");
		// With an unknown first operand, upstream consumes the optional slot and
		// reports the missing required suffix. It must not infer a different skip.
		final optionalRoot = ".tmp/constructor-parameter-contract-optional_unknown";
		final optionalSource = 'class Packet{public var text:String;public function new(?prefix:Int,text:String){this.text=text;}}'
			+ 'class Main{static function read(value):String{var packet=new Packet(value);return packet.text;}'
			+ 'static function main():Void{Sys.println(read("ok"));}}';
		upstream(optionalRoot, optionalSource, false);
		rejected = false;
		try {
			@:privateAccess M14GenericDynamicInferenceTest.typeSource(optionalSource, optionalRoot, optionalRoot + "/Main.hx");
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("Not enough arguments") < 0 && error.message.indexOf("No compatible method signature") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "constructor context invented an optional skip for an unknown input";
		Sys.println("CONSTRUCTOR_PARAMETER_CONTEXT:PASS optional_unknown");
	}

	/** Upstream acceptance and output are independent of the local constructor selection implementation. */
	static function upstream(root:String, source:String, accepted:Bool):Void {
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (accepted ? code != 0 || stdout != "ok\n" : code == 0 || stderr.indexOf("should be") < 0)
			throw "upstream constructor context differs: " + root + stdout + stderr;
		Sys.println("CONSTRUCTOR_PARAMETER_CONTEXT_UPSTREAM:PASS " + root);
	}
}
