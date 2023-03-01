open Printf
open Ast 

type code_index = int 
type stack_index = int 
type heap_index = int 
type static_distance = int 
type offset  = int 

type label = string 
type location = label * (code_index option) 

type status_code = 
  | Halted 
  | Running 
  | CodeIndexOutOfBound 
  | StackIndexOutOfBound 
  | HeapIndexOutOfBound 
  | StackUnderflow 

type stack_item = 
  | STACK_INT of int 
  | STACK_BOOL of bool 
  | STACK_UNIT 
  | STACK_HI of heap_index    (* Pointer into Heap            *) 
  | STACK_RA of code_index    (* return address               *) 
  | STACK_FP of stack_index   (* Frame pointer                *) 
  | STACK_EP of stack_index   (* Stack pointer                *)


type heap_type = 
  | HT_PAIR 
  | HT_INL 
  | HT_INR 
  | HT_CLOSURE 

type heap_item = 
  | HEAP_INT of int 
  | HEAP_BOOL of bool 
  | HEAP_UNIT 
  | HEAP_HI of heap_index    (* Pointer into Heap            *) 
  | HEAP_CI of code_index    (* Code pointer for closures    *) 
  | HEAP_HEADER of int * heap_type (* int is number of items to follow *)       


type value_path =
  | STACK_LOCATION of offset
  | HEAP_LOCATION of offset

type 'a instruction =
  | PUSH of 'a * stack_item    (* modified *)
  | LOOKUP of 'a * value_path  (* modified *)
  | UNARY of 'a * unary_oper
  | OPER of 'a * oper
  | ASSIGN of 'a
  | SWAP of 'a
  | POP of 'a
  (*  | BIND of var            not needed *)
  | FST of 'a
  | SND of 'a
  | DEREF of 'a
  | APPLY of 'a
  | RETURN of 'a
  | MK_PAIR of 'a
  | MK_INL of 'a
  | MK_INR of 'a
  | MK_REF of 'a
  | MK_CLOSURE of 'a * location * int (* modified *)
  | TEST of 'a * location
  | CASE of 'a * location
  | GOTO of 'a * location
  | LABEL of 'a * label
  | HALT of 'a
  | TRY of 'a * location
  | UNTRY of 'a 
  | RAISE of 'a

let map f = function
  | PUSH(a, stack_item) -> PUSH(f a, stack_item) 
  | LOOKUP(a, value_path) -> LOOKUP(f a, value_path) 
  | UNARY(a, unary_oper) -> UNARY(f a, unary_oper) 
  | OPER(a, oper) -> OPER(f a, oper) 
  | ASSIGN a -> ASSIGN (f a) 
  | SWAP a -> SWAP (f a) 
  | POP a -> POP (f a) 
  | FST a -> FST (f a) 
  | SND a  -> SND (f a)  
  | DEREF a  -> DEREF (f a)  
  | APPLY a  -> APPLY (f a)  
  | RETURN a  -> RETURN (f a)  
  | MK_PAIR a  -> MK_PAIR (f a)  
  | MK_INL a  -> MK_INL (f a)  
  | MK_INR a  -> MK_INR (f a)  
  | MK_REF a  -> MK_REF (f a)  
  | MK_CLOSURE(a, location, int) -> MK_CLOSURE(f a, location, int) 
  | TEST(a, location) -> TEST(f a, location) 
  | CASE(a, location) -> CASE(f a, location) 
  | GOTO(a, location) -> GOTO(f a, location) 
  | LABEL(a, label) -> LABEL(f a, label) 
  | HALT a  -> HALT (f a)  
  | TRY (a, location) -> TRY (f a, location)
  | UNTRY a -> UNTRY (f a)
  | RAISE a -> RAISE (f a)

type 'a listing = 'a instruction list

type vm_state = 
  {
    stack_bound : stack_index; 
    code_bound  : code_index; 
    heap_bound  : code_index; 
    stack       : stack_item array; 
    heap        : heap_item array; 
    code        : unit instruction array;
    mutable sp : stack_index;  (* stack pointer *) 
    mutable fp : stack_index;  (* frame pointer *) 
    mutable ep : stack_index;  (* exception pointer *) 
    mutable cp : code_index;   (* code pointer  *) 
    mutable hp : heap_index;   (* next free     *) 
    mutable status : status_code; 
  } 

let get_instruction vm = Array.get vm.code vm.cp

let stack_top vm = Array.get vm.stack (vm.sp - 1) 

(********************** Printing ********************************) 

(* let string_of_list sep f l = 
   let rec aux f = function 
     | [] -> ""
     | [t] -> (f t)
     | t :: rest -> (f t) ^  sep  ^ (aux f rest)
   in "[" ^ (aux f l) ^ "]" *)

let string_of_status = function 
  | Halted               -> "halted" 
  | Running              -> "running" 
  | CodeIndexOutOfBound  -> "code index out-of-bound" 
  | StackIndexOutOfBound -> "stack index out-of-bound" 
  | HeapIndexOutOfBound  -> "heap index out-of-bound" 
  | StackUnderflow       -> "stack underflow" 

let string_of_stack_item = function 
  | STACK_INT i      -> "STACK_INT " ^ (string_of_int i)
  | STACK_BOOL true  -> "STACK_BOOL true"
  | STACK_BOOL false -> "STACK_BOOL false"
  | STACK_UNIT       -> "STACK_UNIT"
  | STACK_HI i       -> "STACK_HI " ^ (string_of_int i)
  | STACK_RA i       -> "STACK_RA " ^ (string_of_int i)
  | STACK_FP i       -> "STACK_FP " ^ (string_of_int i)
  | STACK_EP i       -> "STACK_EP " ^ (string_of_int i)

let string_of_heap_type = function 
  | HT_PAIR    -> "HT_PAIR"
  | HT_INL     -> "HT_INL"
  | HT_INR     -> "HT_INR"
  | HT_CLOSURE -> "HT_CLOSURE"


let string_of_heap_item = function 
  | HEAP_INT i      -> "HEAP_INT " ^ (string_of_int i)
  | HEAP_BOOL true  -> "HEAP_BOOL true"
  | HEAP_BOOL false -> "HEAP_BOOL false"
  | HEAP_UNIT       -> "HEAP_UNIT"
  | HEAP_HI i       -> "HEAP_HI " ^ (string_of_int i)
  | HEAP_CI i       -> "HEAP_CI " ^ (string_of_int i)
  | HEAP_HEADER (i, t) -> "HEAP_HEADER(" ^ (string_of_int i) ^ ", " ^ (string_of_heap_type t) ^ ")"


let string_of_value_path = function 
  | STACK_LOCATION offset -> "STACK_LOCATION " ^ (string_of_int offset)
  | HEAP_LOCATION offset  -> "HEAP_LOCATION " ^ (string_of_int offset)

let string_of_location = function 
  | (l, None) -> l 
  | (l, Some i) -> l ^ " = " ^ (string_of_int i) 

let string_of_instruction = function
  | UNARY(_, op) -> "UNARY " ^ (string_of_uop op)
  | OPER(_, op)  -> "OPER " ^ (string_of_bop op)
  | MK_PAIR _ -> "MK_PAIR"
  | FST _      -> "FST"
  | SND _      -> "SND"
  | MK_INL _   -> "MK_INL"
  | MK_INR _   -> "MK_INR"
  | MK_REF _   -> "MK_REF"
  | PUSH(_, v)   -> "PUSH " ^ (string_of_stack_item v)
  | LOOKUP(_, p) -> "LOOKUP " ^ (string_of_value_path p)
  | TEST(_, l)   -> "TEST " ^ (string_of_location l)
  | CASE(_, l)   -> "CASE " ^ (string_of_location l)
  | GOTO(_, l)   -> "GOTO " ^ (string_of_location l)
  | APPLY _    -> "APPLY"
  | RETURN _   -> "RETURN"
  | HALT _     -> "HALT"
  | LABEL(_, l)  -> "LABEL " ^ l
  | SWAP _     -> "SWAP"
  | POP _      -> "POP"
  | DEREF _    -> "DEREF"
  | ASSIGN _   -> "ASSIGN"
  | MK_CLOSURE (_, loc, n)
    -> "MK_CLOSURE(" ^ (string_of_location loc) 
       ^ ", " ^ (string_of_int n) ^ ")"
  | TRY _ -> "TRY"
  | UNTRY _ -> "UNTRY"
  | RAISE _ -> "RAISE"
let rec string_of_listing = function 
  | [] -> "\n"  
  | (LABEL(_, l)) :: rest -> ("\n" ^ l ^ " :") ^ (string_of_listing rest)
  | i :: rest -> "\n\t" ^ (string_of_instruction i) ^ (string_of_listing rest) 

let string_of_installed_code (code, size)  = 
  let rec aux k = 
    if size = k 
    then "" 
    else (string_of_int k) ^ ": " 
         ^ (string_of_instruction (code.(k))) 
         ^ "\n" ^ (aux (k+1)) 
  in aux 0

let string_of_stack(sp, stack) = 
  let rec aux carry j = 
    if j = sp then carry 
    else aux ((string_of_int j) ^ ": " 
              ^ (string_of_stack_item (Array.get stack j)) 
              ^ "\n" ^ carry) (j + 1) 
  in aux "" 0

let string_of_heap vm = 
  let rec aux k = 
    if vm.hp <= k 
    then "" 
    else (string_of_int k) ^ " -> " ^ (string_of_heap_item (vm.heap.(k))) ^ "\n" ^ (aux (k+1)) 
  in "\nHeap = \n" ^ (aux 0) 


let string_of_state vm = 
  "cp = " ^ (string_of_int vm.cp) ^ " -> " 
  ^ (string_of_instruction (get_instruction vm)) ^ "\n"
  ^ "fp = " ^ (string_of_int vm.fp) ^ "\n"
  ^ "Stack = \n" ^(string_of_stack(vm.sp, vm.stack)) 
  ^ (if vm.hp = 0 then "" else string_of_heap vm) 


(* the following two functions are needed to 
   pretty-print heap and stack values 
*) 
let rec string_of_heap_value a vm = 
  match Array.get vm.heap a with     
  | HEAP_INT i      -> string_of_int i
  | HEAP_BOOL true  -> "true"
  | HEAP_BOOL false -> "false"
  | HEAP_UNIT       -> "()"
  | HEAP_HI i       -> string_of_heap_value i vm 
  | HEAP_CI _       -> Errors.complain "string_of_heap_value: expecting value in heap, found code index"
  | HEAP_HEADER (_, ht) -> 
    (match ht with 
     | HT_PAIR -> "(" ^ (string_of_heap_value (a + 1) vm) ^ ", " ^ (string_of_heap_value (a + 2) vm) ^ ")"
     | HT_INL -> "inl(" ^ (string_of_heap_value (a + 1) vm) ^ ")" 
     | HT_INR -> "inr(" ^ (string_of_heap_value (a + 1) vm) ^ ")" 
     | HT_CLOSURE -> "CLOSURE"
    )

let string_of_value vm = 
  match stack_top vm with 
  | STACK_INT i      -> string_of_int i
  | STACK_BOOL true  -> "true"
  | STACK_BOOL false -> "false"
  | STACK_UNIT       -> "()"
  | STACK_HI a       -> string_of_heap_value a vm
  | STACK_RA _       -> Errors.complain "string_of_value: expecting value on stack top, found code index"
  | STACK_FP _       -> Errors.complain "string_of_value: expecting value on stack top, found frame pointer"
  | STACK_EP _       -> Errors.complain "string_of_value: expecting value on stack top, found exception pointer"



(***************************** THE MACHINE ********************************) 


let readint () = let _ = print_string "input> " in read_int() 

let stack_to_heap_item = function 
  | STACK_INT i -> HEAP_INT i
  | STACK_BOOL b -> HEAP_BOOL b
  | STACK_UNIT -> HEAP_UNIT 
  | STACK_HI i -> HEAP_HI i 
  | STACK_RA i -> HEAP_CI i 
  | STACK_FP _ -> Errors.complain "stack_to_heap_item: no frame pointer allowed on heap" 
  | STACK_EP _ -> Errors.complain "stack_to_heap_item: no exception pointer allowed on heap" 

let heap_to_stack_item = function 
  | HEAP_INT i -> STACK_INT i
  | HEAP_BOOL b -> STACK_BOOL b
  | HEAP_UNIT -> STACK_UNIT 
  | HEAP_HI i -> STACK_HI i 
  | HEAP_CI i -> STACK_RA i 
  | HEAP_HEADER (_,_) -> Errors.complain "heap_to_stack_item : heap header not allowed on stack" 

(* cp := cp + 1  *)     
let advance_cp vm = 
  if vm.cp < vm.code_bound 
  then { vm with cp = vm.cp + 1 } 
  else { vm with status = CodeIndexOutOfBound } 

(* ep := k *)
let set_ep (k, vm) = 
  { vm with ep = k }

let goto(i, vm) = { vm with cp = i } 

(* pop n items from stack *) 
let pop(n, vm) = 
  if 0 <= vm.sp - n 
  then { vm with sp =vm.sp - n  } 
  else { vm with status = StackUnderflow } 

let pop_top vm = let c = stack_top vm in (c, pop(1, vm))

(* pop c onto stack  *) 
let push(c, vm) = 
  if vm.sp < vm.stack_bound 
  then let _ = Array.set vm.stack vm.sp c in { vm with sp = vm.sp + 1 } 
  else { vm with status = StackIndexOutOfBound } 

let swap vm = 
  let (c1, vm1) = pop_top vm in 
  let (c2, vm2) = pop_top vm1 in push(c2, push(c1, vm2))


let do_unary = function 
  | (NOT,  STACK_BOOL m) -> STACK_BOOL (not m)
  | (NEG,  STACK_INT m)  -> STACK_INT (-m)
  | (READ, STACK_UNIT)   -> STACK_INT (readint())
  | (op, _) -> Errors.complain ("do_unary: malformed unary operator: " ^ (string_of_unary_oper op))

let do_oper = function 
  | (AND,  STACK_BOOL m,  STACK_BOOL n) -> STACK_BOOL (m && n)
  | (OR,   STACK_BOOL m,  STACK_BOOL n) -> STACK_BOOL (m || n)
  | (EQB,  STACK_BOOL m,  STACK_BOOL n) -> STACK_BOOL (m = n)
  | (LT,   STACK_INT m,   STACK_INT n)  -> STACK_BOOL (m < n)
  | (EQI,  STACK_INT m,   STACK_INT n)  -> STACK_BOOL (m = n)
  | (ADD,  STACK_INT m,   STACK_INT n)  -> STACK_INT (m + n)
  | (SUB,  STACK_INT m,   STACK_INT n)  -> STACK_INT (m - n)
  | (MUL,  STACK_INT m,   STACK_INT n)  -> STACK_INT (m * n)
  | (DIV,  STACK_INT m,   STACK_INT n)  -> STACK_INT (m / n)
  | (op, _, _)  -> Errors.complain ("do_oper: malformed binary operator: " ^ (string_of_oper op))


let perform_op(op, vm) = 
  let (v_right, vm1) = pop_top vm in 
  let (v_left, vm2) = pop_top vm1 in 
  push(do_oper(op, v_left, v_right), vm2) 

let perform_unary(op, vm) = 
  let (v, vm1) = pop_top vm in push(do_unary(op, v), vm1) 

(* implement garbage collection! 

   This should free up all heap space 
   not reachable from the stack. 

   Might also increase heap size. 

   Result: 
   None = no progress 
   Some(vm') = progress made, resulting in vm'
*) 
let invoke_garbage_collection _  = None 

let allocate(n, vm) = 
  let hp1 = vm.hp in 
  if hp1 + n < vm.heap_bound 
  then (hp1, { vm with hp = vm.hp + n })  
  else match invoke_garbage_collection vm with 
    | None -> Errors.complain "allocate : heap exhausted"
    | Some vm2 -> 
      if vm2.hp + n < vm2.heap_bound 
      then (vm2.hp, { vm2 with hp = vm2.hp + n })  
      else Errors.complain "allocate : heap exhausted"

let mk_pair vm = 
  let (v_right, vm1) = pop_top vm in 
  let (v_left, vm2) = pop_top vm1 in 
  let (a, vm3) = allocate(3, vm2) in 
  let header = HEAP_HEADER (3, HT_PAIR) in 
  let _ = Array.set vm.heap a header in 
  let _ = Array.set vm.heap (a + 1) (stack_to_heap_item v_left) in 
  let _ = Array.set vm.heap (a + 2) (stack_to_heap_item v_right) in 
  push(STACK_HI a, vm3) 

let do_fst vm = 
  let (v, vm1) = pop_top vm in 
  match v with 
  | STACK_HI a -> 
    (match vm1.heap.(a) with 
     | HEAP_HEADER(_, HT_PAIR) -> 
       push(heap_to_stack_item (vm.heap.(a + 1)), vm1) 
     | _ -> Errors.complain "do_fst : unexpectd heap item"     
    )
  | _ -> Errors.complain "do_fst : expecting heap pointer on stack"


let do_snd vm = 
  let (v, vm1) = pop_top vm in 
  match v with 
  | STACK_HI a -> 
    (match vm1.heap.(a) with 
     | HEAP_HEADER(_, HT_PAIR) -> 
       push(heap_to_stack_item (vm.heap.(a + 2)), vm1)      
     | _ -> Errors.complain "do_snd : unexpectd heap item"
    )
  | _ -> Errors.complain "do_snd : expecting heap pointer on stack"

let mk_inl vm = 
  let (v, vm1) = pop_top vm in 
  let (a, vm2) = allocate(2, vm1) in 
  let header = HEAP_HEADER (2, HT_INL) in 
  let _ = Array.set vm2.heap a header in 
  let _ = Array.set vm2.heap (a + 1) (stack_to_heap_item v) in 
  push(STACK_HI a, vm2) 

let mk_inr vm = 
  let (v, vm1) = pop_top vm in 
  let (a, vm2) = allocate(2, vm1) in 
  let header = HEAP_HEADER (2, HT_INR) in 
  let _ = Array.set vm2.heap a header in 
  let _ = Array.set vm2.heap (a + 1) (stack_to_heap_item v) in 
  push(STACK_HI a, vm2) 

let case(i, vm) = 
  let (c, vm1) = pop_top vm in 
  match c with 
  | STACK_HI a -> 
    let vm2 = push(heap_to_stack_item(vm.heap.(a + 1)), vm1) in 
    (match vm1.heap.(a) with 
     | HEAP_HEADER(_, HT_INR) -> goto(i, vm2) 
     | HEAP_HEADER(_, HT_INL) -> advance_cp vm2 
     | _ -> Errors.complain "case: runtime error, expecting union header in heap" 
    ) 
  | _ -> Errors.complain "case: runtime error, expecting heap index on top of stack" 


let mk_ref vm = 
  let (v, vm1) = pop_top vm in 
  let (a, vm2) = allocate(1, vm1) in 
  let _ = Array.set vm2.heap a (stack_to_heap_item v) in push(STACK_HI a, vm2) 


let deref vm = 
  let (v, vm1) = pop_top vm in 
  match v with 
  | STACK_HI a -> push(heap_to_stack_item (Array.get vm1.heap a) , vm1) 
  | _ -> Errors.complain "deref"

let assign vm = 
  let (c1, vm1) = pop_top vm in 
  let (c2, _) = pop_top vm1 in 
  match c2 with 
  | STACK_HI a ->
    if vm.sp < vm.heap_bound 
    then let _ = Array.set vm.heap a (stack_to_heap_item c1) in push(STACK_UNIT, vm)
    else { vm with status = HeapIndexOutOfBound } 
  | _ -> Errors.complain "assing: runtime error, expecting heap index on stack" 


let test(i, vm) = 
  pop(1, if stack_top vm = STACK_BOOL true then advance_cp vm else { vm with cp = i })

let return vm = 
  let current_fp = vm.fp in 
  match vm.stack.(current_fp), vm.stack.(vm.fp + 1) with 
  | (STACK_FP saved_fp, STACK_RA k) -> 
    let return_value = stack_top vm 
    in push(return_value, { vm with cp = k; fp = saved_fp ; sp = current_fp - 2}) 
  | _ -> Errors.complain "return : malformed stack frame" 

let fetch fp vm = function 
  | STACK_LOCATION offset -> vm.stack.(fp + offset)
  | HEAP_LOCATION offset -> 
    (match vm.stack.(fp - 1) with 
     | STACK_HI a -> heap_to_stack_item (vm.heap.(a + offset + 1))
     | _ -> Errors.complain "search : expecting closure pointer"
    ) 

let lookup fp vm vlp = push(fetch fp vm vlp, vm)

let mk_closure = function 
  | ((_, Some i), n, vm) -> 
    let (a, vm1) = allocate(2 + n, vm)       in 
    let header = HEAP_HEADER (2 + n, HT_CLOSURE) in 
    let code_address = HEAP_CI i             in 
    let _ = vm1.heap.(a)     <- header       in 
    let _ = vm1.heap.(a + 1) <- code_address in 
    let rec aux m = 
      if m = n 
      then () 
      else let v = stack_to_heap_item vm1.stack.(vm.sp - (m + 1)) in 
        let _ = vm1.heap.(a + m + 2) <- v in 
        aux (m + 1)
    in 
    let _ = aux 0 in 
    let vm2 = pop(n, vm1) in push(STACK_HI a, vm2) 
  | ((_, None), _, _) ->  Errors.complain "mk_closure : internal error, no address in closure!"

let apply vm = 
  match stack_top vm with 
  | STACK_HI a -> 
    (match vm.heap.(a+1) with
     | HEAP_CI i -> 
       let new_fp = vm.sp 
       in let saved_fp = STACK_FP vm.fp
       in let return_index = STACK_RA (vm.cp + 1)
       in let new_vm = { vm with cp = i; fp = new_fp }
       in push(return_index, push(saved_fp, new_vm ))
     | _ -> Errors.complain "apply: runtime error, expecting code index in heap") 
  | _ -> Errors.complain "apply: runtime error, expecting heap index on top of stack" 

let add_try (vm, k) =
  push(STACK_INT(k), 
    push(STACK_INT vm.fp, 
      push(STACK_INT vm.ep, vm) (* TODO: Check *)
    )
  )

let untry vm = 
  let v, vm1 = pop_top vm in
  let vm2 = pop (2, vm1) in 
  let i, vm3 = pop_top vm2 in
  match i with 
  | STACK_EP(i) -> {(push(v, vm3)) with ep = i}
  | _ -> Errors.complain "untry: runtime error, expecting exception pointer on top of stack"

let raise vm = 
  let rec find_try vm = 
    let top1, vm1 = pop_top vm in 
    let top2, vm2 = pop_top vm1 in
    let top3, vm3 = pop_top vm2 in
    match (top1, top2, top3) with
    | (STACK_INT(cp), STACK_INT(fp), STACK_INT(ep)) -> 
      {vm3 with cp=cp; fp=fp; ep=ep}
    | (_, _, _) ->
      if vm1.status = StackUnderflow then
        Errors.complain "raise: runtime error, expecting previous try block on stack"
      else find_try vm1 in
  let v, vm1 = pop_top vm in
  push (v, (find_try vm1))



let step vm =
  match get_instruction vm with
  | UNARY(_, op)          -> advance_cp (perform_unary(op, vm))
  | OPER(_, op)           -> advance_cp (perform_op(op, vm))
  | MK_PAIR _           -> advance_cp (mk_pair vm)
  | FST _              -> advance_cp (do_fst vm)
  | SND _              -> advance_cp (do_snd vm)
  | MK_INL _            -> advance_cp (mk_inl vm)
  | MK_INR _           -> advance_cp (mk_inr vm)
  | PUSH(_, c)            -> advance_cp (push(c, vm))

  | APPLY _             -> apply vm
  | LOOKUP(_, vp)         -> advance_cp (lookup vm.fp vm vp)
  | RETURN _            -> return vm
  | MK_CLOSURE(_, l, n)  -> advance_cp (mk_closure(l, n, vm))

  | SWAP _              -> advance_cp (swap vm)
  | POP _               -> advance_cp (pop (1, vm))
  | LABEL(_, _)           -> advance_cp vm
  | DEREF _             -> advance_cp (deref vm)
  | MK_REF _           -> advance_cp (mk_ref vm)
  | ASSIGN _          -> advance_cp(assign vm)
  | HALT _              -> { vm with status = Halted }
  | GOTO (_, (_, Some i))  -> goto(i, vm)
  | TEST (_, (_, Some i))  -> test(i, vm)
  | CASE (_, (_, Some i))  -> case(i, vm)
  | TRY (_, (_, Some i)) -> advance_cp (add_try (vm, i))
  | UNTRY (_) -> advance_cp (untry vm)
  | RAISE (_) -> raise vm

  | _ -> Errors.complain ("step : bad state = " ^ (string_of_state vm) ^ "\n")


(* DRIVER *) 

let rec driver n vm = 
  let _ = if Option.verbose 
    then print_string ("========== state " ^ (string_of_int n) ^ 
                       " ==========\n" ^ (string_of_state vm) ^ "\n") 
    else () 
  in if vm.status = Running then driver (n+1) (step vm) else vm 

let map_instruction_labels f = function 
  | GOTO(l, (lab, _)) -> GOTO(l, (lab, Some(f lab)))
  | TEST (l, (lab, _)) -> TEST(l, (lab, Some(f lab)))
  | CASE (l, (lab, _)) -> CASE(l, (lab, Some(f lab)))
  | MK_CLOSURE (l, ((lab, _)), n) -> MK_CLOSURE((l, (lab, Some(f lab)), n))
  | inst -> inst 

let rec find l y = 
  match l with 
  | [] -> Errors.complain ("Compile.find : " ^ y ^ " is not found")
  | (x, v) :: rest -> if x = y then v else find rest y 


(* put code listing into an array, associate an array index to each label *) 
let load instr_list = 
  (* find array index for each label *) 
  let mk_label_to_address l = 
    let rec aux carry k = function 
      | [] -> carry 
      | ((LABEL (_, lab)) :: rest) -> aux ((lab, k) :: carry) (k +1) rest
      | _ :: rest           -> aux carry (k+1) rest 
    in aux [] 0 l 
  in let label_to_address = mk_label_to_address instr_list 
  in let locate_instr = map_instruction_labels (find label_to_address)
  in let located_instr_list = List.map locate_instr instr_list 
  in let result = Array.of_list located_instr_list
  in (result, Array.length result) 

let initial_state l = 
  let (code_array, c_bound) = load l in 
  let _ = if Option.verbose 
    then print_string ("\nInstalled Code = \n" ^ (string_of_installed_code(code_array, c_bound))) 
    else () in 
  { 
    stack_bound = Option.stack_max; 
    heap_bound = Option.heap_max; 
    code_bound = c_bound; 
    stack = Array.make Option.stack_max (STACK_INT 0);
    heap = Array.make Option.heap_max (HEAP_INT 0);
    code = code_array; 
    ep = 0;
    sp = 0; 
    fp = 0; 
    cp = 0; 
    hp = 0; 
    status = Running; 
  } 

let first_frame vm = 
  let saved_fp = STACK_FP 0
  in let return_index = STACK_RA 0 
  in push(return_index, push(saved_fp, vm))

let run l = 
  let vm = driver 1 (first_frame (initial_state l)) in 
  match vm.status with 
  | Halted   -> vm 
  | status -> Errors.complain ("run : stopped wth status " ^ (string_of_status status))




(* COMPILE *) 

let label_ref = ref 0
let new_label = 
  let get () = let v = !label_ref in (label_ref := (!label_ref) + 1; "L"^ (string_of_int v))
  in get 

(*

Interp 2

 | (APPLY :: ds,  V(CLOSURE (_, (c, env))) :: (V v) :: evs) 
    -> (c @ ds, (V v) :: (EV env) :: evs)

Interp 3 

 | (APPLY,  V(CLOSURE ((_, Some i), env)) :: (V v) :: evs) 
    -> (i, (V v) :: (EV env) :: (RA (cp + 1)) :: evs)


Jargon VM : 

     [clsoure    ] 
     [arg        ]   
        ... 

 == APPLY ==> 

     [return address]
fp ->[old fp        ] 
     [clsoure       ] 
     [arg           ]   
        ... 

*) 

let positions l = 
  let rec aux k = function 
    | [] -> [] 
    | a :: rest -> (a, k) :: (aux (k+1) rest) 
  in aux 1 l 


let rec comp vmap = function
  | Unit l           -> ([], [PUSH(l, STACK_UNIT)])
  | Boolean(l, b)      -> ([], [PUSH (l, STACK_BOOL b)])
  | Integer(l, n)      -> ([], [PUSH (l, STACK_INT n)])
  | UnaryOp(l, op, e) -> let (defs, c) = comp vmap e in  (defs, c @ [UNARY(l, op)])
  | Op(l, e1, op, e2) -> let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    (defs1 @ defs2, c1 @ c2 @ [OPER(l, op)])
  | Pair(l, e1, e2)   -> let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    (defs1 @ defs2, c1 @ c2 @ [MK_PAIR l])
  | Fst(l, e)          -> let (defs, c) = comp vmap e in (defs, c @ [FST l])
  | Snd(l, e)          -> let (defs, c) = comp vmap e in (defs, c @ [SND l])
  | Inl(l, e)          -> let (defs, c) = comp vmap e in (defs, c @ [MK_INL l])
  | Inr(l, e)          -> let (defs, c) = comp vmap e in (defs, c @ [MK_INR l])
  | Case(l, e1, (l', x1, e2), (l'', x2, e3)) ->
    let inr_label = new_label () in
    let after_inr_label = new_label () in
    let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap (Lambda(l', x1, e2)) in
    let (defs3, c3) = comp vmap (Lambda(l'', x2, e3)) in
    (defs1 @ defs2 @ defs3,
     (c1
      @ [CASE(l, (inr_label, None))]
      @ c2
      @ [APPLY l'; GOTO (l', (after_inr_label, None));
         LABEL (l', inr_label)]
      @ c3
      @ [APPLY l''; LABEL(l'', after_inr_label)]))
  | If(l, e1, e2, e3) -> let else_label = new_label () in
    let after_else_label = new_label () in
    let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    let (defs3, c3) = comp vmap e3 in
    (defs1 @ defs2 @ defs3,
     (c1
      @ [TEST(l, (else_label, None))]
      @ c2
      @ [GOTO (l, (after_else_label, None)); LABEL(l, else_label)]
      @ c3
      @ [LABEL(l, after_else_label)]))
  | Seq (_, [])         -> ([], [])
  | Seq (_, [e])        -> comp vmap e
  | Seq (l, (e ::rest)) -> let (defs1, c1) = comp vmap e in
    let (defs2, c2) = comp vmap (Seq(l, rest)) in
    (defs1 @ defs2, c1 @ [POP l] @ c2)
  | Ref (l, e)          -> let (defs, c) = comp vmap e in (defs, c @ [MK_REF l])
  | Deref (l, e)        -> let (defs, c) = comp vmap e in (defs, c @ [DEREF l])
  | While(l, e1, e2)  -> let test_label = new_label () in
    let end_label = new_label () in
    let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    (defs1 @ defs2,
     [LABEL(l, test_label)]
     @ c1
     @ [TEST(l, (end_label, None))]
     @ c2
     @ [POP l; GOTO(l, (test_label, None)); LABEL(l, end_label); PUSH(l, STACK_UNIT)])
  | Assign(l, e1, e2) -> let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    (defs1 @ defs2, c1 @ c2 @ [ASSIGN l])

  | App(l, e1, e2)    -> let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap e2 in
    (defs1 @ defs2, c2 @ c1 @ [APPLY l])
  | Var(l, x)           -> ([], [LOOKUP(l, find vmap x)])
  | LetFun(l, f, (l', x, e1), e2) -> comp vmap (App(l, Lambda(l, f, e2), Lambda(l', x, e1)))
  | Lambda(l, x, e)           -> comp_lambda vmap (l, None, x, e)
  | LetRecFun(l, f, (l', x, e1), e2) ->
    let (defs1, c1) = comp vmap (Lambda(l, f, e2)) in
    let (defs2, c2) = comp_lambda vmap (l', Some f, x, e1) in
    (defs1 @ defs2, c2 @ c1 @ [APPLY l])
  (* TODO: implement functionality *)
  | Try(l, e1, x, (l', x', e2))  -> 
    let exception_label = new_label () in
    let post_exception_label = new_label () in
    let (defs1, c1) = comp vmap e1 in
    let (defs2, c2) = comp vmap (Lambda(l', x', e2)) in (* TODO: check if this works *)
    (defs1 @ defs2, TRY(l, (exception_label, None)) :: c1 @ [UNTRY l; GOTO(l, (post_exception_label, None)); LABEL(l, exception_label)] @ c2 @ [APPLY l; LABEL(l, post_exception_label)])
  | Raise(l, e) -> 
    let (defs, c) = comp vmap e in
    (defs, c @ [RAISE(l)])

and comp_lambda vmap (l, f_opt, x, e) =
  let bound_vars = match f_opt with | None -> [x]          | Some f -> [x; f] in
  let f = new_label () in
  let f_bind =     match f_opt with | None -> []           | Some f -> [(f, STACK_LOCATION (-1))]  in
  let x_bind = (x, STACK_LOCATION (-2)) in
  let fvars = Free_vars.free_vars (bound_vars, e)   in
  let fetch_fvars = List.map (fun y -> LOOKUP(l, find vmap y)) fvars in
  let fvar_bind (y, p) = (y, HEAP_LOCATION p) in
  let env_bind = List.map fvar_bind (positions fvars) in
  let new_vmap = x_bind :: (f_bind @ env_bind @ vmap) in
  let (defs, c) = comp new_vmap e in
  let def = [LABEL(l, f)] @ c @ [RETURN l] in
  (def @ defs, (List.rev fetch_fvars) @ [MK_CLOSURE(l, (f, None), List.length fvars)])

let compile e = 
  let (defs, c) = comp [] e in 
  let l = Ast.get_tag e in
  let result = c          (* body of program *) 
               @ [HALT l]   (* stop the interpreter *) 
               @ defs in  (* the function definitions *) 
  let _ = if Option.verbose 
    then print_string ("\nCompiled Code = \n" ^ (string_of_listing result))
    else () 
  in result 

let interpret e =
  (* Remove annotation from AST *)
  let e' = Ast.map (fun _ -> ()) e in
  run (compile e')

let reset = fun _ -> label_ref := 0
