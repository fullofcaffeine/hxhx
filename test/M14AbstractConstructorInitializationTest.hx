import hxhx.CompilerJsonParser;
import hxhx.CompilerJsonValue;

private typedef InitializationCase = {
	final name:String;
	final body:String;
	final accepted:Bool;
}

/** Preserve upstream constructor-initialization admission, including its control-flow exceptions. */
class M14AbstractConstructorInitializationTest {
	static function cases():Array<InitializationCase> {
		final document = CompilerJsonParser.parse(sys.io.File.getContent("test/oracle/constructor_initialization_seed/cases.json"));
		return switch document {
			case JsonArray(entries): [
					for (entry in entries)
						switch entry {
							case JsonObject(fields):
								switch [fields.get("name"), fields.get("body"), fields.get("accepted")] {
									case [JsonString(name), JsonString(body), JsonBool(accepted)]: {name: name, body: body, accepted: accepted};
									case _: throw "constructor initialization case has invalid fields";
								}
							case _:
								throw "constructor initialization case must be an object";
						}
				];
			case _: throw "constructor initialization cases must be an array";
		};
	}

	static function main():Void {
		final failures = new Array<String>();
		for (entry in cases()) {
			final source = 'class Main { static function main():Void { new Result(false); } }\n'
				+ 'abstract Result(Int) { public function new(flag:Bool) { '
				+ entry.body
				+ ' } }\n';
			var diagnostic:Null<String> = null;
			try {
				final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
				TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			if (entry.accepted && diagnostic != null)
				failures.push(entry.name + ": valid constructor rejected: " + diagnostic);
			else if (!entry.accepted && diagnostic == null)
				failures.push(entry.name + ": uninitialized constructor accepted");
			else if (!entry.accepted && diagnostic.indexOf("Missing this = value") < 0)
				failures.push(entry.name + ": unexpected rejection: " + diagnostic);
		}
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("ABSTRACT_CONSTRUCTOR_INITIALIZATION:PASS");
	}
}
