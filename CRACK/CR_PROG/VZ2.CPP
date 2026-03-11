#include <stdio.h>
#include <stdlib.h>

int main(){
    FILE* fp = fopen("VZ2.BIN", "wb");
    for(int i = 0xFFE1; i < 0xFFFA; i++){
        fputc(0x00, fp);
    }

    fputc(0xFC, fp); // FFFA
    fputc(0xFF, fp); // FFFB
    fputc(0xA9, fp); // FFFC
    fputc(0x01, fp); // FFFD
    fputc(0x03, fp); // FFFE
    fputc(0x01, fp); // FFFF
    fputc(0x0D, fp);
    fclose(fp);
}