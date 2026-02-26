class BalancedTreeDispatchMain {
	static function main() {
		final tree:haxe.ds.BalancedTree<Int, String> = new haxe.ds.BalancedTree<Int, String>();
		Sys.println(Std.string(tree != null));
	}
}
