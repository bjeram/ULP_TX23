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

	.global data_header
data_header:
	.long 0
	
	.global wind_direction
wind_direction:
	.long 0

	.global crc8_check
crc8_check:
	.long 0
	.global crc8_value
crc8_value:
	.long 0
	
	.global err
err:
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
	psr
	jump get_values 

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
	 /* keep it low for 500 ms */
	stage_rst                  
wait01:  stage_inc  1          
    wait 65535 /* ~8ms*/
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
	/* and wait for HIGH*/
	stage_rst
wait_data_start: 
	stage_inc 1
	jumps err_timeout1, 200, GT /* 2s*/
	wait 800 /* 100us */
	GPIO_read
	and r0, r0, 1
	jump wait_data_start, eq

	ret

err_timeout1:
	move r0, 0x1
	move r0, err
    st r2, r0, 0

	jump exit_wake 

get_values:
	psr
	jump rst_pulse
		
	wait 4900 /* 600us  to get ot the mid of bit/pulse*/
	
	/* 9 bytes from scratchpad memory,*/
	stage_rst
	move r0, scratchpad_memory

	push r0
	move r2, 1 // previous bit is 1 (rst_pulse)
	psr
    jump read_4bits
	pop r0
	or r2, r2, 0x10 // as we have read the first of 5 bits in rst_pulse
	st r2, r0, 0

	
/****/	
	move r0, data_header
    st r2, r0, 0
	move r0, scratchpad_memory
/****/
	add r0, r0, 1
/* let's read wind direction and speed (16bits) */
	push r0
	move r2, 1 /* previous bit value should be always 1 (11011) for read_16bits*/
	psr
    jump read_16bits
	pop r0
	st r2, r0, 0 /* write to scratchpad_memory */
//	add r0, r0, 1
/****/	
	move r0, wind_direction
	and r2, r2, 0xF
    st r2, r0, 0

	move r0, scratchpad_memory
	add r0, r0, 2
/****/

/* CRC */ 
	push r0
	// set previos bit from previos value
	rsh r2, r2, 15
	and r2, r2, 0x1
	//move r2, 0 /* for testin/prototyping previos bit value is set to 0 TBC for read_4bits*/
	psr
    jump read_4bits
	pop r0
	st r2, r0, 0 /* store CRC */
	add r0, r0, 1

/* wind and speed but in different format, but still 16 bits*/
// not right result as previos value is not set (r1) !!!!
	push r0
	rsh r2, r2, 3
	and r2, r2, 0x1
//	move r2, 0 /* for testin/prototyping previos bit value is set to 0 TBC */
	psr
    jump read_16bits
	pop r0
	st r2, r0, 0 /* store */
	
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

/* R2 should containe previos bit version
(4bits) read_byte stores in R2 on return. */
read_4bits:
	move r1, r2

	move r2, 0
	move r0, 0
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


/* R2 should contain previos bit 
(16bits) read_byte stores in R2 on return. */
read_16bits:
	move r1, r2 // previos bit to r1

	move r2, 0
	move r0, 0

read_16bits_loop:
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
	jumpr read_16bits_loop, 16, LT

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
		GPIO_read 
		jumpr edge_read, 1, GE
		stage_inc  1          
        jumps wait_for_high, 12, LT   /*  12 * 100us = 1.2ms */
		ret /* value is in r0 */

wait_for_low:
		wait 800 /* 100us*/
		GPIO_read 
		jumpr edge_read, 1, LT
		stage_inc  1          
        jumps wait_for_low, 12, LT   /*  12 * 100us = 1.2ms */
		ret /* value is in r0 */

edge_read:
		wait 4800 /* 600us  to get mid of the bit */
		ret

