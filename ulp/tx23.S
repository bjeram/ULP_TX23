#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"

#include "stack.S"

/*gpio 15  = PAD3 = RTC_GPIO13 */
.macro GPIO_read
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 13, 1)
.endm

/* Set pin high-impedance state (input mode) */
/* high imedance pin has an indeterminate state. it is nether high or low which is also commonly referred as "floating" or "tri-stated". To set it to high or low, it has to be driven by an external source */
.macro GPIO_H
	WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TC_REG, RTC_GPIO_ENABLE_W1TC_S + 13, 1, 1)
.endm

/* Output mode */
.macro GPIO_L
	WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TS_REG, RTC_GPIO_ENABLE_W1TS_S + 13, 1, 1)
.endm

/* These two marco for set bus high and set low when GPIO_L is called, enable W1TS. */
.macro GPIO_high
	WRITE_RTC_REG(RTC_GPIO_OUT_W1TS_REG, RTC_GPIO_OUT_DATA_W1TS_S + 13, 1, 1) 
.endm

.macro GPIO_low
	WRITE_RTC_REG(RTC_GPIO_OUT_W1TC_REG, RTC_GPIO_OUT_DATA_W1TC_S + 13, 1, 1) 
/*	WRITE_RTC_REG(RTC_GPIO_OUT_REG, RTC_GPIO_OUT_DATA_S + 13, 1, 0) */
.endm
    


	/* Define variables, which go into .bss section (zero-initialized data) */
	.bss
	.global stack
stack:
	.skip 24
	.global stackEnd
stackEnd:
	.long 0

	.global temperatureC
temperatureC:
	.long 0
	
	.global temperatureF
temperatureF:
	.long 0

	.global crc8_check
crc8_check:
	.long 0
	.global crc8_value
crc8_value:
	.long 0
	
	.global scratchpad_memory
scratchpad_memory:	// Return 9 Bytes of data after an 0xBE command.
	.long 0		// Byte 0: Temperature LSB
	.long 0		// Byte 1: Temperature MSB
	.long 0		// Byte 2: Th Register
	.long 0		// Byte 3: Tl Register
	.long 0 	// Byte 4: Configuraion Register
	.long 0		// Byte 5: Reserved 
	.long 0		// Byte 6: Reserved
	.long 0		// Byte 7: Reserved
	.long 0		// Byte 8: CRC value


	/* Code goes into .text section */
	.text
	.global entry
entry:

/* Register general usage: */
/* R1 is used for scratech register: So, don't use it if you are push/pop/psr/ret */
/* R3 is used as stack pointer: DON'T USE */
/* R0 is sometime used for JUMPR .... */
/* R2 is free to use: Here, R2 is either used as passing para or as a return var. */

	move r3, stackEnd

	/* disable hold on gpio 15 (data pin) looks like it is not needed */
//  WRITE_RTC_REG(RTC_IO_TOUCH_PAD3_REG, RTC_IO_TOUCH_PAD3_HOLD_S, 1, 0) 

	psr
	jump get_values 


/*
	move r1, temperatureC
	st r0, r1, 0

	psr 
	jump get_values

	move r1, temperatureF
	st r0, r1, 0
*/

	jump exit_wake 

exit:
	/* ULP will restart when half */
	halt

exit_wake:
        READ_RTC_REG(RTC_CNTL_DIAG0_REG, 19, 1)
        and r0, r0, 1
        jump exit, eq

        /* Wake up the SoC and stop ULP program */
	wake
        /* Stop the wakeup timer so it does not restart ULP */
        /* WRITE_RTC_FIELD(RTC_CNTL_STATE0_REG, RTC_CNTL_ULP_CP_SLP_TIMER_EN, 0) */
        halt


rst_pulse:
	/* set OUTPUT_W1TS for output */
	GPIO_L
	/* ULP running at 8mhz, 8mhz  = 1us per 8 cpu cycles, thats 0.125us per one cpu cycle.  */
	/* So, 500us delay = 500/0.125 => 4,000 cpu cycles. */
	/* wait 500 microsecond, 1000 ms = 1 millisecon */
	GPIO_low
	 /* wait 500 ms */
	stage_rst                  
wait01:  stage_inc  1          
    wait 65535 /* 8ms*/
	wait 65535
	wait 65535
    jumps wait01, 21, LT   
	
	GPIO_high
	GPIO_H
	/* wait another 1.2ms */
	wait    9800
	/* GPIO_read r0 holds input result */
	/* 16mSec  */
    wait 65535 /* 8ms*/
	wait 65535
	
wait_data_start: 
	wait 800
	GPIO_read
	and r0, r0, 1
	jump wait_data_start, eq

	ret
	
/* R0 - (16bit) temperature is store in R0 on return. */
/* This work with one device on the bus, for multiple devicse you should send ROM-ID after rst_pulse */
get_values:
	psr
	jump rst_pulse
	
	/* delay 750ms, looping 750x in delay_ms */
	/* 0x44 convert command: convertion is slow, 750 milliseconds */
	/*psr
	jump delay_ms
	*/
	
	wait 4800 /* 600us */
	/* read 9 bytes from scratchpad memory,*/
	stage_rst
	move r0, scratchpad_memory

	push r0
	psr
    jump read_5bits
	pop r0
	st r2, r0, 0
/****/	
	move r0, temperatureC
    st r2, r0, 0
	move r0, scratchpad_memory
/****/
	add r0, r0, 1

	push r0
	psr
    jump read_4bits
	pop r0
	st r2, r0, 0
	add r0, r0, 1
ret
	push r0
	psr
    jump read_12bits
	pop r0
	st r2, r0, 0
	add r0, r0, 1

	push r0
	psr
    jump read_4bits
	pop r0
	st r2, r0, 0
	add r0, r0, 1

	push r0
	psr
    jump read_4bits
	pop r0
	st r2, r0, 0
	add r0, r0, 1
	

	push r0
	psr
    jump read_12bits
	pop r0
	st r2, r0, 0
	add r0, r0, 1

	ret 

/* R2: (5bits) read_byte stores in R2 on return. */
read_5bits:
	
	move r2, 0  /* read-out data (bits) */ 
	move r0, 0  /* bit index */
	move r1, 0 

	/* in next two stes we are assuming that first read is 1 = bit is 1*/
	move r2, 1  /* read-out data (bits) */ /* first value is always 1 TBC*/
	move r0, 1  /* bit index  as first bit is already read*/
	move r1, 1 /* previos bit value is always 1 TBC */
	

read_5bits_loop:
	push r0

	/* put previos value to r0 */
	move r0, r1
	psr
	jump read_wait
/*	jump read_bit */
	move r1, r0
	pop r0

	push r1 /* store current (previos) bit value*/
	lsh r1, r1, r0
	or r2, r2, r1
	pop r1

	/* wait 9750 *//* 1200us */
	add r0, r0, 1
	jumpr read_5bits_loop, 5, LT

	ret

/* R2: (4bits) read_byte stores in R2 on return. */
read_4bits:
	
	move r2, 0
	move r0, 0

	/* in next two stes we are assuming that first read is 1 = bit is 1*/
	/* previos value must bwe 11011 */
	move r1, 1 /* previos bit value is always 1 TBC */
read_4bits_loop:
	push r0
	/* put previos value to r0 */
	move r0, r1
	psr
	jump read_wait
	/* jump read_bit */
	move r1, r0
	pop r0

	push r1 /* store current (previos) bit value*/
	lsh r1, r1, r0
	or r2, r2, r1
	pop r1

	/* wait 9750 *//* 1.2ms */
	add r0, r0, 1
	jumpr read_4bits_loop, 4, LT

	ret

/* R2: (12bits) read_byte stores in R2 on return. */
read_12bits:
	/*
	psr
	jump read_bit
	move r2, r0
	wait(120)  15 us 
	move r0, 1
	*/
	move r2, 0
	move r0, 0

read_12bits_loop:
	push r0
	psr
	jump read_bit
	move r1, r0
	pop r0

	lsh r1, r1, r0
	or r2, r2, r1

	/* wait(120)  15 us */
	wait 9750 /* 1.2ms */
	add r0, r0, 1
	jumpr read_12bits_loop, 12, LT

	ret

/* R0: (1bit) stores GPIO input on return. */
/* since R2 is used to store all the bits */
read_bit:
	GPIO_H
	GPIO_read 
	
	ret


/* reads next bit eather value cahnged, or timer (1.2ms) */
/* R0: (1bit) stores GPIO input on return. */
/* r0 should contain previos value = bit*/
/* since R2 is used to store all the bits */
read_wait:

		stage_rst
		jumpr wait_for_low, 1, GE /* EQ does not work ??? */

wait_for_high:
		wait 800 /* 100us*/
//		GPIO_H /* do we actaully need this ?? */
		GPIO_read 
		jumpr edge_read, 1, GE
		stage_inc  1          
        jumps wait_for_high, 12, LT   /*  12 * 100us = 1.2ms */
		ret /* value is in r0 */

wait_for_low:
		wait 800 /* 100us*/
//		GPIO_H /* do we actaully need this ?? */
		GPIO_read 
		jumpr edge_read, 1, LT
		stage_inc  1          
        jumps wait_for_low, 12, LT   /*  12 * 100us = 1.2ms */
		ret /* value is in r0 */

edge_read:
		wait 4800 /* 600us  to get mid of the bit */
		ret


delay_ms:
	/* delay 750 mill sec, wait 0.75 sec, 1000 millisecond = 1 second */
	/* 1ms = 1,000 us */
	move r0, 750
	delay_ms_loop:

	sub r0, r0, 1
	wait(7990) /* 1millsecond = 1000 microsecond */
	jumpr delay_ms_loop, 1, GE
	ret

