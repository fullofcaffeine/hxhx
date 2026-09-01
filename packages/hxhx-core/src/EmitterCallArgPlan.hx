/**
	Maps source call arguments to the fixed parameters of one lowered Stage3 call.

	A null source index means that the declaration permits omission at that
	position, so the emitter must supply the target representation of an omitted
	Haxe argument. Parameters before `firstRenderedParam` were already applied to
	the rendered callee, such as an instance receiver written as `fn (this_)`.
**/
class EmitterCallArgPlan {
	final fixedSourceIndices:Array<Null<Int>>;
	final firstRenderedParam:Int;
	final restSourceStart:Int;

	public function new(fixedSourceIndices:Array<Null<Int>>, firstRenderedParam:Int, restSourceStart:Int) {
		this.fixedSourceIndices = fixedSourceIndices == null ? [] : fixedSourceIndices.copy();
		this.firstRenderedParam = firstRenderedParam;
		this.restSourceStart = restSourceStart;
	}

	/** Return source indices aligned with the signature's fixed parameters. **/
	public function getFixedSourceIndices():Array<Null<Int>>
		return fixedSourceIndices.copy();

	/** Return the first fixed parameter that still needs target emission. **/
	public function getFirstRenderedParam():Int
		return firstRenderedParam;

	/** Return the first source argument that belongs in the lowered rest array. **/
	public function getRestSourceStart():Int
		return restSourceStart;
}
