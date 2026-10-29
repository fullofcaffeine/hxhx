import backend.BackendContext;
import backend.js.JsBackend;
import sys.io.File;

/**
	Declared abstract indexed updates (`values["x"]++`, `++values["x"]`, `values["x"] += 2`)
	must run on JavaScript exactly as upstream Haxe 4.3.7 JavaScript does.

	The fixture under `test/js_indexed_update` prints old/new values, stored results,
	selected-operator events and operand evaluation order for populated, explicit-null
	and absent Map entries, an Int map, a nullable Int map, and an abstract whose setter
	returns another type than its getter. Upstream must reproduce `expected.stdout`;
	hxhx must produce the same output through the real Map providers, without the raw
	carrier indexing fallback that ordinary arrays use.
 */
class M14JsIndexedUpdateRuntimeTest {
	static function main():Void {
		final fixture = "test/js_indexed_update";
		final expected = File.getContent(fixture + "/expected.stdout");
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		observe(configured == null ? "node_modules/.bin/haxe" : configured, ["-cp", fixture, "-main", "Main", "-js", output + "/upstream.js"], "");
		observe("node", ["--use-strict", output + "/upstream.js"], expected);
		Sys.println("JS_INDEXED_UPDATE_UPSTREAM:PASS");
		final loaded = JsSourceProgramFixture.load({
			sources: [{path: "Main.hx", source: File.getContent(fixture + "/Main.hx")}],
			requiredModules: ["haxe.ds.Map", "haxe.ds.StringMap"]
		});
		final program = JsSourceProgramFixture.retain(loaded, "full");
		requireProjectedUpdates(program);
		final script = output + "/main.js";
		new JsBackend().emit(program, new BackendContext(output, script, "Main", false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--use-strict", script], expected);
		Sys.println("JS_INDEXED_UPDATE_RUNTIME:PASS");
		for (name in ["upstream.js", "main.js", "main.js.map"])
			if (sys.FileSystem.exists(output + "/" + name))
				sys.FileSystem.deleteFile(output + "/" + name);
		sys.FileSystem.deleteDirectory(output);
	}

	/**
		Every update of a declared-index place in `Main` must reach the backend as its
		selected getter/step/setter calls. A surviving typed `a[i]` read, `++`/`--` or
		compound assignment on a `Map` or `Cells` value would make the backend index the
		carrier directly, which is the fallback ordinary arrays use; a `++`/`--` or
		compound assignment whose place is a call (the projected getter) would update a
		temporary and lose the setter write.
	 */
	static function requireProjectedUpdates(program:MacroExpandedProgram):Void {
		final declared = ["haxe.ds.Map", "Main.Cells"];
		function declaredPlace(value:TypedExpr):Bool {
			final identity = value.getType().unwrapNull().getNominalIdentity();
			return identity != null && declared.contains(identity.getCanonicalName());
		}
		function expression(value:TypedExpr):Void {
			final children = value.getExpressions();
			final place = children.length > 0 ? children[0] : null;
			final update = switch value.getTag() {
				case Unary: value.getUnaryOperator() == Increment || value.getUnaryOperator() == Decrement;
				case CompoundAssign: true;
				case _: false;
			};
			switch value.getTag() {
				case ArrayAccess if (place != null && declaredPlace(place)):
					throw "declared indexed place survived as a raw carrier read";
				case _ if (update && place != null && place.getTag() == ArrayAccess && declaredPlace(place.getExpressions()[0])):
					throw "declared indexed update survived as a raw carrier update";
				case _ if (update && place != null && place.getTag() == Call):
					throw "declared indexed update survived as an update of its getter call";
				case _:
			}
			for (child in children)
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (module in program.getTypedModules())
			for (owner in module.getTypedClasses())
				if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
					for (fn in owner.getFunctions())
						if (fn.getBody() != null)
							for (entry in fn.getBody().getStatements())
								statement(entry);
	}

	/** Bound each child; a failure retains the exact command output. */
	static function observe(executable:String, arguments:Array<String>, expected:String):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout != expected || stderr != "")
			throw "indexed update observer differs: " + executable + " " + arguments.join(" ") + ": " + code + "\n" + stdout + stderr;
	}
}
