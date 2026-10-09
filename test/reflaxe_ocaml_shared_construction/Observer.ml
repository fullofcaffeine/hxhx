(* Independent constructor contract: initialization precedes the body and returns
   the exact allocated record. Exceptions must preserve the effects already made. *)
type instance = { mutable value : int }

let events = ref []
let allocated = ref None
let record label = events := !events @ [label]

let allocate value =
  record "allocate";
  let instance = { value } in
  allocated := Some instance;
  instance

let initialize self value fail =
  record "body";
  (match !allocated with
  | Some original when original == self -> ()
  | _ -> failwith "constructor received another instance");
  if self.value <> value then failwith "initializer did not run first";
  self.value <- value + 1;
  if fail then failwith "constructor failure"

let verify create =
  let first = create 7 false in
  if !events <> ["allocate"; "body"] || first.value <> 8 then
    failwith "constructor order or value";
  (match !allocated with
  | Some original when original == first -> ()
  | _ -> failwith "constructor returned another instance");
  events := [];
  let second = create 11 false in
  if first == second || second.value <> 12 || first.value <> 8 then
    failwith "instances share storage";
  events := [];
  let failed =
    try ignore (create 19 true); false
    with Failure message when message = "constructor failure" -> true
  in
  if not failed || !events <> ["allocate"; "body"] then
    failwith "constructor exception or effects were lost";
  match !allocated with
  | Some instance when instance.value = 20 -> ()
  | _ -> failwith "constructor mutation was lost before exception"
