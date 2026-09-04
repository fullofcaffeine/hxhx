package;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import haxe.macro.JSGenApi;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Records the public Haxe custom-generator behavior needed by native hosts.

	The fixture is a behavior oracle, not an implementation. Compiler objects
	remain inside upstream Haxe. The generated candidate contains only stable
	text observations, and a small host model publishes the complete directory.
**/
class ContractGenerator {
	static var events:Array<String> = [];
	static var valueExpression:Null<TypedExpr>;
	static var afterTypingTypes:Array<String> = [];
	static var generationTypes:Array<String> = [];
	static var sourceFacts:Array<String> = [];
	static var tracePath = "";
	static var publicRoot = "";
	static var candidateRoot = "";
	static var requestId = "";
	static var profile = "";
	static var fault = "none";

	public static function install():Void {
		tracePath = requiredDefine("contract_trace");
		publicRoot = requiredDefine("contract_public_root");
		requestId = requiredDefine("contract_request");
		profile = requiredDefine("contract_profile");
		fault = optionalDefine("contract_fault", "none");
		candidateRoot = publicRoot + ".candidate-" + requestId;
		events = [];
		valueExpression = null;
		afterTypingTypes = [];
		generationTypes = [];
		sourceFacts = [];
		removeTree(candidateRoot);

		Context.onAfterTyping(types -> {
			recordEvent("after-typing");
			afterTypingTypes = typeNames(types);
			valueExpression = findValueExpression(types);
			sourceFacts = captureSourceFacts(types);
		});
		Context.onGenerate(types -> {
			recordEvent("on-generate");
			generationTypes = generationTypeNames(types);
		});
		Context.onAfterGenerate(() -> {
			try {
				publishCandidate();
				recordEvent("host-publish");
				recordEvent("after-generate");
				closeRequest();
			} catch (error:haxe.Exception) {
				recordEvent("host-publish-rollback");
				abortAndClose();
				throw error;
			}
		});
		Compiler.setCustomJSGenerator(generate);
	}

	static function generate(api:JSGenApi):Void {
		recordEvent("generator-prepare");
		final mainExpression = api.main;
		final probeExpression = valueExpression;
		if (mainExpression == null)
			Context.fatalError("custom-generator fixture received no main expression", Context.currentPos());
		if (probeExpression == null)
			Context.fatalError("custom-generator fixture received no value expression", Context.currentPos());

		var typeAccessorCalls = 0;
		api.setTypeAccessor(type -> {
			typeAccessorCalls += 1;
			return switch type {
				case TInst(reference, _): "$fixture_" + reference.get().name;
				case TEnum(reference, _): "$fixture_" + reference.get().name;
				case TType(reference, _): "$fixture_" + reference.get().name;
				case TAbstract(reference, _): "$fixture_" + reference.get().name;
				case _: "$fixture_value";
			};
		});
		final featurePresentBeforeAdd = api.hasFeature("custom.generator.fixture");
		final statement = api.generateStatement(mainExpression);
		final value = api.generateValue(probeExpression);
		final added = api.addFeature("custom.generator.fixture");
		final present = api.hasFeature("custom.generator.fixture");
		final candidateLines = [
			"contract=custom-generator-host-v2",
			"profile=" + profile,
			"after-typing=" + afterTypingTypes.join(","),
			"on-generate=" + generationTypes.join(","),
			"post-dce-facts=" + capturePostDceFacts(api.types).join("|"),
			"source-facts=" + sourceFacts.join("|"),
			"value=" + value,
			"statement=" + statement.split("\n").join("\\n"),
			"type-accessor-calls=" + typeAccessorCalls,
			"feature-present-before-add=" + featurePresentBeforeAdd,
			"feature-added=" + added,
			"feature-present=" + present
		];
		createDirectory(candidateRoot);
		File.saveContent(Path.join([candidateRoot, "output.txt"]), candidateLines.join("\n") + "\n");
		final candidateFiles = ["output.txt", "manifest.txt"];
		if (Context.defined("contract_extra")) {
			candidateFiles.push("extra.txt");
			File.saveContent(Path.join([candidateRoot, "extra.txt"]), "extra candidate output\n");
		}
		candidateFiles.sort(compareStrings);
		File.saveContent(Path.join([candidateRoot, "manifest.txt"]), candidateFiles.join("\n") + "\n");

		if (fault == "before-seal") {
			recordEvent("abort-before-seal");
			abortAndClose();
			Context.fatalError("injected custom-generator failure before candidate seal", Context.currentPos());
		}
		if (fault == "raw") {
			recordEvent("abort-raw");
			abortAndClose();
			throw new haxe.Exception("injected raw custom-generator failure");
		}
	}

	/** Replaces the complete public directory and restores it after any error. */
	static function publishCandidate():Void {
		if (!FileSystem.exists(candidateRoot) || !FileSystem.isDirectory(candidateRoot))
			throw new haxe.Exception("custom-generator candidate directory is missing");
		final backupRoot = publicRoot + ".backup-" + requestId;
		removeTree(backupRoot);
		var priorOutputMoved = false;
		try {
			if (FileSystem.exists(publicRoot)) {
				FileSystem.rename(publicRoot, backupRoot);
				priorOutputMoved = true;
			}
			if (fault == "during-publish")
				throw new haxe.Exception("injected custom-generator publication failure");
			FileSystem.rename(candidateRoot, publicRoot);
			removeTree(backupRoot);
		} catch (error:haxe.Exception) {
			removeTree(publicRoot);
			if (priorOutputMoved && FileSystem.exists(backupRoot))
				FileSystem.rename(backupRoot, publicRoot);
			throw error;
		}
	}

	static function findValueExpression(types:Array<ModuleType>):Null<TypedExpr> {
		for (type in types) {
			switch type {
				case TClassDecl(reference):
					final cls = reference.get();
					if (cls.name == "Main") {
						for (field in cls.statics.get()) {
							if (field.name == "valueProbe")
								return field.expr();
						}
					}
				case _:
			}
		}
		return null;
	}

	static function typeNames(types:Array<ModuleType>):Array<String> {
		final names = [for (type in types) typeName(type)];
		names.sort(compareStrings);
		return names;
	}

	static function typeName(type:ModuleType):String {
		final base:BaseType = switch type {
			case TClassDecl(reference): reference.get();
			case TEnumDecl(reference): reference.get();
			case TTypeDecl(reference): reference.get();
			case TAbstract(reference): reference.get();
		};
		return fullName(base);
	}

	static function generationTypeNames(types:Array<Type>):Array<String> {
		final names = new Array<String>();
		for (type in types) {
			final name = generationTypeName(type);
			if (name != null)
				names.push(name);
		}
		names.sort(compareStrings);
		return names;
	}

	static function generationTypeName(type:Type):Null<String> {
		final base:Null<BaseType> = switch type {
			case TInst(reference, _): reference.get();
			case TEnum(reference, _): reference.get();
			case TType(reference, _): reference.get();
			case TAbstract(reference, _): reference.get();
			case _: null;
		};
		return base == null ? null : fullName(base);
	}

	static function captureSourceFacts(types:Array<ModuleType>):Array<String> {
		final facts = new Array<String>();
		for (type in types) {
			switch type {
				case TClassDecl(reference):
					final cls = reference.get();
					if (cls.name == "ContractBox")
						facts.push(captureContractBox(cls));
					if (cls.name == "ContractReadable")
						facts.push("interface:" + fullName(cls) + ":parameters=" + typeParameterNames(cls.params).join(",") + ":read="
							+ captureField(requiredField(cls.fields.get(), "read")) + ":position=" + sourcePosition(cls));
				case TTypeDecl(reference):
					final definition = reference.get();
					if (definition.name == "ContractEnvelope")
						facts.push(captureContractEnvelope(definition));
				case TAbstract(reference):
					final abstraction = reference.get();
					if (abstraction.name == "ContractMode")
						facts.push(captureContractMode(abstraction));
				case _:
			}
		}
		facts.sort(compareStrings);
		return facts;
	}

	static function captureContractBox(cls:ClassType):String {
		final fields = cls.fields.get();
		final interfaces = [
			for (implemented in cls.interfaces)
				fullName(implemented.t.get()) + "<" + [for (parameter in implemented.params) TypeTools.toString(parameter)].join(",") + ">"
		];
		interfaces.sort(compareStrings);
		final parent = cls.superClass == null ? "none" : fullName(cls.superClass.t.get())
			+ "<"
			+ [for (parameter in cls.superClass.params) TypeTools.toString(parameter)].join(",") + ">";
		return "class:" + fullName(cls) + ":parameters=" + typeParameterNames(cls.params).join(",") + ":parent=" + parent + ":interfaces="
			+ interfaces.join(",") + ":read=" + captureField(requiredField(fields, "read")) + ":format=" + captureField(requiredField(fields, "format"))
			+ ":format-overloads=" + requiredField(fields, "format").overloads.get().length + ":envelope=" + captureField(requiredField(fields, "envelope"))
			+ ":unused-before-dce=" + hasField(fields, "unusedRuntimeMember") + ":position=" + sourcePosition(cls);
	}

	static function captureContractEnvelope(definition:DefType):String {
		final fields = switch definition.type {
			case TAnonymous(reference): reference.get().fields.copy();
			case _: [];
		};
		fields.sort((left, right) -> compareStrings(left.name, right.name));
		return "typedef:"
			+ fullName(definition)
			+ ":parameters="
			+ typeParameterNames(definition.params).join(",")
			+ ":fields="
			+ [
				for (field in fields)
					field.name + ":optional=" + field.meta.has(":optional") + ":type=" + TypeTools.toString(field.type)
			].join(",") + ":position=" + sourcePosition(definition);
	}

	static function captureContractMode(abstraction:AbstractType):String {
		final values = new Array<String>();
		if (abstraction.impl != null) {
			for (field in abstraction.impl.get().statics.get()) {
				if (field.meta.has(":enum")) {
					final expression = field.expr();
					values.push(field.name + "=" + (expression == null ? "missing" : constantText(expression)));
				}
			}
		}
		values.sort(compareStrings);
		return "abstract:" + fullName(abstraction) + ":enum=" + abstraction.meta.has(":enum") + ":underlying=" + TypeTools.toString(abstraction.type)
			+ ":values=" + values.join(",") + ":position=" + sourcePosition(abstraction);
	}

	static function capturePostDceFacts(types:Array<Type>):Array<String> {
		final facts = new Array<String>();
		for (type in types) {
			switch type {
				case TInst(reference, _):
					final cls = reference.get();
					if (cls.name == "ContractBox")
						facts.push("class:" + fullName(cls) + ":unused-after-dce=" + hasField(cls.fields.get(), "unusedRuntimeMember"));
				case _:
			}
		}
		facts.sort(compareStrings);
		return facts;
	}

	static function captureField(field:ClassField):String {
		return field.name + ":type=" + TypeTools.toString(field.type) + ":kind=" + fieldKind(field.kind) + ":public=" + field.isPublic + ":final="
			+ field.isFinal + ":abstract=" + field.isAbstract + ":position=" + sourcePosition(field);
	}

	static function fieldKind(kind:FieldKind):String {
		return switch kind {
			case FVar(read, write): "var(" + read.getName() + "," + write.getName() + ")";
			case FMethod(method): "method(" + method.getName() + ")";
		};
	}

	static function constantText(expression:TypedExpr):String {
		return switch expression.expr {
			case TConst(TString(value)): 'string($value)';
			case TConst(TInt(value)): 'int($value)';
			case TCast(inner, _), TMeta(_, inner), TParenthesis(inner): constantText(inner);
			case _: "non-literal";
		};
	}

	static function requiredField(fields:Array<ClassField>, name:String):ClassField {
		for (field in fields)
			if (field.name == name)
				return field;
		throw new haxe.Exception('missing fixture field $name');
	}

	static function hasField(fields:Array<ClassField>, name:String):Bool {
		for (field in fields)
			if (field.name == name)
				return true;
		return false;
	}

	static function typeParameterNames(parameters:Array<TypeParameter>):Array<String> {
		return [for (parameter in parameters) parameter.name];
	}

	static function fullName(base:BaseType):String {
		return base.pack.concat([base.name]).join(".");
	}

	static function sourcePosition(value:{pos:Position}):String {
		final position = Context.getPosInfos(value.pos);
		return Path.withoutDirectory(position.file) + ":" + position.min + "-" + position.max;
	}

	static function recordEvent(event:String):Void {
		events.push(event);
		File.saveContent(tracePath, events.join("\n") + "\n");
	}

	static function closeRequest():Void {
		recordEvent("close");
		valueExpression = null;
		afterTypingTypes = [];
		generationTypes = [];
		sourceFacts = [];
	}

	static function abortAndClose():Void {
		removeTree(candidateRoot);
		closeRequest();
	}

	static function createDirectory(path:String):Void {
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
	}

	static function removeTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (entry in FileSystem.readDirectory(path))
			removeTree(Path.join([path, entry]));
		FileSystem.deleteDirectory(path);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}

	static function requiredDefine(name:String):String {
		final value = Context.definedValue(name);
		if (value == null || value.length == 0)
			Context.fatalError('missing required define $name', Context.currentPos());
		return value;
	}

	static function optionalDefine(name:String, fallback:String):String {
		final value = Context.definedValue(name);
		return value == null || value.length == 0 ? fallback : value;
	}
}
#end
