#include <sys/types.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
static double modes[4],targets[4]={500,600,500,660};
static int ticks=0,failWrite=0;
static double cpu=35;
static const char *requestPath;
static void setRequest(const char *value){FILE *f=fopen(requestPath,"w");assert(f);fputs(value,f);fclose(f);chmod(requestPath,0600);}
unsigned int mock_sleep(unsigned int seconds);
int mock_usleep(useconds_t t){return 0;}
double smc_read_number(const char *key){
 int fan=key[1]-'0';if(!strcmp(key,"FNum"))return 4;
 if(strstr(key,"Md"))return modes[fan];
 if(strstr(key,"Tg"))return targets[fan];
 if(strstr(key,"Ac"))return targets[fan];
 return strstr(key,"Mx")?2500:500;
}
double thermal_read(const char *key){return cpu;}
int smc_set_target(int fan,double target){if(failWrite)return -6;targets[fan]=target;return 0;}
int smc_set_mode(int fan,int mode){modes[fan]=mode;return 0;}
#define sleep mock_sleep
#define usleep mock_usleep
#define main helper_main
#include "../Sources/FanAssist.c"
#undef main
unsigned int mock_sleep(unsigned int seconds){
 ticks++;
 if(ticks==1){for(int i=0;i<4;i++)assert(modes[i]==(cpu>=80?0:1));setRequest("0");}
 else {for(int i=0;i<4;i++)assert(modes[i]==0);stop=1;}
 return 0;
}
int main(void){
 char dir[]="/tmp/MacThermalTests-XXXXXX";assert(mkdtemp(dir));char request[256],status[256];
 snprintf(request,256,"%s/request",dir);snprintf(status,256,"%s/status",dir);requestPath=request;sessionOwner=getuid();
 FILE *f=fopen(status,"w");fclose(f);chmod(status,0600);
 double minimum[4]={500,500,500,500},maximum[4]={1200,2500,2500,2500};
 setRequest("1");assert(worker(request,status,minimum,maximum)==0);assert(ticks==2);
 stop=0;ticks=0;cpu=81;setRequest("1");assert(worker(request,status,minimum,maximum)==0);
 stop=0;cpu=35;failWrite=1;setRequest("1");assert(worker(request,status,minimum,maximum)==5);assert(restoreAll());
 modes[0]=1;assert(restoreAll());assert(modes[0]==0);
 unlink(request);assert(requestState(request)==-1);unlink(status);rmdir(dir);
 puts("OK : renfort, retour après refroidissement, sécurité CPU, écriture refusée, restauration après interruption, perte du signal");
}
