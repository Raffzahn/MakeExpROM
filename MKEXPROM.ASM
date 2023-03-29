        PAGE      59,132
        TITLE     MKEXPROM
;---------------------------------------------------------------------;
;                                                                     ;
;        MaKe EXPandion ROM                                           ;
;                                                                     ;
;        Converts a binary (COM) File into a ROM image by             ;
;        - Checking (and writing) 55AA signature to the file start    ;
;        - Writing block count into byte 3                            ;
;        - filling up to the next 2 KiB border with FFh               ;
;        - adding a checksum into the last byte of the last block     ;
;                                                                     ;
;        The program uses                                             ;
;        - STDIN (Handle 0) for Input                                 ;
;        - STDOUT (Handle 1) for output                               ;
;        - STDERR (Handle 2) for messages                             ;
;                                                                     ;
;        Usage: MKEXPROM  <COM_FILE >ROM_IMAGE                        ;
;                                                                     ;
;        Needs to be linked with minimum RAM assigned using "/CP:1"   ;
;                                                                     ;
;--------,--------,--------------------,------------------------------;


;Segment Order
_TEXT    SEGMENT  PARA PUBLIC 'CODE'
_TEXT    ENDS
_DATA    SEGMENT  PARA PUBLIC 'DATA'
_DATA    ENDS
CONST    SEGMENT  PARA PUBLIC 'CONST'
CONST    ENDS
STACK    SEGMENT  PARA STACK  'STACK'
         ALIGN    16
         DW       64 DUP (0)           ; 64 Words stack
STACK    ENDS

DGROUP   GROUP    _TEXT,_DATA,CONST

; Macros
LCONR    MACRO    reg,msg
         LOCAL    OTXT,OSTR,OEND
;; Defines a constant message and loads optionally a register

CONST    SEGMENT
OTXT     DW       OEND-OSTR
OSTR     DB       &msg
OEND     EQU      $
CONST    ENDS

         IFNB     <&reg>
         LEA      &reg,OTXT            ; Pointer to output record
         ENDIF
         ENDM

CONOUT   MACRO    msg
;; Defines a constant message and calls output to STDERR
         
         LCONR    SI,<&msg>
         CALL     WRERR

         ENDM

; Constants
CR       EQU      13
LF       EQU      10
STDIN    EQU      0
STDOUT   EQU      1
STDERR   EQU      2
ROMBFLN  EQU      8000h                ; ROM-Buffer-Length 32 KiB


; Data
_DATA    SEGMENT
ROMOFS   DW       ?                    ; Resd Porition within ROM-Segment
ROMSEG   DW       ?                    ; ROM-Segment
RDLEN    DW       ?                    ; Length to be read
ROMLEN   DW       ?                    ; Total ROM Length
OUTTXT   DW       4                    ; Buffer to format and output a 16 bit value
OUTVAL   DB       '0000'
_DATA    ENDS


CONST    SEGMENT
TRTAB    DB       '0123456789ABCDEF'   ; Translation Table binary (nibble) to readable
CONST    ENDS


_TEXT    SEGMENT  
         ASSUME   CS:_TEXT,SS:STACK

START:
         MOV      AX,DGROUP
         MOV      DS,AX
         MOV      ES,AX
         ASSUME   DS:DGROUP,ES:DGROUP

; 32 Ki Memory as Buffer
         MOV      AH,48h               ; Get Memory
         MOV      BX,ROMBFLN SHR 4 + 1 ; Max ROM size as para (+1 for overflow read)
         INT      21h
         JNC      GOTMEM
         LCONR    SI,<CR,LF,'Memory Request Failed'>
         JMP      ERR1                 ; Print error message and terminate
GOTMEM:
         MOV      ROMSEG,AX            ; Address of Segment used for ROM data
         MOV      ROMOFS,0
         MOV      RDLEN,ROMBFLN        ; Remaining Length

; Read until EOF

RDNEXT:
         MOV      AH,3Fh
         MOV      BX,STDIN
         MOV      CX,RDLEN
         PUSH     DS
         LDS      DX,DWORD PTR ROMOFS  ; Read pointer
         INT      21H
         POP      DS
         JNC      RG2
         LCONR    SI,<CR,LF,'Read Request Failed'>
         JMP      ERR1                 ; Print error message and terminate
RG2:
         CMP      AX,0                 ; EOF ?
         JE       REOF

         ADD      ROMOFS,AX            ; New offset (end) 
         MOV      AX,ROMBFLN
         SUB      AX,ROMOFS            ; Remaining buffer length
         MOV      RDLEN,AX             ; Set as next read lenght
         JG       RDNEXT               ; Read again if remaining length greater zero

; Buffer full Check if EOF at the same time by reading on more time
         MOV      AH,3Fh
         MOV      BX,STDIN
         MOV      CX,1                 ; Redading a ingle char will tell if there's EOF
         PUSH     DS
         LDS      DX,DWORD PTR ROMOFS
         INT      21H
         POP      DS
         CMP      AX,0 
         JE       REOF                 ; Is EOF? - Fine ...
; Not EOF, so really a buffer overflow

         LCONR    SI,<CR,LF,"Buffer Overflow; Input Length >">
         MOV      AX,ROMOFS
         CALL     PRTVAL
         JMP      EXIT

; EOF Input
REOF: 
         LCONR    SI,<CR,LF,"Input Length      : ">
         MOV      AX,ROMOFS
         CALL     PRTVAL

         PUSH     ES
         ASSUME   ES:NOTHING           ; No definition for ROM content
         LES      DI,DWORD PTR ROMOFS  ; Address after last byte read

; Round up to next 2 KiB
; Todo: Optional to other value than 2 KiB - e.f. block size (512 bytes) or arbitrary
         MOV      AX,2047              ; 2 KiB minus 1
         ADD      AX,DI                ; ROMOFS
         AND      AX,0F800h            ; Round down
         MOV      ROMLEN,AX            ; Total lenght of new ROM
         SUB      AX,ROMOFS            ; Amount rounded?
         JZ       NFILL                ; Not rounded -> no fillign needed
         MOV      CX,AX                ; Amount rounded is amount to fill
         LCONR    SI,<CR,LF,"Filled Up To (FF) : ">
         MOV      AX,ROMLEN
         CALL     PRTVAL
         MOV      AL,0FFh              ; Fill-Value
         REP STOSB                     ; Fill
NFILL:

; Check and Update Signature
         XOR      DI,DI                ; Start of ROM
         MOV      AX,0AA55h            ; ROM signature
         MOV      BX,ES:[DI]           ; Previous content
         STOSW                         ; Set signature
         CMP      AX,BX                ; Was there already a valid signature ?
         JE       SIGDA                ; Yes -> cool
         LCONR    SI,<CR,LF,"Signature 55AA Inserted. Was ">
         MOV      AX,BX
         CALL     PRTVAL               ; Print prior content
SIGDA:
; Check/Insert ROM size in 512 byte blocks
         MOV      AL,BYTE PTR ROMLEN+1 ; Higbyte of length (size in 256 byte cuncks)
         SHR      AL,1                 ; Turn into count of 512 byte 
         MOV      AH,ES:[DI]           ; Save prior lenght byte
         STOSB                         ; Set new length byte
         POP      ES
         ASSUME   ES:DGROUP
         CMP      AL,AH                ; Did it differ?
         JE       LENDA                ; No ->
         LCONR    SI,<CR,LF,"ROM Length Old/New: ">
         CALL     PRTVAL               ; Print prior content
LENDA:
; Calculate Checksum
         MOV      CX,ROMLEN
         DEC      CX                   ; Number of bytes in ROM minus 1

         PUSH     DS
         MOV      AX,ROMSEG
         MOV      DS,AX

         XOR      AX,AX
         XOR      SI,SI
ADDLP:
         LODSB                         ; Sum up bytes in AH
         ADD      AH,AL
         LOOP     ADDLP
                 
         MOV      AL,BYTE PTR DS:[SI]  ; Get previous CS-byte
         XCHG     AL,AH
         NEG      AL                   ; Negate sum to get CS Byte
         MOV      BYTE PTR DS:[SI],AL
         POP      DS
         ASSUME   DS:DGROUP
         LCONR    SI,<CR,LF,"ROM CS Old/New    : ">
         CALL     PRTVAL               ; Print OLD/NEW CS

; Output ROM Buffer. Since max 32 KiB, a single write wil ldo it.
         MOV      CX,ROMLEN            ; Len
         JCXZ     WRFIN                ; Nothing to write? -> Done
         MOV      BX,STDOUT
         XOR      DX,DX
         MOV      AX,ROMSEG
         PUSH     DS
         MOV      DS,AX
         MOV      AH,40h
         INT      21h
         POP      DS
         JNC      WRFIN                ; No Write Error? -> Done
         LCONR    SI,<CR,LF,'Write of ROM data failed'>
         JMP      ERR1                 ; Print Error Message and terminate

WRFIN:
         XOR      AX,AX                ; Returncode = 0

EXIT:
; An orderly program would free all allocated resources, but we trust in DOS.
;         PUSH     ES
;         MOV      AX,ROMSEG
;         MOV      ES,AX
;         MOV      AH,49h               ; Free Memory
;         INT      21h
;         JNC      EXIT1
;         LEA      SI,FREERR
;         CALL     ERR2

         MOV      AH,4Ch               ;Terminate
         INT      21h

; Error Handler
ERR1:
         CALL     ERR2                 ; Error code in AX
         JMP      EXIT

ERR2     PROC     NEAR
; Generic DOS Error Handler
; Message in SI, Errorcode in AX
         PUSH     SI
         CALL     WRERR                ; Print Message in DX
         LCONR    SI,<CR,LF,"DOS Error Code ">
         CALL     PRTVAL               ; Print plus  content of AX
         POP      SI
         RET
ERR2     ENDP

;-------------;
; Subroutines ;
;-------------;

WRERR    PROC    NEAR
; Write (Error) Text to STDERR
;
; In: Text in (DS:)SI as lenght terminated sting
;

         PUSH    AX
         PUSH    BX
         PUSH    CX
         PUSH    DX
         PUSH    SI

         LODSW                         ; Load length
         MOV     CX,AX
         MOV     DX,SI                 ; Point DX to text
         MOV     AH,40h                ; Write File
         MOV     BX,STDERR             ; STDERR Handle
         INT     21h                   ; Output

         POP     SI
         POP     DX
         POP     CX
         POP     BX
         POP     AX
         RET
WRERR    ENDP

PRTVAL   PROC    NEAR
; Subroutine to print one 16 bit value in AX and Label in DS:SI
;
; In: Label in SI
;     Value in AX
;
; Out: Text on screen (hopefuly :))
;
         ASSUME   DS:NOTHING,ES:NOTHING
         PUSH     AX
         PUSH     BX
         PUSH     CX
         PUSH     SI
         PUSH     DI

         CALL     WRERR                ; Print Message in SI

         PUSH     DS
         PUSH     ES
         PUSH     AX
         MOV      AX,DGROUP
         MOV      DS,AX
         MOV      ES,AX
         ASSUME   DS:DGROUP,ES:DGROUP
         POP      AX

         LEA      BX,TRTAB             ; Table for XLAT
         LEA      DI,OUTVAL
         PUSH     AX                   ; Preserve low nibble
         MOV      CL,4                 ; A nibble got 4 bits :)
         ROL      AX,CL                ; Top nibble to AL
         AND      AL,0Fh
         XLAT
         STOSB
         ROL      AX,CL                ; 2nd nibble to AL
         AND      AL,0Fh
         XLAT
         STOSB
         ROL      AX,CL                ; 3rd nibble to AL
         AND      AL,0Fh
         XLAT
         STOSB
         POP      AX                   ; Low nibble (restored)
         AND      AL,0Fh
         XLAT
         STOSB
         LEA      SI,OUTTXT
         CALL     WRERR                ; Print value

         ASSUME   DS:NOTHING,ES:NOTHING
         POP      ES
         POP      DS

         POP      DI
         POP      SI
         POP      CX
         POP      BX
         POP      AX

         RET
         
PRTVAL   ENDP

_TEXT    ENDS

        END   START
