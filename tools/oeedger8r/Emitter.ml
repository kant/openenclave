(* 
  Copyright (c) Microsoft Corporation. All rights reserved.
  Licensed under the MIT License. 
*)

open Ast
open Plugin
open Printf
open Util  

(**************************** Begin Code borrowed and tweaked from CodeGen.ml *******************************************************)      
let is_foreign_array (pt: Ast.parameter_type) =
  match pt with
      Ast.PTVal _     -> false
    | Ast.PTPtr(t, a) ->
        match t with
            Ast.Foreign _ -> a.Ast.pa_isary
          | _             -> false
let get_array_dims (ns: int list) =
  (* Get the array declaration from a list of array dimensions.
   * Empty `ns' indicates the corresponding declarator is a simple identifier.
   * Element of value -1 means that user does not specify the dimension size.
   *)
  let get_dim n = if n = -1 then "[]" else sprintf "[%d]" n
  in
    if ns = [] then ""
    else List.fold_left (fun acc n -> acc ^ get_dim n) "" ns

let get_typed_declr_str (ty: Ast.atype) (declr: Ast.declarator) =
  let tystr = Ast.get_tystr  ty in
  let dmstr = get_array_dims declr.Ast.array_dims in
    sprintf "%s %s%s" tystr declr.Ast.identifier dmstr

(* Check whether given parameter is `const' specified. *)
let is_const_ptr (pt: Ast.parameter_type) =
  let aty = Ast.get_param_atype pt in
    match pt with
      Ast.PTVal _      -> false
    | Ast.PTPtr(_, pa) ->
      if not pa.Ast.pa_rdonly then false
      else
        match aty with
          Ast.Foreign _ -> false
        | _             -> true

(* Generate parameter representation. *)
let gen_parm_str (p: Ast.pdecl) =
  let (pt, (declr : Ast.declarator)) = p in
  let aty = Ast.get_param_atype pt in
  let str = get_typed_declr_str aty declr in
    if is_const_ptr pt then "const " ^ str else str

let retval_declr = { Ast.identifier = "_retval"; Ast.array_dims = []; }
let get_ret_tystr (fd: Ast.func_decl) = Ast.get_tystr fd.Ast.rtype
let get_plist_str (fd: Ast.func_decl) =
  if fd.Ast.plist = [] then ""
  else List.fold_left (fun acc pd -> acc ^ ", " ^ gen_parm_str pd)
                      (gen_parm_str (List.hd fd.Ast.plist))
                      (List.tl fd.Ast.plist)


(* This function is used to convert Array form into Pointer form.
 * e.g.: int array[10][20]   =>  [count = 200] int* array
 *
 * This function is called when generating proxy/bridge code and
 * the marshaling structure.
 *)
let conv_array_to_ptr (pd: Ast.pdecl): Ast.pdecl =
  let (pt, declr) = pd in
  let get_count_attr ilist =
    (* XXX: assume the size of each dimension will be > 0. *)
    Ast.ANumber (List.fold_left (fun acc i -> acc*i) 1 ilist)
  in
    match pt with
      Ast.PTVal _        ->  (pt, declr)
    | Ast.PTPtr(aty, pa) ->
      if Ast.is_array declr then
        let tmp_declr = { declr with Ast.array_dims = [] } in
        let tmp_aty = Ast.Ptr aty in
        let tmp_cnt = get_count_attr declr.Ast.array_dims in
        let tmp_pa = { pa with Ast.pa_size = { Ast.empty_ptr_size with Ast.ps_count = Some tmp_cnt } }
        in (Ast.PTPtr(tmp_aty, tmp_pa), tmp_declr)
      else (pt, declr)

(* Note that, for a foreign array type `foo_array_t' we will generate
 *   foo_array_t* ms_field;
 * in the marshaling data structure to keep the pass-by-address scheme
 * as in the C programming language.
*)
let mk_ms_member_decl (pt: Ast.parameter_type) (declr: Ast.declarator) (isecall: bool) =
  let aty = Ast.get_param_atype pt in
  let tystr =  
    if is_foreign_array pt then 
      sprintf "/* foreign array of type %s */ void" (Ast.get_tystr aty)
    else Ast.get_tystr aty 
  in
  let ptr = if is_foreign_array pt then "* " else "" in
  let field = declr.Ast.identifier in
  (* String attribute is available for in/inout both ecall and ocall.
   * For ocall ,strlen is called in trusted proxy ocde, so no need to defense it.
   *)
  let need_str_len_var (pt: Ast.parameter_type) =
    match pt with
    Ast.PTVal _        -> false
    | Ast.PTPtr(_, pa) ->
    if pa.Ast.pa_isstr || pa.Ast.pa_iswstr then
        match pa.Ast.pa_direction with
        Ast.PtrInOut | Ast.PtrIn ->  if isecall then true else false
        | _ -> false
    else false
  in
  let str_len = if need_str_len_var pt then sprintf "\tsize_t %s_len;\n" field else ""
  in
  let dmstr = get_array_dims declr.Ast.array_dims in
    sprintf "\t%s%s %s%s;\n%s" tystr ptr field dmstr str_len

(**************************** END Code borrowed and tweaked from CodeGen.ml *******************************************************)      

(* Open a file for writing in the specified directory.
   Also emit auto-generated marker in file.
 *)
let open_file (filename:string) (dir:string) = 
    let os = if dir = "." then
              open_out filename
            else
              open_out (dir ^ separator_str ^ filename) in
    fprintf os "/*\n";
    fprintf os " *  This file is auto generated by oeedger8r. DO NOT EDIT.\n";    
    fprintf os " */\n";
    os


(* oe: util functions *)
let oe_mk_ms_struct_name (fname: string) = fname ^ "_args_t"

(* Construct the string of structure definition *)
let oe_mk_struct_decl (fs: string) (name: string) =
  sprintf "typedef struct _%s {\n%s    oe_result_t _result;\n } %s;\n" name fs name

(* oe: Generate marshaling structure definition *)
let oe_gen_marshal_struct_impl (fd: Ast.func_decl) (errno: string) (isecall: bool) =
  let member_list_str = errno ^
  let new_param_list = List.map conv_array_to_ptr fd.Ast.plist in
  List.fold_left (fun acc (pt, declr) ->
          acc ^ mk_ms_member_decl pt declr isecall) "" new_param_list in
let struct_name = oe_mk_ms_struct_name fd.Ast.fname in
  match fd.Ast.rtype with
      Ast.Void -> oe_mk_struct_decl member_list_str struct_name
    | _ -> let rv_str = mk_ms_member_decl (Ast.PTVal fd.Ast.rtype) retval_declr isecall
           in oe_mk_struct_decl (rv_str ^ member_list_str) struct_name

(* This is the most complex function. 
 * For a parameter, get its size experssion.
*)
let oe_get_param_size (ptype, decl, argstruct) = 
  (* get the base type of the parameter *)
  let atype = 
    match Ast.get_param_atype ptype with
    | Ast.Ptr at -> at
    | _ -> Ast.get_param_atype ptype
  in 
  let base_t = Ast.get_tystr atype in

  let type_expr = 
    match ptype with
      | Ast.PTPtr (atype, ptr_attr) ->
        if ptr_attr.Ast.pa_isptr then
          sprintf "*(%s)0" base_t
        else base_t
      | _ -> base_t
  in

  (* convert an attribute to string *)
  let attr_value_to_string av = 
    match av with
    | None -> ""
    | Some (Ast.ANumber n) -> string_of_int n
    | Some (Ast.AString s) -> sprintf "%s%s" argstruct s  (*another parameter name *)
  in 
  let pa_size_to_string pa = 
    let c = attr_value_to_string pa.Ast.ps_count in
    if c <> "" then sprintf "(%s * sizeof(%s))" c type_expr
    else attr_value_to_string pa.Ast.ps_size
  in
  let decl_size_to_string (ptype:Ast.parameter_type) (d:Ast.declarator) =
    let dims = List.map  (fun i-> "[" ^ (string_of_int i) ^ "]") d.Ast.array_dims in
    let dims_expr = String.concat "" dims in
    sprintf "sizeof(%s%s)" type_expr dims_expr
  in
    match ptype with
        Ast.PTPtr (atype, ptr_attr) ->
          let pa_size = pa_size_to_string ptr_attr.Ast.pa_size in
          (* Compute declared size *)
          let decl_size = decl_size_to_string ptype decl in
          if  ptr_attr.Ast.pa_isstr then
            argstruct ^ decl.Ast.identifier ^ "_len * sizeof(char)"
          else if ptr_attr.Ast.pa_iswstr then
            argstruct ^ decl.Ast.identifier ^ "_len * sizeof(wchar_t)" 
          else 
            (* Prefer size attribute over decl size *)
            if pa_size="" then decl_size else pa_size
        | _ -> ""


(* Generate the prototype for a given function.
 * Optionally add an oe_enclave_t* first parameter.
 *)
let oe_gen_prototype (fd: Ast.func_decl) =
  sprintf "%s %s(%s)" (get_ret_tystr fd) fd.Ast.fname (get_plist_str fd)

let oe_gen_wrapper_prototype (fd: Ast.func_decl) (is_ecall:bool) =
  let plist_str = get_plist_str fd in  
  let retval_str = 
    if fd.Ast.rtype = Ast.Void then ""
    else sprintf "%s* _retval" (get_ret_tystr fd) in  
  let args = 
    if is_ecall then
      ["oe_enclave_t* enclave"; retval_str; plist_str]
    else
      [retval_str; plist_str] in 
  let args = List.filter (fun s-> s <> "") args
  in 
    sprintf "oe_result_t %s(%s)" fd.Ast.fname (String.concat ", " args)

(*
  Emit struct or union
*)

let emit_struct_or_union  (os:out_channel) (s:Ast.struct_def) (union:bool) =
  fprintf os "typedef %s %s {\n" (if union then "union" else "struct") s.Ast.sname;
  List.iter (fun (atype, decl) -> 
    let dims = List.map (fun d-> sprintf "[%d]" d) decl.Ast.array_dims in
    let dims_str = String.concat "" dims in
    fprintf os "    %s %s%s;\n" (Ast.get_tystr atype) decl.Ast.identifier dims_str
  ) s.Ast.mlist;
  fprintf os "} %s;\n\n" s.Ast.sname

let emit_enum (os:out_channel) (e:Ast.enum_def) = 
  let n = List.length e.Ast.enbody in
  fprintf os "typedef enum %s {\n" e.Ast.enname;
  List.iteri (fun idx (name, value) ->
    fprintf os "    %s%s" name
    (match value with
      | Ast.EnumVal (Ast.AString s) -> " = " ^ s
      | Ast.EnumVal (Ast.ANumber n) -> " = " ^ (string_of_int n)
      | Ast.EnumValNone -> "");
    if idx != (n-1) then fprintf os ",\n"
  ) e.Ast.enbody;
  fprintf os "} %s;\n\n" e.Ast.enname

(*
* Emit composite types defined in edl.
*)  
let emit_composite_type (os:out_channel) = function
| Ast.StructDef s -> emit_struct_or_union os s false  
| Ast.UnionDef u -> emit_struct_or_union os u true
| Ast.EnumDef e -> emit_enum os e
  
(*
 * Get function id for a given function.
 *)
let get_function_id (f:Ast.func_decl) =
  sprintf "fcn_id_%s" f.fname

(*
 * Emit function ids.
 *)
let emit_function_ids (os:out_channel) (ec: enclave_content) = 
  fprintf os "\n/* trusted function ids */\n";
  fprintf os "enum {\n";
  List.iteri (fun idx f ->
    fprintf os "    %s = %d,\n" (get_function_id f.Ast.tf_fdecl) idx
  ) ec.tfunc_decls;
  fprintf os "    fcn_id_trusted_call_id_max = OE_ENUM_MAX\n";
  fprintf os "};\n\n";
  fprintf os "\n/* untrusted function ids */\n";
  fprintf os "enum {\n";
  List.iteri (fun idx f ->
    fprintf os "    %s = %d,\n" (get_function_id f.Ast.uf_fdecl) idx
  ) ec.ufunc_decls;
  fprintf os "    fcn_id_untrusted_call_max = OE_ENUM_MAX\n";
  fprintf os "};\n\n"

(* oe: Generate args.h which contains structs for ecalls and ocalls *)
let oe_gen_args_header (ec: enclave_content) (dir:string)=  
  let structs = List.append
    (* For each ecall, generate its marshalling struct *)
    (List.map (fun d -> oe_gen_marshal_struct_impl d.Ast.tf_fdecl "" true) ec.tfunc_decls)
    (* For each ocall, generate its marshalling struct *) 
    (List.map (fun d -> oe_gen_marshal_struct_impl d.Ast.uf_fdecl "" true) ec.ufunc_decls)
  in  
  let header_fname = sprintf "%s_args.h" ec.file_shortnm in
  let guard_macro = sprintf "%s_ARGS_H" (String.uppercase ec.enclave_name) in
  let os = open_file header_fname dir in  
    fprintf os "#ifndef %s\n" guard_macro;
    fprintf os "#define %s\n\n" guard_macro;
    fprintf os "#include <stdint.h>\n";
    fprintf os "#include <stdlib.h> /* for wchar_t */ \n\n";
    fprintf os "#include <openenclave/bits/result.h>\n\n";
    List.iter (fun inc -> fprintf os "#include \"%s\"\n" inc) ec.include_list;    
    if ec.include_list <> [] then fprintf os "\n";
    if ec.comp_defs <> [] then fprintf os "/* User types specified in edl */\n";
    List.iter (emit_composite_type os) ec.comp_defs;
    if ec.comp_defs <> [] then fprintf os "\n";
    fprintf os "%s" (String.concat "\n" structs);
    emit_function_ids os ec; 
    fprintf os "\n#endif // %s\n" guard_macro;
    close_out os
  
(* 
  Generate a cast expression for a pointer argument.
  Pointer arguments need to be cast to their root type, since the
  marshalling struct has the root pointer.
  For example, int a[10][20] needs to be cast to int *.
*)
let get_cast_to_mem_expr (ptype, decl)= 
  match ptype with
  | Ast.PTVal _ -> ""
  | Ast.PTPtr (t, _) ->
      if Ast.is_array decl then
        sprintf "(%s*) " (get_tystr t)
      else if is_foreign_array ptype then
        sprintf "/* foreign array of type %s */ " (get_tystr t)
      else 
        sprintf "(%s) " (get_tystr t)

(* 
  Generate a cast expression to a specific pointer type.  
  For example, int* needs to be cast to  * (int ( *  )[5][6]).
*)
let get_cast_from_mem_expr (ptype, decl)= 
  match ptype with
  | Ast.PTVal _ -> ""
  | Ast.PTPtr (t, attr) ->
      if Ast.is_array decl then
        sprintf "*(%s (*)%s) " (get_tystr t) (get_array_dims decl.Ast.array_dims)
      else if is_foreign_array ptype then
        sprintf "/*foreign array*/ *(%s *) " (get_tystr t)
      else
        if attr.Ast.pa_rdonly then
           (* for ptrs, only constness is removed; add it back *)
           sprintf "(const %s) " (get_tystr t)
        else ""
  
let oe_copy_members_to_enclave (os:out_channel) (fd: Ast.func_decl) =  
  let is_primitive ptype =
    match ptype with
    | Ast.PTPtr (atype, ptr_attr) -> not ptr_attr.Ast.pa_chkptr
    | _ -> true     
  in
  let gen_copy_member (ptype, decl) =
    if is_primitive ptype then
      fprintf os "    enc_args.%s = args.%s;\n"      
        decl.Ast.identifier
        decl.Ast.identifier
  in 
  fprintf os "    /* Copy primitive properties to enc_args */\n";
  List.iter gen_copy_member fd.Ast.plist;
  fprintf os "\n"

let oe_gen_allocate_buffers (os:out_channel) (fd: Ast.func_decl) =    
  let gen_allocate_buffer (ptype, decl) =
    match ptype with
      | Ast.PTPtr (atype, ptr_attr) ->
          if ptr_attr.Ast.pa_chkptr then
            let size = oe_get_param_size (ptype, decl, "args.") in
            let macro = 
              match ptr_attr.Ast.pa_direction with
                | Ast.PtrOut -> "OE_CHECKED_ALLOCATE_OUTPUT"                
                | _ -> "OE_CHECKED_COPY_INPUT"
            in 
            fprintf os "    %s(enc_args.%s, args.%s, %s); \n" 
                macro decl.Ast.identifier 
                decl.Ast.identifier
                size            
          else ()
      | _ -> () (* Non pointer arguments *)    
  in 
  fprintf os "    /* Copy checked buffers properties to enclave memory */\n";
  List.iter gen_allocate_buffer fd.Ast.plist;
  fprintf os "\n"
  
let oe_gen_free_buffers (os:out_channel) (fd: Ast.func_decl) =  
  let gen_free_buffer (ptype, decl) =
    match ptype with
      | Ast.PTPtr (atype, ptr_attr) ->
          if ptr_attr.Ast.pa_chkptr then
            (fprintf os "    if (enc_args.%s)\n" decl.Ast.identifier;
             fprintf os "        free (enc_args.%s); \n" decl.Ast.identifier)            
          else ()
      | _ -> () (* Non pointer arguments *)    
  in 
  fprintf os "    /* Free enclave buffers */\n";
  List.iter gen_free_buffer fd.Ast.plist;
  fprintf os "\n"

let oe_gen_copy_outputs (os:out_channel) (fd: Ast.func_decl) =  
  let gen_free_buffer (ptype, decl) =
    match ptype with
      | Ast.PTPtr (atype, ptr_attr) ->
          if ptr_attr.Ast.pa_chkptr then
            match ptr_attr.Ast.pa_direction with
            Ast.PtrOut | Ast.PtrInOut -> 
              fprintf os "    if (args.%s)\n" decl.Ast.identifier;
              fprintf os "        memcpy(args.%s, enc_args.%s, %s);\n"
                decl.Ast.identifier
                decl.Ast.identifier
                (oe_get_param_size (ptype, decl, "args."))              
            | _ -> ()               
          else ()
      | _ -> () (* Non pointer arguments *)    
  in 
  fprintf os "\n    /* Copy output buffers */\n";
  List.iter gen_free_buffer fd.Ast.plist;
  fprintf os "\n"  
  
let oe_gen_call_enclave_function (os:out_channel) (fd: Ast.func_decl) =  
  let params = List.map (fun (pt, decl) -> 
    sprintf "%senc_args.%s" (get_cast_from_mem_expr (pt, decl))decl.Ast.identifier) fd.Ast.plist 
  in
  let params_str = "(" ^ (String.concat ", " params ) ^ ")" in
  let ret_str = match fd.Ast.rtype with
    | Ast.Void -> ""
    | _ -> "p_host_args->_retval = " in
  let call_str = ret_str ^ fd.Ast.fname ^ params_str in
  fprintf os "    /* lfence after checks */\n";
  fprintf os "    oe_lfence();\n\n";
  fprintf os "    /* Call enclave function */\n";
  fprintf os "    %s;\n" call_str  
  

(* oe: Generate ecall function . *)
let oe_gen_ecall_function (os:out_channel) (fd: Ast.func_decl) =  
  fprintf os "OE_ECALL void ecall_%s(%s_args_t* p_host_args)\n" fd.Ast.fname fd.Ast.fname;
  fprintf os "{\n";
  fprintf os "    oe_result_t __result = OE_FAILURE;\n";
  fprintf os "    %s_args_t args, enc_args;\n\n" fd.Ast.fname;
  fprintf os "    memset(&args, 0, sizeof(args));\n";
  fprintf os "    memset(&enc_args, 0, sizeof(enc_args));\n\n";
  fprintf os "    if (!p_host_args || !oe_is_outside_enclave(p_host_args, sizeof(*p_host_args)))\n";
  fprintf os "        goto done;\n\n";
  fprintf os "    /* Copy p_host_arg to prevent TOCTOU issues. */\n";
  fprintf os "    args = *(%s_args_t*) p_host_args;\n\n" fd.Ast.fname;
  oe_copy_members_to_enclave os fd;
  oe_gen_allocate_buffers os fd;
  oe_gen_call_enclave_function os fd;
  oe_gen_copy_outputs os fd;
  fprintf os "    __result = OE_OK; \n\n";
  fprintf os "done:\n";
  oe_gen_free_buffers os fd;
  fprintf os "    if (p_host_args) \n";
  fprintf os "        p_host_args->_result = __result;\n";
  fprintf os "}\n\n"
  

let oe_gen_ecall_functions (os:out_channel) (ec: enclave_content)  =
  fprintf os "\n\n/****** ECALL function wrappers  *************/\n";
  List.iter 
    (fun f -> oe_gen_ecall_function os f.Ast.tf_fdecl)
    ec.tfunc_decls

let oe_gen_ecall_table (os:out_channel) (ec: enclave_content)  =
  fprintf os "\n\n/****** ECALL function table  *************/\n";
  fprintf os "oe_ecall_func_t _oe_ecalls_table[] = {\n";
  List.iter 
    (fun f -> fprintf os "    (oe_ecall_func_t) ecall_%s,\n" f.Ast.tf_fdecl.fname)
    ec.tfunc_decls;
  fprintf os "};\n\n";
  fprintf os "size_t _oe_ecalls_table_size = OE_COUNTOF(_oe_ecalls_table);\n\n"  
  
let gen_fill_marshal_struct (os:out_channel) (fd:Ast.func_decl)  (args:string) =
  (* Generate assignment argument to corresponding field in args *)
  List.iter (fun (ptype, decl)->
    let varname = decl.Ast.identifier in 
    fprintf os "    %s.%s = %s%s;\n" args varname (get_cast_to_mem_expr (ptype, decl)) varname; 
    (* for string parameter fill the len field *)
    match ptype with
        | Ast.PTPtr(_, attr) -> 
            if attr.Ast.pa_isstr then 
                fprintf os "    %s.%s_len = (%s) ? (strlen(%s) + 1) : 0;\n" args varname varname varname 
            else if attr.Ast.pa_iswstr then
                fprintf os "    %s.%s_len = (%s) ? (wcslen(%s) + 1) : 0;\n" args varname varname varname
        | _ ->()
  ) fd.Ast.plist;
  fprintf os "\n"

let oe_get_host_ecall_function (os:out_channel) (fd:Ast.func_decl) =
  fprintf os "%s" (oe_gen_wrapper_prototype fd true);
  fprintf os "\n";
  fprintf os "{\n";
  fprintf os "    oe_result_t __result = OE_FAILURE;\n\n";
  fprintf os "    /* Marshal arguments */ \n";
  fprintf os "    %s_args_t __args; \n\n" fd.Ast.fname;
  fprintf os "    memset(&__args, 0, sizeof(__args));\n";
  gen_fill_marshal_struct os fd "__args";
  fprintf os "    /* Call enclave function */\n";
  fprintf os "    if(oe_call_enclave_function(enclave,%s, &__args, sizeof(__args), NULL, 0, NULL) != OE_OK || (__result=__args._result) != OE_OK)\n" (get_function_id fd);
  fprintf os "        goto done;\n\n";
  fprintf os "    /* successful ecall. */\n";
  if fd.Ast.rtype <> Ast.Void then 
    fprintf os "    *_retval = __args._retval;\n";
  fprintf os "    __result = OE_OK;\n";   
  fprintf os "done:    \n";  
  fprintf os "    return __result;\n";
  fprintf os "}\n\n"

let iter_ptr_params f params = 
  List.iter (fun (ptype, decl)->
    match ptype with
        | Ast.PTPtr(_, attr) ->  f (ptype, decl, attr)
        | _ ->()
  ) params

(* Generate ocalls wrapper function *)
let oe_gen_ocall_enclave_wrapper (os:out_channel) (fd:Ast.func_decl) =
  fprintf os "%s\n{\n" (oe_gen_wrapper_prototype fd false);
  fprintf os "    oe_result_t __result = OE_FAILURE;\n\n";
  fprintf os "    /* Marshal arguments */ \n";
  fprintf os "    %s_args_t __args, __host_args, *__p_host_args = NULL; \n" fd.Ast.fname;
  fprintf os "    memset(&__args, 0, sizeof(__args)); \n";
  fprintf os "    memset(&__host_args, 0, sizeof(__host_args)); \n";
  fprintf os "    uint8_t* __host_buffer = NULL;\n";
  fprintf os "    uint8_t* __host_ptr = NULL;\n";
  fprintf os "    uint64_t __host_buffer_size = sizeof(__args);\n\n";
  gen_fill_marshal_struct os fd "__args";
  
  fprintf os "    /* Update size of buffer to allocate in host. */\n";
  iter_ptr_params (fun (ptype, decl, attr) ->
    if attr.Ast.pa_chkptr then
      fprintf os "    __host_buffer_size += %s; \n" (oe_get_param_size (ptype, decl, "__args."))
  ) fd.Ast.plist;

  fprintf os "\n    /* Allocate host buffer and copy inputs to host. */\n";
  fprintf os "    __host_buffer = __host_ptr = (uint8_t*) oe_host_malloc(__host_buffer_size); \n";
  fprintf os "    if (__host_buffer == 0) { \n";
  fprintf os "        __result = OE_OUT_OF_MEMORY;\n";
  fprintf os "        goto done;\n";
  fprintf os "    }\n\n";
  fprintf os "    /* Copy buffer fields to host. */\n";
  iter_ptr_params ( fun (ptype, decl, attr) -> 
    let varname = decl.Ast.identifier in 
    if attr.Ast.pa_isstr && attr.Ast.pa_chkptr then 
      fprintf os "    OE_COPY_TO_HOST(__args.%s, %s, __args.%s_len*sizeof(char));\n" varname varname varname
    else if attr.Ast.pa_iswstr && attr.Ast.pa_chkptr then
      fprintf os "    OE_COPY_TO_HOST(__args.%s, %s, __args.%s_len*sizeof(wchar_t));\n" varname varname varname
    else if attr.Ast.pa_chkptr then
      fprintf os "    OE_COPY_TO_HOST(__args.%s, %s, %s);\n" varname varname (oe_get_param_size (ptype, decl, "__args.") )
  ) fd.Ast.plist;

  fprintf os "\n    /* Copy args struct to host memory. */\n";
  fprintf os "    __p_host_args = (%s_args_t*)__host_ptr;\n" fd.Ast.fname;
  fprintf os "    *__p_host_args = __args;\n";

 (* Generate call to host *)
  fprintf os "\n    /* Call host function */\n";
  fprintf os "    if(oe_call_host_function(%s, __p_host_args, sizeof(*__p_host_args), NULL, 0, NULL) != OE_OK)\n" (get_function_id fd);
  fprintf os "        goto done;\n\n";
  fprintf os "    /* Copy args struct back to enclave memory to prevent TOCTOU issues. */ \n";
  fprintf os "    __host_args = *(%s_args_t*) __p_host_args; \n" fd.Ast.fname;
  fprintf os "    if ((__result = __host_args._result) != OE_OK)\n        goto done;\n\n";
  fprintf os "    /* Copy buffer outputs to enclave memory. */\n";
  iter_ptr_params (fun (ptype, decl, attr) ->
    match attr.Ast.pa_direction with
      | Ast.PtrOut | Ast.PtrInOut ->
          let varname = decl.Ast.identifier in
          let size = oe_get_param_size (ptype, decl, "__args.") in
          if attr.Ast.pa_chkptr then
            fprintf os "    OE_COPY_FROM_HOST(%s, __host_args.%s, %s);\n" varname varname size
          else ();
      | _ -> ()
  ) fd.Ast.plist;
  fprintf os "\n    /* successful ocall */\n";
  if fd.Ast.rtype <> Ast.Void then fprintf os "    *_retval = __host_args._retval;\n";  
  fprintf os "    __result = OE_OK;\n";
  fprintf os "done:\n";  
  fprintf os "    oe_host_free(__host_buffer);\n";
  fprintf os "    return __result;\n";
  fprintf os "}\n\n" 

(*
 * Generate ocall function table and registration
 *)  
let oe_gen_ocall_table (os:out_channel) (ec:enclave_content) =
  fprintf os "\n/*ocall function table*/\n";
  fprintf os "static oe_ocall_func_t _%s_ocall_function_table[]= {\n" ec.enclave_name;
  List.iter (fun fd ->
    fprintf os "    (oe_ocall_func_t) ocall_%s,\n" fd.Ast.uf_fdecl.fname
  )  ec.ufunc_decls;
  fprintf os "    NULL\n";
  fprintf os "};\n\n"

(* Generate ocalls wrapper function *)
let oe_gen_ocall_host_wrapper (os:out_channel) (fd:Ast.func_decl) =
  fprintf os "OE_OCALL void ocall_%s(%s_args_t* args)\n{\n" fd.Ast.fname fd.Ast.fname;
  fprintf os "    /* Forward the call */ \n";
  let params = List.map (fun (pt, decl) -> 
    sprintf "%sargs->%s" (get_cast_from_mem_expr (pt,decl)) decl.Ast.identifier) fd.Ast.plist 
  in
  let call_expr = sprintf "%s(%s)" fd.Ast.fname (String.concat ", " params) in
  if fd.Ast.rtype = Ast.Void then
    fprintf os "    %s;\n" call_expr
  else 
    fprintf os "    args->_retval = %s;\n" call_expr;
  fprintf os "}\n\n"

let rec is_wchar_t_type = function
| Ast.WChar -> true
| Ptr ty -> is_wchar_t_type ty
| _ -> false

(* check if function has wstring parameters *)
let uses_wchar_t_params (fd:Ast.func_decl) =
    List.exists (fun (pt, decl) -> is_wchar_t_type (Ast.get_param_atype pt)) fd.Ast.plist

(* Valid oe support *)
let validate_oe_support (ec: enclave_content) (ep: edger8r_params) =
  (* check supported options *)
  if ep.use_prefix then failwithf "--use_prefix option is not supported by oeedger8r.";
  if ep.header_only then failwithf "--header_only option is not supported by oeedger8r.";
  List.iter (fun f -> 
    (if f.Ast.tf_is_priv then 
        failwithf "Function '%s': 'private' specifier is not supported by oeedger8r" f.Ast.tf_fdecl.fname);
    (if f.Ast.tf_is_switchless then
        failwithf "Function '%s': switchless ecalls and ocalls are not yet supported by Open Enclave SDK." f.Ast.tf_fdecl.fname);  
    (if uses_wchar_t_params f.Ast.tf_fdecl then
        printf "Warning: Function '%s': wchar_t has different sizes on windows and linux.\n" f.Ast.tf_fdecl.fname);     
  ) ec.tfunc_decls;
  List.iter (fun f -> 
    (if f.Ast.uf_fattr.fa_convention <> Ast.CC_NONE then
        let cconv_str = Ast.get_call_conv_str f.Ast.uf_fattr.Ast.fa_convention in
        printf "Warning: Function '%s': Calling convention '%s' for ocalls is not supported by oeedger8r.\n" f.Ast.uf_fdecl.fname cconv_str);
    (if f.Ast.uf_fattr.fa_dllimport then
        failwithf "Function '%s': dllimport is not supported by oeedger8r." f.Ast.uf_fdecl.fname);
    (if f.Ast.uf_allow_list != [] then
        printf "Warning: Function '%s': Reentrant ocalls are not supported by Open Enclave. Allow list ignored.\n" f.Ast.uf_fdecl.fname);
    (if f.Ast.uf_is_switchless then
        failwithf "Function '%s': switchless ecalls and ocalls are not yet supported by Open Enclave SDK." f.Ast.uf_fdecl.fname);
    (if uses_wchar_t_params f.Ast.uf_fdecl then
        printf "Warning: Function '%s': wchar_t has different sizes on windows and linux.\n" f.Ast.uf_fdecl.fname);          
  ) ec.ufunc_decls

  (*
    Includes are emitted in args.h.
    Imported functions have already been brought into function lists.
  *)  

let gen_t_h (ec: enclave_content) (ep: edger8r_params) =
  let fname = ec.file_shortnm ^ "_t.h" in
  let guard = sprintf "EDGER8R_%s_T_H" (String.uppercase ec.file_shortnm) in
  let os = open_file fname ep.trusted_dir in  
  fprintf os "#ifndef %s\n" guard;
  fprintf os "#define %s\n\n" guard;
  fprintf os "#include <openenclave/enclave.h>\n";  
  fprintf os "#include \"%s_args.h\"\n\n" ec.file_shortnm;  
  fprintf os "OE_EXTERNC_BEGIN\n\n";
  if ec.tfunc_decls <> [] then (
    fprintf os "/* List of ecalls */\n\n";
    List.iter (fun f -> fprintf os "%s;\n" (oe_gen_prototype f.Ast.tf_fdecl)) ec.tfunc_decls;
    fprintf os "\n");
  if ec.ufunc_decls <> [] then (
    fprintf os "/* List of ocalls */\n\n";
    List.iter (fun d -> fprintf os"%s;\n" (oe_gen_wrapper_prototype d.Ast.uf_fdecl false))  ec.ufunc_decls;
    fprintf os "\n");
  fprintf os "OE_EXTERNC_END\n\n";
  fprintf os "#endif // %s\n" guard;
  close_out os  

let gen_t_c (ec: enclave_content) (ep: edger8r_params) =
  let ecalls_fname = ec.file_shortnm ^ "_t.c" in
  let os = open_file ecalls_fname ep.trusted_dir in
  fprintf os "#include \"%s_t.h\"\n" ec.file_shortnm;  
  fprintf os "#include <openenclave/edger8r/enclave.h>\n";  
  fprintf os "#include <stdlib.h>\n";
  fprintf os "#include <string.h>\n";
  fprintf os "#include <wchar.h>\n";  
  fprintf os "\n";
  fprintf os "OE_EXTERNC_BEGIN\n\n";
  if ec.tfunc_decls <> [] then (
    oe_gen_ecall_functions os ec;
    oe_gen_ecall_table os ec);
  if ec.ufunc_decls <> [] then (
    fprintf os "\n/* ocall wrappers */\n\n";
    List.iter (fun d -> oe_gen_ocall_enclave_wrapper os d.Ast.uf_fdecl)  ec.ufunc_decls);
  fprintf os "OE_EXTERNC_END\n";
  close_out os 

let oe_emit_create_enclave_decl (os:out_channel)  (ec:enclave_content) =
  fprintf os "oe_result_t oe_create_%s_enclave(const char* path,\n" ec.enclave_name;
  fprintf os "                                 oe_enclave_type_t type,\n";
  fprintf os "                                 uint32_t flags,\n";
  fprintf os "                                 const void* config,\n";
  fprintf os "                                 uint32_t config_size,\n";
  fprintf os "                                 oe_enclave_t** enclave);\n\n"

let oe_emit_create_enclave_defn (os:out_channel)  (ec:enclave_content) =
  fprintf os "oe_result_t oe_create_%s_enclave(const char* path,\n" ec.enclave_name;
  fprintf os "                                 oe_enclave_type_t type,\n";
  fprintf os "                                 uint32_t flags,\n";
  fprintf os "                                 const void* config,\n";
  fprintf os "                                 uint32_t config_size,\n";
  fprintf os "                                 oe_enclave_t** enclave)\n";
  fprintf os "{\n";
  fprintf os "    return oe_create_enclave(path, type, flags, config, config_size,_%s_ocall_function_table, %d, enclave);\n"
                ec.enclave_name (List.length ec.ufunc_decls);
  fprintf os "}\n\n"


let gen_u_h (ec: enclave_content) (ep: edger8r_params) =
  let fname = ec.file_shortnm ^ "_u.h" in
  let guard = sprintf "EDGER8R_%s_U_H" (String.uppercase ec.file_shortnm) in
  let os = open_file fname ep.untrusted_dir in  
  fprintf os "#ifndef %s\n" guard;
  fprintf os "#define %s\n\n" guard;
  fprintf os "#include <openenclave/host.h>\n";  
  fprintf os "#include \"%s_args.h\"\n\n" ec.file_shortnm;  
  fprintf os "OE_EXTERNC_BEGIN\n\n";
  oe_emit_create_enclave_decl os ec;
  if ec.tfunc_decls <> [] then (
    fprintf os "/* List of ecalls */\n\n";
    List.iter (fun f -> fprintf os "%s;\n" (oe_gen_wrapper_prototype f.Ast.tf_fdecl true)) ec.tfunc_decls;
    fprintf os "\n");
  if ec.ufunc_decls <> [] then (
    fprintf os "/* List of ocalls */\n\n";
    List.iter (fun d -> fprintf os"%s;\n" (oe_gen_prototype d.Ast.uf_fdecl))  ec.ufunc_decls;
    fprintf os "\n");
  fprintf os "OE_EXTERNC_END\n\n";
  fprintf os "#endif // %s\n" guard;
  close_out os  


let gen_u_c (ec: enclave_content) (ep: edger8r_params) =
  let ecalls_fname = ec.file_shortnm ^ "_u.c" in
  let os = open_file ecalls_fname ep.untrusted_dir in
  fprintf os "#include \"%s_u.h\"\n" ec.file_shortnm;  
  fprintf os "#include <openenclave/edger8r/host.h>\n";  
  fprintf os "#include <stdlib.h>\n";
  fprintf os "#include <string.h>\n";
  fprintf os "#include <wchar.h>\n";  
  fprintf os "\n";
  fprintf os "OE_EXTERNC_BEGIN\n\n";
  if ec.tfunc_decls <> [] then (
    fprintf os "/* Wrappers for ecalls */\n\n";
    List.iter (fun d -> oe_get_host_ecall_function os d.Ast.tf_fdecl; fprintf os "\n\n")  ec.tfunc_decls);
  if ec.ufunc_decls <> [] then (
    fprintf os "\n/* ocall functions */\n\n";
    List.iter (fun d -> oe_gen_ocall_host_wrapper os d.Ast.uf_fdecl)  ec.ufunc_decls);
  oe_gen_ocall_table os ec;
  oe_emit_create_enclave_defn os ec;
  fprintf os "OE_EXTERNC_END\n";
  close_out os   

(* Generate the Enclave code. *)
let gen_enclave_code (ec: enclave_content) (ep: edger8r_params) =
  validate_oe_support ec ep;
  
  if ep.gen_trusted then(
    oe_gen_args_header ec ep.trusted_dir;
    gen_t_h ec ep;
    gen_t_c ec ep;
  );
  if ep.gen_untrusted then (
    oe_gen_args_header ec ep.untrusted_dir;
    gen_u_h ec ep;
    gen_u_c ec ep;
  );
  printf "Success.\n"


(* Install the plugin *)
let _ = 
  Printf.printf "Generating edge routines for the Open Enclave SDK.\n";
  Plugin.instance.available <- true;
  Plugin.instance.gen_edge_routines <- gen_enclave_code;

