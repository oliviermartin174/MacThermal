#include "SMC.h"
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <string.h>
#include <errno.h>
static uid_t sessionOwner;
static volatile sig_atomic_t stop=0;
static void stopping(int s){stop=1;}
static double readfan(int fan,const char *suffix){char key[5];snprintf(key,5,"F%d%s",fan,suffix);return smc_read_number(key);}
static void report(const char *path,const char *text){
 int fd=open(path,O_WRONLY|O_NOFOLLOW|O_NONBLOCK);
 if(fd<0)return;
 struct stat st;
 if(fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==sessionOwner && st.st_nlink==1 && (st.st_mode&077)==0){
  if(ftruncate(fd,0)==0)write(fd,text,strlen(text));
 }
 close(fd);
}
static int requestState(const char *path){
 int fd=open(path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);if(fd<0)return -1;
 struct stat st;char value=0;int valid=fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==sessionOwner && st.st_nlink==1 && (st.st_mode&077)==0 && time(NULL)-st.st_mtime<=12 && read(fd,&value,1)==1;
 close(fd);return valid && value>='0' && value<='2'?value-'0':-1;
}
static int automatic(int i){
 for(int attempt=0;attempt<4;attempt++){
  if(readfan(i,"Md")==0)return 1;
  smc_set_mode(i,0);usleep(250000);
 }
 return readfan(i,"Md")==0;
}
static int restoreAll(void){int ok=1;for(int i=0;i<4;i++)if(!automatic(i))ok=0;return ok;}
static int worker(const char *request,const char *status,const double *minimum,const double *maximum){
 double floor[4]={0};int active=0;
 while(!stop){
  int demand=requestState(request);if(demand<0)break;
  // Independent CPU fail-safe: relinquish manual control when the proximity
  // sensor becomes inaccessible or unusually hot. Apple handles other sensors.
  double cpu=thermal_read("TC0P");int safety=!isfinite(cpu) || cpu>=80;
  if(demand==0 || safety){
   if(active && !restoreAll())return 6;
   active=0;memset(floor,0,sizeof(floor));
   report(status,safety?"safety-auto":"ready");
  }else{
   for(int i=0;i<4;i++){
    if(!active){
     if(readfan(i,"Md")!=0)return 5;
     double target=readfan(i,"Tg"),rpm=readfan(i,"Ac");
     if(!isfinite(target) || !isfinite(rpm))return 5;
     floor[i]=fmax(target,rpm);
    }
    // Never lower the target captured from Apple's controller during this boost.
    double target=demand==2?maximum[i]:fmin(maximum[i],fmax(floor[i],minimum[i]+.2*(maximum[i]-minimum[i])));
    floor[i]=target;
    if(smc_set_target(i,target)!=0 || smc_set_mode(i,1)!=0 || smc_set_target(i,target)!=0)return 5;
    int verified=0;
    for(int n=0;n<4;n++){
     double actual=readfan(i,"Tg");
     if(readfan(i,"Md")==1 && isfinite(actual) && fabs(actual-target)<=5){verified=1;break;}
     usleep(250000);
    }
    if(!verified)return 5;
   }
   active=1;report(status,demand==2?"boost-max":"boost");
  }
  sleep(1);
 }
 return 0;
}
int main(int argc,char **argv){
 if(argc!=3 || geteuid()!=0)return 1;
 char model[64]={0};size_t length=sizeof(model);sysctlbyname("hw.model",model,&length,0,0);
 if(strcmp(model,"MacPro7,1") || smc_read_number("FNum")!=4)return 2;
 const char *request=argv[1],*status=argv[2];
 struct stat st;if(lstat(request,&st) || !S_ISREG(st.st_mode) || st.st_nlink!=1 || (st.st_mode&077)!=0)return 3;
 sessionOwner=st.st_uid;
 double minimum[4],maximum[4];
 for(int i=0;i<4;i++){
  minimum[i]=readfan(i,"Mn");maximum[i]=readfan(i,"Mx");
  if(!isfinite(minimum[i]) || !isfinite(maximum[i]) || minimum[i]<500 || maximum[i]>2500 || minimum[i]>=maximum[i] || readfan(i,"Md")!=0){report(status,"preflight-error");return 4;}
 }
 signal(SIGTERM,stopping);signal(SIGINT,stopping);signal(SIGHUP,stopping);
 pid_t child=fork();
 if(child<0){report(status,"preflight-error");return 4;}
 if(child==0){int result=worker(request,status,minimum,maximum);_exit(result);}
 // Privileged supervisor owns restoration, even if the worker crashes or is killed.
 int result=0;int exitStatus=0;
 while(1){
  pid_t waited=waitpid(child,&exitStatus,WNOHANG);
  if(waited==child)break;
  if(waited<0 && errno!=EINTR){result=5;break;}
  if(stop || requestState(request)<0){
   kill(child,SIGTERM);
   int reaped=0;
   for(int n=0;n<4;n++){usleep(250000);if(waitpid(child,&exitStatus,WNOHANG)==child){reaped=1;break;}}
   if(!reaped){kill(child,SIGKILL);while(waitpid(child,&exitStatus,0)<0 && errno==EINTR){}}
   break;
  }
  sleep(1);
 }
 if(result==0){if(WIFEXITED(exitStatus))result=WEXITSTATUS(exitStatus);else result=5;}
 if(!restoreAll()){report(status,"restore-error");return 6;}
 report(status,result==5?"unsupported":result==6?"stopped-restored":"stopped");
 return result==6?0:result;
}
