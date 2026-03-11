#include <stdio.h>

int main() {
    FILE *file = fopen("PATCH1.COM", "rb+");

    fseek(file, 0x78 ,SEEK_SET);  
    
    unsigned char new_byte = 0xEB;
    fwrite(&new_byte, 1, 1, file);

    fclose(file);
}