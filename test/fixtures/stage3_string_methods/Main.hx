class Box {
	public var text:String;

	public function new(text:String) {
		this.text = text;
	}

	public function get():String {
		return text;
	}
}

/**
	Calls each standard String method on a String that comes from a different
	place: a local, an instance field, a static field, an array index, a static
	call result, an instance call result, a type check, and a nullable local.
**/
class Main {
	static var title:String = "Hello;World";

	static function make():String {
		return "Hello;World";
	}

	static function show(label:String, s:String):Void {
		Sys.println(label + " upper=" + s.toUpperCase() + " lower=" + s.toLowerCase());
		Sys.println(label + " charAt=" + s.charAt(1) + " code=" + s.charCodeAt(1));
		Sys.println(label + " indexOf=" + s.indexOf("o") + "," + s.indexOf("o", 5));
		Sys.println(label + " lastIndexOf=" + s.lastIndexOf("o") + "," + s.lastIndexOf("o", 5));
		Sys.println(label + " split=" + s.split(";").length + " substr=" + s.substr(1, 3) + "," + s.substr(6));
		Sys.println(label + " substring=" + s.substring(1, 4) + "," + s.substring(6) + " toString=" + s.toString());
	}

	static function main():Void {
		final local = "Hello;World";
		Sys.println("local " + local.toUpperCase() + " " + local.toLowerCase() + " " + local.toString());
		final box = new Box("Hello;World");
		Sys.println("field " + box.text.toUpperCase() + " " + box.text.toLowerCase() + " " + box.text.toString());
		Sys.println("field "
			+ box.text.charAt(0)
			+ " "
			+ box.text.charCodeAt(0)
			+ " "
			+ box.text.indexOf("W")
			+ " "
			+ box.text.lastIndexOf("l"));
		Sys.println("field " + box.text.split(";")[1] + " " + box.text.substr(0, 5) + " " + box.text.substring(6, 11));
		Sys.println("static " + Main.title.toUpperCase() + " " + title.toLowerCase() + " " + title.toString() + " " + title.split(";")[0]);
		Sys.println("static " + title.charAt(4) + " " + title.charCodeAt(4) + " " + title.indexOf(";") + " " + title.lastIndexOf("o", 3));
		Sys.println("static " + title.substr(-5) + " " + title.substring(0, 1));
		final parts = "a;b".split(";");
		Sys.println("index " + parts[1].toUpperCase() + " " + parts[0].toUpperCase().toLowerCase() + " " + parts[1].toString());
		Sys.println("index " + parts[1].charAt(0) + " " + parts[1].charCodeAt(0) + " " + parts[0].indexOf("a") + " " + parts[0].lastIndexOf("a"));
		Sys.println("index " + parts[1].split("").length + " " + parts[1].substr(0) + " " + parts[1].substring(0, 1));
		Sys.println("call " + make().toUpperCase() + " " + make().toLowerCase() + " " + make().toString() + " " + make().split(";")[1]);
		Sys.println("call " + make().charAt(1) + " " + make().charCodeAt(1) + " " + make().indexOf("l") + " " + make().lastIndexOf("l"));
		Sys.println("call " + make().substr(1, 2) + " " + make().substring(2, 4));
		Sys.println("method " + box.get().toUpperCase() + " " + box.get().toLowerCase() + " " + box.get().substr(6).toUpperCase());
		Sys.println("chain " + "a=b;c=d".split(";")[1].split("=")[1].toUpperCase() + " " + local.substr(6).toLowerCase());
		final value:Dynamic = "Hello;World";
		Sys.println("cast " + (value : String).toUpperCase() + " " + (cast value : String).toLowerCase() + " " + (value : String).charAt(0));
		Sys.println("cast " + (value : String).split(";")[0] + " " + (value : String).substring(0, 2) + " " + (value : String).toString());
		final maybe:Null<String> = "Hello;World";
		Sys.println("nullable " + maybe.toUpperCase() + " " + maybe.toLowerCase() + " " + maybe.toString() + " " + maybe.substr(6));
		show("arg", local);
		show("field-arg", box.text);
		show("index-arg", "Hello;World;x".split(";").slice(0, 2).join(";"));
	}
}
