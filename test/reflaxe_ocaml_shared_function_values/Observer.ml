(* Independently observe emitted function inputs and results, not only termination. *)
let () =
  assert (Main.choose 7 9 = 7);
  assert (Main.choose (-3) 11 = -3);
  assert (Main.logical true);
  assert (not (Main.logical false));
  assert (Main.text "h\195\169\000z" = "h\195\169\000z")
