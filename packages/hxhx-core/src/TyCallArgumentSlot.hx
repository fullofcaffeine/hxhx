/**
	A selected parameter slot refers to source operand positions, not their types.
	Keep this data independent of typing and alignment so projection can reuse it
	without depending on the compiler's recursive declaration graph.
 */
enum TyCallArgumentSlot {
	Omitted;
	Supplied(sourceIndex:Int);
	RestElements(sourceIndices:Array<Int>);
	RestSpread(sourceIndex:Int);
}
