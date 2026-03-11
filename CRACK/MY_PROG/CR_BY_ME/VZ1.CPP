#include <stdio.h>
#include <stdlib.h>

int main(){
    FILE* fp = fopen("VZ1.BIN", "wb");
    for(int i = 0x0234; i < 0x02B6; i++){
        fputc(0x00, fp);
    }
    fputc(0x0D, fp);
    fclose(fp);
}