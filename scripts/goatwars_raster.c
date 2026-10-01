#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include "dcs_lcd_draw.h"
int main(int argc,char **argv) {
  if(argc!=2) return 2;
  FILE *input=fopen(argv[1],"r");
  if(!input) return 2;
  size_t len; if (fscanf(input,"%zu\n",&len)!=1 || len>10000) return 2;
  BaseDisplayItem *items=calloc(len,sizeof(*items));
  for(size_t i=0;i<len;i++) {
    int tag; unsigned color; BaseDisplayItem *v=&items[i];
    if(fscanf(input,"%d %d %d %d %d %u ",&tag,&v->x,&v->y,&v->width,&v->height,&color)!=6 || tag<0 || tag>3) return 2;
    v->brcolor=(color<<8)|255;
    if(tag==0) v->primitive=PrimitiveRect;
    if(tag==1 || tag==3) {
      v->primitive=PrimitiveText; v->data.text_data.fgcolor=v->brcolor; v->brcolor=0;
      if(tag==3) {
        unsigned background;
        if(fscanf(input,"%u ",&background)!=1)return 2;
        v->brcolor=(background<<8)|255;
      }
      char buf[256]; fgets(buf,sizeof(buf),input); size_t l=strcspn(buf,"\r\n");buf[l]=0;
      v->data.text_data.text=strdup(buf);v->width=(int)l*8;v->height=16;
    }
    if(tag==2) {
      v->primitive=PrimitiveScaledCroppedImage;
      if(fscanf(input,"%d %d %d %d %d %d ",&v->source_x,&v->source_y,&v->x_scale,&v->y_scale,&v->data.image_data_with_size.width,&v->data.image_data_with_size.height)!=6) return 2;
      if(v->x_scale<=0 || v->y_scale<=0 || v->data.image_data_with_size.width<=0 || v->data.image_data_with_size.height<=0) return 2;
      char path[1024];fgets(path,sizeof(path),input);path[strcspn(path,"\r\n")]=0;
      FILE *image=fopen(path,"rb"); if(!image)return 3;
      size_t size=v->data.image_data_with_size.width*v->data.image_data_with_size.height*4;
      char *data=malloc(size); if(fread(data,1,size,image)!=size)return 4;fclose(image);
      v->data.image_data_with_size.pix=data;v->brcolor=color ? ((color<<8)|255) : 0;
    }
  }
  fclose(input);
  uint16_t row[320]; struct DCSLCDScreen screen={.w=320,.h=240,.pixels=row};
  clock_t begin=clock(); unsigned long checksum=0;
  for(int n=0;n<30;n++)for(int y=0;y<240;y++) {
    for(int x=0;x<320;) x+=dcs_lcd_draw_x(&screen,x,y,items,len);
    checksum+=row[160];
  }
  printf("items=%zu raster_us=%.2f checksum=%lu\n",len,1e6*(clock()-begin)/CLOCKS_PER_SEC/30,checksum);
  const char *dump_path=getenv("GOATWARS_FRAME_DUMP");
  if(dump_path) {
    FILE *dump=fopen(dump_path,"wb"); if(!dump)return 5;
    for(int y=0;y<240;y++) {
      for(int x=0;x<320;) x+=dcs_lcd_draw_x(&screen,x,y,items,len);
      if(fwrite(row,sizeof(uint16_t),320,dump)!=320)return 5;
    }
    fclose(dump);
  }

}
