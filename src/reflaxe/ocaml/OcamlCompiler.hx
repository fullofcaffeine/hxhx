package reflaxe.ocaml;

#if (macro || reflaxe_runtime)

import haxe.io.Path;
import haxe.macro.Type;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;

import reflaxe.DirectToStringCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlBuilder;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRecordField;
import reflaxe.ocaml.ast.OcamlTypeDecl;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeRecordField;
import reflaxe.ocaml.ast.OcamlVariantConstructor;
import reflaxe.ocaml.runtimegen.DuneProjectEmitter;
import reflaxe.ocaml.runtimegen.OcamlBuildRunner;
import reflaxe.ocaml.runtimegen.RuntimeCopier;
import reflaxe.GenericCompiler;
import reflaxe.output.DataAndFileInfo;

using StringTools;

/**
 * Minimal OCaml compiler scaffold.
 *
 * Milestone 0 goal: register with Reflaxe and emit at least one `.ml` file.
 * Later milestones replace string stubs with a real OCaml IR pipeline.
 */
class OcamlCompiler extends DirectToStringCompiler {
	public static var instance:OcamlCompiler;
	final ctx:CompilationContext = new CompilationContext();
	final printer:OcamlASTPrinter = new OcamlASTPrinter();
	var mainModuleId:Null<String> = null;

	#if macro
	static var haxeStdRoots:Null<Array<String>> = null;

	static function normalizePath(p:String):String {
		if (p == null) return "";
		var s = p.replace("\\", "/");
		if (!s.endsWith("/")) s += "/";
		return s;
	}

	static function detectHaxeStdRoots():Array<String> {
		if (haxeStdRoots != null) return haxeStdRoots;

		final roots:Array<String> = [];
		for (cp in haxe.macro.Context.getClassPath()) {
			if (cp == null || cp.length == 0) continue;

			// Identify the real Haxe std root by probing for known files.
			// Avoid confusing it with this repo's own `std/` folder.
			final stdHx = Path.join([cp, "Std.hx"]);
			final logHx = Path.join([cp, "haxe", "Log.hx"]);
			if (sys.FileSystem.exists(stdHx) && sys.FileSystem.exists(logHx)) {
				roots.push(normalizePath(cp));
			}
		}

		haxeStdRoots = roots;
		return roots;
	}

	static function isPosInHaxeStd(pos:haxe.macro.Expr.Position):Bool {
		final info = haxe.macro.Context.getPosInfos(pos);
		final file = normalizePath(info.file);
		for (root in detectHaxeStdRoots()) {
			if (StringTools.startsWith(file, root)) return true;
		}
		return false;
	}
	#end

	public function new() {
		super();
		instance = this;
	}

	public override function generateOutputIterator():Iterator<DataAndFileInfo<reflaxe.output.StringOrBytes>> {
		// Ensure type declarations (enums/typedefs/abstracts) appear before value
		// definitions in each module, since OCaml requires constructors/types to
		// be declared before use.
		final all:CompiledCollection<String> = enums.concat(typedefs).concat(abstracts).concat(classes);
		var index = 0;
		return {
			hasNext: () -> index < all.length,
			next: () -> {
				final data = all[index++];
				return data.withOutput(data.data);
			}
		};
	}

	public function compileClassImpl(
		classType:ClassType,
		varFields:Array<ClassVarData>,
		funcFields:Array<ClassFuncData>
	):Null<String> {
		ctx.currentModuleId = classType.module;
		ctx.variableRenameMap.clear();
		ctx.assignedVars.clear();
		#if macro
		ctx.currentIsHaxeStd = isPosInHaxeStd(classType.pos);
		#end

		final mainModule = getMainModule();
		final isMain = switch (mainModule) {
			case TClassDecl(clsRef):
				final m = clsRef.get();
				(m.module == classType.module) && (m.name == classType.name);
			case _: false;
		}
		if (isMain) {
			mainModuleId = StringTools.replace(classType.module, ".", "_");
		}

		final fullName = (classType.pack ?? []).concat([classType.name]).join(".");

		// Guardrails (M5.6.4): fail fast for OO features we haven't implemented.
		#if macro
		if (!ctx.currentIsHaxeStd) {
			final problems:Array<String> = [];

			if (classType.isInterface) {
				problems.push("interfaces");
			}

			if (classType.superClass != null) {
				final sup = classType.superClass.t.get();
				final supName = (sup.pack ?? []).concat([sup.name]).join(".");
				problems.push("inheritance (extends " + supName + ")");
			}

			if (classType.interfaces != null && classType.interfaces.length > 0) {
				final ifaceNames = classType.interfaces.map(function(i) {
					final it = i.t.get();
					return (it.pack ?? []).concat([it.name]).join(".");
				});
				problems.push("implements " + ifaceNames.join(", "));
			}

			if (problems.length > 0) {
				haxe.macro.Context.error(
					"reflaxe.ocaml (M5): unsupported OO feature(s) in '" + fullName + "': " + problems.join("; ")
					+ ".\nSupported for now: flat classes (fields + methods) without extends/implements. (bd: haxe.ocaml-28t.6.4)",
					classType.pos
				);
			}
		}
		#end

		final items:Array<OcamlModuleItem> = [];
		final builder = new OcamlBuilder(ctx);

		// Header marker as a no-op binding to keep output non-empty and debuggable.
		items.push(OcamlModuleItem.ILet([{
			name: "__reflaxe_ocaml__",
			expr: OcamlExpr.EConst(OcamlConst.CUnit)
		}], false));

		final lets:Array<OcamlLetBinding> = [];

		// Instance surface (M5): record type + create + instance methods.
		final instanceVars = varFields.filter(v -> !v.isStatic);
		final hasInstanceVars = instanceVars.length > 0;

		var ctorFunc:Null<ClassFuncData> = null;
		final instanceMethods:Array<ClassFuncData> = [];
		for (f in funcFields) {
			if (f.expr == null) continue;
			if (f.isStatic) continue;
			if (f.field.name == "new") {
				ctorFunc = f;
			} else {
				instanceMethods.push(f);
			}
		}

		final hasInstanceSurface = hasInstanceVars || instanceMethods.length > 0 || ctorFunc != null;
		if (hasInstanceSurface) {
			final typeFields:Array<OcamlTypeRecordField> = hasInstanceVars
				? instanceVars.map(v -> ({
					name: v.field.name,
					isMutable: true,
					typ: ocamlTypeExprFromHaxeType(v.field.type)
				}))
				: [];

			final typeDecl:OcamlTypeDecl = {
				name: "t",
				params: [],
				kind: hasInstanceVars
					? OcamlTypeDeclKind.Record(typeFields)
					: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TIdent("unit"))
			};
			items.push(OcamlModuleItem.IType([typeDecl], false));

			// create: allocate record, run ctor body, return self
			var createParams:Array<OcamlPat> = [OcamlPat.PConst(OcamlConst.CUnit)];
			var ctorBody:OcamlExpr = OcamlExpr.EConst(OcamlConst.CUnit);
			if (ctorFunc != null && ctorFunc.expr != null) {
				final argInfo = ctorFunc.args.map(a -> ({
					id: a.tvar != null ? a.tvar.id : -1,
					name: a.getName()
				}));
				switch (builder.buildFunctionFromArgsAndExpr(argInfo, ctorFunc.expr)) {
						case OcamlExpr.EFun(params, body):
							createParams = params;
							ctorBody = body;
						case _:
				}
			}

			final selfInit:OcamlExpr = if (hasInstanceVars) {
				final fields:Array<OcamlRecordField> = [];
				for (v in instanceVars) {
					final init = v.findDefaultExpr();
					final value = init != null ? builder.buildExpr(init) : defaultValueForType(v.field.type);
					fields.push({ name: v.field.name, value: value });
				}
				OcamlExpr.ERecord(fields);
			} else {
				OcamlExpr.EConst(OcamlConst.CUnit);
			}

			final createBody = OcamlExpr.ELet(
				"self",
				selfInit,
				OcamlExpr.ESeq([ctorBody, OcamlExpr.EIdent("self")]),
				false
			);
			lets.push({ name: "create", expr: OcamlExpr.EFun(createParams, createBody) });

			for (f in instanceMethods) {
				final compiled = {
					final argInfo = f.args.map(a -> ({
						id: a.tvar != null ? a.tvar.id : -1,
						name: a.getName()
					}));
					switch (builder.buildFunctionFromArgsAndExpr(argInfo, f.expr)) {
						case OcamlExpr.EFun(params, b):
							OcamlExpr.EFun([OcamlPat.PVar("self")].concat(params), b);
						case _:
							OcamlExpr.EFun([OcamlPat.PVar("self")], OcamlExpr.EConst(OcamlConst.CUnit));
					}
				};
				lets.push({ name: f.field.name, expr: compiled });
			}
		}

		// Static functions (M2+)
		for (f in funcFields) {
			if (f.expr == null) continue;
			if (!f.isStatic) continue;

			final name = f.field.name;
			final argInfo = f.args.map(a -> ({
				id: a.tvar != null ? a.tvar.id : -1,
				name: a.getName()
			}));
			final compiled = builder.buildFunctionFromArgsAndExpr(argInfo, f.expr);

			lets.push({ name: name, expr: compiled });
		}
		if (lets.length > 0) {
			items.push(OcamlModuleItem.ILet(lets, false));
		}

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe type: " + fullName + " *)\n\n";
		out += printer.printModule(items);

		return out;
	}

	public override function onOutputComplete() {
		#if eval
		if (output == null || output.outputDir == null) return;
		final outDir = output.outputDir;

		final noDune = haxe.macro.Context.defined("ocaml_no_dune");
		if (!noDune) {
			DuneProjectEmitter.emit(output, {
				projectName: DuneProjectEmitter.defaultProjectName(outDir),
				exeName: DuneProjectEmitter.defaultExeName(outDir),
				mainModuleId: mainModuleId
			});
		}

		final noRuntime = haxe.macro.Context.defined("ocaml_no_runtime");
		if (!noRuntime) {
			RuntimeCopier.copy(output, "runtime");
		}

		final buildMode = haxe.macro.Context.definedValue("ocaml_build");
		final shouldRun = haxe.macro.Context.defined("ocaml_run");
		final noBuild = haxe.macro.Context.defined("ocaml_no_build");
		final emitOnly = haxe.macro.Context.defined("ocaml_emit_only");

		final shouldBuild = !noBuild && !emitOnly;
		final strictBuild = buildMode != null;

		if (!shouldBuild && !shouldRun && buildMode == null) return;

		final exeName = DuneProjectEmitter.defaultExeName(outDir);
		final mode = buildMode != null ? buildMode : "native";

		final result = OcamlBuildRunner.tryBuildAndMaybeRun({
			outDir: outDir,
			exeName: exeName,
			mode: mode,
			run: shouldRun,
			strict: strictBuild
		});

		switch (result) {
			case Ok(msg):
				if (msg != null) haxe.macro.Context.warning(msg, haxe.macro.Context.currentPos());
			case Err(msg):
				// Strict mode (ocaml_build=...) should stop compilation if build fails.
				haxe.macro.Context.error(msg, haxe.macro.Context.currentPos());
		}
		#end
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
		final fullName = (enumType.pack ?? []).concat([enumType.name]).join(".");

		// ocaml.* surface types map to native Stdlib types; do not emit duplicate type decls.
		if (enumType.pack != null && enumType.pack.length == 1 && enumType.pack[0] == "ocaml") {
			switch (enumType.name) {
				case "List", "Option", "Result":
					return null;
				case _:
			}
		}

		final typeName = ocamlTypeName(enumType.name);
		final typeParams = enumType.params.map(p -> ocamlTypeParam(p.name));

		final ctors:Array<OcamlVariantConstructor> = [];
		for (opt in options) {
			final args:Array<OcamlTypeExpr> = [];
			for (a in opt.args) {
				var argType = ocamlTypeExprFromHaxeType(a.type);
				if (a.opt) {
					argType = OcamlTypeExpr.TApp("option", [argType]);
				}
				args.push(argType);
			}
			ctors.push({ name: opt.name, args: args });
		}

		final decl:OcamlTypeDecl = {
			name: typeName,
			params: typeParams,
			kind: OcamlTypeDeclKind.Variant(ctors)
		};

		final items:Array<OcamlModuleItem> = [OcamlModuleItem.IType([decl], false)];

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe enum: " + fullName + " *)\n\n";
		out += printer.printModule(items);
		return out;
	}

	public function compileExpressionImpl(expr:TypedExpr, topLevel:Bool):Null<String> {
		final builder = new OcamlBuilder(ctx);
		final e = builder.buildExpr(expr);
		return printer.printExpr(e);
	}

	function compileConstant(c:TConstant):Null<String> {
		return switch (c) {
			case TInt(i): Std.string(i);
			case TFloat(f): Std.string(f);
			case TString(s): "\"" + escapeOcamlString(s) + "\"";
			case TBool(b): b ? "true" : "false";
			case TNull: "()"; // placeholder
			case TThis: "self"; // placeholder
			case TSuper: "super"; // placeholder
		}
	}

	static function escapeOcamlString(s:String):String {
		// Minimal escaping for scaffold output; printer milestone will replace.
		return s
			.replace("\\", "\\\\")
			.replace("\"", "\\\"")
			.replace("\n", "\\n")
			.replace("\r", "\\r")
			.replace("\t", "\\t");
	}

	static function ocamlTypeName(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0) return "t";
		final first = haxeName.charCodeAt(0);
		final isUpper = first >= 65 && first <= 90;
		var s = (isUpper ? String.fromCharCode(first + 32) : haxeName.substr(0, 1)) + haxeName.substr(1);
		s = sanitizeLowerIdent(s);
		return s.length > 0 ? s : "t";
	}

	static function ocamlTypeParam(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0) return "a";
		return sanitizeLowerIdent(haxeName.toLowerCase());
	}

	static function sanitizeLowerIdent(name:String):String {
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c).toLowerCase() : "_");
		}
		var s = out.toString();
		if (s.length == 0) return s;
		final first = s.charCodeAt(0);
		if (first >= 48 && first <= 57) s = "_" + s;
		return s;
	}

	static function moduleIdToOcamlModuleName(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0) return "Main";
		final flat = moduleId.split(".").join("_");
		return flat.substr(0, 1).toUpperCase() + flat.substr(1);
	}

	function ocamlTypeExprFromHaxeType(t:Type):OcamlTypeExpr {
		return switch (t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlTypeExpr.TIdent("int");
					case "Float": OcamlTypeExpr.TIdent("float");
					case "Bool": OcamlTypeExpr.TIdent("bool");
					case "Void": OcamlTypeExpr.TIdent("unit");
					default: OcamlTypeExpr.TIdent("Obj.t");
				}
			case TInst(cRef, params):
				final c = cRef.get();
				switch (c.name) {
					case "String": OcamlTypeExpr.TIdent("string");
					default:
						OcamlTypeExpr.TIdent("Obj.t");
				}
			case TEnum(eRef, params):
				final e = eRef.get();
				final modName = moduleIdToOcamlModuleName(e.module);
				final full = modName + "." + ocamlTypeName(e.name);
				params.length == 0 ? OcamlTypeExpr.TIdent(full) : OcamlTypeExpr.TApp(full, params.map(ocamlTypeExprFromHaxeType));
			case TType(tRef, _):
				OcamlTypeExpr.TIdent("Obj.t");
			case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_):
				OcamlTypeExpr.TIdent("Obj.t");
			case TFun(_, _):
				OcamlTypeExpr.TIdent("Obj.t");
		}
	}

	function defaultValueForType(t:Type):OcamlExpr {
		return switch (t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					default: OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case TInst(cRef, _):
				final c = cRef.get();
				switch (c.name) {
					case "String": OcamlExpr.EConst(OcamlConst.CString(""));
					default: OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}
}

#end
