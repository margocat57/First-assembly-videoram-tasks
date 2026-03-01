# Program for Drawing a Frame Around Text from Command Line (DOS, .COM)

## Description
This assembly language program for DOS (.tiny model) accepts command line arguments, extracts text and frame parameters, then displays the text with a decorative frame in video memory. Since it uses the .tiny model and is a single-segment program, it generates a .COM file for execution.

### Parameters (in hexadecimal format with 'h' suffix):
1. **height** - frame height (number of lines)
2. **vertical_char** - character for vertical lines
3. **top_right_char** - top-right corner character
4. **horizontal_char** - character for horizontal lines
5. **top_left_char** - top-left corner character
6. **bottom_left_char** - bottom-left corner character
7. **bottom_right_char** - bottom-right corner character

### Separators:
- Parameters are separated by semicolons (';')
- All parameters must have the 'h' suffix (hexadecimal)
- The last parameter is separated from the text by a space

## Example 
> ```
> program.com 3h;0bah;0bbh;0cdh;0c9h;0c8h;0bch; Meow, Poltorashka
> ```

## Color Settings (defined inside the program)
- **Frame color (COLF)** - `00001011b` (cyan characters on black background)
- **Text color (COLW)** - `00111001b` (lilac characters on cyan background)


## Error Handling
If there are insufficient arguments or they are incorrect, the program will display:
> ```
> No enough arguments or arguments are incorrect
> ```
and terminate with return code 1 (AX=4C01h).