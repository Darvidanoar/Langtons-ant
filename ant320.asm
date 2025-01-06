.segment "STARTUP"
;******************************************************************
; Langton's ant (https://en.wikipedia.org/wiki/Langton%27s_ant)
;
; Langton's ant is a two-dimensional Turing machine with a very simple 
; set of rules but complex emergent behavior.
;
; The ant moves in what appears to be fairly irregular pattern until
; aroung 10,000 moves when it starts building a 'highway' pattern
; consisting of 104 repeating moves.
;******************************************************************

.segment "ZEROPAGE"
;******************************************************************
; The KERNAL and BASIC reserve all the addresses from $0080-$00FF. 
; Locations $00 and $01 determine which banks of RAM and ROM are  
; visible in high memory, and locations $02 through $21 are the
; pseudoregisters used by some of the new KERNAL calls
; (r0 = $02+$03, r1 = $04+$05, etc)
; So we have $22 through $7f to do with as we please, which is 
; where .segment "ZEROPAGE" variables are stored.
;******************************************************************

;.org $0022

; Zero Page
XPos:             .res 2   ; current X Co-ordinate of ant
YPos:             .res 2   ; current Y Co-ordinate of ant
PixelAddr:        .res 3   ; Pixel address of ant (used when converting x/y coords to a memory address)

; Global Variables
paint_color:      .res 1
CurrDir:          .res 1
CurrCellColour:   .res 1

.segment "INIT"
.segment "ONCE"
.segment "CODE"

;.org $080D

   jmp start

.include "..\..\INC\x16.inc"

; VERA
VSYNC_BIT         = $01
DISPLAY_SCALE     = 64 ; 2X zoom

; PETSCII
SPACE             = $20
CHAR_O            = $4f
CLR               = $93
HOME              = $13
CHAR_Q            = $51
CHAR_G            = $47
CHAR_ENTER        = $0D

; Colors
BLACK             = 0
WHITE             = 1
RED               = 2


start:
   stz VERA_dc_video ; disable display

   ; scale display to 2x zoom (320x240)
   lda #DISPLAY_SCALE
   sta VERA_dc_hscale
   sta VERA_dc_vscale

   ; configure layer 0
   lda #$07 ; 8bpp bitmap  
   sta VERA_L0_config

   ; enable layer 0, output mode VGA
   lda #$11
   sta VERA_dc_video

   ; initialise
   jsr clear_screen

   ;Set Start Pos at middle of screen (160,120)
   lda #$a0
   sta XPos
   stz XPos+1
   lda #$78
   sta YPos
   stz YPos+1

   ; set the starting direction the ant in facing (north)
   lda #$00
   sta CurrDir

   ; get the colour of the cell under the ant
   jsr getCell
   sta CurrCellColour
   
   ; set the paint_colour to red and paint the ant
   lda #RED
   sta paint_color
   jsr paint_cell

main_loop:

   ; based on he rules, calculate the next direction and paint the current cell its new colour
   jsr getNextDir
   jsr paint_cell

   ; move the ant to its new cell
   jsr moveAnt

   ; set the paint_colour to red and paint the ant
   lda #RED
   sta paint_color
   jsr paint_cell

   ; a delay to slow the process down.  Comment this out if you want to run a full speed.
   ;jsr delay

   ; check if the user has pushed 'q' tpo quit
   jsr GETIN
   cmp #CHAR_Q
   beq @exit ; Q was pressed

   jmp main_loop

@exit:
   lda #SPACE
   lda #CLR
   jsr CHROUT
   rts
   

moveAnt:
   ; based on the Current Direction, move the ant to the next cell co-ordinates
   lda CurrDir
   bne @checkSouth
   ; North
   lda YPos
   sec
   sbc #$01
   sta YPos
   lda YPos+1
   sbc #$00
   sta YPos+1
   jsr checkXYWrap
   jsr getCell
   sta CurrCellColour
   bra @next
@checkSouth:
   lda CurrDir
   cmp #$02
   bne @checkEast
   ; South
   lda YPos
   clc
   adc #$01
   sta YPos
   lda YPos+1
   adc #$00
   sta YPos+1
   jsr checkXYWrap
   jsr getCell
   sta CurrCellColour
   bra @next
@checkEast:
   lda CurrDir
   cmp #$01
   bne @checkWest
   ; East
   lda XPos
   clc
   adc #$01
   sta XPos
   lda XPos+1
   adc #$00
   sta XPos+1
   jsr checkXYWrap
   jsr getCell
   sta CurrCellColour
   bra @next
@checkWest:
   ; West
   lda XPos
   sec
   sbc #$01
   sta XPos
   lda XPos+1
   sbc #$00
   sta XPos+1
   jsr checkXYWrap
   jsr getCell
   sta CurrCellColour
@next:
   rts


getNextDir:
   ; based on he rules, calculate the next direction
   ; NextDir Values:
   ; 0=North
   ; 1=East
   ; 2=South
   ; 3=West

   lda CurrCellColour
   bne @TurnCW
@TurnCCW:
   lda CurrDir
   dec
   and #%00000011
   sta CurrDir
   lda #WHITE
   sta paint_color
   bra @endNextDir
@TurnCW:
   lda CurrDir
   inc
   and #%00000011
   sta CurrDir
   lda #BLACK
   sta paint_color
@endNextDir:
   rts


paint_cell: 
; Input: XPos/YPos = text map coordinates
; Input: paint_color
   jsr getPixelAddr
   stz VERA_ctrl
   lda PixelAddr+2
   sta VERA_addr_bank
   lda PixelAddr+1
   sta VERA_addr_high ; Y
   lda PixelAddr
   sta VERA_addr_low ; 2*X + 1
   lda paint_color
   sta VERA_data0
   rts

clear_screen:
   lda #$10 ; Stride 1, Bank 0
   sta VERA_addr_bank
   stz VERA_addr_low
   stz VERA_addr_high
   ldy #$00
clear_screen_loopY0:   
   ldx #$00
clear_screen_loopX0:
   stz VERA_data0
   dex
   bne clear_screen_loopX0
   dey
   bne clear_screen_loopY0

   ldy #$2C
clear_screen_loopY1:   
   ldx #$00
clear_screen_loopX1:
   stz VERA_data0
   dex
   bne clear_screen_loopX1
   dey
   bne clear_screen_loopY1
   rts


getCell: 
   ; Input: XPos/YPos = text map coordinates
   ; Output: A = value of the tile
   jsr getPixelAddr
   stz VERA_ctrl
   lda PixelAddr+2 ; stride = 0, bank 
   sta VERA_addr_bank
   lda PixelAddr+1
   sta VERA_addr_high 
   lda PixelAddr
   sta VERA_addr_low 
   lda VERA_data0   
   rts

getPixelAddr:
   ; Input: XPos/YPos = text map coordinates
   ; Output: PixelAddr
   stz PixelAddr
   stz PixelAddr+1
   stz PixelAddr+2
   ldy YPos
   beq @addX
@Yloop:
   lda PixelAddr
   clc
   adc #$40
   sta PixelAddr
   lda PixelAddr+1
   adc #$01
   sta PixelAddr+1
   lda PixelAddr+2
   adc #$00
   sta PixelAddr+2
   dey
   bne @Yloop
@addX:
   clc
   lda PixelAddr
   adc XPos
   sta PixelAddr
   lda PixelAddr+1
   adc XPos+1
   sta PixelAddr+1
   lda PixelAddr+2
   adc #$00
   sta PixelAddr+2
   rts 

checkXYWrap:
   ; Input XPos/YPos = text map coordinates
   ; this subroutine does the screen wrap around
   lda XPos+1
   cmp #$FF ; has x gone past the left border?
   bne @checkXRight
   lda XPos
   cmp #$FF ; has x gone past the left border?
   bne @checkXRight
   lda #$01 ; set XPos to 319
   sta XPos+1
   lda #$3f
   sta XPos
@checkXRight:
   lda XPos+1
   cmp #$01 ; has x gone past the right border?
   bne @checkYTop
   lda XPos
   cmp #$40
   bne @checkYTop 
   lda #$00
   sta XPos+1
   sta XPos
@checkYTop:
   lda YPos+1
   cmp #$ff ; has y gone past the top border?
   bne @checkYBottom
   lda YPos
   cmp #$ff
   bne @checkYBottom
   stz YPos+1
   lda #$ef
   sta YPos
@checkYBottom:
   lda YPos
   cmp  #$f0 ; has y gone past the bottom border?
   bne @endcheckXYWrap
   stz YPos
@endcheckXYWrap:
   rts



delay:                  ; Standard issue delay loop
    lda #$00
delayloop_outer:
    pha
    lda #$00
delayloop_inner:
    inc
    bne delayloop_inner
    pla
    inc   
    bne delayloop_outer
    rts