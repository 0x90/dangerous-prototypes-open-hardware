;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  BootLoader.                                                             ;;
;;  Copyright (C) 2007 Diolan ( http://www.diolan.com )                     ;;
;;                                                                          ;;
;;  This program is free software: you can redistribute it and/or modify    ;;
;;  it under the terms of the GNU General Public License as published by    ;;
;;  the Free Software Foundation, either version 3 of the License, or       ;;
;;  (at your option) any later version.                                     ;;
;;                                                                          ;;
;;  This program is distributed in the hope that it will be useful,         ;;
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of          ;;
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           ;;
;;  GNU General Public License for more details.                            ;;
;;                                                                          ;;
;;  You should have received a copy of the GNU General Public License       ;;
;;  along with this program.  If not, see <http://www.gnu.org/licenses/>    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Flash Reading / Writing
;-----------------------------------------------------------------------------
	#include "P18F24J50.INC"
	#include "boot.inc"
	#include "boot_if.inc"
	#include "usb_defs.inc"
;-----------------------------------------------------------------------------
; Constants
;-----------------------------------------------------------------------------
; boot_cmd & boot_rep
CMD_OFFS	equ	0
ID_OFFS		equ	1
ADDR_LO_OFFS	equ	2
ADDR_HI_OFFS	equ	3
FLUSH_OFFS	equ 4
SIZE_OFFS	equ	5
CODE_OFFS	equ	6
VER_MAJOR_OFFS	equ	2
VER_MINOR_OFFS	equ	3
VER_SMINOR_OFFS	equ	4
EEDATA_OFFS	equ	6

;-----------------------------------------------------------------------------
; Global Variables
;-----------------------------------------------------------------------------
	EXTERN	boot_cmd
	EXTERN	boot_rep
	EXTERN	hid_report_in

;-----------------------------------------------------------------------------
; Extern Functions
;-----------------------------------------------------------------------------
;	EXTERN	store_fsr1_fsr2
;	EXTERN	restore_fsr1_fsr2
;	EXTERN	xtea_encode
;	EXTERN	xtea_decode
	EXTERN jumpentry

;-----------------------------------------------------------------------------
; Local Variables
;-----------------------------------------------------------------------------
BOOT_DATA	UDATA
cntr		res	1
hold_r		res	1	; Current Holding Register for tblwt
	global	eep_mark_set
eep_mark_set	res	1       

;-----------------------------------------------------------------------------
; START
;-----------------------------------------------------------------------------
BOOT_ASM_CODE	CODE
;	GLOBAL	read_code    
;	GLOBAL	write_code    
;	GLOBAL	erase_code    
;	GLOBAL	set_eep_mark
;	GLOBAL	clr_eep_mark
	GLOBAL	bootloader_soft_reset
	GLOBAL	hid_process_cmd
	GLOBAL	copy_boot_rep
;-----------------------------------------------------------------------------
;       erase_code 
;-----------------------------------------------------------------------------
; DESCR :
; INPUT : boot_cmd
; OUTPUT: 
; NOTES : Assume TBLPTRU=0
;-----------------------------------------------------------------------------
erase_code
	;!!!18f24j50 change!!! setup the write
	movlw 	0x08
	movf	boot_cmd + ADDR_HI_OFFS, W
	clrf	boot_cmd + ADDR_LO_OFFS

	rcall	load_address	; TBLPTR = addr
	;!!!18f24j50 change!!! setup the size
	movlw 0x0D ;16 pages -2 bootloader, -1 CFG protection
	movwf boot_cmd + SIZE_OFFS	

erase_code_loop
	; while( size_x64 )

	;!!!18f24j50 change!!!	
	; Erase 1024 (not 64) bytes block
	bsf	EECON1, FREE	; Enable row Erase (not PRORGRAMMING)
	rcall	flash_write	; Erase block. EECON1.FREE will be cleared by HW
	
	; TBLPTR += 1024
	;!!!18f24j50 change!!!
	;movlw	0x00
	;addwf	TBLPTRL
	movlw	0x04	;1024/0x400 bytes erased at a time
	;addwfc	TBLPTRH
	addwf	TBLPTRH
	
	decfsz	boot_cmd + SIZE_OFFS
	bra	erase_code_loop
	return

;-----------------------------------------------------------------------------
;       read_code 
;-----------------------------------------------------------------------------
; DESCR :
; INPUT : boot_cmd
; OUTPUT: boot_rep
; NOTES : Assume TBLPTRU=0
;-----------------------------------------------------------------------------
read_code
	rcall	load_address_size8		; TBLPTR=addr cntr=size8 & 0x3C
	lfsr	FSR0, boot_rep + CODE_OFFS	; FSR0=&boot_rep.data

        ; while( cntr-- )
read_code_loop
	tblrd*+
	movff	TABLAT, POSTINC0
	decfsz	cntr
	bra	read_code_loop
	

;-----------------------------------------------------------------------------
;       write_code 
;-----------------------------------------------------------------------------
; DESCR :
; INPUT : boot_cmd
; OUTPUT: 
; NOTES : Assume TBLPTRU=0
;-----------------------------------------------------------------------------
write_code
	; TBLPTR = addr
	rcall	load_address_size8		; TBLPTR=addr cntr=size8 & 0x3C
	lfsr	FSR0,boot_cmd + CODE_OFFS	; FSR0=&boot_cmd.data
	tblrd*-					; TBLPTR--
	
	; while( cntr-- )
write_code_loop
	movff	POSTINC0, TABLAT
	tblwt+*			; *(++Holding_Register) = *data++
;	incf	hold_r		; hold_r++
;	btfsc	hold_r, 5	; if( hold_r == 0x20 )  End of Holding Area
;	rcall	flash_write	;     write_flash       Dump Holding Area to Flash
	decfsz	cntr
	bra	write_code_loop
	
;	tstfsz	hold_r		; if( hold_r != 0 )     Holding Area not dumped
;	tstfsz	boot_cmd + FLUSH_OFFS		; if packet says flush, save to eeprom
	btfsc boot_cmd + FLUSH_OFFS, 0	;if bit 0 is set, write the data
	rcall	flash_write	;       write_flash     Dump Holding Area to Flash

        return

;-----------------------------------------------------------------------------
;       read_id 
;-----------------------------------------------------------------------------
; DESCR :
; INPUT : 
; OUTPUT: boot_rep
; NOTES : Will leave TBLPTRU=0
;-----------------------------------------------------------------------------
read_id
	rcall	rdwr_id_init
	lfsr	FSR0, boot_rep + CODE_OFFS	; FSR0=&boot_rep.data	
	; while( cntr-- )
read_id_loop
	tblrd*+
	movff	TABLAT, POSTINC0
	decfsz	cntr
	bra	read_id_loop
	
rdwr_id_return
	clrf	TBLPTRU                  
	return

	
;-----------------------------------------------------------------------------
;       write_id 
;-----------------------------------------------------------------------------
; DESCR :
; INPUT : boot_cmd
; OUTPUT: 
; NOTES : Will leave TBLPTRU=0
;-----------------------------------------------------------------------------
write_id
	rcall   rdwr_id_init
	lfsr    FSR0, boot_cmd + CODE_OFFS	; FSR0=&boot_cmd.data
	
	; Erase
	bsf	EECON1, FREE			; Enable row Erase (not PRORGRAMMING)
	rcall	flash_write			; Erase block. EECON1.FREE will be cleared by HW
	
	; while( cntr-- )
write_id_loop
	movff	POSTINC0, TABLAT
	tblwt*+
	decfsz	cntr
	bra	write_id_loop
	
	rcall	flash_write
	bra	rdwr_id_return
	
rdwr_id_init
	movlw	0x20
	movwf	TBLPTRU
	clrf	TBLPTRH                  
	clrf	TBLPTRL		; TBLPTR=0x200000
	movlw	0x08
	movwf	cntr		; cntr=8
	movwf	boot_rep + SIZE_OFFS
	return

;-----------------------------------------------------------------------------
; DESCR : Write data to EEPROM
; INPUT : boot_cmd
; OUTPUT:  boot_rep
; NOTES :
;-----------------------------------------------------------------------------
write_eeprom
	rcall	eeprom_init
;	lfsr	FSR0, boot_cmd + EEDATA_OFFS	; FSR0=&boot_cmd.write_eeprom.data
        ; while( cntr-- )
write_eeprom_loop
;	movff	POSTINC0, EEDATA
;	rcall	eeprom_write
;	btfsc	EECON1, WR			; Is WRITE completed?
;	bra	$ - 2				; Wait until WRITE complete
;	incf	EEADR, F			; Next address
;	decfsz	cntr
;	bra	write_eeprom_loop
	return
;-----------------------------------------------------------------------------
; DESCR : Read data from EEPROM
; INPUT : boot_cmd
; OUTPUT: boot_rep
; NOTES :
;-----------------------------------------------------------------------------
read_eeprom
	rcall	eeprom_init
;	lfsr	FSR0, boot_rep + EEDATA_OFFS	; FSR0=&boot_rsp.read_eeprom.data
        ; while( cntr-- )
read_eeprom_loop
;	bsf	EECON1, RD			; Read data
;	movff	EEDATA, POSTINC0
;	incf	EEADR, F			; Next address
;	decfsz	cntr
;	bra	read_eeprom_loop
	return
;-----------------------------------------------------------------------------
; DESCR : Setup EEPROM registers and vars
; INPUT : boot_cmd
; OUTPUT:
; NOTES :
;-----------------------------------------------------------------------------
eeprom_init
;	movf	boot_cmd + ADDR_LO_OFFS, W	; EEPEOM address to read
;	movwf	EEADR
;	movf	boot_cmd + SIZE_OFFS, W		; Size  of data to read
;	movwf	cntr
;	movwf	boot_rep + SIZE_OFFS
;	clrf	EECON1, W
	return
;-----------------------------------------------------------------------------
; Assembler Functions written to save code space
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
;       hid_process_cmd
;-----------------------------------------------------------------------------
; DESCR : Process HID command in boot_cmd
; INPUT : 
; OUTPUT: 
; NOTES : 
;-----------------------------------------------------------------------------
hid_process_cmd
	movf	boot_cmd + CMD_OFFS, W			; W = boot_cmd.cmd
	bz	return_hid_process_cmd			; if( boot_cmd.cmd == 0 ) return

	; Start processing
	movwf	boot_rep + CMD_OFFS			; boot_rep.cmd = boot_cmd.cmd
	movff	boot_cmd + ID_OFFS, boot_rep + ID_OFFS	; boot_rep.id = boot_cmd.id
	

	clrf	boot_cmd + CMD_OFFS			; boot_cmd.cmd = 0
	; switch( boot_cmd.cmd )
	dcfsnz	WREG
	bra	read_code	; cmd=1 BOOT_READ_FLASH
	dcfsnz	WREG
	bra	write_code	; cmd=2 BOOT_WRITE_FLASH
	dcfsnz	WREG
	bra	erase_code	; cmd=3 BOOT_ERASE_FLASH
	dcfsnz	WREG
	bra	get_fw_version	; cmd=4 BOOT_GET_FW_VER
	dcfsnz	WREG
	bra	soft_reset	; cmd=5 BOOT_RESET
	dcfsnz	WREG
	bra	read_id		; cmd=6 BOOT_READ_ID
	dcfsnz	WREG
	bra	write_id	; cmd=7 BOOT_WRITE_ID
;	dcfsnz	WREG
;	bra	read_eeprom	; cmd=8 BOOT_READ_EEPROM
;	dcfsnz	WREG
;	bra	write_eeprom	; cmd=9 BOOT_WRITE_EEPROM

        ; If command is not processed sned back BOOT_CMD_UNKNOWN                                                                         
unknown_cmd
	movlw	BOOT_CMD_UNKNOWN
	movwf	boot_rep + CMD_OFFS	; boot_rep.cmd = BOOT_CMD_UNKNOWN
	
return_hid_process_cmd
	return
	
;-----------------------------------------------------------------------------
;       get_fw_version 
;-----------------------------------------------------------------------------
; DESCR : get_fw_version
; INPUT : 
; OUTPUT: 
; NOTES : 
;-----------------------------------------------------------------------------
get_fw_version
	movlw	FW_VER_MAJOR
	movwf	boot_rep + VER_MAJOR_OFFS 
	movlw	FW_VER_MINOR
	movwf	boot_rep + VER_MINOR_OFFS 
	movlw	FW_VER_SUB_MINOR
	movwf	boot_rep + VER_SMINOR_OFFS
	return

;-----------------------------------------------------------------------------
;       soft_reset       
;       bootloader_soft_reset       
;-----------------------------------------------------------------------------
; DESCR : Reset         
; INPUT : 
; OUTPUT: 
; NOTES : 
;-----------------------------------------------------------------------------
; Soft Reset and run Application FW
bootloader_soft_reset
	bcf     UCON,USBEN      ; Disable USB Engine
	
	; Delay to show USB device reset
	clrf	cntr
	clrf	WREG
	decfsz	WREG
	bra	$ - 2
	decfsz	cntr
	bra	$ - 8

	bra jumpentry ;jump to entry point

soft_reset	; Reset USB    
soft_reset2
	bcf     UCON,USBEN      ; Disable USB Engine
	
	; Delay to show USB device reset
	clrf	cntr
	clrf	WREG
	decfsz	WREG
	bra	$ - 2
	decfsz	cntr
	bra	$ - 8
	
	reset

;-----------------------------------------------------------------------------
;       copy_boot_rep 
;-----------------------------------------------------------------------------
; DESCR : boot_rep => hid_report_in, boot_rep <= 0
; INPUT : boot_rep
; OUTPUT: 
; NOTES : 
;-----------------------------------------------------------------------------
copy_boot_rep
	rcall	store_fsr1_fsr2
	
	lfsr	FSR0, boot_rep
	lfsr	FSR1, hid_report_in
	movlw	HID_IN_EP_SIZE
	
	; while( w )
copy_boot_rep_loop
	movff	INDF0, POSTINC1
	clrf	POSTINC0
	decfsz	WREG
	bra	copy_boot_rep_loop
	
	; restore FSR1,FSR2 and return
	bra	restore_fsr1_fsr2

;-----------------------------------------------------------------------------
;       set_eep_mask 
;       clr_eep_mask 
;-----------------------------------------------------------------------------
; DESCR : 
; INPUT : 
; OUTPUT: 
; NOTES : 
;-----------------------------------------------------------------------------
clr_eep_mark
;	movlw	~(EEPROM_MARK)
;	clrf	eep_mark_set	; EEP_MARK will be cleared
	bra	write_eep_mark
set_eep_mark
;	movlw	EEPROM_MARK
;	bsf	eep_mark_set, 0	; EEP_MARK will be set
write_eep_mark
;	movwf	EEDATA		; Set Data
;	movlw	EEPROM_MARK_ADDR
;	movwf	EEADR		; Set Address
;	bcf	EECON1, EEPGD	; Access EEPROM (not code memory)
;	rcall	eeprom_write	; Perform write sequence
;	btfsc	EECON1, WR
;	bra	$ - 2		; Wait EEIF=1 write completed
;	bcf	EECON1, WREN	; Disable writes
	return

;-----------------------------------------------------------------------------
; Local Functions
;-----------------------------------------------------------------------------
; cntr = boot_rep_size8 = boot_cmd.size8 & 0x3C
load_address_size8
	movf	boot_cmd + SIZE_OFFS, W
	;andlw	0x3C ;!!! 18f24j50
	movwf	cntr
	movwf	boot_rep + SIZE_OFFS

; TBLPTR = boot_rep.addr = boot_cmd.addr; hold_r = boot_cmd.addr_lo & 0x1F
load_address
	movf	boot_cmd + ADDR_HI_OFFS, W
	movwf	TBLPTRH
	movwf	boot_rep + ADDR_HI_OFFS
	movf	boot_cmd + ADDR_LO_OFFS, W
	movwf	TBLPTRL
	movwf	boot_rep + ADDR_LO_OFFS
	andlw	0x1F
	movwf	hold_r
	return

; write flash (if EECON1.FREE is set will perform block erase)          
flash_write
	bcf	EECON1, WPROG	; 64byte writes
	btfsc boot_cmd + FLUSH_OFFS, 1	;if bit 1 is set, this is a 2byte write
	bsf	EECON1, WPROG	; 2byte writes
; write eeprom EEADR,EEDATA must be preset, EEPGD must be cleared       
eeprom_write
;	bcf	EECON1, CFGS	; Access code memory (not Config)
	bsf	EECON1, WREN	; Enable write
	movlw	0x55
	movwf	EECON2
	movlw	0xAA
	movwf	EECON2
	bsf	EECON1, WR	; Start flash/eeprom writing
	clrf	hold_r		; hold_r=0
	return
;-----------------------------------------------------------------------------

; These were in xtea.asm, 
; but we didn't need encryption so we removed xtea
; and moved these funcitons here where they're used.
	
	global	_fsr
_fsr	res	4	; Temporary storage for FSR's

	; Store FSR1,FSR2
	GLOBAL  store_fsr1_fsr2        
store_fsr1_fsr2
	movff	FSR1L, _fsr                         
	movff	FSR1H, _fsr + 1
	movff	FSR2L, _fsr + 2
	movff	FSR2H, _fsr + 3
	return

	; Restore FSR1, FSR2
	GLOBAL	restore_fsr1_fsr2
restore_fsr1_fsr2
	movff	_fsr, FSR1L                        
	movff	_fsr + 1, FSR1H                          
	movff	_fsr + 2, FSR2L                        
	movff	_fsr + 3, FSR2H                          
	return

	END
