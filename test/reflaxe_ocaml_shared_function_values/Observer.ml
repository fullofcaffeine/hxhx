(* Independently observe emitted function inputs and results, not only termination. *)
let () =
  List.iter (fun left -> List.iter (fun right ->
    assert (Main.equal left right = (left = right));
    assert (Main.different left right = (left <> right));
    assert (not (Main.callComparison left right))
  ) [-9; 0; 11]) [-9; 0; 11];
  List.iter (fun left -> List.iter (fun right ->
    assert (Main.conjunction left right = (left && right));
    assert (Main.disjunction left right = (left || right))
  ) [false; true]) [false; true];
  assert (Main.choose 7 9 = 7);
  assert (Main.choose (-3) 11 = -3);
  assert (Main.logical true);
  assert (not (Main.logical false));
  assert (Main.text "h\195\169\000z" = "h\195\169\000z");
  assert (Main.invoke 3 5 = 3);
  assert (Main.invoke (-8) 3 = -8);
  assert (Main.scoped 8 = 8);
  Main.hx_done ();
  assert (Main.branch true 0 9 = 0);
  assert (Main.branchReturn true 7 9 = 7);
  assert (Main.branchReturn false 7 9 = 9);
  assert (Main.branch false 0 9 = 9);
  assert (not (Main.branchBool true false true));
  assert (Main.branchBool false false true);
  assert (Main.branchText true "left" "right" = "left");
  assert (Main.branchText false "left" "right" = "right");
  assert (Main.branchBlock true (-7) 9 = -7);
  assert (Main.branchBlock false (-7) 9 = 9);
  assert (Main.nestedBranch true true 5 = 5);
  assert (Main.nestedBranch true false 5 = 17);
  assert (Main.nestedBranch false true 5 = 29);
  assert (Main.nestedBranch false false 5 = 5)

(* These effects independently detect OCaml's unspecified argument evaluation order. *)
let events = ref []
let left () = events := !events @ ["left"]; 11
let right () = events := !events @ ["right"]; 29
let combine first second =
  assert (first = 11 && second = 29);
  events := !events @ ["combine"];
  47
let assert_order result =
  assert (result = 47);
  assert (!events = ["left"; "right"; "combine"])

(* The generated expression must run its condition once and only one alternative. *)
let selected = ref false
let reset_conditional flag = selected := flag; events := []
let condition () = events := !events @ ["condition"]; !selected
let assert_conditional flag result =
  assert (result = (if flag then 11 else 29));
  assert (!events = (if flag then ["condition"; "left"] else ["condition"; "right"]))

(* A selected right operand can throw; a skipped operand must have no effects. *)
exception Binary_right
let binary_first = ref false
let binary_second = ref false
let binary_throws = ref false
let reset_binary first second throws =
  events := []; binary_first := first; binary_second := second; binary_throws := throws
let binary_left () = events := !events @ ["left"]; !binary_first
let binary_right () =
  events := !events @ ["right"];
  if !binary_throws then raise Binary_right else !binary_second
