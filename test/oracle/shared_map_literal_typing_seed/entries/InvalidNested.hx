import haxe.ds.Map;

/** Entry context also checks the fields of fresh nested records. */
class InvalidNested {
	static function main():Void {
		final value:Map<String, {item:Int}> = ["value" => {item: true}];
	}
}
