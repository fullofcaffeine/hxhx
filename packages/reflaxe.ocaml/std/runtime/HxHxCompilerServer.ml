(* HXHX Stage3 compiler-server socket bridge.

   Why
   - Stage3 currently needs `--wait <host:port>` / `--connect <host:port>` transport support,
     but bootstrap codegen does not yet reliably access `sys.net.Socket.input/output` from Haxe.

   What
   - [waitSocket mode]:
       start a socket server and answer null-terminated request frames.
   - [connect mode request]:
       send one null-terminated request frame and return the raw response bytes.

   Scope
   - This bridge currently focuses on display-style requests used by Stage3 bring-up.
   - Non-display requests return an error-prefixed response (`0x02...`).
*)

let split_host_port (mode : string) : string * int =
  let trimmed = String.trim mode in
  if trimmed = "" then failwith "missing host/port value";
  let host, port_s =
    match String.rindex_opt trimmed ':' with
    | None -> ("127.0.0.1", trimmed)
    | Some idx ->
        let h = String.sub trimmed 0 idx |> String.trim in
        let p =
          String.sub trimmed (idx + 1) (String.length trimmed - idx - 1)
          |> String.trim
        in
        let h = if h = "" then "127.0.0.1" else h in
        (h, p)
  in
  let port =
    try int_of_string port_s with _ -> failwith ("invalid port: " ^ port_s)
  in
  if port <= 0 || port > 65535 then failwith ("invalid port: " ^ port_s);
  (host, port)

let resolve_host (host : string) : Unix.inet_addr =
  try Unix.inet_addr_of_string host
  with _ ->
    let entry = Unix.gethostbyname host in
    if Array.length entry.Unix.h_addr_list = 0 then
      failwith ("cannot resolve host: " ^ host)
    else entry.Unix.h_addr_list.(0)

let send_all (sock : Unix.file_descr) (payload : string) : unit =
  let bytes = Bytes.unsafe_of_string payload in
  let rec loop off len =
    if len > 0 then
      let sent = Unix.send sock bytes off len [] in
      if sent <= 0 then failwith "socket send failed" else loop (off + sent) (len - sent)
  in
  loop 0 (Bytes.length bytes)

let read_until_nul (sock : Unix.file_descr) : string =
  let tmp = Bytes.create 4096 in
  let out = Buffer.create 256 in
  let rec loop () =
    let n = Unix.recv sock tmp 0 4096 [] in
    if n = 0 then Buffer.contents out
    else
      let stop = ref false in
      let i = ref 0 in
      while !i < n && not !stop do
        let c = Bytes.get tmp !i in
        if c = '\000' then stop := true else Buffer.add_char out c;
        incr i
      done;
      if !stop then Buffer.contents out else loop ()
  in
  loop ()

let read_all (sock : Unix.file_descr) : string =
  let tmp = Bytes.create 4096 in
  let out = Buffer.create 256 in
  let rec loop () =
    let n = Unix.recv sock tmp 0 4096 [] in
    if n = 0 then Buffer.contents out
    else (
      Buffer.add_subbytes out tmp 0 n;
      loop ())
  in
  loop ()

let trim_cr (s : string) : string =
  let len = String.length s in
  if len > 0 && s.[len - 1] = '\r' then String.sub s 0 (len - 1) else s

let parse_args (request : string) : string list =
  let before_stdin =
    match String.index_opt request '\001' with
    | None -> request
    | Some idx -> String.sub request 0 idx
  in
  request |> (fun _ -> before_stdin)
  |> String.split_on_char '\n'
  |> List.map trim_cr
  |> List.filter (fun s -> s <> "")

let rec find_display_arg = function
  | "--display" :: value :: _ -> Some value
  | _ :: tl -> find_display_arg tl
  | [] -> None

let synthesize_display_response (display_request : string) : string =
  let ends_with suffix =
    let sl = String.length suffix in
    let dl = String.length display_request in
    dl >= sl && String.sub display_request (dl - sl) sl = suffix
  in
  if ends_with "@diagnostics" then "[{\"diagnostics\":[]}]"
  else if ends_with "@module-symbols" then "[{\"symbols\":[]}]"
  else if ends_with "@signature" then
    "{\"signatures\":[],\"activeSignature\":0,\"activeParameter\":0}"
  else if ends_with "@toplevel" then "<il></il>"
  else if ends_with "@type" then "<type>Dynamic</type>"
  else if ends_with "@position" then "<list></list>"
  else if ends_with "@usage" then "<list></list>"
  else "<list></list>"

let handle_request (request : string) : string =
  let args = parse_args request in
  match find_display_arg args with
  | Some display_request -> synthesize_display_response display_request
  | None -> "\002hxhx(stage3): wait socket request failed"

let waitSocket (mode : string) : int =
  let host, port = split_host_port mode in
  let addr = resolve_host host in
  let listener = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  (try Unix.setsockopt listener Unix.SO_REUSEADDR true with _ -> ());
  Unix.bind listener (Unix.ADDR_INET (addr, port));
  Unix.listen listener 10;
  while true do
    let client, _ = Unix.accept listener in
    (try
       let request = read_until_nul client in
       let reply = handle_request request in
       send_all client reply
     with _ -> ());
    (try Unix.close client with _ -> ())
  done;
  0

let connect (mode : string) (request : string) : string =
  let host, port = split_host_port mode in
  let addr = resolve_host host in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect sock (Unix.ADDR_INET (addr, port));
  send_all sock (request ^ "\000");
  let response = read_all sock in
  Unix.close sock;
  response
