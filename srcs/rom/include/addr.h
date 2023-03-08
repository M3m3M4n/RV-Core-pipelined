#ifndef ADDR_H
#define ADDR_H

#include <stdint.h>

uint32_t * addr_gpio_in           = (uint32_t *)0xfffffff8; // 32 bit == 32 ios
uint32_t * addr_gpio_out          = (uint32_t *)0xfffffffc;
uint32_t * addr_hdmi_frame_buffer = (uint32_t *)0x40000000; // 640 480
uint32_t * addr_hdmi_status_1     = (uint32_t *)0x40009600; // others
uint32_t * addr_hdmi_status_2     = (uint32_t *)0x40009604; // x, y coords. 16 bits

#endif