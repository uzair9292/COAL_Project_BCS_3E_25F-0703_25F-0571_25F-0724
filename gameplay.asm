[org 0x0100]
jmp start

screen_w equ 320
screen_h equ 200
map_w equ 60
map_h equ 12
tile_size equ 16
fps equ 30
title equ 0
playing equ 1
paused equ 2
dying equ 3
life_lost equ 4
win_sequence equ 5
level_complete equ 6
game_over equ 7
exit equ 8
key_esc equ 0x01
key_enter equ 0x1c
key_p equ 0x19
key_shift equ 0x2a
key_space equ 0x39
key_up equ 0x48
key_left equ 0x4b
key_right equ 0x4d
key_down equ 0x50

; TEST HARNESS ENGINE -- leave unchanged for integration
; Reference implementation: review and replace comments in your own words.
old_keyboard: dd 0
old_timer: dd 0
ticks: dw 0
last_tick: dw 0
elapsed_ticks: dw 1
bios_fraction: dw 0
clock_fraction: dw 0
state_frames: dw 0
menu_choice: db 0
state_table: dw TitleState,PlayingState,PausedState,DyingState
            dw LifeLostState,WinState,CompleteState,GameOverState,ExitState
; InitBuffer: shrink PSP allocation, allocate 4000 paragraphs.
; Inputs none; output CF indicates failure; preserves registers.
InitBuffer:
    push ax
    push bx
    push es
    push cs
    pop es
    mov bx,(program_end-$$+0x100+15)/16
    mov ah,0x4a
    int 0x21
    jc initbuffer_done
    mov bx,4000
    mov ah,0x48
    int 0x21
    jc initbuffer_done
    mov [framebuffer_seg],ax
initbuffer_done:
    pop es
    pop bx
    pop ax
    ret
; ClearBuffer(colour): fill 64000 bytes; no register outputs.
ClearBuffer:
    push bp
    mov bp,sp
    push ax
    push cx
    push di
    push es
    mov es,[framebuffer_seg]
    mov al,[bp+4]
    mov ah,al
    xor di,di
    mov cx,32000
    cld
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    pop bp
    ret 2
; PresentBuffer: copy entire frame to VGA; preserves registers.
PresentBuffer:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax,[framebuffer_seg]
    mov ds,ax
    mov ax,0xa000
    mov es,ax
    xor si,si
    xor di,di
    mov cx,32000
    cld
    rep movsw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret
; InstallInterrupts: save DOS vectors, install IRQ1 and IRQ0, set PIT ~30 Hz.
; No inputs/outputs; preserves general and segment registers used.
InstallInterrupts:
    push ax
    push bx
    push dx
    push es
    mov ax,0x3509
    int 0x21
    mov [old_keyboard],bx
    mov [old_keyboard+2],es
    mov ax,0x3508
    int 0x21
    mov [old_timer],bx
    mov [old_timer+2],es
    mov dx,KeyboardISR
    mov ax,0x2509
    int 0x21
    mov dx,TimerISR
    mov ax,0x2508
    int 0x21
    cli
    mov al,0x36
    out 0x43,al
    mov ax,39773
    out 0x40,al
    mov al,ah
    out 0x40,al
    sti
    pop es
    pop dx
    pop bx
    pop ax
    ret
; RestoreInterrupts: reset standard PIT and restore both DOS vectors.
RestoreInterrupts:
    push ax
    push dx
    push ds
    cli
    mov al,0x36
    out 0x43,al
    xor al,al
    out 0x40,al
    out 0x40,al
    sti
    lds dx,[cs:old_timer]
    mov ax,0x2508
    int 0x21
    lds dx,[cs:old_keyboard]
    mov ax,0x2509
    int 0x21
    pop ds
    pop dx
    pop ax
    ret
; KeyboardISR: IRQ1; updates held-key array, acknowledges PIC.
; No inputs/outputs; preserves interrupted registers.
KeyboardISR:
    push ax
    push bx
    in al,0x60
    cmp al,0xe0
    je keyboardisr_ack
    cmp al,0xe1
    je keyboardisr_ack
    xor bx,bx
    mov bl,al
    and bl,0x7f
    test al,0x80
    jnz keyboardisr_release
    mov byte [cs:key_states+bx],1
    jmp keyboardisr_ack
keyboardisr_release:
    mov byte [cs:key_states+bx],0
keyboardisr_ack:
    in al,0x61
    mov ah,al
    or al,0x80
    out 0x61,al
    mov al,ah
    out 0x61,al
    mov al,0x20
    out 0x20,al
    pop bx
    pop ax
    iret
; TimerISR: count frames; chain BIOS at average original 18.2 Hz.
TimerISR:
    push ax
    inc word [cs:ticks]
    add word [cs:bios_fraction],39773
    jc timerisr_chain
    mov al,0x20
    out 0x20,al
    pop ax
    iret
timerisr_chain:
    pop ax
    jmp far [cs:old_timer]
; WaitForTick: block until next hardware tick, without fixed delays.
WaitForTick:
    push ax
waitfortick_wait:
    cli
    mov ax,[ticks]
    cmp ax,[last_tick]
    jne waitfortick_ready
    sti
    hlt
    jmp waitfortick_wait
waitfortick_ready:
    push ax
    sub ax,[last_tick]
    mov [elapsed_ticks],ax
    pop ax
    mov [last_tick],ax
    sti
    pop ax
    ret
; ReadKeys: snapshot held keys and rising edges, preserves registers.
ReadKeys:
    push ax
    push bx
    push cx
    xor bx,bx
    mov cx,128
    pushf
    cli
readkeys_loop:
    mov al,[key_states+bx]
    mov [keys_held+bx],al
    mov ah,[previous_keys+bx]
    mov [previous_keys+bx],al
    xor ah,1
    and al,ah
    mov [keys_pressed+bx],al
    inc bx
    loop readkeys_loop
    popf
    pop cx
    pop bx
    pop ax
    ret
; ResetLevel: restore world and hero; keep accumulated score/coins/lives.
ResetLevel:
    mov word [mario_x],0x2000
    mov word [mario_x+2],0
    mov word [mario_y],0x9000 ; top = 144, feet = 160
    mov word [mario_y+2],0
    mov word [velocity_x],0
    mov word [velocity_y],0
    mov word [camera_x],0
    mov byte [hp],1
    mov byte [form],0
    mov byte [on_ground],1
    mov byte [facing],0
    mov byte [pose],0
    mov word [invuln_timer],0
    mov byte [stomp_chain],0
    mov byte [death_request],0
    mov byte [win_request],0
    mov word [flag_points],0
    mov word [time_left],300
    mov word [clock_fraction],0
    call ResetMap
    call ResetEntities
    ret
; NewGame: reset counters and level.
NewGame:
    mov word [score_low],0
    mov word [score_high],0
    mov byte [coins],0
    mov byte [lives],3
    call ResetLevel
    ret
; TickClock: update countdown from elapsed hardware ticks.
TickClock:
    push ax
    mov ax,[elapsed_ticks]
    add [clock_fraction],ax
newgame_next:
    cmp word [clock_fraction],fps
    jb newgame_done
    sub word [clock_fraction],fps
    cmp word [time_left],0
    je newgame_dead
    dec word [time_left]
    jnz newgame_next
newgame_dead:
    mov byte [death_request],1
newgame_done:
    pop ax
    ret
; DrawFrame: render shared world and HUD then present it.
DrawFrame:
    push ax
    mov ax,9
    push ax
    call ClearBuffer
    call DrawMap
    call DrawEntities
    call DrawHero
    call DrawHUD
    call PresentBuffer
    pop ax
    ret
; TitleState: menu selection and start/exit.
TitleState:
    cmp byte [keys_pressed+key_esc],0
    jne titlestate_exit
    cmp byte [keys_pressed+key_up],0
    jne titlestate_toggle
    cmp byte [keys_pressed+key_down],0
    je titlestate_enter
titlestate_toggle:
    xor byte [menu_choice],1
titlestate_enter:
    cmp byte [keys_pressed+key_enter],0
    je titlestate_draw
    cmp byte [menu_choice],0
    jne titlestate_exit
    call NewGame
    mov byte [game_state],playing
    ret
titlestate_exit:
    mov byte [game_state],exit
    ret
titlestate_draw:
    call DrawTitle
    ret
; PlayingState: update in manual's specified order.
PlayingState:
    cmp byte [keys_pressed+key_esc],0
    jne playingstate_title
    cmp byte [keys_pressed+key_p],0
    jne playingstate_pause
    call UpdatePlayer
    call UpdateEnemies
    call UpdateItems
    call CheckCollisions
    call TickClock
    cmp word [invuln_timer],0
    je playingstate_events
    dec word [invuln_timer]
playingstate_events:
    cmp byte [death_request],0
    jne playingstate_die
    cmp byte [win_request],0
    jne playingstate_win
    call UpdateCamera
    call DrawFrame
    ret
playingstate_title:
    mov byte [game_state],title
    ret
playingstate_pause:
    mov byte [game_state],paused
    ret
playingstate_die:
    mov word [state_frames],0
    mov word [velocity_y],-0x500
    cmp byte [death_request],2
    jne playingstate_dying
    mov word [velocity_y],0x400
playingstate_dying:
    mov byte [game_state],dying
    ret
playingstate_win:
    push word [flag_points]
    call AddScore
    mov word [state_frames],0
    mov byte [game_state],win_sequence
    ret
; PausedState: freeze all simulation, overlay pause.
PausedState:
    cmp byte [keys_pressed+key_esc],0
    jne pausedstate_title
    cmp byte [keys_pressed+key_p],0
    je pausedstate_draw
    mov byte [game_state],playing
    ret
pausedstate_title:
    mov byte [game_state],title
    ret
pausedstate_draw:
    call DrawPause
    ret
; DyingState: move hero with gravity, no collision; decrement life once.
DyingState:
    push ax
    push dx
    mov ax,[velocity_y]
    cwd
    add [mario_y],ax
    adc [mario_y+2],dx
    add word [velocity_y],0x40
    mov byte [pose],2
    call DrawFrame
    inc word [state_frames]
    cmp word [state_frames],45
    jb dyingstate_done
    dec byte [lives]
    mov word [state_frames],0
    mov byte [game_state],life_lost
    cmp byte [lives],0
    jne dyingstate_done
    mov byte [game_state],game_over
dyingstate_done:
    pop dx
    pop ax
    ret
; LifeLostState: show lives screen for two seconds, reset level.
LifeLostState:
    call DrawLifeLost
    inc word [state_frames]
    cmp word [state_frames],60
    jb lifeloststate_done
    call ResetLevel
    mov byte [game_state],playing
lifeloststate_done:
    ret
; WinState: slide down, then hide hero; add time bonus once.
WinState:
    push ax
    push dx
    inc word [state_frames]
    cmp word [state_frames],30
    ja winstate_walk
    cmp word [mario_y+2],0
    jne winstate_slide
    cmp word [mario_y],0x9000
    jae winstate_draw
winstate_slide:
    add word [mario_y],0x400
    adc word [mario_y+2],0
winstate_draw:
    call DrawFrame
    jmp winstate_done
winstate_walk:
    call DrawWinWorld
    cmp word [state_frames],60
    jb winstate_done
    mov ax,[time_left]
    mov dx,50
    mul dx
    push ax
    call AddScore
    mov byte [game_state],level_complete
winstate_done:
    pop dx
    pop ax
    ret
; CompleteState/GameOverState: display screen until Enter.
CompleteState:
    call DrawComplete
    jmp ReturnOnEnter
GameOverState:
    call DrawGameOver
ReturnOnEnter:
    cmp byte [keys_pressed+key_enter],0
    je returnonenter_done
    mov byte [game_state],title
returnonenter_done:
    ret
; ExitState: main loop performs cleanup.
ExitState:
    ret

; TEST ROUTINES -- replace your assigned routines only
; Temporary stand-ins for teammates. Never submit as finished gameplay.
; Draw simple coloured bars to verify the engine independently.
ResetMap:
    ret
ResetEntities:
    ret
UpdateEnemies:
    ret
UpdateItems:
    ret
CheckCollisions:
    ret
UpdateCamera:
    ret
DrawEntities:
    ret
DrawHUD:
    ret
; DemoRect(x,y,w,h,colour), all coordinates in bounds.
DemoRect:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov es,[framebuffer_seg]
    mov ax,[bp+6]
    mov bx,320
    mul bx
    add ax,[bp+4]
    mov di,ax
    mov dx,[bp+10]
    mov al,[bp+12]
    cld
demorect_row:
    mov cx,[bp+8]
    rep stosb
    add di,320
    sub di,[bp+8]
    dec dx
    jnz demorect_row
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10

DrawMap:
    push ax
    mov ax,2
    push ax
    mov ax,40
    push ax
    mov ax,320
    push ax
    mov ax,160
    push ax
    mov ax,0
    push ax
    call DemoRect
    pop ax
    ret
DrawHero:
    push ax
    push bx
    mov ax,[mario_x]
    mov al,ah
    mov ah,[mario_x+2]
    mov bx,ax
    mov ax,[mario_y]
    mov al,ah
    mov ah,[mario_y+2]
    cmp ax,184
    ja drawhero_done
    cmp bx,304
    ja drawhero_done
    push dx
    mov dx,ax
    mov ax,4
    push ax
    mov ax,16
    push ax
    mov ax,16
    push ax
    mov ax,dx
    push ax
    mov ax,bx
    push ax
    call DemoRect
    pop dx
drawhero_done:
    pop bx
    pop ax
    ret
UpdatePlayer:
    push ax
    mov ax,[mario_x]
    mov al,ah
    mov ah,[mario_x+2]
    cmp byte [keys_held+key_left],0
    je updateplayer_right
    cmp ax,0
    je updateplayer_right
    sub word [mario_x],0x100
    sbb word [mario_x+2],0
    dec ax
updateplayer_right:
    cmp byte [keys_held+key_right],0
    je updateplayer_events
    cmp ax,304
    jae updateplayer_events
    add word [mario_x],0x100
    adc word [mario_x+2],0
updateplayer_events:
    cmp byte [keys_pressed+0x20],0 ; D: simulated death
    je updateplayer_win
    mov byte [death_request],1
updateplayer_win:
    cmp byte [keys_pressed+0x11],0 ; W: simulated win
    je updateplayer_done
    mov byte [win_request],1
    mov word [flag_points],100
updateplayer_done:
    pop ax
    ret
AddScore:
    push bp
    mov bp,sp
    push ax
    mov ax,[bp+4]
    add [score_low],ax
    adc word [score_high],0
    pop ax
    pop bp
    ret 2
DrawTitle:
    push ax
    xor ax,ax
    push ax
    call ClearBuffer
    mov ax,8
    push ax
    mov ax,30
    push ax
    mov ax,160
    push ax
    mov ax,60
    push ax
    mov ax,80
    push ax
    call DemoRect
    mov ax,8
    push ax
    mov ax,30
    push ax
    mov ax,160
    push ax
    mov ax,110
    push ax
    mov ax,80
    push ax
    call DemoRect
    cmp byte [menu_choice],0
    jne drawtitle_exit
    mov ax,10
    push ax
    mov ax,30
    push ax
    mov ax,160
    push ax
    mov ax,60
    push ax
    mov ax,80
    push ax
    call DemoRect
    jmp drawtitle_show
drawtitle_exit:
    mov ax,12
    push ax
    mov ax,30
    push ax
    mov ax,160
    push ax
    mov ax,110
    push ax
    mov ax,80
    push ax
    call DemoRect
drawtitle_show:
    call PresentBuffer
    pop ax
    ret
DrawPause:
    push ax
    mov ax,14
    push ax
    mov ax,40
    push ax
    mov ax,140
    push ax
    mov ax,80
    push ax
    mov ax,90
    push ax
    call DemoRect
    call PresentBuffer
    pop ax
    ret
DrawLifeLost:
    push ax
    mov ax,4
    push ax
    call ClearBuffer
    call PresentBuffer
    pop ax
    ret
DrawComplete:
    push ax
    mov ax,2
    push ax
    call ClearBuffer
    call PresentBuffer
    pop ax
    ret
DrawGameOver:
    push ax
    xor ax,ax
    push ax
    call ClearBuffer
    mov ax,4
    push ax
    mov ax,40
    push ax
    mov ax,240
    push ax
    mov ax,80
    push ax
    mov ax,40
    push ax
    call DemoRect
    call PresentBuffer
    pop ax
    ret
DrawWinWorld:
    push ax
    mov ax,9
    push ax
    call ClearBuffer
    call DrawMap
    call PresentBuffer
    pop ax
    ret

; TEST ENTRY AND STACK
start:
    push cs
    pop ds
    cli
    mov ax,cs
    mov ss,ax
    mov sp,stack_top
    sti
    cld
    call InitBuffer
    jc startup_error
    mov ax,0x0013
    int 0x10
    call InstallInterrupts
    call NewGame
    mov byte [game_state],title
main_loop:
    call WaitForTick
    call ReadKeys
    xor bx,bx
    mov bl,[game_state]
    shl bx,1
    call word [state_table+bx]
    cmp byte [game_state],exit
    jne main_loop
    call RestoreInterrupts
    mov ax,3
    int 0x10
    mov es,[framebuffer_seg]
    mov ah,0x49
    int 0x21
    mov ax,0x4c00
    int 0x21
startup_error:
    mov dx,error_msg
    mov ah,9
    int 0x21
    mov ax,0x4c01
    int 0x21
error_msg: db 'Unable to allocate frame buffer.$'

; Shared variables (identical in all three files).
framebuffer_seg: dw 0
; Positions are signed 24.8 stored as two words: low word first.
; Integer pixel = signed 32-bit value >> 8 (use 16-bit shifts).
mario_x: dd 0
mario_y: dd 0
velocity_x: dw 0
velocity_y: dw 0
camera_x: dw 0
hp: db 1
lives: db 3
coins: db 0
score_low: dw 0
score_high: dw 0
time_left: dw 300
on_ground: db 0
form: db 0
facing: db 0
pose: db 0
invuln_timer: dw 0
stomp_chain: db 0
; Event flags set by gameplay, consumed by core.
death_request: db 0 ; 1 normal, 2 pit
win_request: db 0
flag_points: dw 0
key_states: times 128 db 0
keys_pressed: times 128 db 0
previous_keys: times 128 db 0
; Snapshot read by gameplay; updated once per frame.
keys_held: times 128 db 0
game_state: db title

; Private stack, retained when DOS memory is resized.
times 2048 db 0
stack_top:
program_end:
