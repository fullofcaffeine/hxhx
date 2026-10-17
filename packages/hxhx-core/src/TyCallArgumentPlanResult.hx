/** Result of aligning source arguments with one declaration-owned call signature. **/
enum TyCallArgumentPlanResult {
	Planned(plan:TyCallArgumentPlan);

	/** Retain preceding selections so typing can report an earlier incompatible argument first. */
	MissingRequired(paramIndex:Int, paramName:String, preceding:TyCallArgumentPlan);
}
