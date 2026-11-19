#include "SMC.h"
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <string.h>
// AppleSMC user-client wire layout; writes are restricted to fan registers below.
typedef struct {
 uint32_t key;
 struct { uint8_t major,minor,build,reserved; uint16_t release; } version;
 struct { uint16_t version,length; uint32_t cpu,gpu,memory; } limits;
 struct { uint32_t size,type; uint8_t attributes; } info;
 uint8_t result,status,command;
 uint32_t index;
 uint8_t bytes[32];
} Message;
_Static_assert(sizeof(Message)==80,"SMC ABI mismatch");
static uint32_t code(const char *s) { return (uint32_t)(uint8_t)s[0]<<24 | (uint32_t)(uint8_t)s[1]<<16 | (uint32_t)(uint8_t)s[2]<<8 | (uint8_t)s[3]; }
double smc_read_number(const char *key) {
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if (!service) return NAN;
 io_connect_t connection=0;
 kern_return_t kr=IOServiceOpen(service,mach_task_self(),0,&connection);
 IOObjectRelease(service);
 if(kr!=KERN_SUCCESS) return NAN;
 Message input={0},output={0}; size_t size=sizeof(output);
 input.key=code(key); input.command=9;
 kr=IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size);
 double value=NAN;
 if(kr==KERN_SUCCESS && output.result==0 && output.info.size<=32) {
  input.info=output.info; input.command=5; size=sizeof(output);
  uint32_t type=input.info.type; memset(&output,0,sizeof(output));
  kr=IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size);
  if(kr==KERN_SUCCESS && output.result==0) {
   if(type==code("sp78") && input.info.size==2) value=(int16_t)((output.bytes[0]<<8)|output.bytes[1])/256.0;
   else if(type==code("ui8 ") && input.info.size==1) value=output.bytes[0];
   else if(type==code("fpe2") && input.info.size==2) value=((output.bytes[0]<<8)|output.bytes[1])/4.0;
   else if(type==code("flt ") && input.info.size==4) { float f; memcpy(&f,output.bytes,4); value=f; }
  }
 }
 IOServiceClose(connection);
 return value;
}

double thermal_read(const char *key) { double value=smc_read_number(key); return isfinite(value) && value>0 && value<130 ? value : NAN; }
// Internal bounded writer; only fan target and automatic/manual mode.
static int fan_write(int fan, const char *suffix, double rpm) {
 if(fan<0 || fan>3 || !isfinite(rpm)) return -1;
 if(strcmp(suffix,"Md")==0) { if(rpm!=0 && rpm!=1)return -1; }
 else if(rpm<500 || rpm>2500)return -1;
 char key[5]={'F',(char)('0'+fan),suffix[0],suffix[1],0};
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if(!service) return -2;
 io_connect_t connection=0;
 kern_return_t kr=IOServiceOpen(service,mach_task_self(),0,&connection); IOObjectRelease(service);
 if(kr!=KERN_SUCCESS) return -3;
 Message input={0},output={0}; size_t size=sizeof(output);
 input.key=code(key); input.command=9;
 kr=IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size);
 int status=-4;
 if(kr==KERN_SUCCESS && output.result==0) {
  input.info=output.info; input.command=6;
  if(input.info.type==code("ui8 ") && input.info.size==1 && strcmp(suffix,"Md")==0) { input.bytes[0]=(uint8_t)rpm; }
  else if(input.info.type==code("flt ") && input.info.size==4) { float f=rpm; memcpy(input.bytes,&f,4); }
  else if(input.info.type==code("fpe2") && input.info.size==2) { uint16_t v=(uint16_t)(rpm*4);input.bytes[0]=v>>8;input.bytes[1]=v&255; }
  else { IOServiceClose(connection);return -5; }
  memset(&output,0,sizeof(output));size=sizeof(output);
  kr=IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size);
  status=kr==KERN_SUCCESS && output.result==0 ? 0 : -6;
 }
 IOServiceClose(connection);return status;
}

int smc_set_target(int fan, double rpm) { return fan_write(fan,"Tg",rpm); }
int smc_set_mode(int fan, int mode) { return fan_write(fan,"Md",mode); }
