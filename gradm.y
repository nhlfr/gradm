%{
#include "gradm.h"

extern int gradmlex(void);

struct ip_acl ip;
%}

%union {
	char *string;
	__u32 long_int;
	__u8 mode;
}

%token <string> ROLE ROLE_NAME ROLE_TYPE SUBJECT SUBJ_NAME OBJ_NAME 
%token <string> RES_NAME RES_SOFTHARD CONNECT BIND IPADDR IPPORT IPTYPE
%token <string> IPPROTO OBJ_MODE SUBJ_MODE IPNETMASK CAP_NAME ROLE_ALLOW_IP
%type <long_int> subj_mode obj_mode ip_netmask
%type <mode> role_type

%%

compiled_acl:			various_acls
	|			compiled_acl various_acls
	;

various_acls:			role_label
	|			role_allow_ip
	|			subject_label
	|			object_file_label
	|			object_cap_label
	|			object_res_label
	|			object_connect_ip_label
	|			object_bind_ip_label
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
				 struct stat fstat;

				 if (!add_proc_subject_acl(current_role, $2, $3))
					exit(EXIT_FAILURE);

				 if (!stat($2, &fstat) && S_ISREG(fstat.st_mode)) {
					if (is_valid_elf_binary($2)) {
						if (!add_proc_object_acl(current_subject, $2, proc_object_mode_conv("x"), GR_FLEARN))
							exit(EXIT_FAILURE);
					} else {
						if (!add_proc_object_acl(current_subject, $2, proc_object_mode_conv("rx"), GR_FLEARN))
							exit(EXIT_FAILURE);
					}
				 }
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
				{ $$ = proc_subject_mode_conv($1); }
	;

obj_mode: /* empty */
				{ $$ = proc_object_mode_conv(""); }
	|			OBJ_MODE
				{ $$ = proc_object_mode_conv($1); }
	;

role_allow_ip:			ROLE_ALLOW_IP IPADDR ip_netmask
				{
					add_role_allowed_ip(current_role, get_ip($2), $3);
				}
	;

object_connect_ip_label:	CONNECT IPADDR ip_netmask ip_ports ip_typeproto
				{
				 ip.addr = get_ip($2);
				 ip.netmask = $3;
				 add_ip_acl(current_subject, GR_IP_CONNECT, &ip);
				 memset(&ip, 0, sizeof(ip));
				}
	;

object_bind_ip_label:		BIND IPADDR ip_netmask ip_ports ip_typeproto
				{
				 ip.addr = get_ip($2);
				 ip.netmask = $3;
				 add_ip_acl(current_subject, GR_IP_BIND, &ip);
				 memset(&ip, 0, sizeof(ip));
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
