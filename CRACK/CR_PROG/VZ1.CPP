#include <stdio.h>
#include <stdlib.h>

int main(){
    unsigned char bytes[]={
        0xEF, 0xBE, 
        0xBA, 0xFA, 0x01, 
        0xB4, 0x0A
    };
    FILE* fp = fopen("VZ1.BIN", "wb");
    for(int i = 0x017D; i < 0x0196; i++){
        fputc(0x00, fp);
    }
    fwrite(bytes, sizeof(bytes), 1, fp);
    fputc(0x0D, fp);
    fclose(fp);
}