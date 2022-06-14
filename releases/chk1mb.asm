; C128 16MB RAM check test routines
*	=	$1300			;call routine with bank to test in A (0-255)
bnkstr = $fc			;Temp storage to place the operating bank
						;Routine is much smaller for the version 2 MMU
wrbank	sta bnkstr		;Save A (our mem bank #)
		lda $d500		;Remember current config
		sta $d504		
		ora #%11000000  ;Switch to MMU bank 3
		sta $d500		
		lda bnkstr		;Get our operating memory bank
		sta $d50d		;Swap it into bank 3
		sta $8000		;Store the current bank number in that bank.
		sta $8001
		sta $8002
		sta $8003
		lda $ff04		;back to our regularly scheduled operation
		rts			
		brk
chkbnk	sta bnkstr		;What bank are we checking?
		lda $d500		;Remember current config
		sta $d504		
		ora #%11000000  ;Switch to MMU bank 3
		sta $d500		
		lda bnkstr		;Get our operating memory bank
		sta $d50d		;Swap it into bank 3
		ldx #$00
chklp1	lda $8000,x		;check the 4 bytes for the correct bank #
		cmp $fb
		bne chkerr
		inx
		cpy #$03
		beq chkend
		jmp chklp1
chkend	lda #$00		;$00 = no error
		jsr resbnk
		rts
chkerr	ldy $fb			;if error, return expected byte in y
		lda $8000,x		;found byte in A
		jsr resbnk
		rts				;byte # in x
		brk
mmuchk  pha				;saves A, X and Y altered.
		lda $d50b		;get mmu size and version
		and #$0f		;put version into x
		tax
		lda $d50b		;put size into y
		and #$f0		;size = 64*(2^y) kb
		lsr
		lsr
		lsr
		lsr
		tay
		txa				;is this a version 2 MMU?
		cmp #02			;set flags to indicate
		pla
		rts
