;;; 80 characters wide please ;;;;;;;;;;;;;;;;;;;;;;;;;; 8-space tabs please ;;;


;
;;;
;;;;;  ADB Test Host
;;;
;


;;; Connections ;;;

;;;                                                    ;;;
;                     .--------.                         ;
;             Supply -|01 \/ 08|- Ground                 ;
;    ADB <-->    RA5 -|02    07|- RA0    ---> UART Tx    ;
;        --->    RA4 -|03    06|- RA1    <--- UART Rx    ;
;        --->    RA3 -|04    05|- RA2    <---            ;
;                     '--------'                         ;
;                                                        ;
;    ADB should be pulled up with a 470-ohm resistor.    ;
;                                                        ;
;;;                                                    ;;;


;;; Assembler Directives ;;;

	list		P=PIC12F1840, F=INHX32, ST=OFF, MM=OFF, R=DEC, X=ON
	#include	P12F1840.inc
	__config	_CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _CPD_OFF & _BOREN_OFF & _CLKOUTEN_OFF & _IESO_OFF & _FCMEN_OFF
			;_FOSC_INTOSC	Internal oscillator, I/O on RA5
			;_WDTE_OFF	Watchdog timer disabled
			;_PWRTE_ON	Keep in reset for 64 ms on start
			;_MCLRE_OFF	RA3/!MCLR is RA3
			;_CP_OFF	Code protection off
			;_CPD_OFF	Data memory protection off
			;_BOREN_OFF	Brownout reset off
			;_CLKOUTEN_OFF	CLKOUT disabled, I/O on RA4
			;_IESO_OFF	Internal/External switch not needed
			;_FCMEN_OFF	Fail-safe clock monitor not needed
	__config	_CONFIG2, _WRT_OFF & _PLLEN_ON & _STVREN_ON & _LVP_OFF
			;_WRT_OFF	Write protection off
			;_PLLEN_ON	4x PLL on
			;_STVREN_ON	Stack over/underflow causes reset
			;_LVP_OFF	High-voltage on Vpp to program


;;; Macros ;;;

DELAY	macro	value		;Delay 3*W cycles, set W to 0
	movlw	value
	decfsz	WREG,F
	bra	$-1
	endm

DNOP	macro
	bra	$+1
	endm


;;; Constants ;;;

;WARNING: do NOT use RA2 for ADB, the Schmitt Trigger takes too long to react
ADB_PRT	equ	PORTA	;Port where ADB bus is connected
ADB_PIN	equ	RA5	;Pin where ADB bus is connected
PULLADB	equ	0x1E	;TRIS value for port when ADB is pulled low
RLSADB	equ	0x3E	;TRIS value for port when ADB is released
TRISADB	equ	5	;Value for TRIS instruction for ADB port


;;; Variable Storage ;;;

	cblock	0x70	;Bank-common registers
	
	X15
	X14
	X13
	X12
	X11
	X10
	X9
	X8
	X7
	X6
	X5
	X4
	X3
	X2
	X1
	X0
	
	endc


;;; Vectors ;;;

	org	0x0		;Reset vector
	goto	Init

	org	0x4		;Interrupt vector


;;; Interrupt Handler ;;;

Interrupt
	bra	$


;;; Mainline ;;;

Init
	banksel	OSCCON		;32 MHz (w/PLL) high-freq internal oscillator
	movlw	B'11110000'
	movwf	OSCCON

	banksel	RCSTA		;UART async mode, 115200 kHz, but receiver not
	movlw	B'01001000'	; enabled just yet
	movwf	BAUDCON
	clrf	SPBRGH
	movlw	68
	movwf	SPBRGL
	movlw	B'00100110'
	movwf	TXSTA
	movlw	B'10000000'
	movwf	RCSTA
	clrf	TXREG

	banksel	OPTION_REG	;Weak pull-ups on
	movlw	B'01111111'
	movwf	OPTION_REG

	banksel	ANSELA		;All pins digital, not analog
	clrf	ANSELA

	banksel	LATA		;Ready to pull PORTA lines low when outputs
	clrf	LATA

	banksel	TRISA		;TX out, rest are open-collector outputs,
	movlw	B'00111110'	; currently off
	movwf	TRISA

	movlw	12		;Delay approximately 2 ms at an instruction
	movwf	X0		; clock of 2 MHz until the PLL kicks in and the
PllWait	DELAY	110		; instruction clock gears up to 8 MHz
	decfsz	X0,F
	bra	PllWait

	movlb	3		;Enable UART receiver
	bsf	RCSTA,CREN	; "
	movlb	0		; "

	call	AdbReset	;Reset the ADB

Main
	btfss	PIR1,RCIF	;Wait for a byte to come in from UART
	bra	$-1		; "
	movlb	3		;If we received a break character (or framing
	btfsc	RCSTA,FERR	; error), reset the bus
	bra	ResetAdb	; "
	movf	RCREG,W		;Get the received ADB command and save it for
	movlb	0		; later
	movwf	X2		; "
	andlw	B'00001100'	;If received ADB command was a listen command,
	xorlw	B'00001000'	; jump ahead to receive the payload
	btfsc	STATUS,Z	; "
	bra	Listen		; "
	xorlw	B'00000100'	;If received ADB command was a talk command,
	btfsc	STATUS,Z	; jump ahead to deal with a payload received off
	bra	Talk		; the bus
	movf	X2,W		;Otherwise just send the ADB command
	call	AdbCommand	; "
	movlb	3		;Send the result over the UART
	movwf	TXREG		; "
	movlb	0		; "
	bra	Main		;Return to await next command

Listen
	btfss	PIR1,RCIF	;Wait for a byte to come in from UART
	bra	$-1		; "
	movlb	3		;Get the received payload length and save it
	movf	RCREG,W		; "
	movlb	0		; "
	movwf	X3		; "
	movlw	0x20		;Move the pointer to the beginning of linear
	movwf	FSR0H		; memory
	clrf	FSR0L		; "
Listen0	btfss	PIR1,RCIF	;Wait for a byte to come in from UART
	bra	$-1		; "
	movlb	3		;Store the received byte in the buffer
	movf	RCREG,W		; "
	movlb	0		; "
	movwi	FSR0++		; "
	decfsz	X3,F		;If there are more bytes to receive, loop to
	bra	Listen0		; receive the next
	movf	FSR0L,W		;Restore the received payload length from the
	movwf	X3		; pointer's current position
	movlw	0x20		;Move the pointer to the beginning of linear
	movwf	FSR0H		; memory again
	clrf	FSR0L		; "
	movf	X2,W		;Send the listen command over ADB
	call	AdbCommand	; "
	movwf	X2		;Store the result for later
	DELAY	0		;Delay 1536 cycles (192 us) between command (and
	DELAY	0		; SRQ, if there is one) and payload
	movf	X3,W		;Send a payload containing the number of bytes
	call	AdbSend		; the host stored earlier over ADB
	movf	X2,W		;Send the result of the command over the UART
	movlb	3		; "
	movwf	TXREG		; "
	movlb	0		; "
	bra	Main		;Return to await next command

Talk
	movf	X2,W		;Send the listen command over ADB
	call	AdbCommand	; "
	movwf	X2		;Store the result for later
	movlw	0x20		;Move the pointer to the beginning of linear
	movwf	FSR0H		; memory
	clrf	FSR0L		; "
	call	AdbReceive	;Receive the payload, if there is one
	movf	FSR0L,W		;Use the pointer's current position to derive
	movwf	X3		; the length of the received payload and save it
	movf	X2,W		;Send the result of the command over UART
	movlb	3		; "
	movwf	TXREG		; "
	movf	X3,W		;Send the length of the received payload over
	movwf	TXREG		; UART
	movlb	0		; "
	btfsc	STATUS,Z	;If no payload was received, return to await
	bra	Main		; next command
	movlw	0x20		;Move the pointer to the beginning of linear
	movwf	FSR0H		; memory again
	clrf	FSR0L		; "
Talk0	btfss	PIR1,TXIF	;Wait for transmitter to be ready for another
	bra	$-1		; byte
	moviw	FSR0++		;Pick up next byte from buffer and send it over
	movlb	3		; UART
	movwf	TXREG		; "
	movlb	0		; "
	decfsz	X3,F		;Loop until all bytes are sent
	bra	Talk0		; "
	bra	Main		;Return to await next command

ResetAdb
	movf	RCREG,W		;Throw away the received byte (which will be a
	movlb	0		; zero if this really is a break character)
	call	AdbReset	;Reset the ADB
	bra	Main		;Return to await next command


;;; Subprograms ;;;

;Reset the ADB by pulling it low for 3 ms.  Trashes X0.
AdbReset
	movlw	PULLADB		;Pull ADB low for 24000 cycles (3 ms)
	tris	TRISADB		; "
	movlw	32		; "
	movwf	X0		; "
AdbRst0	DELAY	248		; "
	decfsz	X0,F		; "
	bra	AdbRst0		; "
	DELAY	31		; "
	movlw	RLSADB		;Release ADB
	tris	TRISADB		; "
	retlw	0		;Return	

;Send the command byte in WREG.  Return value in WREG is 2 if ADB is stuck, 1 if
; a device made an SRQ, 0 if neither.  Trashes X1 and X0.
AdbCommand
	xorlw	0xFF		;Complement WREG value and save to send as
	movwf	X0		; command
	bsf	STATUS,C	;Make sure carry is set for later rotation
	movlw	PULLADB		;Pull ADB low for 6400 cycles (800 us)
	tris	TRISADB		; "
	movlw	9		; "
	movwf	X1		; "
AdbCmd0	DELAY	235		; "
	decfsz	X1,F		; "
	bra	AdbCmd0		; "
	DELAY	8		; "
	nop			; "
	movlw	RLSADB		;Release ADB for 560 cycles (70 us)
	tris	TRISADB		; "
	DELAY	94		; "
	nop			; "
AdbCmd1	DELAY	91		; "
	DNOP			; "
	movlw	PULLADB		;Pull ADB low for next bit
	tris	TRISADB		; "
	DELAY	91		;Release ADB after 280 cycles (35 us) if the
	DNOP			; next bit is a one (which we've inverted to a
	rlf	X0,F		; zero)
	movf	X0,F		; "
	movlw	RLSADB		; "
	btfss	STATUS,C	; "
	tris	TRISADB		; "
	bcf	STATUS,C	;Prepare a zero to rotate in next time
	DELAY	79		;Whether a one or a zero, release ADB after 520
	movlw	RLSADB		; cycles (65 us)
	tris	TRISADB		; "
	btfss	STATUS,Z	;If the buffer is emptied and we just sent a
	bra	AdbCmd1		; zero stop bit, proceed, else loop
	DELAY	4		;Give ADB time to rise, just in case
	btfsc	ADB_PRT,ADB_PIN	;If ADB is high, no SRQ or stuck error, so
	retlw	0		; return 0
AdbCmd2	btfsc	ADB_PRT,ADB_PIN	;If ADB was released within 3600 cycles (450
	retlw	1		; us), it's an SRQ so return 1
	DELAY	3		;Delay and loop
	decfsz	X1,F		; "
	bra	AdbCmd2		; "
	retlw	2		;ADB is still low, so it's stuck, return 2

;Send WREG bytes starting from FSR0.  Trashes X0 and the buffer it reads from.
AdbSend
	movwf	X0		;Save count of bytes to send
	movlw	PULLADB		;Pull ADB low for start (one) bit
	tris	TRISADB		; "
	DELAY	92		;Release ADB after 280 cycles (35 us)
	DNOP			; "
	movlw	RLSADB		; "
	tris	TRISADB		; "
	DELAY	171		;520 cycles (65 us) until ADB is pulled low
	nop			; again
	bsf	STATUS,C	;Set the carry bit as an end-of-byte sentinel
AdbSnd0	rlf	INDF0,F		;Rotate the first bit of this byte into place
	bra	AdbSnd2		;Ensure uniform delay until ADB is pulled low
AdbSnd1	DELAY	2		; "
AdbSnd2	movlw	PULLADB		;Pull ADB low for next bit
	tris	TRISADB		; "
	DELAY	92		;Release ADB after 280 cycles (35 us) if the
	nop			; next bit is a one
	movlw	RLSADB		; "
	btfsc	STATUS,C	; "
	tris	TRISADB		; "
	bcf	STATUS,C	;Prepare a zero to rotate in next time
	DELAY	79		;Whether a one or a zero, release ADB after 520
	movlw	RLSADB		; cycles (65 us)
	tris	TRISADB		; "
	DELAY	89		;280 cycles (35 us) until ADB is pulled low
	rlf	INDF0,F		;Rotate the next bit into place
	movf	INDF0,F		;If there is a bit still to send, loop, else
	btfss	STATUS,Z	; continue
	bra	AdbSnd1		; "
	addfsr	FSR0,1		;Advance the buffer pointer
	decfsz	X0,F		;Decrement the bytes-to-send count and loop if
	bra	AdbSnd0		; there are more bytes to send, else continue
	DNOP			;Compensation delay before pulling ADB low again
	DNOP			; "
	movlw	PULLADB		;Pull ADB low for stop bit
	tris	TRISADB		; "
	DELAY	172		;Release ADB 520 cycles (65 us) later
	DNOP			; "
	movlw	RLSADB		; "
	tris	TRISADB		; "
	retlw	0		;Done

;Receive bytes into the buffer pointed to by FSR0.  Return value in WREG is 2 if
; bus is stuck, 0 otherwise (receiving no data is not an error).  Trashes X0.
AdbReceive
	movlw	B'00000001'	;Prepare to receive first byte by setting up bit
	movwf	INDF0		; buffer with sentinel bit
	movlw	0		;Clear timer for first bit
	bcf	STATUS,C	;Carry is used to signal when byte is done
	clrf	X0		;Wait 3584 cycles (448 us) for device to pull
AdbRcv0	btfss	ADB_PRT,ADB_PIN	; ADB low
	bra	AdbRcv1		; "
	DELAY	3		; "
	decfsz	X0,F		; "
	bra	AdbRcv0		; "
	retlw	0		;If it never does, return
AdbRcv1	clrf	X0		;Wait 1280 cycles (160 us) for device to release
AdbRcv2	btfsc	ADB_PRT,ADB_PIN	; ADB
	bra	AdbRcv3		; "
	decfsz	X0,F		; "
	bra	AdbRcv2		; "
	retlw	2		;If it never does, return stuck-bus error
AdbRcv3	clrf	X0		;Wait 1280 cycles (160 us) for device to pull
AdbRcv4	btfss	ADB_PRT,ADB_PIN	; ADB low again
	bra	AdbRcv5		; "
	decfsz	X0,F		; "
	bra	AdbRcv4		; "
	retlw	0		;If it never does, return
AdbRcv5	btfsc	ADB_PRT,ADB_PIN	;Wait 1280 cycles (160 us) for device to release
	bra	AdbRcv6		; ADB, timing it in multiples of 5 cycles in
	incfsz	WREG,W		; WREG
	bra	AdbRcv5		; "
	retlw	2		;If it never does, return stuck-bus error
AdbRcv6	movwf	X0		;Save the counter for later use
	movlw	0		;Reset counter to 0
AdbRcv7	btfss	ADB_PRT,ADB_PIN	;Wait 1280 cycles (160 us) for device to pull
	bra	AdbRcv8		; ADB low again, timing it in multiples of 5
	incfsz	WREG,W		; cycles in WREG
	bra	AdbRcv7		; "
	addfsr	FSR0,1		;If it never does, advance the pointer so caller
	retlw	0		; knows the response length and return success
AdbRcv8	btfsc	STATUS,C	;If the last bit completed a byte, we need to
	bra	AdbRcv9		; start a new one
	subwf	X0,W		;Compare time up and time down, rotate result
	rlf	INDF0,F		; into byte
	btfsc	STATUS,C	;If a 1 fell out, this byte is done; complement
	comf	INDF0,F		; it because result of the subwf is inverted
	movlw	1		;Reset counter to 1 (compensating for this code)
	bra	AdbRcv5		; and loop to get the next bit
AdbRcv9	subwf	X0,W		;Compare time up and time down, result in carry
	movlw	B'00000001'	;Set up next bit buffer with sentinel bit
	movwi	++FSR0		; "
	rlf	INDF0,F		;Rotate result of comparison into byte
	movlw	1		;Reset counter to 1 (compensating for this code)
	bra	AdbRcv5		;Loop to get first bit of next byte


;;; End of Program ;;;
	end
