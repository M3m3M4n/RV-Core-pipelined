// No loader available, compile then extract code as ROM
// Bare metal C, no libs included

#include "addr.h"
#include "reset.h"
#include "font88.h"

char screenbufferchar [60][80];

void writebuffer()
{
    // read signal
    //if ((*addr_hdmi_status_1) & 0b10) { // new frame
        for (int y = 0; y < 480; y++) {
            for (int x = 0; x < 80; x++) { // write row data byte by byte
                int charbuffer_x = x;
                int charbuffer_y = y / 8; // row data (font wise)
                int byte_select  = y % 8;
                char chardata    = screenbufferchar[charbuffer_y][charbuffer_x];
                *((char*)addr_hdmi_frame_buffer + (80 * y + x)) = font8x8_basic[chardata][byte_select];
            }
        }
    //}
}

int main(void) {

    for (int i = 0 ; i < 60; i++) {
        for (int j = 0; j < 80; j++) {
            int pos = j % 4;
            /* switch (pos)
            {
            case 0:
                screenbufferchar[i][j] = 0;
                break;
            case 1:
                screenbufferchar[i][j] = 1;
                break;
            case 2:
                screenbufferchar[i][j] = 1;
                break;
            case 3:
                screenbufferchar[i][j] = 2;
                break;
            default:
                break;
            } */
            screenbufferchar[i][j] = 0;
        }
    }

    screenbufferchar[1][1]  = 'H';
    screenbufferchar[1][2]  = 'E';
    screenbufferchar[1][3]  = 'L';
    screenbufferchar[1][4]  = 'L';
    screenbufferchar[1][5]  = 'O';
    screenbufferchar[1][6]  = ' ';
    screenbufferchar[1][7]  = 'W';
    screenbufferchar[1][8]  = 'O';
    screenbufferchar[1][9]  = 'R';
    screenbufferchar[1][10] = 'L';
    screenbufferchar[1][11] = 'D';
    screenbufferchar[1][12] = '!';

    while(1){
        writebuffer();
    }

    return 0;
}
