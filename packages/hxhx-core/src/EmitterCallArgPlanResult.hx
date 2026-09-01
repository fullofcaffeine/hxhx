/** Result of aligning source arguments with one declaration-owned call signature. **/
enum EmitterCallArgPlanResult {
	Planned(plan:EmitterCallArgPlan);
	MissingRequired(paramIndex:Int, paramName:String);
}
