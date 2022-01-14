; MEMORY: ------------------------------------------------------------------------------------------

; Mega CD MMIO addresses used for communicating with msu-md driver on the mega cd (mode 1)
MSU_COMM_CMD        equ $a12010                 ; Comm command 0 (high byte)
MSU_COMM_ARG        equ $a12011                 ; Comm command 0 (low byte)
MSU_COMM_CMD_CK     equ $a1201f                 ; Comm command 7 (low byte)
MSU_COMM_STATUS     equ $a12020                 ; Comm status 0 (0-ready, 1-init, 2-cmd busy)

; Where to put the code
ROM_END             equ $3ff522

; Variables
victory             equ $fffffefe

; MSU COMMANDS: ------------------------------------------------------------------------------------------

MSU_PLAY            equ $1100                   ; PLAY      decimal no. of track (1-99) playback will be stopped in the end of track
MSU_PLAY_LOOP       equ $1200                   ; PLAY LOOP decimal no. of track (1-99) playback will restart the track when end is reached
MSU_PAUSE           equ $1300                   ; PAUSE     vol fading time. 1/75 of sec. (75 equal to 1 sec) instant stop if 0 pause playback
MSU_RESUME          equ $1400                   ; RESUME    none. resume playback
MSU_VOL             equ $1500                   ; VOL       volume 0-255. set cdda volume
MSU_NOSEEK          equ $1600                   ; NOSEEK    0-on(default state), 1-off(no seek delays)  seek time emulation switch
MSU_PLAYOF          equ $1a00                   ; PLAYOF    #1 = decimal no. of track (1-99) #2 = offset in sectors from the start of the track to apply when looping play cdda track and loop from specified sector offset

; MACROS: ------------------------------------------------------------------------------------------

    macro MSU_WAIT
.\@
        tst.b   MSU_COMM_STATUS
        bne.s   .\@
    endm

    macro MSU_COMMAND cmd, param
        MSU_WAIT
        move.w  #(\1|\2),MSU_COMM_CMD           ; Send msu cmd
        addq.b  #1,MSU_COMM_CMD_CK              ; Increment command clock
    endm

; MEGA DRIVE OVERRIDES : ------------------------------------------------------------------------------------------

        ; M68000 Reset vector
        org     $4
        dc.l    ENTRY_POINT                     ; Custom entry point for redirecting

        org     $200                            ; Original ENTRY POINT
Game
        jsr     restart

        ; Original play_music_track sub routine
        org     $1faf44
        jmp     play_music_track

        ; Game over
        org     $30972e
        jmp     play_game_over
        org     $30973e
        rts

        ; Continue
        org     $232cd0
        rept    9
        nop
        endr
        jsr     play_continue

        ; Title screen
        org     $2328fa
        jsr     play_title_screen

        ; Goro lives
        org     $232b02
        jsr     play_goro_lives
        org     $232b08
        moveq   #-1,d3

        ; Victory
        org     $12738
        jmp     init_vars
init_vars_return
        org     $233572
        jsr     play_victory
        org     $309f3e
        moveq   #-1,d3
        org     $309f5e
        moveq   #-1,d3
        org     $309f7e
        moveq   #-1,d3
        org     $308f90
        moveq   #-1,d3
        org     $308e56
        moveq   #-1,d3

        ; Ermac
        org     $19e818
        moveq   #$3f,d0     ; Map Ermac stage music to The Pit
        org     $234432     ; Replace Ermac intro sound with title screen instead of "choose your fighter"
        jsr     play_title_screen
        org     $2344a2
        nop
        nop
        nop

        ; Goro crash fix
        org     $62a0
        move    a7,usp
        org     $62ac
        move    usp,a7

        org     ROM_END

ENTRY_POINT
        bsr     audio_init
        jmp     Game


; MSU-MD Init: -------------------------------------------------------------------------------------

        align   2
audio_init
        bsr     msu_driver_init
        tst.b   d0                              ; if 1: no CD Hardware found
.audio_init_fail
        bne     .audio_init_fail                ; Loop forever

        MSU_COMMAND MSU_NOSEEK, 1
        MSU_COMMAND MSU_VOL,    255
        rts

; Sound: -------------------------------------------------------------------------------------

        align   2

init_vars
        lea     victory,sp
        sf      (sp)
        jmp     init_vars_return


restart
        MSU_COMMAND MSU_PAUSE,  0

        ; Run original code
        tst.l   $a10008
        rts


play_game_over
        MSU_COMMAND MSU_PLAY,18
        rts


play_continue
        MSU_COMMAND MSU_PLAY,20
        rts


play_victory
        st  victory

        MSU_COMMAND MSU_PLAY,21
        rts


play_title_screen
        MSU_COMMAND MSU_PLAY,22
        rts


play_goro_lives
        MSU_COMMAND MSU_PLAY,23
        rts


play_music_track
        tst.b   victory
        beq     .continue
            clr.w   d0                          ; Skip playing other tracks while in victory mode
            bra     .original_code
.continue
        tst.b   d0                              ; d0 = track number
        bne     .play
            ; 0 = Stop
            MSU_COMMAND MSU_PAUSE, 0
        bra     .original_code
.play
        ; Save used registers
        movem.l d1-d2/a0,-(sp)

        lea     AUDIO_TBL(pc),a0
        moveq   #((AUDIO_TBL_END-AUDIO_TBL)/2)-1,d1
.find_track_loop
            move.w  d1,d2
            add.w   d2,d2
            move.w  (a0,d2),d2
            cmp.b   d2,d0
            bne     .next_track

                ; Set cd track number
                move.b  d1,d2
                addq.b  #1,d2

                ; Send play command
                MSU_WAIT
                move.w  d2,MSU_COMM_CMD
                addq.b  #1,MSU_COMM_CMD_CK

                ; Run stop command for original driver
                clr.w   d0
                bra     .play_done
.next_track
        dbra    d1,.find_track_loop

        ; If no matching cd track found run original track

        ; First stop any still playing cd track
        MSU_COMMAND MSU_PAUSE, 0

.play_done
        ; Restore used registers
        movem.l  (sp)+,d1-d2/a0

.original_code
        addq.w  #1,d0
        move.w  d0,($fa42).w
        st      ($fad4).w
        sf      ($faa6).w
        clr.b   ($face).w
        clr.w   ($fa3e).w
        clr.w   ($fa40).w
        sf      ($fa62).w
        rts

; TABLES: ------------------------------------------------------------------------------------------

        align 2
AUDIO_TBL
        ;       # Command|id                    # Track Name
        dc.w    MSU_PLAY_LOOP|$02               ; 01 - Choose Your Fighter
        dc.w    MSU_PLAY_LOOP|$0f               ; 02 - Courtyard
        dc.w    MSU_PLAY|$1d                    ; 03 - Courtyard Victory
        dc.w    MSU_PLAY_LOOP|$1e               ; 04 - Entrance
        dc.w    MSU_PLAY|$2f                    ; 05 - Entrance Victory
        dc.w    MSU_PLAY_LOOP|$30               ; 06 - Warriors Shrine
        dc.w    MSU_PLAY|$3e                    ; 07 - Warriors Shrine Victory
        dc.w    MSU_PLAY_LOOP|$3f               ; 08 - The Pit
        dc.w    MSU_PLAY|$4f                    ; 09 - The Pit Victory
        dc.w    MSU_PLAY_LOOP|$0b               ; 10 - Goro's Lair
        dc.w    MSU_PLAY|$52                    ; 11 - Goro's Lair Victory
        dc.w    MSU_PLAY_LOOP|$50               ; 12 - The Hall
        dc.w    MSU_PLAY|$53                    ; 13 - The Hall Victory
        dc.w    MSU_PLAY|$0a                    ; 14 - 2 Player Versus
        dc.w    MSU_PLAY|$55                    ; 15 - Test Your Might
        dc.w    MSU_PLAY_LOOP|$04               ; 16 - Bio Screen
        dc.w    MSU_PLAY_LOOP|$08               ; 17 - Battle plan
        dc.w    MSU_PLAY_LOOP|$ff               ; 18 - Game Over (Unmapped)
        dc.w    MSU_PLAY|$54                    ; 19 - Fatality
AUDIO_TBL_END

; MSU-MD DRIVER: -----------------------------------------------------------------------------------

        align 2
msu_driver_init
        incbin  "msu-drv.bin"
