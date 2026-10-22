/** Payload variants expose a boxed enum mistaken for a native constructor. */
private enum Payload {
	Empty;
	Item(number:Int);
}

private typedef PayloadAlias = Payload;

/** Ordinary fields with protocol names must recover their exact enum type. */
class Main {
	static var receiverReads = 0;

	static function describe(value:Payload):String {
		return switch value {
			case Empty: "empty";
			case Item(number): "item:" + number;
		};
	}

	static function nullable(value:Null<Payload>):String {
		return value == null ? "absent" : describe(value);
	}

	static function receiver(entry:{name:String, value:Payload}):{name:String, value:Payload} {
		receiverReads++;
		return entry;
	}

	static function readKey(entry:{key:Payload}):Payload {
		return entry.key;
	}

	static function readNext(entry:{next:Payload}):Payload {
		return entry.next;
	}

	static function readConstant(entry:{hasNext:Payload}):Payload {
		return entry.hasNext;
	}

	static function readAlias(entry:{value:PayloadAlias}):PayloadAlias {
		return entry.value;
	}

	static function readNullable(entry:{value:Null<Payload>}):Null<Payload> {
		return entry.value;
	}

	static function main():Void {
		final bindings:Array<{name:String, value:Payload}> = [{name: "entry", value: Item(37)}];
		Sys.println("stored=" + describe(bindings[0].value));
		Sys.println("renamed=" + describe(({payload: Item(39)} : {payload:Payload}).payload));
		Sys.println("key=" + describe(readKey({key: Item(41)})));
		Sys.println("next=" + describe(readNext({next: Item(43)})));
		Sys.println("constant=" + describe(readConstant({hasNext: Empty})));
		final alias:{value:PayloadAlias} = {value: Item(45)};
		Sys.println("alias=" + describe(readAlias(alias)));
		bindings[0].value = Item(47);
		Sys.println("written=" + describe(bindings[0].value));
		Sys.println("receiver=" + describe(receiver(bindings[0]).value) + ":" + receiverReads);
		final optional:{value:Null<Payload>} = {value: null};
		Sys.println("nullable=" + nullable(readNullable(optional)));
		optional.value = Item(49);
		Sys.println("nullable-written=" + nullable(readNullable(optional)));
		final present:{value:Null<Payload>} = {value: Item(53)};
		Sys.println("nullable-present=" + nullable(readNullable(present)));
		#if ocaml_structural_enum_imap_diagnostic
		final map:haxe.Constraints.IMap<String, Payload> = new haxe.ds.StringMap<Payload>();
		#else
		final map = new haxe.ds.StringMap<Payload>();
		#end
		map.set("entry", Item(51));
		for (key => value in map)
			Sys.println("tuple=" + key + ":" + describe(value));
	}
}
