// Offline OGG -> WAV through the already-installed IINA libmpv PCM file sink.
// No UI, scripts, network input, configuration, or physical audio output.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
typedef void mpv_handle;
typedef struct {int event_id;int error;uint64_t reply_userdata;void *data;} mpv_event;
extern mpv_handle *mpv_create(void);
extern int mpv_set_option_string(mpv_handle *,const char *,const char *);
extern int mpv_initialize(mpv_handle *);
extern int mpv_command(mpv_handle *,const char **);
extern mpv_event *mpv_wait_event(mpv_handle *,double);
extern void mpv_terminate_destroy(mpv_handle *);
int main(int argc,char **argv){
 if(argc!=3)return 2;
 mpv_handle *h=mpv_create();if(!h)return 3;
 const char *options[][2]={{"config","no"},{"load-scripts","no"},{"terminal","no"},{"vo","null"},{"vid","no"},{"ao","pcm"},{"ao-pcm-file",argv[2]},{"ao-pcm-waveheader","yes"},{"audio-format","s16"},{"audio-channels","mono"},{"audio-samplerate","24000"},{"idle","yes"},{"keep-open","no"}};
 for(unsigned i=0;i<sizeof(options)/sizeof(options[0]);i++){int r=mpv_set_option_string(h,options[i][0],options[i][1]);if(r<0){fprintf(stderr,"option rejected: %s (%d)\n",options[i][0],r);mpv_terminate_destroy(h);return 4;}}
 if(mpv_initialize(h)<0){mpv_terminate_destroy(h);return 5;}
 const char *args[]={"loadfile",argv[1],NULL};if(mpv_command(h,args)<0){mpv_terminate_destroy(h);return 6;}
 int done=0;for(int i=0;i<600;i++){mpv_event *e=mpv_wait_event(h,.1);if(e->event_id==7){done=1;break;}if(e->event_id==1)break;}
 mpv_terminate_destroy(h);printf("PCM file sink completed=%d; no device output selected.\n",done);return done?0:7;
}
