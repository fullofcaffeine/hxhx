package backend.cpp;

import backend.cpp.CppManagedStoragePlan.CppManagedCellPlan;
import backend.cpp.CppManagedStoragePlan.CppManagedFunctionPlan;

/**
	Plan cells and nested callable transport from one exact capture catalog.
	The catalog may belong to a method or field initializer. Its root remains
	the caller's responsibility; only real nested functions receive callable ABIs.
	Binding events and lexical capture edges retain their original typed identities.
 */
class CppManagedCaptureStorage {
	final catalog:TypedBackendCaptureCatalog;
	final cells:Array<CppManagedCellPlan> = [];
	final closures:haxe.ds.StringMap<CppManagedFunctionPlan> = new haxe.ds.StringMap();

	public function new(catalog:TypedBackendCaptureCatalog, resolveType:TyType->TyType) {
		if (catalog == null || resolveType == null)
			throw "managed captures require an exact catalog and type application";
		this.catalog = catalog;
		final facts = catalog.getPlan();
		final captured = new haxe.ds.StringMap<Bool>();
		for (fn in facts.getFunctions())
			for (binding in fn.getCaptures())
				captured.set(binding.getCanonicalIdentity(), true);
		final byBinding = new haxe.ds.StringMap<CppManagedCellPlan>();
		for (source in facts.getBindings()) {
			final key = source.binding.getCanonicalIdentity();
			if (captured.exists(key)) {
				if (byBinding.exists(key))
					throw "managed storage repeats a declaration origin";
				final cell = new CppManagedCellPlan(source);
				cells.push(cell);
				byBinding.set(key, cell);
			}
		}
		for (expression in catalog.getExpressions()) {
			final fn = catalog.require(expression);
			final environment = new Array<CppManagedCellPlan>();
			for (binding in fn.getCaptures()) {
				final cell = byBinding.get(binding.getCanonicalIdentity());
				if (cell == null)
					throw "managed capture lacks its declaration allocation event";
				environment.push(cell);
			}
			final parameters = [
				for (binding in facts.getBindings())
					if (binding.functionIdentity == fn.identity && binding.creation == FunctionEntry) binding
			];
			parameters.sort((left, right) -> left.slot - right.slot);
			closures.set(fn.identity,
				new CppManagedFunctionPlan(fn, environment, resolveType(catalog.requireCallableType(expression)), parameters, null, resolveType));
		}
	}

	public function getCells():Array<CppManagedCellPlan> {
		catalog.assertCurrent();
		return cells.copy();
	}

	public function requireCell(binding:TyLocalBinding):CppManagedCellPlan {
		catalog.assertCurrent();
		if (binding != null)
			for (cell in cells)
				if (cell.source.binding == binding)
					return cell;
		throw "managed storage does not promote this binding";
	}

	public function requireClosure(expression:HxExpr):CppManagedFunctionPlan {
		final facts = catalog.require(expression);
		final closure = closures.get(facts.identity);
		if (closure == null)
			throw "managed storage lacks a cataloged closure";
		return closure;
	}

	/** Initializer and method capture catalogs contain real closures, never a substitute method root. */
	public function requireFunction(owner:CppManagedFunctionOwner):CppManagedFunctionPlan {
		return switch owner {
			case Closure(expression): requireClosure(expression);
			case Root(_): throw "capture storage cannot select a method root";
		};
	}
}
