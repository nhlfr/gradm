%{
#include "gradm.h"

extern int gradmlex(void);

struct ip_acl ip;
struct var_object *var_obj = NULL;
char *nested[MAX_NEST_DEPTH];
int current_nest_depth = 0;
%}

%union {
	char *string;
	__u32 num;
	__u16 shortnum;
	struct var_object * var;
}

%token <string> ROLE ROLE_NAME ROLE_TYPE SUBJECT SUBJ_NAME OBJ_NAME 
%token <string> RES_NAME RES_SOFTHARD CONNECT BIND IPPORT IPTYPE
%token <string> IPPROTO IPNETMASK CAP_NAME ROLE_ALLOW_IP
%token <string> ROLE_TRANSITION VARIABLE DEFINE DEFINE_NAME DISABLED
%token <string> ID_NAME USER_TRANS_ALLOW GROUP_TRANS_ALLOW 
%token <string> USER_TRANS_DENY GROUP_TRANS_DENY DOMAIN_TYPE DOMAIN
%token <num> OBJ_MODE SUBJ_MODE IPADDR
%type <num> subj_mode obj_mode ip_netmask
%type <shortnum> role_type
%type <var> variable_expression
%left '&'
%left '|'
%left '-'

%%

compiled_acl:			various_acls
	|			compiled_acl various_acls
	;

various_acls:			role_label
	|			domain_label
	|			role_allow_ip
	|			role_transitions
	|			subject_label
	|			user_allow_label
	|			user_deny_label
	|			group_allow_label
	|			group_deny_label
	|			variable_object
	|			variable_expression
				{
					interpret_variable($1);
				}
	|			nested_label
	|			object_file_label
	|			object_cap_label
	|			object_res_label
	|			object_connect_ip_label
	|			object_bind_ip_label
	;

variable_expression:		VARIABLE
				{
					$$ = sym_retrieve($1);
					if (!$$) {
						fprintf(stderr, "Variable \"%s\" not defined on line %lu of %s.\n", $1, lineno, current_acl_file);
						exit(EXIT_FAILURE);
					}
				}
	|			variable_expression '|' variable_expression
				{
					$$ = union_objects($1, $3);
				}
	|			variable_expression '&' variable_expression
				{
					$$ = intersect_objects($1, $3);
				}
	|			variable_expression '-' variable_expression
				{
					$$ = differentiate_objects($1, $3);
				}
	|			'(' variable_expression ')'
				{
					$$ = $2;
				}
	;

variable_object:		DEFINE DEFINE_NAME '{' var_object_list '}'
				{
				  if (sym_retrieve($1)) {
					fprintf(stderr, "Duplicate variable \"%s\" defined on line %lu of %s.\n", $1, lineno, current_acl_file);
					exit(EXIT_FAILURE);
				  }
				  sym_store($2, var_obj);
				  var_obj = NULL;
				}
	;

var_object_list:		OBJ_NAME obj_mode
				{
				  add_var_object(&var_obj, $1, $2);
				}
	|			var_object_list OBJ_NAME obj_mode
				{
				  add_var_object(&var_obj, $2, $3);
				}
	;

domain_label:			DOMAIN ROLE_NAME DOMAIN_TYPE 
				{
				 if (!add_role_acl(&current_role, $2, GR_ROLE_DOMAIN | role_mode_conv($3), 1))
					exit(EXIT_FAILURE);
				}
				domain_user_list
	;

domain_user_list:		ROLE_NAME
				{
					add_domain_child(current_role, $1);
				}
	|			domain_user_list ROLE_NAME
				{
					add_domain_child(current_role, $2);
				}
	;

role_label: 			ROLE ROLE_NAME role_type
				{
				 if (!add_role_acl(&current_role, $2, $3, 0))
					exit(EXIT_FAILURE);
				}
	;

role_type: /* empty */
				{ $$ = role_mode_conv(""); }
	|			ROLE_TYPE
				{ $$ = role_mode_conv($1); }
	;

subject_label:			SUBJECT SUBJ_NAME subj_mode
				{
				 if (current_role && current_role->roletype & GR_ROLE_LEARN) {
					fprintf(stderr, "Error on line %lu of %s.\n"
							"Subjects are not allowed for a role with learning enabled, as "
							"they are generated by the learning mode.\n"
							"The RBAC system will not load until you correct this error.\n\n",
							lineno, current_acl_file);
					exit(EXIT_FAILURE);
				 }

				 if (!add_proc_subject_acl(current_role, $2, $3, 0))
					exit(EXIT_FAILURE);
				}
	;

nested_label:			SUBJECT SUBJ_NAME nested_subjs subj_mode
				{
					add_proc_nested_acl(current_role, $2, nested, current_nest_depth, $4);
					current_nest_depth = 0;
				}
	;

nested_subjs:			':' SUBJ_NAME
				{
					nested[current_nest_depth] = $2;
					current_nest_depth++;
				}
	|
				nested_subjs ':' SUBJ_NAME
				{
					if (current_nest_depth >= MAX_NEST_DEPTH) {
						fprintf(stderr, "Nesting too deep (over %d) on line %lu of %s.\n", MAX_NEST_DEPTH,
								lineno, current_acl_file);
						exit(EXIT_FAILURE);
					}
					nested[current_nest_depth] = $3;
					current_nest_depth++;
				}
	;

user_allow_ids:			ID_NAME
				{
					add_id_transition(current_subject, $1, GR_ID_USER, GR_ID_ALLOW);
				}
	|
				user_allow_ids ID_NAME
				{
					add_id_transition(current_subject, $2, GR_ID_USER, GR_ID_ALLOW);
				}
	;
user_allow_label:		USER_TRANS_ALLOW user_allow_ids
				{
				}
	;

user_deny_ids:			ID_NAME
				{
					add_id_transition(current_subject, $1, GR_ID_USER, GR_ID_DENY);
				}
	|
				user_deny_ids ID_NAME
				{
					add_id_transition(current_subject, $2, GR_ID_USER, GR_ID_DENY);
				}
	;
user_deny_label:		USER_TRANS_DENY user_deny_ids
				{
				}
	;

group_allow_ids:		ID_NAME
				{
					add_id_transition(current_subject, $1, GR_ID_GROUP, GR_ID_ALLOW);
				}
	|
				group_allow_ids ID_NAME
				{
					add_id_transition(current_subject, $2, GR_ID_GROUP, GR_ID_ALLOW);
				}
	;
group_allow_label:		GROUP_TRANS_ALLOW group_allow_ids
				{
				}
	;

group_deny_ids:			ID_NAME
				{
					add_id_transition(current_subject, $1, GR_ID_GROUP, GR_ID_DENY);
				}
	|
				group_deny_ids ID_NAME
				{
					add_id_transition(current_subject, $2, GR_ID_GROUP, GR_ID_DENY);
				}
	;
group_deny_label:		GROUP_TRANS_DENY group_deny_ids
				{
				}
	;

object_file_label:		OBJ_NAME obj_mode
				{
				 if (!add_proc_object_acl(current_subject, $1, $2, GR_FEXIST))
					exit(EXIT_FAILURE);
				}
	;

object_cap_label:		CAP_NAME
				{
				 add_cap_acl(current_subject, $1);
				}
	;

object_res_label:		RES_NAME RES_SOFTHARD RES_SOFTHARD
				{
				 add_res_acl(current_subject, $1, $2, $3);
				}
	;

subj_mode: /* empty */
				{ $$ = proc_subject_mode_conv(""); }
	|			SUBJ_MODE
				{ $$ = $1; }
	;

obj_mode: /* empty */
				{ $$ = proc_object_mode_conv(""); }
	|			OBJ_MODE
				{ $$ = $1; }
	;

role_transitions:		ROLE_TRANSITION role_names
				{
				}
	;

role_names:			ROLE_NAME
				{
					add_role_transition(current_role, $1);
				}
	|			role_names ROLE_NAME
				{
					add_role_transition(current_role, $2);
				}
	;

role_allow_ip:			ROLE_ALLOW_IP IPADDR ip_netmask
				{
					add_role_allowed_ip(current_role, $2, $3);
				}
	;

object_connect_ip_label:	CONNECT IPADDR ip_netmask ip_ports ip_typeproto
				{
				 ip.addr = $2;
				 ip.netmask = $3;
				 add_ip_acl(current_subject, GR_IP_CONNECT, &ip);
				 memset(&ip, 0, sizeof(ip));
				}
	|
				CONNECT DISABLED
				{
				 add_ip_acl(current_subject, GR_IP_CONNECT, &ip);
				}
	;

object_bind_ip_label:		BIND IPADDR ip_netmask ip_ports ip_typeproto
				{
				 ip.addr = $2;
				 ip.netmask = $3;
				 add_ip_acl(current_subject, GR_IP_BIND, &ip);
				 memset(&ip, 0, sizeof(ip));
				}
	|
				BIND DISABLED
				{
				 add_ip_acl(current_subject, GR_IP_BIND, &ip);
				}
	;

ip_netmask: /* emtpy */
				{ $$ = 0xffffffff; }
	|			'/' IPNETMASK
				{
				  unsigned int bits = atoi($2);

				  if (!bits)
					$$ = 0UL;
				  else
					$$ = 0xffffffff << (32 - bits);
				}
	;

ip_ports: /* emtpy */
				{
				 ip.low = 0;
				 ip.high = 65535;
				}
	|			':' IPPORT
				{
				 ip.low = ip.high = atoi($2);
				}
	|			':' IPPORT '-' IPPORT
				{
				 ip.low = atoi($2);
				 ip.high = atoi($4);
				}
	;

ip_typeproto:			IPPROTO
				{ conv_name_to_type(&ip, $1); }
	|			IPTYPE
				{ conv_name_to_type(&ip, $1); }
	| 			ip_typeproto IPPROTO
				{ conv_name_to_type(&ip, $2); }
	|			ip_typeproto IPTYPE
				{ conv_name_to_type(&ip, $2); }
	;
