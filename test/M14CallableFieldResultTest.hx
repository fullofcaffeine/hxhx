import sys.io.File;

/** Calls through class fields must retain their callable result and evaluate operands once. */
class M14CallableFieldResultTest {
	static function main():Void {
		check("generic_inherited",
			'class Parent<T>{public var callback:T->T;public function new(value:T->T){callback=value;}}class Child extends Parent<String>{public function new(){super(echo);}static function echo(value:String):String{return value;}}class Main{static function main():Void{var holder=new Child();Sys.println((holder.callback)("generic"));}}',
			"generic\n");
		check("generic_callable",
			'class Holder<T>{public var callback:T;public function new(value:T){callback=value;}}class Main{static function echo(value:String):String{return value;}static function main():Void{var holder=new Holder<String->String>(echo);Sys.println(holder.callback("applied"));}}',
			"applied\n");
		final common = 'class Holder{public var callback:String->String;public function new(){callback=read;}public function read(value:String):String{return "value:"+value;}public function run():String{return this.callback("this");}}class Child extends Holder{public function new(){super();}}';
		check("instance",
			common + 'class Main{static function main():Void{var holder=new Holder();Sys.println(holder.callback("instance"));Sys.println(holder.run());}}',
			"value:instance\nvalue:this\n");
		check("inherited", common + 'class Main{static function main():Void{var holder=new Child();Sys.println(holder.callback("inherited"));}}',
			"value:inherited\n");
		check("static",
			'class Holder{public static var callback:String->String=read;static function read(value:String):String{return "value:"+value;}}class Main{static function main():Void{Sys.println(Holder.callback("static"));}}',
			"value:static\n");
		check("receiver_order",
			common +
			'class Main{static var holder=new Holder();static function receiver():Holder{Sys.println("receiver");return holder;}static function argument():String{Sys.println("argument");return "ordered";}static function main():Void{Sys.println(receiver().callback(argument()));}}',
			"receiver\nargument\nvalue:ordered\n");
		check("invalid", common + 'class Main{static function main():Void{var holder=new Holder();holder.callback(1);}}', null);
	}

	/** Compare the upstream decision, then require the same runtime output from the typed JavaScript path. */
	static function check(name:String, source:String, expected:Null<String>):Void {
		final root = ".tmp/callable_field_result_" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (expected == null ? code == 0 || errors.indexOf("Int should be String") < 0 : code != 0 || output != expected)
			throw "upstream callable field contract differs: " + name + output + errors;
		Sys.println("UPSTREAM_CALLABLE_FIELD:PASS " + name);
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		var typed:Null<TypedModule> = null;
		try {
			typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (error:TyperError) {
			if (expected != null || Std.string(error).indexOf("Int should be String") < 0)
				throw error;
		}
		if (expected == null) {
			if (typed != null)
				throw "invalid field argument was accepted";
		} else {
			if (typed == null)
				throw "valid field call was rejected";
			JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		}
		Sys.println("CALLABLE_FIELD_RESULT:PASS " + name);
	}
}
