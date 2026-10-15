import backend.cpp.CppManagedProgramPlan;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppTypedProgramProjection.CppTypedModuleProjection;

/** Inject a source edit at a read boundary that production rendering does not expose to callers. */
private class ReadBoundaryProbe extends CppTypedProgramProjection {
	public var onRead:Null<Void->Void> = null;

	public function new(program:MacroExpandedProgram) {
		super(program);
	}

	override public function getModules():Array<CppTypedModuleProjection> {
		final action = onRead;
		onRead = null;
		if (action != null)
			action();
		return super.getModules();
	}
}

/** Full source validation must bound rendering without weakening standalone or local ownership checks. */
class M14CppValidationBoundaryTest {
	static function fixture():{program:MacroExpandedProgram, dormant:TypedFunction} {
		final main = new ResolvedModule("Main", "Main.hx", ParserStage.parse('class Main {
 static var seed:Int = 3;
 static function main():Void { var box = new Box(seed); if (box.read() != 3) throw "bad value"; }
}
class Box {
 var value:Int;
 public function new(value:Int) { this.value = value; }
 public function read():Int return value;
}', "Main.hx"));
		final unused = new ResolvedModule("Unused", "Unused.hx", ParserStage.parse('class Unused {
 public static function dormant():Int return 7;
}', "Unused.hx"));
		final index = TyperIndex.build([main, unused]);
		final typedMain = TyperStage.typeResolvedModule(main, index);
		final typedUnused = TyperStage.typeResolvedModule(unused, index);
		return {program: new MacroExpandedProgram([typedMain, typedUnused], false), dormant: typedUnused.getTypedClasses()[0].getFunctions()[0]};
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) < 0)
				throw error;
			return;
		}
		throw "validation boundary accepted " + diagnostic;
	}

	static function main():Void {
		final input = fixture();
		final ordinary = new CppManagedProgramPlan(new CppTypedProgramProjection(input.program), "Main").render();
		final selected = new ReadBoundaryProbe(input.program);
		if (new CppManagedProgramPlan(selected, "Main").render() != ordinary
			|| new CppManagedProgramPlan(selected, "Main").render() != ordinary)
			throw "bounded rendering changed native source or retained request state";
		final body = HxFunctionDecl.getBody(input.dormant.getSourceDeclaration());
		final mutate = () -> body.push(HxStmt.SExpr(HxExpr.EInt(99), HxPos.unknown()));
		selected.onRead = () -> {
			mutate();
		};
		reject(() -> new CppManagedProgramPlan(selected, "Main").render(), "changed");
		body.pop();
		if (new CppManagedProgramPlan(selected, "Main").render() != ordinary)
			throw "failed render retained planning state";

		// Public full checks remain unconditional even during a target-owned render.
		selected.onRead = () -> {
			mutate();
			selected.assertCurrent();
		};
		reject(() -> new CppManagedProgramPlan(selected, "Main").render(), "changed");
		body.pop();

		selected.onRead = () -> {
			new CppManagedProgramPlan(selected, "Main").render();
		};
		reject(() -> new CppManagedProgramPlan(selected, "Main").render(), "already planning");
		reject(() -> new CppManagedProgramPlan(selected, "Missing").render(), "one exact requested main");
		mutate();
		reject(() -> {
			@:privateAccess selected.assertPlanningCurrent();
		}, "changed");
		reject(() -> new CppManagedProgramPlan(selected, "Main").render(), "changed");
		reject(() -> new backend.cpp.CppManagedClassStorage(selected), "changed");
		body.pop();
		selected.assertCurrent();
		final projectedMain = selected.getModules()[0].projection.getClasses()[0].getFunctions()[0].getBody();
		selected.onRead = () -> {
			projectedMain.push(HxStmt.SExpr(HxExpr.EInt(99), HxPos.unknown()));
		};
		reject(() -> new CppManagedProgramPlan(selected, "Main").render(), "projection was mutated");
		projectedMain.pop();

		// Construction and rendering have separate lifetimes. A render failure
		// must restore full checks even when the plan itself remains reusable.
		final plan = new CppManagedProgramPlan(selected, "Main");
		selected.onRead = () -> {
			mutate();
		};
		reject(() -> plan.render(), "changed");
		reject(() -> {
			@:privateAccess selected.assertPlanningCurrent();
		}, "changed");
		body.pop();
		if (plan.render() != ordinary)
			throw "render failure retained planning state";
		selected.onRead = () -> {
			throw "injected render failure";
		};
		reject(() -> plan.render(), "injected render failure");
		if (plan.render() != ordinary)
			throw "exception retained planning state";
		if (new CppManagedProgramPlan(selected, "Main").render() != ordinary)
			throw "a later render inherited a failed validation scope";
		Sys.println("CPP_VALIDATION_BOUNDARY:PASS");
	}
}
