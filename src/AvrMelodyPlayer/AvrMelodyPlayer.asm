;=============================================================
; title			: AvrMelodyPlayer
; author		: Nobuhiro Kuroiwa
; started on	: 11/07/2012
; clock			: clk=8MHz
;=============================================================
; melody data select
; TINKLE	: Twinkle twinkle litttle star
; XMAS		: We wish you are merry christmas
;#define		TWINKLE	; uncommend if you want to change melody
;#define		XMAS		; commend if you above is commented out
#define		JAWS		; commend if you above is commented out

; header files
.include "m168def.inc"	;
.include "musicnote.inc"	; definition of music stuff

;=============================================================
; constants
;=============================================================
; timer cont
.equ T10USEC	= 248	; Pre Scale=1/8, 100KHz
.equ PRE_SCALE	= 0x2	; 1/8

;=============================================================
; variables
;=============================================================
.def sreg_save	= r0	; to store sreg
.def one		= r1	; constant 1
.def ten		= r2	; constant 10
.def t10us		= r3	; count for 10us
.def t100us		= r4	; count for 100us
.def t1ms		= r5	; count for 1ms
.def t10ms		= r6	; count for 10ms
.def t100ms		= r7	; count for 100ms
.def t1s		= r8	; count for 1s
.def sctopl		= r9	; sound interval count low byte
.def sctoph		= r10	; sound interval count high byte
.def mcnt		= r11	; t100ms counter
.def mtop		= r12	; tcnt top value
.def scntl		= r13	; scntl compare value
.def scnth		= r14	; scnth compare value

.def acc		= r16	; accumulator
.def acc2		= r17	; accumulator2

;=============================================================
; macro
;=============================================================
; time count
.macro TIME_COUNT		; TIME_COUNT @0 @1
	inc		@0			; increment register given by @0
	cp		@0, ten		; compare the register
	brne	@1			; if the register != 10 jump to @1
	clr		@0			; clear the register
.endmacro

; flip port output
.macro FLIP_PORTOUT		; FLIP_PORT portx, port_bit
	in		acc, @0
	ldi		acc2, @1	; bit mask
	eor		acc, acc2
	out		@0, acc		; output
.endmacro

;=============================================================
; program
;=============================================================
.cseg					   ; Code segment

;=============================================================
; vectors
;=============================================================
.org 	0x0000		jmp	main	 	; reset handler
.org	0x0020		jmp intr_time0	; timer0 overflow handler

;=============================================================
; main
;=============================================================
main:
	cli

	; initialize stack pointer
	ldi		acc, low(ramend)	; get lower byte of end of ram address
	out		spl, acc			; init stack lower pointer
	ldi		acc, high(ramend)	; get higher byte of end of ram address
	out		sph, acc			; init stack higher pointer

	; initialize constant register
	ldi		acc, 1			; put constant 1 in register
	mov		one, acc
	ldi		acc, 10			; put constant 10 in register
	mov		ten, acc

	; initialize port b
	ldi	 	acc, 0xFF		; PORTB all bits are output
	out	 	DDRB, acc		; set direction
	ldi	 	acc, 0x00		; set output data
	out	 	PORTB, acc		; set all to low

	; initialize port d
	ldi	 	acc, 0xFF		; PORTD all bits are output
	out	 	DDRD, acc		; set direction
	ldi	 	acc, 0x00		; set output data
	out	 	PORTD, acc		; set all to low

	; Timer/Counter 0 initialize
	; tccr0a=0, standard mode
	lds		acc, timsk0
	sbr	 	acc,(1<<TOIE0)	; set overflow interruption bit
	sts	 	TIMSK0, acc		; allow timer0 overflow interruption
	ldi	 	acc, T10USEC	; 10us count
	out	 	TCNT0, acc		; set timer0 counter
	ldi	 	acc, PRE_SCALE	; set prescale
	out	 	TCCR0B, acc		; start timer0

	; initialize our counters
	clr	 	t10us			; init counter for 10us
	clr	 	t100us			; init counter for 100usr
	clr	 	t1ms			; init counter for 1ms
	clr		t10ms			; init counter for 10ms

	; initialize sound interval counter
	clr		sctopl			; sound interval count low
	clr		sctoph			; sound interval count high

	; initialize melody counter
	clr		mcnt			; initialize melody counter

	; load data
	ldi		zl, low(SNDDATA<<1)		; init zl
	ldi		zh, high(SNDDATA<<1)	; init zh

	lpm		mtop, z+			; initialize tcnt compare value
	lpm		sctopl, z+		; count untill scntl becomes this value
	clr		sctoph			; and scnth becomes this value. but not used this time

	sei						; allow all interruption

main_loop:
	out	 	PORTB, sctopl	; output current sctopl value
	rjmp	main_loop		; loop

;=============================================================
; timer0 interruption
;=============================================================
intr_time0:
	in		sreg_save, SREG	; preserve status
	push	sreg_save
	push	acc				; preserve acc
	push	acc2			; preserve acc1

	; reset timer
	clr		acc				; stop counter
	out		tccr0b, acc

	ldi		acc, T10USEC	; 10usec count
	out		TCNT0, acc		; set timer0

	ldi		acc, PRE_SCALE
	out		tccr0b, acc

	TIME_COUNT t10us,	intr_time0_sndpwm	; count wrap around for 10us
	TIME_COUNT t100us,	intr_time0_sndpwm	; count wrap around for 100us
	TIME_COUNT t1ms,	intr_time0_sndpwm	; count wrap around for 1ms
	TIME_COUNT t10ms,	intr_time0_sndpwm	; count wrap around for 10ms
	TIME_COUNT t100ms,	initr_time0_setsnd	; count wrap around for 100ms
	TIME_COUNT t1s,		initr_time0_setsnd	; count wrap around for 1s

initr_time0_setsnd:
	rcall	set_snd			; called every 100ms

intr_time0_sndpwm:
	rcall	snd_pwm

intr_time0_end:
	pop		acc2			; restore acc2			
	pop		acc				; restore acc
	pop		sreg_save
	out		SREG, sreg_save	; restore sreg
	reti					;

;=============================================================
; set sound frequency
;=============================================================
set_snd:
	inc		mcnt
	cp		mtop, mcnt
	brne	set_snd_exit	; if mtop!=mcnt, do nothing
	clr		mcnt

	; check more data left
	cpi		zl, low(SNDDATA_END<<1)
	brne	set_snd_asgn
	cpi		zh, high(SNDDATA_END<<1)
	brne	set_snd_asgn

	; if data is end, reset pointer with head position
	ldi		zl, low(SNDDATA<<1)
	ldi		zh, high(SNDDATA<<1)

set_snd_asgn:
	lpm		mtop, z+		; initialize tcnt compare value
	lpm		sctopl, z+		; count untill scntl becomes this value
	clr		sctoph			; and scnth becomes this value. but not used this time
	clr		scntl
	clr		scnth
set_snd_exit:
	ret

;=============================================================
; sound frequency pwm
;=============================================================
snd_pwm:
	clc
	adc		scntl, one
	brcc	snd_pwm1
	clc
	adc		scnth, one
	brcc	snd_pwm1
	clc
snd_pwm1:
	cp		sctopl, scntl
	brne	snd_pwm_ext
	cp		sctoph, scnth
	brne	snd_pwm_ext
	FLIP_PORTOUT portd, 0b0000_0001
	clr		scntl
	clr		scnth
snd_pwm_ext:
	ret

;=============================================================
; data
;=============================================================
#ifdef TWINKLE
SNDDATA:
	.db NOTE_8, TONE_2C
	.db NOTE_8, TONE_1C
	.db NOTE_8, TONE_2C
	.db NOTE_8, TONE_1C
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2A
	.db NOTE_8, TONE_1A
	.db NOTE_8, TONE_2A
	.db NOTE_8, TONE_1A
	.db NOTE_2, TONE_2G

	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2D
	.db NOTE_8, TONE_1D
	.db NOTE_8, TONE_2D
	.db NOTE_8, TONE_1D
	.db NOTE_2, TONE_2C

	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_2, TONE_2D

	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_2, TONE_2D

	.db NOTE_8, TONE_2C
	.db NOTE_8, TONE_1C
	.db NOTE_8, TONE_2C
	.db NOTE_8, TONE_1C
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2G
	.db NOTE_8, TONE_1G
	.db NOTE_8, TONE_2A
	.db NOTE_8, TONE_1A
	.db NOTE_8, TONE_2A
	.db NOTE_8, TONE_1A
	.db NOTE_2, TONE_2G

	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2F
	.db NOTE_8, TONE_1F
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2E
	.db NOTE_8, TONE_1E
	.db NOTE_8, TONE_2D
	.db NOTE_8, TONE_1D
	.db NOTE_8, TONE_2D
	.db NOTE_8, TONE_1D
	.db NOTE_2, TONE_2C
SNDDATA_END:
#endif

#ifdef XMAS
SNDDATA:
	.db NOTE_8, TONE_2G
	.db NOTE_16, TONE_3C
	.db NOTE_16, TONE_2C
	.db NOTE_16, TONE_3C
	.db NOTE_16, TONE_2D
	.db NOTE_16, TONE_3C
	.db NOTE_16, TONE_2B
	.db NOTE_16, TONE_2A
	.db NOTE_16, TONE_1A
	.db NOTE_16, TONE_2A
	.db NOTE_16, TONE_1A

	.db NOTE_8, TONE_2A
	.db NOTE_16, TONE_2D
	.db NOTE_16, TONE_1D
	.db NOTE_16, TONE_2D
	.db NOTE_16, TONE_2E
	.db NOTE_16, TONE_2D
	.db NOTE_16, TONE_2C
	.db NOTE_8, TONE_1B
	.db NOTE_16, TONE_1G
	.db NOTE_16, TONE_0G

	.db NOTE_8, TONE_1G
	.db NOTE_16, TONE_2E
	.db NOTE_16, TONE_1E
	.db NOTE_16, TONE_2E
	.db NOTE_16, TONE_2F
	.db NOTE_16, TONE_2E
	.db NOTE_16, TONE_2D
	.db NOTE_8, TONE_2C
	.db NOTE_16, TONE_1A
	.db NOTE_16, TONE_0A
	.db NOTE_16, TONE_1A
	.db NOTE_16, TONE_1G
	.db NOTE_8, TONE_1A
	.db NOTE_8, TONE_2D
	.db NOTE_8, TONE_1B
	.db NOTE_4, TONE_2C
SNDDATA_END:
#endif

#ifdef JAWS
SNDDATA:
	.db NOTE_4, TONE_1E		;ta--da
	.db NOTE_16, TONE_1F
	.db NOTE_16, TONE_NONE
	.db NOTE_8, TONE_NONE
	.db NOTE_4, TONE_NONE

	.db NOTE_4, TONE_1E		;ta--da,ta--da
	.db NOTE_16, TONE_1F
	.db NOTE_16, TONE_NONE
	.db NOTE_8, TONE_NONE
	.db NOTE_4, TONE_1E
	.db NOTE_16, TONE_1F
	.db NOTE_16, TONE_NONE
	.db NOTE_8, TONE_NONE

	.db NOTE_8, TONE_1E		;ta-da,ta-da
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_16, TONE_NONE
	.db NOTE_8, TONE_1E
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_16, TONE_NONE

	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE

	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_2G
	.db NOTE_WL, TONE_2AS

	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_2G
	.db NOTE_WL, TONE_3C

	.db NOTE_8, TONE_3E
	.db NOTE_8, TONE_2B
	.db NOTE_8, TONE_3FS
	.db NOTE_8, TONE_2B
	.db NOTE_16, TONE_3GS
	.db NOTE_16, TONE_3A
	.db NOTE_16, TONE_3B
	.db NOTE_16, TONE_3GS
	.db NOTE_8, TONE_3FS
	.db NOTE_8, TONE_2B

	.db NOTE_8, TONE_3E
	.db NOTE_8, TONE_2B
	.db NOTE_16, TONE_3FS
	.db NOTE_16, TONE_2A
	.db NOTE_16, TONE_3GS
	.db NOTE_16, TONE_2FS
	.db NOTE_8, TONE_3CS
	.db NOTE_4, TONE_2B
	.db NOTE_8, TONE_2B

	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_1F
	.db NOTE_32, TONE_NONE

	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2F
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2E
	.db NOTE_32, TONE_NONE
	.db NOTE_32, TONE_2F
	.db NOTE_32, TONE_NONE

	.db NOTE_4, TONE_NONE
SNDDATA_END:
#endif

;=============================================================
;=============================================================
;		   END
;=============================================================
