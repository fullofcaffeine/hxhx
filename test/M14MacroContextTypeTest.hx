import haxe.macro.Expr;
import haxe.macro.Type;
import hxhx.macro.MacroContextHostServices;
import hxhx.macro.MacroState;
import hxhxmacrohost.MacroContextWire;
import hxhxmacrohost.MacroTypeWire;
import sys.io.File;

/**
	Both halves of `Context.typeof`, `Context.follow`, and `Ref.get` (Context PR 3), in the interpreter.

	The compiler side (`MacroContextHostServices`, `MacroTypeServices`) types expressions at
	`test/fixtures/project-macro-typeof/src/Main.hx` with a real index and loader. The plugin side
	(`hxhxmacrohost.MacroTypeWire`) decodes the answers into `haxe.macro.Type` values whose refs call
	back into the compiler. `isFloat` and `show` repeat the fixture's `TypeProbe`, and every line
	must equal the output haxe 4.3.7 printed for the fixture (`expected.stdout`).

	It also checks the handle rules: a handle from an earlier macro call is stale (`invalid`), a ref
	the macro built itself cannot be sent back, and a type the typer rejects is a catchable
	`haxe.macro.Expr.Error`.
**/
class M14MacroContextTypeTest {
	static inline final FIXTURE = "test/fixtures/project-macro-typeof";

	static function main():Void {
		final file = sys.FileSystem.absolutePath(FIXTURE + "/src/Main.hx");
		final typer = typerAt(file);
		// One services value per macro call: `forCall` starts the call.
		final services = MacroContextHostServices.forCall(file, null, typer);
		final wire = new MacroTypeWire(request -> MacroContextHostServices.handle(services, request));

		final lines = [
			"isFloat 1.5 " + isFloat(wire, macro 1.5),
			"isFloat 1 " + isFloat(wire, macro 1),
			"isFloat text " + isFloat(wire, macro "x"),
			"isFloat typedef " + isFloat(wire, macro Main.ratio),
			"isFloat null float " + isFloat(wire, macro Main.maybeRatio),
			"isFloat call " + isFloat(wire, macro Main.half()),
			"isFloat sqrt " + isFloat(wire, macro Math.sqrt(2)),
			"isFloat unknown " + isFloat(wire, macro missingName),
			describe(wire, macro "text"),
			describe(wire, macro 1.5),
			describe(wire, macro Main.count),
			describe(wire, macro Main.color),
			describe(wire, macro Main.point),
			describe(wire, macro Main.anything),
			describe(wire, macro Main.names),
			describe(wire, macro Main.scale)
		];
		final expected = File.getContent(FIXTURE + "/expected.stdout").split("\n");
		for (index in 0...lines.length)
			require(lines[index] == expected[index],
				"line "
				+ (index + 1)
				+ " differs from haxe 4.3.7:\n  hxhx:     "
				+ lines[index]
				+ "\n  upstream: "
				+ expected[index]);

		// Class fields come through their own ref (`ClassType.fields`), as upstream's do.
		switch wire.typeof(macro Main.names) {
			case TInst(c, _):
				final fields = c.get().fields.get();
				final names = [for (field in fields) field.name];
				require(names.indexOf("length") >= 0 && names.indexOf("push") >= 0, "Array member fields: " + names.join(","));
				for (field in fields)
					if (field.name == "push")
						require(field.kind.match(FMethod(_)) && field.type.match(TFun(_, _)), "Array.push must be a method");
			case _:
				throw "Main.names must be a class instance";
		}

		// A typing failure is `haxe.macro.Expr.Error` at the expression, which a macro may catch.
		final failure = try {
			wire.typeof(macro MissingType.value);
			null;
		} catch (error:haxe.macro.Expr.Error) {
			error;
		}
		require(failure != null
			&& failure.message == "Type not found : MissingType", "typeof of a missing type must throw haxe.macro.Expr.Error");

		// A ref from an earlier macro call is stale; the same type given to this call is not.
		final early = wire.typeof(macro Main.color);
		final later = MacroContextHostServices.forCall(file, null, typer);
		final laterWire = new MacroTypeWire(request -> MacroContextHostServices.handle(later, request));
		switch early {
			case TEnum(ref, _):
				final stale = thrown(() -> ref.get());
				require(StringTools.startsWith(stale, "macro context: invalid: type handle ") && stale.indexOf("is stale") > 0,
					"a stale handle must be invalid: " + stale);
			case _:
				throw "Main.color must be an enum";
		}
		switch laterWire.typeof(macro Main.color) {
			case TEnum(ref, _):
				require(ref.get().names.join(",") == "Red,Green", "a handle given to this call must work");
			case _:
				throw "Main.color must be an enum";
		}

		// A ref the macro built itself has no compiler handle.
		final own:Ref<ClassType> = {get: () -> throw "unused", toString: () -> "Own"};
		require(thrown(() -> laterWire.follow(TInst(own, []),
			false)) == "macro context: invalid: this Ref was not given by the compiler, so it cannot be sent back",
			"a macro-built ref must be rejected");

		// Every unsupported answer is counted; this test asks for none.
		require(MacroState.getContextUnsupported() == 0, "no Context answer here is unsupported");
		Sys.println("M14_MACRO_CONTEXT_TYPE:PASS");
	}

	/** The typer of the fixture's `Main` class, as the expression macro pass builds it for a call. */
	static function typerAt(file:String):hxhx.macro.MacroCallTyper {
		final source = File.getContent(file);
		final parsed = ParserStage.parse(source, file);
		final resolved = new ResolvedModule("Main", file, parsed);
		final index = TyperIndex.buildHeaders([resolved]);
		// The pinned standard library, found as the other std-reading tests find it. Core Tests has
		// no `vendor/haxe`, and `HAXE_STD_PATH` may be a list, so neither is used as is.
		final std = sys.FileSystem.absolutePath(M14Stage0StdPath.locate());
		final loader = new ModuleLoader([haxe.io.Path.directory(file), std], new haxe.ds.StringMap<String>(), index, _ -> false);
		loader.markResolvedAlready([resolved]);
		final declaration = parsed.getDecl();
		final directives = HxModuleDecl.getDirectives(declaration);
		final resolvedDirectives = TyperStage.resolveModuleDirectives(directives, "", "Main", index, loader);
		return {context: new TyperContext(index, file, "Main", "", directives, "Main", loader, resolvedDirectives), loader: loader};
	}

	/** The fixture's `isFloat`: upstream's test builder shape. */
	static function isFloat(wire:MacroTypeWire, e:Expr):Bool {
		try
			return switch (wire.follow(wire.typeof(e), false)) {
				case TAbstract(tr, _):
					tr.get().name == "Float";
				case _:
					false;
			} catch (e:Dynamic) {
			return false;
		}
	}

	static function describe(wire:MacroTypeWire, e:Expr):String {
		final t = wire.typeof(e);
		return show(t) + " => " + show(wire.follow(t, false)) + " | once " + show(wire.follow(t, true));
	}

	static function show(t:Type):String {
		return switch t {
			case TInst(c, params):
				final value = c.get();
				"TInst "
				+ c.toString()
				+ " name="
				+ value.name
				+ " module="
				+ value.module
				+ " pack="
				+ value.pack.join(".")
				+ " params="
				+ list(params);
			case TAbstract(a, params):
				final value = a.get();
				"TAbstract "
				+ a.toString()
				+ " name="
				+ value.name
				+ " module="
				+ value.module
				+ " params="
				+ list(params);
			case TEnum(en, params):
				final value = en.get();
				"TEnum "
				+ en.toString()
				+ " module="
				+ value.module
				+ " names="
				+ value.names.join(",")
				+ " params="
				+ list(params);
			case TType(td, params):
				final value = td.get();
				"TType " + td.toString() + " module=" + value.module + " params=" + list(params);
			case TFun(args, ret):
				"TFun(" + [for (arg in args) arg.name + (arg.opt ? "?" : "") + ":" + show(arg.t)].join(", ") + ") -> " + show(ret);
			case TAnonymous(a):
				final names = [for (field in a.get().fields) field.name];
				names.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
				"TAnonymous " + names.join(",");
			case TDynamic(_):
				"TDynamic";
			case TMono(_):
				"TMono";
			case TLazy(_):
				"TLazy";
		}
	}

	static function list(params:Array<Type>):String
		return "[" + [for (param in params) show(param)].join("; ") + "]";

	static function thrown(run:() -> Dynamic):String {
		try {
			run();
		} catch (error:String) {
			return error;
		}
		return "";
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
