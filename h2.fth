\ This program is written in a pseudo Forth like language, it is *not* Forth
\ and does not behave like it, it just looks like it. This should be thought
\ of as assembly code and not Forth.
\ 
\ For a grammar of the language look into the file "h2.c". 
\ 
\ Execution begins at a label called "start". 

\ Outputs: 0x6000 - 0x7FFF
\ NB. 0x6000 itself is not used.
constant oNotUsed      0x6000  
constant oLeds         0x6001  
constant oVgaCursor    0x6002  
constant oVgaCtrl      0x6003  
constant oVgaTxtAddr   0x6004  
constant oVgaTxtDin    0x6005  
constant oVgaWrite     0x6006  
constant oUartWrite    0x6007  
constant oUartStbWrite 0x6008  
constant oUartAckDout  0x6009  
constant oTimerCtrl    0x600a
constant o8SegLED_0    0x600b 
constant o8SegLED_1    0x600c
constant o8SegLED_2    0x600d 
constant o8SegLED_3    0x600e


\ Inputs: 0x6000 - 0x7FFF
constant iButtons      0x6000 
constant iSwitches     0x6001
constant iVgaTxtDout   0x6002 
constant iUartRead     0x6003 
constant iUartAckWrite 0x6004 
constant iUartStbDout  0x6005 
constant iPs2New       0x6006 
constant iPs2Char      0x6007 
constant iTimerCtrl    0x6008

\ Interrupt service Routine: Memory locations
constant isrReset      0
constant isrClock      1
constant isrUartAck    2
constant isrUartStb    3
constant isrUnused03   4
constant isrUnused04   5
constant isrUnused05   6
constant isrUnused06   7

\ Initial value of VGA
\ BIT     MEANING
\  7   -  Select high fonts
\  6   -  Enable VGA
\  5   -  Cursor enable
\  4   -  Cursor blinks
\  3   -  Cursor mode
\  2   -  Blue
\  1   -  Green 
\  0   -  Blue 
constant vgaInit       122 \ 0x007A 
constant vgaX          80
constant vgaY          40

\ Initial value of timer
\ BIT     MEANING
\ 15   -  Enable Timer
\ 14   -  Reset Timer Value immediately
\ 13   -  Interrupt Enable
\ 12-0 -  Value to compare against
constant timerInit     0x8032

\ Place a variable here
constant cursorX        1024
constant cursorY        1025
constant cursorT        1026
constant cursor         1027

\ TODO: 
\ * Function for displaying numbers on the display
\ * key? key emit and a VGA driver
\ * Bootloader 
\ * Minimal Forth interpreter

: 1+ 1 + ;
: 2+ 2 + ;
: 2/ 1 rshift ;
: 2* 1 lshift ;
: >= < invert ;
: >  swap < ;
: u> swap u< ;
: u>= u< invert ;
: <> = invert ;
\ : 0<> 0= invert ;
: 2dup over over ;
: 2drop drop drop ;
: negate invert 1+ ;
: - negate + ;
: tuck swap over ;
: +! tuck @ + swap ! ;
\ @todo AT-XY
: y1+ 1 cursorY +! cursorY @ vgaY u>= if 0 cursorY ! then ;
: x1+ 1 cursorX +! cursorX @ vgaX u>= if 0 cursorX ! y1+ then ;
: cursorT1+ 1 cursorT +! cursorT @ 3200 u>= if 0 cursorT ! then ;

: uart-write ( char -- bool : write out a character ) 
	begin iUartAckWrite @ 0 = until oUartWrite ! 1 oUartStbWrite ! iUartAckWrite @ ; 

: uart-read  ( -- char : blocks until character read in )
	begin iUartStbDout @ 0 = until iUartRead  @ 1 oUartAckDout  ! ;

: init
	
	vgaInit   oVgaCtrl   ! \ Turn on VGA monitor
	timerInit oTimerCtrl ! \ Enable timer
	5         o8SegLED_0 !
	6         o8SegLED_1 !
	7         o8SegLED_2 !
	8         o8SegLED_3 ! ;

start:
	 init

nextChar:

	begin 
		iSwitches @ oLeds !  \ Set LEDs to switches
		\ iPs2New   @        \ Wait for PS/2 a character
		iUartStbDout @       \ Wait for UART character
	until 
	cursorT   @ oVgaTxtAddr !     \ Set index into VGA memory
	uart-read dup uart-write drop oVgaTxtDin  !     \ Character to write
	         1 oVgaWrite   !     \ Perform write

	x1+
	cursorT1+

	cursorX @ cursorY @ 8 lshift or oVgaCursor !

branch nextChar

