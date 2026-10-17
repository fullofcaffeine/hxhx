/** Supply the real upstream Array implementation to isolated native quotation observers. */
class ArrayProvider {
	static function wrap<T>(storage:neko.NativeArray<T>, length:Int):Array<T> {
		if (neko.NativeArray.length(storage) != length)
			throw "quotation storage length differs";
		return neko.NativeArray.toArray(storage);
	}

	static function main():Void {
		// The VM module export table is dynamic. Only this typed, length-checked factory is exported.
		neko.vm.Module.local().setExport("wrap", wrap);
	}
}
