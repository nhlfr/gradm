#include "gradm.h"

struct gr_learn_group_node **role_list = NULL;
extern FILE *fulllearn_pass1in;
extern FILE *fulllearn_pass2in;
extern FILE *fulllearn_pass3in;
extern int fulllearn_pass1parse(void);
extern int fulllearn_pass2parse(void);
extern int fulllearn_pass3parse(void);

void fulllearn_pass1(FILE *stream)
{
	fulllearn_pass1in = stream;
	fulllearn_pass1parse();
	reduce_roles(&role_list);

	return;
}

int full_reduce_subjects(struct gr_learn_group_node *group,
			 struct gr_learn_user_node *user, FILE *unused)
{
	struct gr_learn_file_tmp_node **tmp;

	if (user) {
		if (!user->tmp_subject_list)
			insert_file(&(user->subject_list), "/", GR_FIND, 1);
		else {
			sort_file_list(user->tmp_subject_list);
			tmp = user->tmp_subject_list;
			while (*tmp) {
				insert_file(&(user->subject_list), (*tmp)->filename, (*tmp)->mode, 1);
				tmp++;
			}
		}
	} else {
		if (!group->tmp_subject_list)
			insert_file(&(group->subject_list), "/", GR_FIND, 1);
		else {
			sort_file_list(group->tmp_subject_list);
			tmp = group->tmp_subject_list;
			while (*tmp) {
				insert_file(&(group->subject_list), (*tmp)->filename, (*tmp)->mode, 1);
				tmp++;
			}
		}
	}

	return 0;
}

int full_reduce_allowed_ips(struct gr_learn_group_node *group,
			    struct gr_learn_user_node *user,
			    FILE *unused)
{
	if (user)
		reduce_ip_tree(user->allowed_ips);
	else if (group)
		reduce_ip_tree(group->allowed_ips);

	return 0;
}	

void fulllearn_pass2(FILE *stream)
{
	fulllearn_pass2in = stream;
	fulllearn_pass2parse();
	traverse_roles(role_list, &full_reduce_subjects, NULL);
	traverse_roles(role_list, &full_reduce_allowed_ips, NULL);

	return;
}

int full_reduce_object_node(struct gr_learn_file_node *subject,
			    struct gr_learn_file_node *unused1,
			    FILE *unused2)
{
	struct gr_learn_file_tmp_node **tmp = subject->tmp_object_list;
	if (!tmp)
		return 0;
	sort_file_list(tmp);
	while (*tmp) {
		insert_file(&(subject->object_list), (*tmp)->filename, (*tmp)->mode, 0);
		tmp++;
	}

	first_stage_reduce_tree(subject->object_list);
	second_stage_reduce_tree(subject->object_list);

	enforce_high_protected_paths(subject);

	third_stage_reduce_tree(subject->object_list);

	return 0;
}

int full_reduce_objects(struct gr_learn_group_node *group,
			 struct gr_learn_user_node *user,
			 FILE *unused)
{
	struct gr_learn_file_node *subjects;

	if (user)
		subjects = user->subject_list;
	else
		subjects = group->subject_list;

	traverse_file_tree(subjects, &full_reduce_object_node, NULL, NULL);

	return 0;
}

int full_reduce_ip_node(struct gr_learn_file_node *subject,
			struct gr_learn_file_node *unused1,
			FILE *unused2)
{
	struct gr_learn_ip_node *tmp = subject->connect_list;

	reduce_ip_tree(tmp);
	reduce_ports_tree(tmp);

	tmp = subject->bind_list;

	reduce_ip_tree(tmp);
	reduce_ports_tree(tmp);

	return 0;
}	

int full_reduce_ips(struct gr_learn_group_node *group,
			 struct gr_learn_user_node *user,
			FILE *unused)
{
	struct gr_learn_file_node *subjects;

	if (user)
		subjects = user->subject_list;
	else
		subjects = group->subject_list;

	traverse_file_tree(subjects, &full_reduce_ip_node, NULL, NULL);

	return 0;
}

void fulllearn_pass3(FILE *stream)
{
	fulllearn_pass3in = stream;
	fulllearn_pass3parse();
	traverse_roles(role_list, &full_reduce_objects, NULL);
	traverse_roles(role_list, &full_reduce_ips, NULL);

	return;
}

void enforce_hidden_file(struct gr_learn_file_node *subject, char *filename)
{
	struct gr_learn_file_node *objects = subject->object_list;
	struct gr_learn_file_node *retobj;
	
	retobj = match_file_node(objects, filename);
	if (retobj->mode & GR_FIND && !strcmp(retobj->filename, filename))
		retobj->mode = 0;
	else if (retobj->mode & GR_FIND)
		insert_file(&(subject->object_list), strdup(filename), 0, 0);

	return;
}

int ensure_subject_security(struct gr_learn_file_node *subject,
			struct gr_learn_file_node *unused1,
			FILE *unused2)
{
	if (strcmp(subject->filename, "/"))
		return 0;

	enforce_hidden_file(subject, "/etc/ssh");
	enforce_hidden_file(subject, "/dev/mem");
	enforce_hidden_file(subject, "/dev/kmem");
	enforce_hidden_file(subject, "/dev/port");
	enforce_hidden_file(subject, "/proc/kcore");
	enforce_hidden_file(subject, GRSEC_DIR);
	enforce_hidden_file(subject, "/dev/grsec");

	return 0;
}

int ensure_role_security(struct gr_learn_group_node *group,
			 struct gr_learn_user_node *user,
			FILE *unused)
{
	struct gr_learn_file_node *subjects;

	if (user)
		subjects = user->subject_list;
	else
		subjects = group->subject_list;

	traverse_file_tree(subjects, &ensure_subject_security, NULL, NULL);

	return 0;
}

void fulllearn_finalpass(void)
{
	traverse_roles(role_list, &ensure_role_security, NULL);
	return;
}

void generate_full_learned_acls(char *learn_log, FILE *stream)
{
	FILE *learnlog;

	learnlog = fopen(learn_log, "r");
	if (learnlog == NULL) {
		fprintf(stderr, "Unable to open learning log: %s.\n"
				"Error: %s\n", learn_log, strerror(errno));
		exit(EXIT_FAILURE);
	}
	fulllearn_pass1(learnlog);
	fseek(learnlog, 0, SEEK_SET);
	fulllearn_pass2(learnlog);
	fseek(learnlog, 0, SEEK_SET);
	fulllearn_pass3(learnlog);
	fclose(learnlog);

	fulllearn_finalpass();

	display_roles(role_list, stream);

	return;
}