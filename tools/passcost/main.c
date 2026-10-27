#include <stdio.h>
#include <time.h>
long long mic_push(long long); long long mic_reg(long long);
static long long now(void){struct timespec t;clock_gettime(1,&t);return t.tv_sec*1000000000LL+t.tv_nsec;}
int main(void){
  long long n=200000000, t0,t1,a,b,r1,r2;
  mic_push(1000); mic_reg(1000);
  t0=now(); r1=mic_push(n); t1=now(); a=t1-t0;
  t0=now(); r2=mic_reg(n);  t1=now(); b=t1-t0;
  printf("push/pop  传递: %lld ns\n", a);
  printf("寄存器    传递: %lld ns\n", b);
  printf("差异: %+lld%%  (正=push/pop 更慢)\n", (a-b)*100/b);
  fprintf(stderr,"chk %lld %lld\n",r1,r2);
  return (r1!=r2);
}
