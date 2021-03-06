;=============================================================
; title			: AvrMelodyPlayer
; author		: Nobuhiro Kuroiwa
; started on	: 11/07/2012
; clock			: clk=8MHz
;=============================================================

; chip select
;#define			ATMEGA168	; Atmega168
#define			ATTINY45	; AtTiny45

; melody data select
; TINKLE	: Twinkle twinkle litttle star
; XMAS		: We wish you are merry christmas
;#define		TWINKLE	; uncommend if you want to change melody
;#define		XMAS		; commend if you above is commented out
#define		JAWS		; commend if you above is commented out

; header files
#ifdef ATMEGA168
.include "m168def.inc"
#endif
#ifdef ATTINY45
.include "tn45def.inc"
#endif

.include "musicnote.inc"	; definition of music stuff

;=============================================================
; constants
;=============================================================
; timer cont
.equ T10USEC	= 248	; Pre Scale=1/8, 100KHz
.equ PRE_SCALE	= 0x2	; 1/8
.equ PRT_SND	= portb	; port for sound pwm
.equ DDR_SND	= ddrb	; ddr for PRT_SND
.equ PIN_SND	= 0		; pin for above

#ifdef ATMEGA168
.equ TIMERMASK	= TIMSK0
#endif
#ifdef ATTINY45
.equ TIMERMASK	= TIMSK
#endif

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
.def sctop		= r9	; sound interval count
.def mcnt		= r11	; t100ms counter
.def mtop		= r12	; tcnt top value
.def scnt		= r13	; scntl compare value

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
.macro FlipOut			; FlipOut portx, port_bit
	in		acc, @0
	ldi		acc2, @1	; bit mask
	eor		acc, acc2
	out		@0, acc		; output
.endmacro

; usage: OutReg addr, reg 
.macro OutReg 
	.if @0 < 0x40 
		out @0, @1 
	.elif ((@0 >= 0x60) && (@0 < SRAM_START)) 
		sts @0,@1 
	.else 
		.error "OutReg: Invalid I/O register address" 
	.endif 
.endmacro

;=============================================================
; program
;=============================================================
.cseg					   ; Code segment

;=============================================================
; vectors
;=============================================================
#ifdef ATMEGA168
.org 	0x0000		rjmp main	 	; reset handler
.org	0x0020		rjmp intr_time0	; timer0 overflow handler
#endif
#ifdef ATTINY45
.org 	0x0000		rjmp main	 	; reset handler
.org	0x0005		rjmp intr_time0	; timer0 overflow handler
#endif

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

	; initialize port
	sbi		DDR_SND, PIN_SND

	; Timer/Counter 0 initialize
	; tccr0a=0, standard mode
	ldi		acc, 0
	sbr	 	acc,(1<<TOIE0)	; set overflow interruption bit
	OutReg	TIMERMASK, acc	; allow timer0 overflow interruption
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
	clr		sctop			; sound interval count

	; initialize melody counter
	clr		mcnt			; initialize melody counter

	; load data
	ldi		zl, low(SNDDATA<<1)		; init zl
	ldi		zh, high(SNDDATA<<1)	; init zh

	lpm		mtop, z+		; initialize tcnt compare value
	lpm		sctop, z+		; count untill scnt becomes this value

	sei						; allow all interruption

main_loop:
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
	TIME_COUNT t100ms,	intr_time0_setsnd	; count wrap around for 100ms
	TIME_COUNT t1s,		intr_time0_setsnd	; count wrap around for 1s

intr_time0_setsnd:
	rcall	set_freq			; called every 100ms

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
; supporsed to be called every 100ms
;=============================================================
set_freq:
	mov		acc, mcnt
	inc		mcnt
	cp		acc, mtop
	brlt	set_freq_ext	; if mcnt<mtop, do nothing

	; check more data left
	cpi		zl, low(SNDDATA_END<<1)
	brne	set_freq_asgn
	cpi		zh, high(SNDDATA_END<<1)
	brne	set_freq_asgn

	; if data is end, reset pointer with head position
	ldi		zl, low(SNDDATA<<1)
	ldi		zh, high(SNDDATA<<1)
	clr		mcnt

set_freq_asgn:
	lpm		mtop, z+		; initialize tcnt compare value
	lpm		sctop, z+		; count untill scnt becomes this value
	clr		scnt
	mov		mcnt, one
set_freq_ext:
	ret

;=============================================================
; sound frequency pwm
; supporsed to be called every 10us
;=============================================================
snd_pwm:
	ldi		acc, 0
	cp		sctop, acc
	breq	snd_pwm_clr
	rjmp	snd_pwm_out
snd_pwm_mute:
	cbi		PRT_SND, PIN_SND
	ret
snd_pwm_out:
	inc		scnt
	cp		scnt, sctop
	brlo	snd_pwm_ext
	FlipOut	PRT_SND, 1<<PIN_SND
snd_pwm_clr:
	clr		scnt
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
