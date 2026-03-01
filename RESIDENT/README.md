# Resident assembly program

## Description
This is a resident program for DOS written in Assembly language (.286, .model tiny). It intercepts keyboard and timer interrupts to display CPU register values in a frame on the screen. The program becomes TSR (Terminate and Stay Resident) after the first launch.

## Interrupts Handled
- **INT 08h** (Timer) - frame protection and register updates
- **INT 09h** (Keyboard) - ESC key detection

## Command Line Parameters
You can customize the frame characters using named parameters:
> ```
> program.com --TL=xxh, --TR=xxh, --BL=xxh, --BR=xxh, --HL=xxh, --VL=xxh,
> ```

Where:
- `--TL=xxh` - left top corner
- `--TR=xxh` - right top corner
- `--BL=xxh` - left bottom corner
- `--BR=xxh` - right bottom corner
- `--HL=xxh` - horizontal line
- `--VL=xxh` - vertical line

## Example 
> ```
> program.com --VL=03h, --HL=04h,
> ```

If no parameters are specified, default pseudographics characters are used:

- `0c9h` - left top corner
- `0bbh` - right top corner
- `0c8h` - left bottom corner
- `0bch` - right bottom corner
- `0cdh` - horizontal line
- `0bah` - vertical line


## How It Works

### First Launch
1. Parses command-line parameters (if any)
2. Saves old interrupt vectors (INT 08h and INT 09h)
3. Installs new interrupt handlers
4. Becomes resident (TSR)

### ESC Handler (INT 09h)
- **If frame not shown (IsFrameShown set to 0):**
- Saves current screen area to `SaveBuffer`
- Draws frame with register values to `DrawBuffer`
- Displays the contents of `DrawBuffer` on the screen
- Sets `IsFrameShown = 1`
- **If frame shown (IsFrameShown set to 1):**
- Restores original screen from `SaveBuffer`
- Sets `IsFrameShown = 0`

### Timer Handler (INT 08h)
- **Every tick:**
- Compares video memory with `DrawBuffer` symbol by symbol
- Restores any corrupted frame characters. If discrepancies are found (meaning some other program has drawn characters in video memory), the mismatching character is transferred to the SaveBuffer, and in its place, the character from the same position in the DrawBuffer is drawn.
- **Every `TimerShift` ticks:**
- Updates register values in `DrawBuffer`
- Refreshes the display using data from `DrawBuffer`

## Frame and Register Colors
In the program, two colors are hardcoded (cannot be changed via the command line):
- **COLF = 00111111b** - color for the frame: **white characters on cyan background**
- **COLW = 00110000b** - color for register values: **black characters on cyan background**

## Notes
- The program displays **11 registers**: AX, BX, CX, DX, SI, DI, SP, BP, DS, ES, SS
- Register values are shown in hexadecimal format
- The frame automatically protects itself from being overwritten by other programs
- Custom frame characters must be specified in hexadecimal format (xxh)
