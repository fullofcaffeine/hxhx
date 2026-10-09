(* Independently observe emitted function inputs and results, not only termination. *)
let () =
  assert (Main.choose 7 9 = 7);
  assert (Main.choose (-3) 11 = -3);
  assert (Main.logical true);
  assert (not (Main.logical false));
  assert (Main.text "h\195\169\000z" = "h\195\169\000z");
  assert (Main.invoke 3 5 = 3);
  assert (Main.invoke (-8) 3 = -8);
  assert (Main.scoped 8 = 8);
  Main.hx_done ()

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
