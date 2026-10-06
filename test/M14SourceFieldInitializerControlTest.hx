/** Field initializers retain lexical bindings and exact nested function/loop destinations. */
class M14SourceFieldInitializerControlTest {
	static function typeSource(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function nodes(expression:TypedExpr):Array<TypedExpr> {
		final found = [expression];
		for (child in expression.getExpressions())
			for (nested in nodes(child))
				found.push(nested);
		return found;
	}

	public static function run():Void {
		initializerReplay();
		initializerCompletion();
		final source = sys.io.File.getContent("test/oracle/source_field_initializer_control_seed/src/Main.hx");
		final typed = typeSource(source);
		final fields = typed.getTypedClasses()[0].getFieldInitializers();
		final projectedFields = typed.getBackendProjection().getClasses()[0].getFieldInitializers();
		if (projectedFields.length != fields.length)
			throw "backend projection lost an initializer";
		for (index in 0...fields.length) {
			final projected = projectedFields[index];
			for (node in nodes(fields[index].getExpression()))
				for (binding in node.getLocalBindings()) {
					final selected = projected.getLocalCatalog().findByIdentity(binding.getIdentity().getCanonicalKey());
					if (selected == null
						|| !selected.getBinding().getIdentity().equals(binding.getIdentity())
						|| selected.getBinding().getCanonicalIdentity() != binding.getCanonicalIdentity())
						throw "initializer projection lost its exact binding catalog: "
							+ fields[index].getField().getName()
								+ " -> "
								+ projected.getField().getName()
								+ ": "
								+ binding.getSourceName();
				}
		}
		switch projectedFields[0].getExpression() {
			case ELoweredControl(Initializer(true), owner, children, _):
				if (owner != projectedFields[0].getStableIdentity() || children.length != 3 || !children[2].match(EIdent(_)))
					throw "initializer projection lost its ordered scope and final value";
			case _:
				throw "static initializer did not retain its shared executable unit";
		}
		final legacyFields = HxClassDecl.getFields(typed.getBackendDeclaration().mainClass);
		if (TypedBodyFingerprint.forExpression(HxFieldDecl.getInit(legacyFields[0])) != TypedBodyFingerprint.forExpression(projectedFields[0].getExpression()))
			throw "declaration projection retained a different initializer path";
		if (fields.length != 2)
			throw "missing typed field initializers";
		for (field in fields) {
			final original = CompilerTypedTreeRevision.expression(field.getField().getCanonicalKey(), field.getExpression());
			final lowered = TypedControlLowering.fieldInitializer(field);
			if (!lowered.completes || lowered.value == null)
				throw "initializer lost its normally produced value";
			final loweredExpressions = nodes(lowered.value);
			final loweredBindings = new Array<TyLocalBinding>();
			for (step in lowered.steps) {
				@:privateAccess TypedBodyInvariant.assertExpr(step, "lowered initializer");
				for (node in nodes(step))
					loweredExpressions.push(node);
			}
			if (loweredExpressions.filter(node -> node.getTag() == SourceFunction || node.getTag() == SourceGroup).length != 0)
				throw "initializer lowering left authored control in its executable tree";
			if (loweredExpressions.filter(node -> node.getTag() == Lambda).length != 1)
				throw "initializer lowering invented or removed a callable";
			for (node in loweredExpressions)
				for (binding in node.getLocalBindings())
					loweredBindings.push(binding);
			for (node in nodes(field.getExpression())) {
				for (binding in node.getLocalBindings())
					if (loweredBindings.indexOf(binding) < 0)
						throw "initializer lowering reconstructed or discarded an authored binding";
				if (node.getControlTarget() != null
					&& loweredExpressions.filter(loweredNode -> loweredNode.getControlTarget() == node.getControlTarget()).length == 0)
					throw "initializer lowering reconstructed an authored control destination";
			}
			if (CompilerTypedTreeRevision.expression(field.getField().getCanonicalKey(), field.getExpression()) != original)
				throw "initializer lowering changed the authored typed tree";
			@:privateAccess TypedBodyInvariant.assertExpr(field.getExpression(), "field initializer");
			final expressions = nodes(field.getExpression());
			final functions = expressions.filter(node -> node.getTag() == SourceFunction);
			if (functions.length != 1)
				throw "initializer lost its authored function";
			final target = functions[0].getControlTarget();
			if (target == null || target.getOwnerIdentity() != field.getField().getCanonicalKey())
				throw "initializer function lost its exact field owner";
			for (node in expressions.filter(node -> node.getTag() == ReturnExpr))
				if (node.getControlTarget() != target)
					throw "return escaped its initializer function";
			final loops = expressions.filter(node -> node.getTag() == WhileExpr);
			for (node in expressions.filter(node -> node.getTag() == BreakExpr || node.getTag() == ContinueExpr))
				if (loops.length != 1 || node.getControlTarget() != loops[0].getControlTarget())
					throw "initializer loop exit lost its exact destination";
		}
		final changed = typeSource(StringTools.replace(source, "value = 2", "value = 1"));
		final originalTarget = nodes(fields[0].getExpression()).filter(node -> node.getTag() == SourceFunction)[0].getControlTarget();
		final changedTarget = nodes(changed.getTypedClasses()[0].getFieldInitializers()[0].getExpression()).filter(node ->
			node.getTag() == SourceFunction)[0].getControlTarget();
		if (originalTarget.getCanonicalIdentity() == changedTarget.getCanonicalIdentity())
			throw "initializer edit did not invalidate nested control identity";
		for (body in ["return 3;", "break;", "continue;"]) {
			var rejected = false;
			try {
				typeSource("class Main { static var value = { " + body + " 4; }; }");
			} catch (error:haxe.Exception) {
				rejected = error.message.indexOf("enclosing") >= 0 || error.message.indexOf("outside") >= 0;
			}
			if (!rejected)
				throw "initializer admitted invalid control: " + body;
		}
		Sys.println("SOURCE_FIELD_INITIALIZER_CONTROL:PASS");
	}

	/** A throw stops initialization before its trailing value or field assignment. */
	static function initializerCompletion():Void {
		final abrupt = typeSource('class Main { static var value:Int = { throw "stop"; 4; }; }').getTypedClasses()[0].getFieldInitializers()[0];
		final lowered = TypedControlLowering.fieldInitializer(abrupt);
		if (lowered.completes || lowered.value != null || lowered.steps.length != 1)
			throw "abrupt initializer acquired a field value";
		final body = lowered.steps[0];
		if (body.getTag() != ControlRegion || body.getExpressions().length != 1 || body.getExpressions()[0].getTag() != ThrowExpr)
			throw "abrupt initializer retained evaluation after its throw";
		final constant = typeSource('class Main { static var value:Int = 4; }').getTypedClasses()[0].getFieldInitializers()[0];
		final plain = TypedControlLowering.fieldInitializer(constant);
		if (!plain.completes || plain.steps.length != 0 || plain.value == null || plain.value.getTag() != IntValue || plain.value.getIntValue() != 4)
			throw "constant initializer acquired an execution wrapper";
	}

	/** Replay keeps exact nested targets; speculative inference cannot invent a return destination. */
	static function initializerReplay():Void {
		final controls = new TyControlScope("Main.value", "source-revision", Initializer);
		if (controls.loopTarget() != null)
			throw "initializer became a loop destination";
		final callback = controls.enter(Function, "callback");
		controls.beginReturns(callback, TyType.fromHintText("Int"));
		if (controls.returnTarget() != callback)
			throw "initializer hid its nested function";
		controls.finishReturns(callback);
		controls.exit(callback);
		final replay = controls.createReplay();
		if (replay.getRoot() != controls.getRoot() || replay.getRoot().getKind() != Initializer)
			throw "replay reconstructed initializer ownership";
		if (replay.enter(Function, "callback") != callback)
			throw "replay reconstructed initializer callback";
		replay.exit(callback);
		replay.assertReplayComplete();
		for (copy in [controls, replay, controls.copyForInference()]) {
			var rejected = false;
			try {
				copy.returnTarget();
			} catch (error:haxe.Exception) {
				rejected = error.message == "return has no enclosing function";
			}
			if (!rejected)
				throw "initializer copy admitted a return";
		}
	}

	static function main():Void
		run();
}
