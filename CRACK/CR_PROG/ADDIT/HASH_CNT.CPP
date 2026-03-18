#include <stdio.h>


int main() {
    FILE *file = fopen("CRACK/CR_PROG/ADDIT/PATCH.COM", "rb+");
    if(!file){
        fprintf(stderr, "Incorrect file - can't open");
        return 0;
    }

    int sum_real = 0;
    char byte = fgetc(file);
    while (byte != EOF) {
        sum_real += (unsigned char)byte; 
        byte = fgetc(file);
    }
    printf("%d\n", sum_real);

    /*
    fseek(file, 0x78 ,SEEK_SET);  
    
    unsigned char new_byte = 0xEB;
    fwrite(&new_byte, 1, 1, file);
    */

    fclose(file);
}