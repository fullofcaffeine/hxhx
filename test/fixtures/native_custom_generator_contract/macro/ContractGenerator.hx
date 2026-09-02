package;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.JSGenApi;
import haxe.macro.Type;
import haxe.io.Path;
import sys.io.File;

/**
	Records the public Haxe custom-generator behavior needed by native hosts.

	The fixture is a behavior oracle, not an implementation. It keeps compiler
	objects inside upstream Haxe and writes only stable text observations.
**/
class ContractGenerator {
	static var events:Array<String> = [];
	static var valueExpression:Null<TypedExpr>;
	static var afterTypingTypes:Array<String> = [];
	static var generationTypes:Array<String> = [];
	static var sourceFacts:Array<String> = [];

	public static function install():Void {
		final tracePath = requiredDefine("contract_trace");
		events = [];
		valueExpression = null;
		afterTypingTypes = [];
		generationTypes = [];
		sourceFacts = [];

		Context.onAfterTyping(types -> {
			events.push("after-typing");
			afterTypingTypes = typeNames(types);
			valueExpression = findValueExpression(types);
			sourceFacts = captureSourceFacts(types);
		});
		Context.onGenerate(types -> {
			events.push("on-generate");
			generationTypes = generationTypeNames(types);
		});
		Context.onAfterGenerate(() -> {
			events.push("after-generate");
			File.saveContent(tracePath, events.join("\n") + "\n");
		});
		Compiler.setCustomJSGenerator(generate);
	}

	static function generate(api:JSGenApi):Void {
		events.push("generator-prepare");
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
		final statement = api.generateStatement(mainExpression);
		final value = api.generateValue(probeExpression);
		final added = api.addFeature("custom.generator.fixture");
		final present = api.hasFeature("custom.generator.fixture");
		File.saveContent(api.outputFile, [
			"contract=custom-generator-host-v1",
			"after-typing=" + afterTypingTypes.join(","),
			"on-generate=" + generationTypes.join(","),
			"source-facts=" + sourceFacts.join("|"),
			"value=" + value,
			"statement=" + statement.split("\n").join("\\n"),
			"type-accessor-calls=" + typeAccessorCalls,
			"feature-added=" + added,
			"feature-present=" + present
		].join("\n") + "\n");
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
		return base.pack.concat([base.name]).join(".");
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
		return base == null ? null : base.pack.concat([base.name]).join(".");
	}

	static function captureSourceFacts(types:Array<ModuleType>):Array<String> {
		final facts = new Array<String>();
		for (type in types) {
			switch type {
				case TClassDecl(reference):
					final cls = reference.get();
					if (cls.name == "ContractBox" || cls.name == "ContractReadable") {
						final fields = cls.fields.get();
						facts.push((cls.isInterface ? "interface:" : "class:") + fullName(cls) + ":parameters=" + cls.params.length + ":interfaces="
							+ cls.interfaces.length + ":read=" + hasField(fields, "read") + ":source=" + sourceFile(cls));
					}
				case TTypeDecl(reference):
					final definition = reference.get();
					if (definition.name == "ContractEnvelope") {
						final fieldCount = switch definition.type {
							case TAnonymous(fields): fields.get().fields.length;
							case _: 0;
						};
						facts.push("typedef:" + fullName(definition) + ":parameters=" + definition.params.length + ":anonymous-fields=" + fieldCount
							+ ":source=" + sourceFile(definition));
					}
				case TAbstract(reference):
					final abstraction = reference.get();
					if (abstraction.name == "ContractMode") {
						facts.push("abstract:" + fullName(abstraction) + ":enum=" + abstraction.meta.has(":enum") + ":source=" + sourceFile(abstraction));
					}
				case _:
			}
		}
		facts.sort(compareStrings);
		return facts;
	}

	static function hasField(fields:Array<ClassField>, name:String):Bool {
		for (field in fields)
			if (field.name == name)
				return true;
		return false;
	}

	static function fullName(base:BaseType):String {
		return base.pack.concat([base.name]).join(".");
	}

	static function sourceFile(base:BaseType):String {
		return Path.withoutDirectory(Context.getPosInfos(base.pos).file);
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
}
#end
