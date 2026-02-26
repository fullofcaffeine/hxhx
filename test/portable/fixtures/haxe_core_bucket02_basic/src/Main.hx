class Main {
	static function restLen(...rest:Int):Int {
		final values:haxe.Rest<Int> = rest;
		return values.append(9).length;
	}

	static function main() {
		var fired = false;
		final event = haxe.MainLoop.add(() -> fired = true);
		event.stop();
		Sys.println("mainloop.hasEvents=" + haxe.MainLoop.hasEvents());
		Sys.println("mainloop.fired=" + fired);

		final nativeStackLen = haxe.NativeStackTrace.toHaxe(haxe.NativeStackTrace.callStack()).length;
		Sys.println("nativeStack.nonneg=" + (nativeStackLen >= 0));

		final pos:haxe.PosInfos = {
			fileName: "Main.hx",
			lineNumber: 42,
			className: "Main",
			methodName: "main"
		};
		Sys.println("pos.line=" + pos.lineNumber);

		Sys.println("resource.count=" + haxe.Resource.listNames().length);
		Sys.println("rest.len=" + restLen(1, 2, 3));

		final serializedInt = haxe.Serializer.run(7);
		final decodedInt = haxe.Unserializer.run(serializedInt);
		Sys.println("serializer.int=" + Std.string(decodedInt));
		final serializedString = haxe.Serializer.run("hxhx");
		final decodedString:String = cast haxe.Unserializer.run(serializedString);
		Sys.println("serializer.string=" + decodedString);
		final serializedObject = haxe.Serializer.run({name: "hxhx", count: 3, enabled: true});
		final decodedObject:Dynamic = haxe.Unserializer.run(serializedObject);
		Sys.println("serializer.object.name=" + Std.string(Reflect.field(decodedObject, "name")));
		Sys.println("serializer.object.count=" + Std.string(Reflect.field(decodedObject, "count")));
		Sys.println("serializer.object.enabled=" + Std.string(Reflect.field(decodedObject, "enabled")));

		Sys.println("systools.quote=" + haxe.SysTools.quoteUnixArg("a b"));
		final template = new haxe.Template("hxhx-template");
		Sys.println("template.created=" + (template != null));
		Sys.println("template.literal=" + template.execute({}));
		final templateSubst = new haxe.Template("hello ::name::");
		Sys.println("template.subst=" + templateSubst.execute({name: "hxhx"}));

		Sys.println("timer.nonneg=" + (haxe.Timer.stamp() >= 0));
		Sys.println("utf8.len=" + haxe.Utf8.length("hxhx"));
		Sys.println("utf8.valid=" + haxe.Utf8.validate("hxhx"));
		Sys.println("utf8.sub=" + haxe.Utf8.sub("hxhx", 1, 2));

		var ucs2Supported = true;
		try {
			final u:haxe.Ucs2 = haxe.Ucs2.fromCharCode(65);
			ucs2Supported = (u.toNativeString() == "A");
		} catch (_:haxe.Exception) {
			ucs2Supported = false;
		}
		Sys.println("ucs2.supported=" + ucs2Supported);
	}
}
