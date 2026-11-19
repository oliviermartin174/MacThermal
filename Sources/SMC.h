#include <stdint.h>
double thermal_read(const char *key);
double smc_read_number(const char *key);
int smc_set_target(int fan, double rpm);
int smc_set_mode(int fan, int mode);
