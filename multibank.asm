; The original game used a continuous script from $14000-$1ffff, even
; though each chapter only needed probably one whole bank at most.
; Since the script was continuous, a chapter would often cross bank
; boundaries anyway, so the game would load two banks for the script at
; once.
;
; Well, we're doing it differently. We're reserving a pair of banks per
; chapter and using the extra space in the second bank (since it doesn't
; have to be shared with text from another chapter) to store code. This
; way we don't have to do any bankswitching acrobatics, because we're
; putting a copy of the code into each of these bank pairs. Thus, a copy
; of the code will always be loaded.

MULTIBANK_REGION_SIZE:      equ     $1000
MULTIBANK_OFFSET:           equ     $4000 - MULTIBANK_REGION_SIZE


; Control codes
CHAR_BOLD_PERIOD:   equ     $0a
CHAR_MNL:           equ     $10
CHAR_END:           equ     $7f


; BIOS stuff
RDVRM:          equ     $004a
WRTVRM:         equ     $004d
FILVRM:         equ     $0056

; Variables from the original game
text_color:     equ     $f301

; This variable was used for this purpose in the original code
char_to_print:  equ     $f2e1

; Other variables
; @TODO@ -- verify this region is safe, or considering using MSX2-specific system RAM (FAF5-FB34)
org $e000

pixel_offset:   rb 1            ; How many pixels to the right do we draw the next char?
tile_increment: rw 1            ; How much we need to increment VRAM addr to
                                ; get to the next tile on the right
vram_addr:      rw 1
char_width:     rb 1
str_width:      rb 1            ; for right-aligning in menus


org $8000 + MULTIBANK_OFFSET, $bfff


HandlePasswordChar:
        cp      'A'
        jp      c, $637c                ; below A-Z range; reject
        cp      'Z' + 1
        jr      c, .accept
        cp      'a'
        jp      c, $637c                ; between A-Z and a-z range; reject
        cp      'z' + 1
        jp      nc, $637c               ; above a-z range; reject
        add     a, 'A' - 'a'            ; letter is lowercase; capitalize it
        ld      (hl), a                 ; put the capitalized char in the buffer
                                        ; (otherwise it will only LOOK capitalized)
        add     a, $50                  ; display it with monospace font

.accept:
        push    af

        xor     a
        ld      (pixel_offset), a

        ; Clear the character that was there in VRAM.
        ; If we don't, our VWF code will cause it to be overstruck.
        ; Note that A is still zero here
        push    hl
        ld      hl, ($f200)             ; Get VRAM pointer
        ld      bc, 8
        call    FILVRM
        pop     hl

        pop     af
        jp      $6381


ClearPasswordDialogueAndPrintString:
        push    hl
        push    de
        push    af
        ld      hl, $0888
        ld      de, 64                  ; VRAM pointer increment
        ld      a, 17                   ; 17 columns to erase
        ld      b, a
        xor     a
        ld      (pixel_offset), a
.loop:
        push    bc
        ld      bc, 20                  ; 20 rows of pixels to erase
        call    FILVRM                  ; A is still 0
        add     hl, de                  ; bump VRAM pointer
        pop     bc
        djnz    .loop
        pop     af
        pop     de
        pop     hl
        call    $4003                   ; print string
        ret


ErasePushSpaceKey:
        ld      hl, $10b8
        ld      b, 28
        xor     a
.loop:
        push    bc
        ld      bc, 8
        call    FILVRM
        pop     bc
        ld      de, 64
        add     hl, de
        djnz    .loop
        jp      $4a8e


; This adds to the code that was at $475d
HandleFirstLineOfDialogue:
        xor     a
        ld      (pixel_offset), a
        ld      hl, $1008               ; The line the patch at $475d was patching over
        ret

; This adds to the code that was at $4771
HandleNewline:
        ld      a, ($f2fe)
        add     a, 12
        ld      ($f2fe), a

        ; Now here's the bit we're adding
        xor     a
        ld      (pixel_offset), a

        ; Back to your regularly scheduled program
        jp      $4763


DrawMenuLetters:
        ld      a, $1b                      ; Set text color to black
        ld      (text_color), a
        ld      a, (ix)                     ; [IX] points to the char in the script
        inc     ix
        add     a, $80                      ; Adjust it to MSX charset
        cp      CHAR_MNL                    ; Is this the <mnl> code?
        jp      z, HandleMenuNewline        ; Branch if so
        call    PrintChar8                  ; Print char
        ld      a, (ix)                     ; Get next char
        cp      CHAR_END                    ; Is it <end>?
        jr      nz, DrawMenuLetters         ; Loop if not
        ret


AfterDisplayingNameTag:
        push    af

        xor     a
        ld      (pixel_offset), a

        ; Now we need to update the VRAM address
        ; The correct address is one of:
        ;   $1188   -- first line of dialogue in main game
        ;   $1194   -- second line
        ;   $11a0   -- third line
        ;   $11ac   -- fourth line
        ;   $0988   -- name tag on password dialogue

        ; Bump VRAM pointer to point to correct place
.loop:
        ld      a, h
        cp      $09
        jr      z, .check_lsb
        cp      $11
        jr      z, .check_lsb
.loop_tail:
        ld      bc, 64
        add     hl, bc
        jr      .loop

.check_lsb:
        ; Now we know the VRAM addr is either 09xx or 11xx
        ld      a, l
        cp      $88
        jr      c, .loop_tail
        cp      $ac
        jr      nc, .loop_tail

        pop     af
        jp      $47a1


; This is a reworked version of the display code from the original game,
; found at $027ba in ROM, $47ba in CPU space. The original routine did
; NOT increment the VRAM pointer on exit; our version does (and so all
; calls to it have to be adjusted accordingly), because now this only
; has to be done sometimes.
;
; Inputs:
;   A = char to print
;   HL = address in VRAM to write char to
;   pixel_offset
;
; Outputs:
;   HL = address in VRAM of next char to write to
;   pixel_offset
PrintChar8:
        push    bc
        ld      bc, 8
        ld      (tile_increment), bc
        pop     bc
        jr      PrintChar

PrintChar64:
        push    bc
        ld      bc, 64
        ld      (tile_increment), bc
        pop     bc
        ; Fall through to PrintChar


PrintChar:
        ld      (char_to_print), a
        ld      (vram_addr), hl
        push    bc
        push    de

        ld      a, (char_to_print)
        call    CalcCharWidth

        call    GetPtrToCharData
        call    Write1stTile

        call    BumpPixelOffset
        jr      c, .one_tile            ; Branch if we don't need to print to another tile

        ; Now we have to draw the second tile
        ; But first write the color for the first tile
        ld      hl, (vram_addr)
        call    WriteColor

        ; Now draw the second one
        call    BumpVramAddr
        call    GetPtrToCharData
        call    Write2ndTile

.one_tile:
        ld      hl, (vram_addr)
        call    WriteColor

        ld      a, (pixel_offset)       ; Is pixel offset 8 (we hit the tile boundary exactly)?
        cp      8
        jr      nz, .done               ; No; we're done here
        xor     a                       ; Yes; set pixel offset to 0 and set VRAM addr to the next tile
        ld      (pixel_offset), a 
        call    BumpVramAddr

.done:
        ld      a, (char_to_print)      ; Put char we've displayed back in A
        cp      '!'                     ; These insert a delay after certain punctuation symbols
        call    z, $4708
        cp      '?'
        call    z, $4708
        cp      ','
        call    z, $4708
        call    $4c56                   ; I assume this is a delay, music, misc. handling
        ld      hl, (vram_addr)
        pop     de
        pop     bc
        ret


; Points DE to the first row of pixels to the char in char_to_print
; Preserves HL
GetPtrToCharData:
        ld      a, (char_to_print)
        ex      de, hl
        ld      bc, font_data
        ld      h, 0                    ; HL = &font_data + A*8
        ld      l, a
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, bc
        ex      de, hl
        ret


; Inputs:
;   A = char whose width we're calculating
;
; Outputs:
;   char_width = A = width of char in pixels
CalcCharWidth:
        push    hl
        ld      b, 0
        ld      c, a
        ld      hl, char_widths
        add     hl, bc
        ld      a, (hl)
        ld      (char_width),a
        pop     hl
        ret


; Carry flag will be clear on exit if caller must draw another tile
BumpPixelOffset:
        ; Bump up the pixel offset
        ld      hl, pixel_offset
        ld      a, (char_width)
        add     a, (hl)
        ld      (hl), a
        cp      9                       ; Did we go past the tile boundary (not just at the edge)?
        ret     c                       ; Return if not

        ; Yep, we did
        and     7                       ; carry flag will still be clear after this
        ld      (hl), a
        ret


BumpVramAddr:
        ld      hl, (vram_addr)         ; Bump VRAM address up to next tile
        ld      bc, (tile_increment)
        add     hl, bc
        ld      (vram_addr), hl
        ret


Write1stTile:
        ld      b, 8
.loop:
        push    bc
        ld      a, (de)                 ; Put line of char to print in C
        ld      c, a
        call    RDVRM                   ; ...and the char that's already in this tile into H
        push    hl
        ld      h, a
        ld      a, (pixel_offset)
        or      a                       ; If pixel offset is zero...
        jr      z, .no_shift            ; ...then don't shift
        ld      b, a
        ld      a, c                    ; Now put line of char to print back in A
.shift:
        srl     a                       ; ...else shift
        djnz    .shift
        ld      c, a                    ; undoes the effect of the next line
                                        ; (A is already line to draw)
.no_shift:
        ld      a, c                    ; put line to draw back in A
        or      h                       ; combine with the tile that was in VRAM before
        pop     hl
        call    WRTVRM
        inc     hl
        inc     de
        pop     bc                      ; Put the .write_chr counter back
        djnz    .loop
        ret


Write2ndTile:
        ld      b, 8
.loop:
        push    bc
        ld      a, (pixel_offset)       ; This loop does A = [DE] << (char_width - pixel_offset)
        ld      b, a
        ld      a, (char_width)
        sub     a, b
        ld      b, a
        ld      a, (de)
.shift:
        sla     a
        djnz    .shift
        call    WRTVRM
        inc     hl
        inc     de
        pop     bc
        djnz    .loop
        ret


; HL holds the VRAM addr of the character data (NOT color data!)
WriteColor:
        ld      de, $2000               ; Now we write to this tile's color table
        add     hl, de
        ld      b, $08
.write_color:
        ld      a, (text_color)
        call    WRTVRM
        inc     hl
        djnz    .write_color
        ret


; Inputs:
;   IX = pointer to text on second line
;   HL = VRAM address
;
; Outputs:
;   HL = new VRAM address
;   pixel_offset
HandleMenuNewline:
        ; Bump HL to point to first char of next line in VRAM
        ; @TODO@ - better way to express this?
        ld      a, l
        and     $3f
        jr      z, .done_bumping
        inc     hl
        jr      HandleMenuNewline       ; loop
.done_bumping:
        call    CalcStrWidth
        ld      a, $40                  ; A = $40 - A
        sub     c                       ; (this is number of pixels to shift text right)
        ld      c, a
        and     7                       ; mod by 8 to get new pixel offset
        ld      (pixel_offset), a
        ld      a, c                    ; put str width back in A
        and     not 7                   ; A -= (A % 8)  -- this is the VRAM offset to add
        ld      c, a
        add     hl, bc
        call    DrawMenuLetters
        ret


; Inputs:
;   IX = pointer to string
;
; Outputs:
;   BC = width of string in pixels (B will be 0)
CalcStrWidth:
        push    ix
        ld      bc, 0
.loop:
        ld      a, (ix)
        cp      CHAR_END
        jr      z, .done
        add     $80                     ; convert to MSX charset
        push    bc
        call    CalcCharWidth
        pop     bc
        add     c
        ld      c, a
        inc     ix
        jr      .loop
.done:
        pop     ix
        ret


font_data:
        incbin  "vwf.bin"


char_widths:
        ;       [the digits and period here are bold]
        ;       0  1  2  3  4  5  6  7  8  9  .  *
        db      7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 3, 4, 0, 0, 0, 0

        ;       [first char here is <mnl> ("menu newline") control code]
        ;       [displays as space when not in a menu]
        db      3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

        ;       [first char here is space]
        ;       [asterisk in this row is not the one we use]
        ;          !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
        db      3, 2, 5, 6, 6, 6, 6, 3, 3, 3, 6, 6, 3, 5, 2, 4

        ;       0  1  2  3  4  5  6  7  8  9  :  ;  <  =  >  ?
        db      5, 3, 6, 6, 6, 6, 6, 6, 6, 6, 2, 3, 6, 6, 6, 6

        ;       @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
        db      6, 6, 6, 6, 6, 5, 5, 6, 6, 2, 5, 5, 5, 6, 6, 6

        ;       P  Q  R  S  T  U  V  W  X  Y  Z  [  ¥  ]  ^  _
        db      6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6

        ;       `  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o
        db      6, 6, 5, 5, 5, 5, 4, 5, 5, 2, 3, 5, 2, 6, 5, 5

        ;       p  q  r  s  t  u  v  w  x  y  z  {  |  }  ~
        db      5, 5, 4, 5, 4, 5, 5, 6, 5, 5, 5, 6, 6, 6, 6, 0

        ;       [first char here is the odd "N"-like character]
        ;       [after skipping a control code, next 5 are "PRESS SPACE"]
        db      7, 0, 8, 8, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0

        ;       [monospace font for passwords]
        ;          A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
        db      0, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8

        ;       P  Q  R  S  T  U  V  W  X  Y  Z
        db      8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0, 0, 0, 0, 0

        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
