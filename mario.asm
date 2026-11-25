[org 0x0100]
jmp start

; Shared constants and data: keep names and sizes identical across files.
; Shared interface: change only by agreement of all three members.
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

tile_empty equ 0
tile_ground equ 1
tile_brick equ 2
tile_question equ 3
tile_mushroom equ 4
tile_used equ 5
tile_pipe_tl equ 6
tile_pipe_tr equ 7
tile_pipe_bl equ 8
tile_pipe_br equ 9
tile_solid equ 10
tile_coin equ 11
tile_pole equ 12
tile_flagtop equ 13
tile_count equ 14
cam_center equ 152
cam_max equ 640
tt equ 0

; ENGINE PROCEDURES (your work)
; Reference implementation: review and replace comments in your own words.
old_keyboard: dd 0
old_timer: dd 0
ticks: dw 0
last_tick: dw 0
elapsed_ticks: dw 1
bios_fraction: dw 0
clock_fraction: dw 0
clock_high: dw 0
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
    call BonusSilence
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
    cmp word [cs:bonus_sound_time],0
    je bonus_irq_done
    dec word [cs:bonus_sound_time]
    jnz bonus_irq_done
    in al,0x61
    and al,0xfc
    out 0x61,al
bonus_irq_done:
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
    call BonusSilence
    mov word [cs:bonus_popup_time],0
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
    mov word [clock_high],0
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
; TickClock: procedure entry.
TickClock:
    push ax
    push dx
    ; Each IRQ represents 39773 PIT input cycles. One second is 1193182 cycles.
    mov ax,[elapsed_ticks]
    mov dx,39773
    mul dx
    add [clock_fraction],ax
    adc [clock_high],dx
clock_next:
    cmp word [clock_high],0x12
    jb clock_done
    ja clock_second
    cmp word [clock_fraction],0x34de
    jb clock_done
clock_second:
    sub word [clock_fraction],0x34de
    sbb word [clock_high],0x12
    cmp word [time_left],0
    je clock_dead
    dec word [time_left]
    jnz clock_next
clock_dead:
    mov byte [death_request],1
clock_done:
    pop dx
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
    call BonusDrawPopup
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
    call BonusAgePopup
    call UpdatePlayer
    call UpdateEnemies
    call UpdateItems
    call CheckCollisions
    call TickClock
    cmp word [invuln_timer],0
    je playingstate_events
    push ax
    mov ax,[elapsed_ticks]
    cmp [invuln_timer],ax
    ja playingstate_invuln_sub
    mov ax,[invuln_timer]
playingstate_invuln_sub:
    sub [invuln_timer],ax
    pop ax
playingstate_events:
    cmp byte [death_request],0
    jne playingstate_die
    cmp byte [win_request],0
    jne playingstate_win
    call UpdateCamera
    call DrawFrame
    ret
playingstate_title:
    call BonusSilence
    mov byte [game_state],title
    ret
playingstate_pause:
    call BonusSilence
    mov byte [game_state],paused
    ret
playingstate_die:
    push ax
    mov ax,4500
    push ax
    mov ax,8
    push ax
    call BonusTone
    pop ax
    mov word [state_frames],0
    mov word [velocity_y],-0x580
    cmp byte [death_request],2
    jne playingstate_dying
    mov word [velocity_y],0x400
playingstate_dying:
    mov word [invuln_timer],0
    mov byte [game_state],dying
    ret
playingstate_win:
    push word [flag_points]
    call AddScore
    push ax
    mov ax,950
    push ax
    mov ax,12
    push ax
    call BonusTone
    pop ax
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
; DyingState: procedure entry.
DyingState:
    push ax
    push dx
    push cx
    mov cx,[elapsed_ticks]
dyingstate_step:
    mov ax,[velocity_y]
    cwd
    add [mario_y],ax
    adc [mario_y+2],dx
    ; A stronger falling acceleration gets the hero off screen in 45 ticks.
    cmp word [velocity_y],0
    jge dyingstate_fall
    add word [velocity_y],0x50
    jmp dyingstate_count
dyingstate_fall:
    add word [velocity_y],0xc0
dyingstate_count:
    inc word [state_frames]
    cmp word [state_frames],45
    jae dyingstate_finish
    loop dyingstate_step
    mov byte [pose],2
    call DrawFrame
    jmp dyingstate_done
dyingstate_finish:
    dec byte [lives]
    mov word [state_frames],0
    mov byte [game_state],life_lost
    cmp byte [lives],0
    jne dyingstate_done
    mov byte [game_state],game_over
dyingstate_done:
    pop cx
    pop dx
    pop ax
    ret
; LifeLostState: show lives screen for two seconds, reset level.
LifeLostState:
    call DrawLifeLost
    push ax
    mov ax,[elapsed_ticks]
    add [state_frames],ax
    pop ax
    cmp word [state_frames],60
    jb lifeloststate_done
    call ResetLevel
    mov byte [game_state],playing
lifeloststate_done:
    ret
; WinState: procedure entry.
WinState:
    push ax
    push dx
    push cx
    mov cx,[elapsed_ticks]
winstate_step:
    inc word [state_frames]
    cmp word [state_frames],30
    ja winstate_count
    ; Pole base top is 144. Small Mario is 16 pixels tall.
    mov ax,0x8000
    cmp byte [hp],2
    jne winstate_target
    mov ax,0x7000
winstate_target:
    cmp word [mario_y+2],0
    jl winstate_slide
    jg winstate_clamp
    cmp [mario_y],ax
    jae winstate_clamp
winstate_slide:
    add word [mario_y],0x400
    adc word [mario_y+2],0
    cmp word [mario_y+2],0
    jl winstate_count
    cmp [mario_y],ax
    jb winstate_count
winstate_clamp:
    mov [mario_y],ax
    mov word [mario_y+2],0
winstate_count:
    cmp word [state_frames],60
    jae winstate_bonus
    loop winstate_step
    cmp word [state_frames],30
    ja winstate_hide
    call DrawFrame
    jmp winstate_done
winstate_hide:
    call DrawWinWorld
    jmp winstate_done
winstate_bonus:
    mov ax,[time_left]
    mov dx,50
    mul dx
    push ax
    call AddScore
    mov byte [game_state],level_complete
winstate_done:
    pop cx
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

; GAMEPLAY INTEGRATION: adapted from Nawal's prototype; uses shared engine data.
; Entity record: 24.8 x/y (two words each), signed 8.8 vx/vy,
; type, state, timer and grace. State 0=removed,1=dormant,2=walking,
; 3=flattened,4=stationary shell,5=sliding shell. Type 3=mushroom.
entity_size equ 16
ent_x equ 0
ent_y equ 4
ent_vx equ 8
ent_vy equ 10
ent_type equ 12
ent_state equ 13
ent_timer equ 14
ent_grace equ 15
entity_count equ 8

; ResetEntities: restore initial enemy records and clear transient items.
; Inputs/outputs none; preserves registers.
ResetEntities:
    push cx
    push si
    push di
    push es
    push ds
    pop es
    mov si,initial_entities
    mov di,entities
    mov cx,entity_size*entity_count/2
    cld
    rep movsw
    pop es
    pop di
    pop si
    pop cx
    ret

; SolidAt(x,y): AX=1 if tile is solid, else 0. Other registers preserved.
SolidAt:
    push bp
    mov bp,sp
    push word [bp+6]
    push word [bp+4]
    call GetTile
    cmp ax,1
    jb solidat_no
    cmp ax,10
    ja solidat_no
    mov ax,1
    jmp solidat_done
solidat_no:
    xor ax,ax
solidat_done:
    pop bp
    ret 4

; PlayerBounds: derive inclusive hitbox from the shared fixed-point position.
; Inputs shared hero; outputs bounds and height in scratch words; preserves registers.
PlayerBounds:
    push ax
    mov ax,[mario_x+1]
    add ax,2
    mov [player_left],ax
    add ax,11
    mov [player_right],ax
    mov ax,[mario_y+1]
    mov [player_top],ax
    mov word [hero_height],16
    cmp byte [hp],2
    jne playerbounds_height
    mov word [hero_height],32
playerbounds_height:
    add ax,[hero_height]
    dec ax
    mov [player_bottom],ax
    pop ax
    ret

; TestPlayerSide(x): test a vertical line of the player hitbox. AX=1 if solid.
; Other registers preserved.
TestPlayerSide:
    push bp
    mov bp,sp
    push word [player_top]
    push word [bp+4]
    call SolidAt
    cmp ax,0
    je gamebranch1
    jmp near testplayerside_done
gamebranch1:
    push word [player_bottom]
    push word [bp+4]
    call SolidAt
    cmp ax,0
    jne testplayerside_done
    cmp word [hero_height],32
    jne testplayerside_done
    push word [player_top]
    pop ax
    add ax,15
    push ax
    push word [bp+4]
    call SolidAt
    cmp ax,0
    jne testplayerside_done
    mov ax,[player_top]
    add ax,16
    push ax
    push word [bp+4]
    call SolidAt
testplayerside_done:
    pop bp
    ret 2

; TestPlayerRow(y): test both horizontal edges of hitbox. AX=1 if solid.
TestPlayerRow:
    push bp
    mov bp,sp
    push word [bp+4]
    push word [player_left]
    call SolidAt
    cmp ax,0
    jne testplayerrow_done
    push word [bp+4]
    push word [player_right]
    call SolidAt
testplayerrow_done:
    pop bp
    ret 2

; UpdatePlayer: input acceleration/friction, jump, gravity, X then Y collision.
; Inputs shared keys and hero; outputs shared hero and event flags; preserves registers.
UpdatePlayer:
    push ax
    push bx
    push dx
    call PlayerBounds
    mov ax,[player_bottom]
    inc ax
    mov [previous_feet],ax
    mov byte [on_ground],0
    cmp word [velocity_y],0
    jl player_initial_ground_done
    push ax
    call TestPlayerRow
    cmp ax,0
    je player_initial_ground_done
    mov byte [on_ground],1
player_initial_ground_done:
    mov bx,0x180
    cmp byte [keys_held+key_shift],0
    je player_speed_limit
    mov bx,0x280
player_speed_limit:
    cmp byte [keys_held+key_left],0
    je player_right_key
    cmp byte [keys_held+key_right],0
    jne player_friction
    mov byte [facing],1
    mov ax,0x20
    cmp word [velocity_x],0
    jle player_accel_left
    mov ax,0x40
player_accel_left:
    sub [velocity_x],ax
    jmp player_limit
player_right_key:
    cmp byte [keys_held+key_right],0
    je player_friction
    mov byte [facing],0
    mov ax,0x20
    cmp word [velocity_x],0
    jge player_accel_right
    mov ax,0x40
player_accel_right:
    add [velocity_x],ax
    jmp player_limit
player_friction:
    mov ax,[velocity_x]
    cmp ax,0x10
    jg player_friction_positive
    cmp ax,-0x10
    jl player_friction_negative
    xor ax,ax
    jmp player_friction_save
player_friction_positive:
    sub ax,0x10
    jmp player_friction_save
player_friction_negative:
    add ax,0x10
player_friction_save:
    mov [velocity_x],ax
player_limit:
    cmp [velocity_x],bx
    jle player_limit_left
    mov [velocity_x],bx
player_limit_left:
    neg bx
    cmp [velocity_x],bx
    jge player_jump
    mov [velocity_x],bx
player_jump:
    cmp byte [keys_pressed+key_space],0
    je player_jump_cut
    cmp byte [on_ground],0
    je player_jump_cut
    mov word [velocity_y],-0x580
    mov byte [on_ground],0
    mov ax,2100
    push ax
    mov ax,3
    push ax
    call BonusTone
player_jump_cut:
    cmp byte [keys_held+key_space],0
    jne player_gravity
    cmp word [velocity_y],-0x200
    jge player_gravity
    mov word [velocity_y],-0x200
player_gravity:
    add word [velocity_y],0x40
    cmp word [velocity_y],0x400
    jle player_move_x
    mov word [velocity_y],0x400
player_move_x:
    mov ax,[velocity_x]
    cwd
    add [mario_x],ax
    adc [mario_x+2],dx
    mov ax,[mario_x+1]
    cmp ax,[camera_x]
    jge player_check_right_edge
    mov ax,[camera_x]
    jmp player_clamp_x
player_check_right_edge:
    cmp ax,944
    jle player_wall
    mov ax,944
player_clamp_x:
    mov word [mario_x],0
    mov [mario_x+1],ax
    mov byte [mario_x+3],0
    mov word [velocity_x],0
player_wall:
    call PlayerBounds
    cmp word [velocity_x],0
    jne gamebranch2
    jmp near player_move_y
gamebranch2:
    jl player_wall_left
    push word [player_right]
    call TestPlayerSide
    cmp ax,0
    je player_move_y
    mov ax,[player_right]
    and ax,0xfff0
    sub ax,14
    jmp player_clamp_wall
player_wall_left:
    push word [player_left]
    call TestPlayerSide
    cmp ax,0
    je player_move_y
    mov ax,[player_left]
    and ax,0xfff0
    add ax,14
player_clamp_wall:
    mov word [mario_x],0
    mov [mario_x+1],ax
    mov byte [mario_x+3],0
    mov word [velocity_x],0
player_move_y:
    mov ax,[velocity_y]
    cwd
    add [mario_y],ax
    adc [mario_y+2],dx
    mov byte [on_ground],0
    call PlayerBounds
    cmp word [player_top],192
    jl player_ceiling_limit
    mov byte [death_request],2
    jmp player_pose
player_ceiling_limit:
    cmp word [player_top],16
    jge player_vertical
    mov word [mario_y],0x1000
    mov word [mario_y+2],0
    mov word [velocity_y],0
    call PlayerBounds
player_vertical:
    cmp word [velocity_y],0
    jl player_ceiling
    ; Check overlap first, then the pixel immediately below the feet.
    ; The second check keeps Mario grounded between fractional movements.
    push word [player_bottom]
    call TestPlayerRow
    cmp ax,0
    jne player_land_overlap
    mov ax,[player_bottom]
    inc ax
    push ax
    call TestPlayerRow
    cmp ax,0
    jne player_land_support
    jmp near player_pose
player_land_overlap:
    mov ax,[player_bottom]
    jmp player_land_align
player_land_support:
    mov ax,[player_bottom]
    inc ax
player_land_align:
    and ax,0xfff0
    sub ax,[hero_height]
    mov word [mario_y],0
    mov [mario_y+1],ax
    mov byte [mario_y+3],0
    mov word [velocity_y],0
    mov byte [on_ground],1
    mov byte [stomp_chain],0
    jmp player_pose
player_ceiling:
    push word [player_top]
    call TestPlayerRow
    cmp ax,0
    je player_pose
    ; Trigger the block under the horizontal centre before correcting y.
    mov ax,[mario_x+1]
    add ax,8
    push word [player_top]
    push ax
    call HitBlock
    mov ax,[player_top]
    and ax,0xfff0
    add ax,16
    mov word [mario_y],0
    mov [mario_y+1],ax
    mov byte [mario_y+3],0
    mov word [velocity_y],0
player_pose:
    mov byte [pose],0
    cmp byte [on_ground],0
    jne player_pose_ground
    mov byte [pose],2
    jmp player_debug
player_pose_ground:
    cmp word [velocity_x],0
    je player_debug
    mov byte [pose],1
player_debug:
    ; T is a documented test key for timeout; no fake win or fake death.
    cmp byte [keys_pressed+0x14],0
    je player_finish
    mov word [time_left],5
    mov word [clock_fraction],0
    mov word [clock_high],0
player_finish:
    call PlayerBounds
    pop dx
    pop bx
    pop ax
    ret

; CollectCoin: shared coin/score/life rules. No inputs/outputs; preserves registers.
CollectCoin:
    push ax
    mov ax,200
    push ax
    call AddScore
    inc byte [coins]
    cmp byte [coins],100
    jb collectcoin_done
    mov byte [coins],0
    call AddLife
collectcoin_done:
    pop ax
    ret

; AddLife: cap extra lives at 99. No inputs/outputs; preserves registers.
AddLife:
    cmp byte [lives],99
    jae addlife_done
    inc byte [lives]
addlife_done:
    ret

; HitBlock(x,y): update the working map, award score or spawn mushroom.
; Inputs whole world pixels on stack; no outputs; preserves registers.
HitBlock:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push si
    mov ax,[bp+4]
    cmp ax,960
    jb gamebranch4
    jmp near hitblock_done
gamebranch4:
    mov bx,ax
    mov ax,[bp+6]
    cmp ax,192
    jb gamebranch5
    jmp near hitblock_done
gamebranch5:
    mov cl,4
    shr ax,cl
    shr bx,cl
    mov dx,60
    mul dx
    add bx,ax
    mov al,[working_map+bx]
    cmp al,tile_brick
    jne hitblock_question
    cmp byte [hp],2
    je gamebranch6
    jmp near hitblock_done
gamebranch6:
    mov byte [working_map+bx],0
    mov ax,50
    push ax
    call AddScore
    jmp hitblock_done
hitblock_question:
    cmp al,tile_question
    jne hitblock_mushroom
    mov byte [working_map+bx],tile_used
    call CollectCoin
    jmp hitblock_done
hitblock_mushroom:
    cmp al,tile_mushroom
    je gamebranch7
    jmp near hitblock_done
gamebranch7:
    mov si,entities+6*entity_size
    cmp byte [si+ent_state],0
    je hitblock_spawn
    add si,entity_size
    cmp byte [si+ent_state],0
    jne hitblock_done
hitblock_spawn:
    mov byte [working_map+bx],tile_used
    mov ax,[bp+4]
    and ax,0xfff0
    mov word [si+ent_x],0
    mov [si+ent_x+1],ax
    mov byte [si+ent_x+3],0
    mov ax,[bp+6]
    and ax,0xfff0
    sub ax,16
    mov word [si+ent_y],0
    mov [si+ent_y+1],ax
    mov byte [si+ent_y+3],0
    mov word [si+ent_vx],0x100
    mov word [si+ent_vy],0
    mov byte [si+ent_type],3
    mov byte [si+ent_state],2
    mov byte [si+ent_timer],0
    mov byte [si+ent_grace],0
hitblock_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 4

; UpdateEnemies: update all six enemy records. Preserves registers.
UpdateEnemies:
    push cx
    push si
    mov si,entities
    mov cx,6
updateenemies_loop:
    push si
    call UpdateEntity
    add si,entity_size
    dec cx
    jnz updateenemies_loop
    call EnemyPairs
    pop si
    pop cx
    ret

; UpdateItems: move active mushroom records. Preserves registers.
UpdateItems:
    push cx
    push si
    mov si,entities+6*entity_size
    mov cx,2
updateitems_loop:
    push si
    call UpdateEntity
    add si,entity_size
    dec cx
    jnz updateitems_loop
    pop si
    pop cx
    ret

; UpdateEntity(address): activate, move, collide with tiles, remove or expire.
; Input record address on stack; outputs updated record; preserves registers.
UpdateEntity:
    push bp
    mov bp,sp
    push ax
    push bx
    push dx
    push si
    mov si,[bp+4]
    cmp byte [si+ent_state],0
    jne gamebranch8
    jmp near updateentity_done
gamebranch8:
    mov ax,[si+ent_x+1]
    mov bx,[camera_x]
    sub bx,32
    cmp ax,bx
    jge gamebranch9
    jmp near updateentity_remove
gamebranch9:
    cmp byte [si+ent_state],1
    jne updateentity_active
    mov bx,[camera_x]
    add bx,336
    cmp ax,bx
    jle gamebranch10
    jmp near updateentity_done
gamebranch10:
    mov byte [si+ent_state],2
updateentity_active:
    cmp byte [si+ent_grace],0
    je updateentity_flat
    dec byte [si+ent_grace]
updateentity_flat:
    cmp byte [si+ent_state],3
    jne updateentity_move
    dec byte [si+ent_timer]
    jz gamebranch11
    jmp near updateentity_done
gamebranch11:
    jmp updateentity_remove
updateentity_move:
    ; Koopa turns at a ledge when walking on ground.
    cmp byte [si+ent_type],2
    je gamebranch12
    jmp near updateentity_x
gamebranch12:
    cmp byte [si+ent_state],2
    jne updateentity_x
    cmp word [si+ent_vy],0
    jne updateentity_x
    mov ax,[si+ent_x+1]
    cmp word [si+ent_vx],0
    jl updateentity_ledge_left
    add ax,16
    jmp updateentity_ledge_check
updateentity_ledge_left:
    dec ax
updateentity_ledge_check:
    mov bx,[si+ent_y+1]
    add bx,16
    push bx
    push ax
    call SolidAt
    cmp ax,0
    jne updateentity_x
    neg word [si+ent_vx]
updateentity_x:
    mov ax,[si+ent_vx]
    cmp ax,0
    jne gamebranch13
    jmp near updateentity_y
gamebranch13:
    cwd
    add [si+ent_x],ax
    adc [si+ent_x+2],dx
    mov ax,[si+ent_x+1]
    cmp ax,0
    jl updateentity_bounce
    cmp ax,944
    jg updateentity_bounce
    cmp word [si+ent_vx],0
    jl updateentity_side
    add ax,15
updateentity_side:
    mov bx,ax
    push word [si+ent_y+1]
    push bx
    call SolidAt
    cmp ax,0
    jne updateentity_bounce
    mov ax,[si+ent_y+1]
    add ax,15
    push ax
    push bx
    call SolidAt
    cmp ax,0
    je updateentity_y
updateentity_bounce:
    ; Undo horizontal movement, then reverse velocity.
    mov ax,[si+ent_vx]
    cwd
    sub [si+ent_x],ax
    sbb [si+ent_x+2],dx
    neg word [si+ent_vx]
updateentity_y:
    add word [si+ent_vy],0x40
    cmp word [si+ent_vy],0x400
    jle updateentity_fall
    mov word [si+ent_vy],0x400
updateentity_fall:
    mov ax,[si+ent_vy]
    cwd
    add [si+ent_y],ax
    adc [si+ent_y+2],dx
    mov bx,[si+ent_y+1]
    cmp bx,192
    jl gamebranch14
    jmp near updateentity_remove
gamebranch14:
    add bx,15
    push bx
    push word [si+ent_x+1]
    call SolidAt
    cmp ax,0
    jne updateentity_land
    mov ax,[si+ent_x+1]
    add ax,15
    push bx
    push ax
    call SolidAt
    cmp ax,0
    je updateentity_done
updateentity_land:
    and bx,0xfff0
    sub bx,16
    mov word [si+ent_y],0
    mov [si+ent_y+1],bx
    mov byte [si+ent_y+3],0
    mov word [si+ent_vy],0
    jmp updateentity_done
updateentity_remove:
    mov byte [si+ent_state],0
updateentity_done:
    pop si
    pop dx
    pop bx
    pop ax
    pop bp
    ret 2

; EntityOverlap(a,b): 16x16 rectangle test, AX=1 if intersecting.
; Both record addresses passed on stack; other registers preserved.
EntityOverlap:
    push bp
    mov bp,sp
    push bx
    push si
    push di
    mov si,[bp+4]
    mov di,[bp+6]
    mov ax,[si+ent_x+1]
    add ax,16
    cmp ax,[di+ent_x+1]
    jle entityoverlap_no
    mov ax,[di+ent_x+1]
    add ax,16
    cmp ax,[si+ent_x+1]
    jle entityoverlap_no
    mov ax,[si+ent_y+1]
    add ax,16
    cmp ax,[di+ent_y+1]
    jle entityoverlap_no
    mov ax,[di+ent_y+1]
    add ax,16
    cmp ax,[si+ent_y+1]
    jle entityoverlap_no
    mov ax,1
    jmp entityoverlap_done
entityoverlap_no:
    xor ax,ax
entityoverlap_done:
    pop di
    pop si
    pop bx
    pop bp
    ret 4

; EnemyPairs: shells defeat walking enemies; walking enemies turn apart.
; Inputs entity table; outputs states/score/velocities; preserves registers.
EnemyPairs:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov si,entities
    mov cx,6
enemypairs_outer:
    mov di,si
    add di,entity_size
    mov dx,cx
    dec dx
    jnz gamebranch15
    jmp near enemypairs_next
gamebranch15:
enemypairs_inner:
    cmp byte [si+ent_state],5
    jne enemypairs_second_shell
    cmp byte [di+ent_state],2
    je gamebranch16
    jmp near enemypairs_advance
gamebranch16:
    push di
    push si
    call EntityOverlap
    cmp ax,0
    jne gamebranch17
    jmp near enemypairs_advance
gamebranch17:
    mov byte [di+ent_state],0
    mov ax,500
    push ax
    call AddScore
    jmp enemypairs_advance
enemypairs_second_shell:
    cmp byte [di+ent_state],5
    jne enemypairs_walkers
    cmp byte [si+ent_state],2
    je gamebranch18
    jmp near enemypairs_advance
gamebranch18:
    push di
    push si
    call EntityOverlap
    cmp ax,0
    jne gamebranch19
    jmp near enemypairs_advance
gamebranch19:
    mov byte [si+ent_state],0
    mov ax,500
    push ax
    call AddScore
    jmp enemypairs_advance
enemypairs_walkers:
    cmp byte [si+ent_state],2
    je gamebranch20
    jmp near enemypairs_advance
gamebranch20:
    cmp byte [di+ent_state],2
    je gamebranch21
    jmp near enemypairs_advance
gamebranch21:
    push di
    push si
    call EntityOverlap
    cmp ax,0
    je enemypairs_advance
    mov ax,[si+ent_x+1]
    cmp ax,[di+ent_x+1]
    jle enemypairs_left_first
    cmp word [si+ent_vx],0
    jge enemypairs_right_second
    neg word [si+ent_vx]
enemypairs_right_second:
    cmp word [di+ent_vx],0
    jle enemypairs_advance
    neg word [di+ent_vx]
    jmp enemypairs_advance
enemypairs_left_first:
    cmp word [si+ent_vx],0
    jle enemypairs_left_second
    neg word [si+ent_vx]
enemypairs_left_second:
    cmp word [di+ent_vx],0
    jge enemypairs_advance
    neg word [di+ent_vx]
enemypairs_advance:
    add di,entity_size
    dec dx
    jz gamebranch22
    jmp near enemypairs_inner
gamebranch22:
enemypairs_next:
    add si,entity_size
    dec cx
    jz gamebranch23
    jmp near enemypairs_outer
gamebranch23:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; HeroOverlap(address): AX=1 if player hitbox overlaps record. Other registers preserved.
HeroOverlap:
    push bp
    mov bp,sp
    push si
    mov si,[bp+4]
    mov ax,[si+ent_x+1]
    cmp ax,[player_right]
    jg herooverlap_no
    add ax,15
    cmp ax,[player_left]
    jl herooverlap_no
    mov ax,[si+ent_y+1]
    cmp ax,[player_bottom]
    jg herooverlap_no
    add ax,15
    cmp ax,[player_top]
    jl herooverlap_no
    mov ax,1
    jmp herooverlap_done
herooverlap_no:
    xor ax,ax
herooverlap_done:
    pop si
    pop bp
    ret 2

; CheckCollisions: handle enemies, items, map coins, flag. Preserves registers.
CheckCollisions:
    push ax
    push bx
    push cx
    push si
    cmp byte [death_request],0
    je gamebranch24
    jmp near checkcollisions_done
gamebranch24:
    call PlayerBounds
    mov si,entities
    mov cx,entity_count
checkcollisions_loop:
    cmp byte [si+ent_state],2
    jae gamebranch25
    jmp near checkcollisions_next
gamebranch25:
    cmp byte [si+ent_state],3
    jne gamebranch26
    jmp near checkcollisions_next
gamebranch26:
    push si
    call HeroOverlap
    cmp ax,0
    jne gamebranch27
    jmp near checkcollisions_next
gamebranch27:
    cmp byte [si+ent_type],3
    jne checkcollisions_shell
    mov byte [si+ent_state],0
    call CollectMushroom
    jmp checkcollisions_next
checkcollisions_shell:
    cmp byte [si+ent_state],4
    jne checkcollisions_grace
    push si
    call KickShell
    jmp checkcollisions_next
checkcollisions_grace:
    cmp byte [si+ent_grace],0
    jne checkcollisions_next
    cmp word [velocity_y],0
    jle checkcollisions_hurt
    mov ax,[si+ent_y+1]
    add ax,8
    cmp [previous_feet],ax
    jg checkcollisions_hurt
    push si
    call StompEnemy
    jmp checkcollisions_next
checkcollisions_hurt:
    call MarioTakeDamage
    cmp byte [death_request],0
    jne checkcollisions_done
checkcollisions_next:
    add si,entity_size
    dec cx
    jz gamebranch28
    jmp near checkcollisions_loop
gamebranch28:
    call CollectMapCoins
    call CheckFlag
checkcollisions_done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; KickShell(address): start shell sliding away from hero, score +400.
; Inputs record pointer; outputs shell state; preserves registers.
KickShell:
    push bp
    mov bp,sp
    push ax
    push si
    mov si,[bp+4]
    mov byte [si+ent_state],5
    mov byte [si+ent_grace],8
    mov ax,[mario_x+1]
    cmp ax,[si+ent_x+1]
    jle kickshell_right
    mov word [si+ent_vx],-0x300
    jmp kickshell_score
kickshell_right:
    mov word [si+ent_vx],0x300
kickshell_score:
    mov ax,400
    push ax
    call AddScore
    pop si
    pop ax
    pop bp
    ret 2

; StompEnemy(address): flatten Goomba or stop Koopa/shell, bounce, score chain.
; Input record pointer; output shared hero and entity state; preserves registers.
StompEnemy:
    push bp
    mov bp,sp
    push ax
    push bx
    push si
    mov si,[bp+4]
    mov word [si+ent_vx],0
    cmp byte [si+ent_type],1
    jne stompenemy_shell
    mov byte [si+ent_state],3
    mov byte [si+ent_timer],30
    jmp stompenemy_bounce
stompenemy_shell:
    mov byte [si+ent_state],4
stompenemy_bounce:
    mov ax,[si+ent_y+1]
    sub ax,[hero_height]
    cmp ax,16
    jge stompenemy_position
    mov ax,16
stompenemy_position:
    mov word [mario_y],0
    mov [mario_y+1],ax
    mov byte [mario_y+3],0
    mov word [velocity_y],-0x300
    cmp byte [keys_held+key_space],0
    je stompenemy_chain
    mov word [velocity_y],-0x480
stompenemy_chain:
    mov byte [on_ground],0
    cmp byte [stomp_chain],10
    jae stompenemy_life
    xor bx,bx
    mov bl,[stomp_chain]
    shl bx,1
    push word [stomp_points+bx]
    call AddScore
    inc byte [stomp_chain]
    jmp stompenemy_done
stompenemy_life:
    call AddLife
stompenemy_done:
    call PlayerBounds
    pop si
    pop bx
    pop ax
    pop bp
    ret 2

; MarioTakeDamage: shrink Super, or request death when Small. Preserves registers.
MarioTakeDamage:
    cmp word [invuln_timer],0
    jne mariodamage_done
    cmp byte [hp],2
    jne mariodamage_die
    mov byte [hp],1
    mov byte [form],0
    add word [mario_y],0x1000
    adc word [mario_y+2],0
    mov word [invuln_timer],60
    call PlayerBounds
    jmp mariodamage_done
mariodamage_die:
    mov byte [death_request],1
mariodamage_done:
    ret

; CollectMushroom: +1000 and grow with feet fixed. Preserves registers.
CollectMushroom:
    push ax
    mov ax,1000
    push ax
    call AddScore
    cmp byte [hp],2
    je collectmushroom_done
    mov byte [hp],2
    mov byte [form],1
    sub word [mario_y],0x1000
    sbb word [mario_y+2],0
    call PlayerBounds
collectmushroom_done:
    pop ax
    ret

; CollectMapCoins: examine map cells overlapped by the player rectangle.
; Inputs current bounds; outputs working map and score; preserves registers.
CollectMapCoins:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov cl,4
    mov ax,[player_top]
    cmp ax,0
    jge collectmapcoins_top
    xor ax,ax
collectmapcoins_top:
    shr ax,cl
    mov si,ax
    mov ax,[player_bottom]
    cmp ax,191
    jle collectmapcoins_bottom
    mov ax,191
collectmapcoins_bottom:
    shr ax,cl
    mov di,ax
    mov ax,[player_left]
    shr ax,cl
    mov [coin_first_col],ax
    mov ax,[player_right]
    shr ax,cl
    mov [coin_last_col],ax
collectmapcoins_row:
    cmp si,di
    jle gamebranch29
    jmp near collectmapcoins_done
gamebranch29:
    mov ax,si
    mov dx,60
    mul dx
    mov bx,[coin_first_col]
collectmapcoins_col:
    cmp bx,[coin_last_col]
    jg collectmapcoins_nextrow
    cmp bx,60
    jae collectmapcoins_nextrow
    push bx
    add bx,ax
    cmp byte [working_map+bx],tile_coin
    jne collectmapcoins_skip
    mov byte [working_map+bx],0
    call CollectCoin
collectmapcoins_skip:
    pop bx
    inc bx
    jmp collectmapcoins_col
collectmapcoins_nextrow:
    inc si
    jmp collectmapcoins_row
collectmapcoins_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; CheckFlag: contact with pole column requests win and height bonus.
; Inputs player bounds; outputs win request, flag points, position; preserves registers.
CheckFlag:
    push ax
    mov ax,[player_right]
    inc ax
    cmp ax,912
    jge gamebranch30
    jmp near checkflag_done
gamebranch30:
    cmp word [player_left],928
    jl gamebranch31
    jmp near checkflag_done
gamebranch31:
    cmp word [player_top],144
    jl gamebranch32
    jmp near checkflag_done
gamebranch32:
    cmp word [player_bottom],32
    jge gamebranch33
    jmp near checkflag_done
gamebranch33:
    mov ax,[player_bottom]
    inc ax
    cmp ax,64
    jl checkflag_high
    cmp ax,80
    jl checkflag_second
    cmp ax,96
    jl checkflag_third
    cmp ax,128
    jl checkflag_fourth
    mov word [flag_points],100
    jmp checkflag_win
checkflag_high:
    mov word [flag_points],5000
    jmp checkflag_win
checkflag_second:
    mov word [flag_points],2000
    jmp checkflag_win
checkflag_third:
    mov word [flag_points],800
    jmp checkflag_win
checkflag_fourth:
    mov word [flag_points],400
checkflag_win:
    mov byte [win_request],1
    mov word [mario_x],0x9000
    mov word [mario_x+2],3
    mov word [camera_x],640
checkflag_done:
    pop ax
    ret

; DrawEntities: choose sprite based on actual entity record state and type.
; Inputs entity table and camera; outputs frame buffer; preserves registers.
DrawEntities:
    push ax
    push bx
    push cx
    push si
    mov si,entities
    mov cx,entity_count
drawentities_loop:
    cmp byte [si+ent_state],2
    jae gamebranch34
    jmp near drawentities_next
gamebranch34:
    mov bx,goomba_walk_sprite
    cmp byte [si+ent_type],3
    jne drawentities_enemy
    mov bx,mushroom_sprite
    jmp drawentities_render
drawentities_enemy:
    cmp byte [si+ent_state],3
    jne drawentities_shell
    mov bx,goomba_flat_sprite
    jmp drawentities_render
drawentities_shell:
    cmp byte [si+ent_state],4
    jb drawentities_walker
    mov bx,shell_sprite
    jmp drawentities_render
drawentities_walker:
    cmp byte [si+ent_type],2
    jne drawentities_render
    mov bx,koopa_sprite
drawentities_render:
    xor ax,ax
    cmp word [si+ent_vx],0
    jge drawentities_direction
    inc ax
drawentities_direction:
    push ax
    push bx
    push word [si+ent_y+1]
    push word [si+ent_x+1]
    call DrawWorldSprite
drawentities_next:
    add si,entity_size
    dec cx
    jz gamebranch35
    jmp near drawentities_loop
gamebranch35:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; DrawWorldSprite(world_x,y,address,flags): convert world x to screen x and draw.
DrawWorldSprite:
    push bp
    mov bp,sp
    push ax
    mov ax,[bp+4]
    sub ax,[camera_x]
    cmp ax,-16
    jl drawworldsprite_done
    cmp ax,screen_w
    jge drawworldsprite_done
    push word [bp+10]
    push word [bp+8]
    push word [bp+6]
    push ax
    call DrawSprite
drawworldsprite_done:
    pop ax
    pop bp
    ret 8
; DrawHUD: score, coins, world, clock, lives and health in fixed top strip.
; No explicit parameters; reads shared counters; preserves registers.
DrawHUD:
    push ax
    xor ax,ax
    push ax
    mov ax,16
    push ax
    mov ax,320
    push ax
    xor ax,ax
    push ax
    push ax
    call FillRect
    call MenuScore
    mov ax,15
    push ax
    mov ax,hud_score
    push ax
    mov ax,0
    push ax
    mov ax,2
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_coins
    push ax
    mov ax,0
    push ax
    mov ax,64
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_world
    push ax
    mov ax,0
    push ax
    mov ax,122
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_time
    push ax
    mov ax,0
    push ax
    mov ax,182
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_lives
    push ax
    mov ax,0
    push ax
    mov ax,230
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_hp
    push ax
    mov ax,0
    push ax
    mov ax,272
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_score_digits
    push ax
    mov ax,8
    push ax
    mov ax,2
    push ax
    call MenuText
    mov ax,menu_coins_digits
    push ax
    xor ax,ax
    mov al,[coins]
    push ax
    call MenuNumber
    mov ax,15
    push ax
    mov ax,menu_coins_digits+1
    push ax
    mov ax,8
    push ax
    mov ax,76
    push ax
    call MenuText
    mov ax,menu_time_digits
    push ax
    push word [time_left]
    call MenuNumber
    mov ax,15
    cmp word [time_left],30
    ja bonus_hurry_colour
    mov ax,12
    test word [ticks],8
    jz bonus_hurry_colour
    xor ax,ax
bonus_hurry_colour:
    push ax
    mov ax,menu_time_digits
    push ax
    mov ax,8
    push ax
    mov ax,182
    push ax
    call MenuText
    mov ax,menu_lives_digits
    push ax
    xor ax,ax
    mov al,[lives]
    push ax
    call MenuNumber
    mov ax,15
    push ax
    mov ax,menu_lives_digits+1
    push ax
    mov ax,8
    push ax
    mov ax,242
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_x
    push ax
    mov ax,8
    push ax
    mov ax,64
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_world_value
    push ax
    mov ax,8
    push ax
    mov ax,122
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,hud_x
    push ax
    mov ax,8
    push ax
    mov ax,230
    push ax
    call MenuText
    xor ax,ax
    push ax
    mov ax,heart_full_sprite
    push ax
    mov ax,8
    push ax
    mov ax,276
    push ax
    call DrawSprite
    xor ax,ax
    push ax
    mov ax,heart_empty_sprite
    cmp byte [hp],2
    jne hud_second_heart
    mov ax,heart_full_sprite
hud_second_heart:
    push ax
    mov ax,8
    push ax
    mov ax,288
    push ax
    call DrawSprite
    pop ax
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

AddScore:
    push bp
    mov bp,sp
    push ax
    mov ax,[bp+4]
    add [score_low],ax
    adc word [score_high],0
    cmp word [score_high],0x000f
    jb addscore_done
    ja addscore_clamp
    cmp word [score_low],0x423f
    jbe addscore_done
addscore_clamp:
    mov word [score_high],0x000f
    mov word [score_low],0x423f
addscore_done:
    cmp byte [game_state],playing
    jne bonus_score_done
    push word [bp+4]
    call BonusScoreEvent
bonus_score_done:
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
    mov ax,14
    push ax
    mov ax,menu_title
    push ax
    mov ax,24
    push ax
    mov ax,106
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_start
    push ax
    mov ax,71
    push ax
    mov ax,130
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_exit
    push ax
    mov ax,121
    push ax
    mov ax,148
    push ax
    call MenuText
    mov ax,7
    push ax
    mov ax,menu_help
    push ax
    mov ax,165
    push ax
    mov ax,85
    push ax
    call MenuText
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
    mov ax,0
    push ax
    mov ax,menu_pause
    push ax
    mov ax,93
    push ax
    mov ax,142
    push ax
    call MenuText
    mov ax,0
    push ax
    mov ax,menu_resume
    push ax
    mov ax,106
    push ax
    mov ax,127
    push ax
    call MenuText
    call PresentBuffer
    pop ax
    ret
DrawLifeLost:
    push ax
    mov ax,4
    push ax
    call ClearBuffer
    mov ax,15
    push ax
    mov ax,menu_world
    push ax
    mov ax,65
    push ax
    mov ax,133
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_lives
    push ax
    mov ax,94
    push ax
    mov ax,112
    push ax
    call MenuText
    mov ax,menu_lives_digits
    push ax
    xor ax,ax
    mov al,[lives]
    push ax
    call MenuNumber
    mov ax,15
    push ax
    mov ax,menu_lives_digits
    push ax
    mov ax,94
    push ax
    mov ax,184
    push ax
    call MenuText
    call PresentBuffer
    pop ax
    ret
DrawComplete:
    push ax
    push bx
    push cx
    push dx
    push di
    mov ax,2
    push ax
    call ClearBuffer
    mov ax,14
    push ax
    mov ax,menu_complete
    push ax
    mov ax,35
    push ax
    mov ax,118
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_score_label
    push ax
    mov ax,65
    push ax
    mov ax,100
    push ax
    call MenuText
    call MenuScore
    mov ax,15
    push ax
    mov ax,menu_score_digits
    push ax
    mov ax,65
    push ax
    mov ax,154
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_coins
    push ax
    mov ax,85
    push ax
    mov ax,100
    push ax
    call MenuText
    mov ax,menu_coins_digits
    push ax
    xor ax,ax
    mov al,[coins]
    push ax
    call MenuNumber
    mov ax,15
    push ax
    mov ax,menu_coins_digits
    push ax
    mov ax,85
    push ax
    mov ax,154
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_time
    push ax
    mov ax,105
    push ax
    mov ax,100
    push ax
    call MenuText
    mov ax,menu_time_digits
    push ax
    xor ax,ax
    mov ax,[time_left]
    push ax
    call MenuNumber
    mov ax,15
    push ax
    mov ax,menu_time_digits
    push ax
    mov ax,105
    push ax
    mov ax,166
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_bonus
    push ax
    mov ax,125
    push ax
    mov ax,100
    push ax
    call MenuText
    mov ax,[time_left]
    mov bx,50
    mul bx
    mov di,menu_bonus_digits+4
    mov bx,10
    mov cx,5
menubonus_loop:
    xor dx,dx
    div bx
    add dl,48
    mov [di],dl
    dec di
    loop menubonus_loop
    mov ax,15
    push ax
    mov ax,menu_bonus_digits
    push ax
    mov ax,125
    push ax
    mov ax,172
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_continue
    push ax
    mov ax,165
    push ax
    mov ax,115
    push ax
    call MenuText
    call PresentBuffer
    pop di
    pop dx
    pop cx
    pop bx
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
    mov ax,12
    push ax
    mov ax,menu_over
    push ax
    mov ax,60
    push ax
    mov ax,133
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_final
    push ax
    mov ax,95
    push ax
    mov ax,100
    push ax
    call MenuText
    call MenuScore
    mov ax,15
    push ax
    mov ax,menu_score_digits
    push ax
    mov ax,95
    push ax
    mov ax,178
    push ax
    call MenuText
    mov ax,15
    push ax
    mov ax,menu_return
    push ax
    mov ax,150
    push ax
    mov ax,115
    push ax
    call MenuText
    call PresentBuffer
    pop ax
    ret
DrawWinWorld:
    push ax
    mov ax,9
    push ax
    call ClearBuffer
    call DrawMap
    call DrawEntities
    call DrawHUD
    call PresentBuffer
    pop ax
    ret

; MenuText(x,y,address,colour): draw zero-terminated uppercase text into buffer.
; Inputs: four stack words. Outputs: none. Preserves all registers.
MenuText:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov es,[framebuffer_seg]
    mov ax,[bp+6]
    mov bx,320
    mul bx
    add ax,[bp+4]
    mov di,ax
    mov si,[bp+8]
menutext_char:
    mov al,[si]
    cmp al,0
    je menutext_done
    inc si
    cmp al,32
    jb menutext_skip
    cmp al,90
    ja menutext_skip
    sub al,32
    xor ah,ah
    mov bx,7
    mul bx
    mov bx,ax
    add bx,menu_font
    push di
    mov cx,7
menutext_row:
    push cx
    mov dl,[bx]
    mov dh,0x10
    mov cx,5
menutext_pixel:
    test dl,dh
    jz menutext_blank
    mov al,[bp+10]
    mov [es:di],al
menutext_blank:
    inc di
    shr dh,1
    loop menutext_pixel
    add di,315
    inc bx
    pop cx
    loop menutext_row
    pop di
menutext_skip:
    add di,6
    jmp menutext_char
menutext_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 8

; MenuNumber(value,address): write unsigned word as three decimal digits.
; Inputs: two stack words. Outputs: destination string. Preserves registers.
MenuNumber:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push di
    mov ax,[bp+4]
    mov di,[bp+6]
    add di,2
    mov bx,10
    mov cx,3
menunumber_loop:
    xor dx,dx
    div bx
    add dl,48
    mov [di],dl
    dec di
    loop menunumber_loop
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 4

; MenuScore: convert two-word score to six decimal digits using word division.
; Inputs: shared score. Output: menu_score_digits. Preserves registers.
MenuScore:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov si,[score_high]
    mov ax,[score_low]
    mov di,menu_score_digits+5
    mov bx,10
    mov cx,6
menuscore_loop:
    push ax
    mov ax,si
    xor dx,dx
    div bx
    mov si,ax
    pop ax
    div bx
    add dl,48
    mov [di],dl
    dec di
    loop menuscore_loop
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; GRAPHICS PROCEDURES - adapted from graphics.asm
; ResetMap: copy original_map over working_map (720 bytes).
; No inputs/outputs; preserves registers.
ResetMap:
    push cx
    push si
    push di
    push es
    push cs
    pop es
    mov si,original_map
    mov di,working_map
    mov cx,map_w*map_h
    cld
    rep movsb
    pop es
    pop di
    pop si
    pop cx
    ret

; PutPixel(x,y,colour): plot one pixel in framebuffer_seg.
; x,y are screen coordinates; anything outside 320x200 is ignored.
; Preserves registers.
PutPixel:
    push bp
    mov bp,sp
    push ax
    push bx
    push dx
    push cx
    push di
    push es
    mov ax,[bp+6]
    cmp ax,screen_h         ; unsigned compare also rejects negatives
    jae putpixel_done
    mov bx,[bp+4]
    cmp bx,screen_w
    jae putpixel_done
    mov dx,ax
    mov cl,8
    shl ax,cl
    mov cl,6
    shl dx,cl
    add ax,dx
    add ax,bx
    mov di,ax
    mov es,[framebuffer_seg]
    mov al,[bp+8]
    mov [es:di],al
putpixel_done:
    pop es
    pop di
    pop cx
    pop dx
    pop bx
    pop ax
    pop bp
    ret 6

; FillRect(x,y,w,h,colour): filled rectangle, clipped to the screen.
; x,y signed; w,h positive. Preserves registers.
FillRect:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov si,[bp+4]           ; si = left edge
    mov bx,si
    add bx,[bp+8]           ; bx = right edge (exclusive)
    cmp si,0
    jge fillrect_left_ok
    xor si,si
fillrect_left_ok:
    cmp bx,screen_w
    jle fillrect_right_ok
    mov bx,screen_w
fillrect_right_ok:
    sub bx,si               ; bx = visible width
    jle fillrect_done
    mov ax,[bp+6]           ; ax = top edge
    mov dx,ax
    add dx,[bp+10]          ; dx = bottom edge (exclusive)
    cmp ax,0
    jge fillrect_top_ok
    xor ax,ax
fillrect_top_ok:
    cmp dx,screen_h
    jle fillrect_bottom_ok
    mov dx,screen_h
fillrect_bottom_ok:
    sub dx,ax               ; dx = visible height
    jle fillrect_done
    push dx
    mov cx,screen_w
    mul cx                  ; ax = top*320 (dx destroyed)
    pop dx
    add ax,si
    mov di,ax
    mov es,[framebuffer_seg]
    mov al,[bp+12]
    cld
fillrect_row:
    mov cx,bx
    rep stosb
    add di,screen_w
    sub di,bx
    dec dx
    jnz fillrect_row
fillrect_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10

; DrawTile(x,y,tile): draw one 16x16 tile at screen position x,y.
; Each tile is a list of boxes (dx,dy,w,h,colour) ending in 0xff.
; Tile 0 and unknown codes draw nothing. Preserves registers.
DrawTile:
    push bp
    mov bp,sp
    push ax
    push bx
    push si
    mov bx,[bp+8]
    cmp bx,tile_count
    jae drawtile_done
    shl bx,1
    mov si,[tile_table+bx]
drawtile_box:
    cmp byte [si],0xff
    je drawtile_done
    xor ax,ax
    mov al,[si+4]
    push ax                 ; colour
    mov al,[si+3]
    push ax                 ; h
    mov al,[si+2]
    push ax                 ; w
    mov al,[si+1]           ; ah is still 0 here
    add ax,[bp+6]
    push ax                 ; y
    xor ax,ax
    mov al,[si]
    add ax,[bp+4]
    push ax                 ; x
    call FillRect
    add si,5
    jmp drawtile_box
drawtile_done:
    pop si
    pop bx
    pop ax
    pop bp
    ret 6

; GetTile(px,py): return AX = tile code at whole-world pixel px,py.
; Returns 0 outside the 960x192 map. Other registers preserved.
GetTile:
    push bp
    mov bp,sp
    push bx
    push cx
    push dx
    mov bx,[bp+4]
    cmp bx,map_w*tile_size  ; unsigned: negative x counts as outside
    jae gettile_outside
    mov ax,[bp+6]
    cmp ax,map_h*tile_size
    jae gettile_outside
    mov cl,4
    shr bx,cl               ; column
    shr ax,cl               ; row
    mov dx,map_w
    mul dx                  ; ax = row*60
    add bx,ax
    mov al,[working_map+bx]
    xor ah,ah
    jmp gettile_done
gettile_outside:
    xor ax,ax
gettile_done:
    pop dx
    pop cx
    pop bx
    pop bp
    ret 4

; DrawSprite(x,y,address,flags): draw a sprite (byte width, byte height,
; then row-major palette bytes). Palette byte 0 is transparent.
; flags bit 0 = mirror horizontally. Clipped by PutPixel. Preserves registers.
DrawSprite:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push si
    mov si,[bp+8]
    xor ax,ax
    mov al,[si]
    mov [sprite_w],ax
    mov al,[si+1]
    mov [sprite_h],ax
    add si,2                ; si = first pixel row
    xor dx,dx               ; dx = row
drawsprite_row:
    cmp dx,[sprite_h]
    jae drawsprite_done
    xor cx,cx               ; cx = column
drawsprite_col:
    cmp cx,[sprite_w]
    jae drawsprite_nextrow
    mov bx,cx
    test word [bp+10],1
    jz drawsprite_read
    mov bx,[sprite_w]       ; mirrored: read from the right edge
    dec bx
    sub bx,cx
drawsprite_read:
    mov al,[si+bx]
    cmp al,tt
    je drawsprite_skip
    xor ah,ah
    push ax                 ; colour
    mov ax,[bp+6]
    add ax,dx
    push ax                 ; y
    mov ax,[bp+4]
    add ax,cx
    push ax                 ; x
    call PutPixel
drawsprite_skip:
    inc cx
    jmp drawsprite_col
drawsprite_nextrow:
    add si,[sprite_w]
    inc dx
    jmp drawsprite_row
drawsprite_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 8

; DrawMap: draw the visible part of working_map using camera_x.
; Only the 21 columns that can be seen are drawn. Preserves registers.
DrawMap:
    push ax
    push bx
    push cx
    push si
    mov si,[camera_x]
    mov cl,4
    shr si,cl               ; si = first visible column
    mov bx,si
    add bx,21
    mov [map_end_col],bx
drawmap_col:
    cmp si,[map_end_col]
    jae drawmap_done
    cmp si,map_w
    jae drawmap_done
    mov bx,si               ; bx = map index of row 0
    xor cx,cx               ; cx = row
drawmap_row:
    cmp cx,map_h
    jae drawmap_nextcol
    xor ax,ax
    mov al,[working_map+bx]
    cmp al,tile_empty
    je drawmap_skip
    push ax                 ; tile
    mov ax,cx
    shl ax,1
    shl ax,1
    shl ax,1
    shl ax,1
    push ax                 ; y = row*16
    mov ax,si
    shl ax,1
    shl ax,1
    shl ax,1
    shl ax,1
    sub ax,[camera_x]
    push ax                 ; x = col*16 - camera_x
    call DrawTile
drawmap_skip:
    add bx,map_w
    inc cx
    jmp drawmap_row
drawmap_nextcol:
    inc si
    jmp drawmap_col
drawmap_done:
    xor ax,ax
    push ax
    mov ax,8
    push ax
    mov ax,320
    push ax
    mov ax,192
    push ax
    xor ax,ax
    push ax
    call FillRect
    xor ax,ax
    push ax
    mov ax,16
    push ax
    mov ax,320
    push ax
    xor ax,ax
    push ax
    push ax
    call FillRect
    pop si
    pop cx
    pop bx
    pop ax
    ret

; DrawHeroPiece(address): private helper. Draws one 16-wide sprite piece at
; hero_screen_x, hero_screen_y+hero_piece_dy, mirrored when facing left.
DrawHeroPiece:
    push bp
    mov bp,sp
    push ax
    xor ax,ax
    mov al,[facing]
    push ax                 ; flags (bit 0 = mirror)
    push word [bp+4]        ; address
    mov ax,[hero_screen_y]
    add ax,[hero_piece_dy]
    push ax                 ; y
    push word [hero_screen_x]
    call DrawSprite
    pop ax
    pop bp
    ret 2

; DrawHero: draw hero from mario_x, mario_y (24.8 fixed), camera_x, form,
; facing and pose. y is the sprite top. Small = 16 tall, big = 32 tall.
; Blinks while invuln_timer is non-zero. Preserves registers.
DrawHero:
    push ax
    push cx
    cmp word [invuln_timer],0
    je drawhero_visible
    test word [ticks],1
    jz drawhero_visible
    jmp near drawhero_done
drawhero_visible:
    mov ax,[mario_x]        ; integer pixel = 32-bit value >> 8
    mov al,ah
    mov ah,[mario_x+2]
    sub ax,[camera_x]
    mov [hero_screen_x],ax
    mov ax,[mario_y]
    mov al,ah
    mov ah,[mario_y+2]
    mov [hero_screen_y],ax
    mov word [hero_piece_dy],0
    mov ax,hero_head
    push ax
    call DrawHeroPiece
    mov word [hero_piece_dy],8
    mov ax,hero_body
    cmp byte [form],0
    je drawhero_body
    mov ax,super_body
 drawhero_body:
    push ax
    call DrawHeroPiece
    mov word [hero_piece_dy],12
    cmp byte [form],0
    je drawhero_select_legs
    mov word [hero_piece_dy],20
 drawhero_select_legs:
    mov ax,hero_legs_stand
    cmp byte [pose],1
    jne drawhero_check_jump
    test word [ticks],8     ; alternate run/stand every 8 ticks
    jz drawhero_legs
    mov ax,hero_legs_run
    jmp drawhero_legs
drawhero_check_jump:
    cmp byte [pose],2
    jne drawhero_legs
    mov ax,hero_legs_jump
drawhero_legs:
    cmp byte [form],0
    je drawhero_render_legs
    cmp ax,hero_legs_run
    je drawhero_super_run
    cmp ax,hero_legs_jump
    je drawhero_super_jump
    mov ax,super_legs_stand
    jmp drawhero_render_legs
 drawhero_super_run:
    mov ax,super_legs_run
    jmp drawhero_render_legs
 drawhero_super_jump:
    mov ax,super_legs_jump
 drawhero_render_legs:
    push ax
    call DrawHeroPiece
drawhero_done:
    pop cx
    pop ax
    ret

; UpdateCamera: follow the hero to the right only (classic scrolling).
; Camera is clamped to 0..cam_max. Preserves registers.
; For a camera that also follows leftwards, delete the "cmp ax,[camera_x]" test.
UpdateCamera:
    push ax
    mov ax,[mario_x]
    mov al,ah
    mov ah,[mario_x+2]
    sub ax,cam_center
    jge updatecamera_high
    xor ax,ax
updatecamera_high:
    cmp ax,cam_max
    jle updatecamera_compare
    mov ax,cam_max
updatecamera_compare:
    cmp ax,[camera_x]
    jle updatecamera_done
    mov [camera_x],ax
updatecamera_done:
    mov ax,[mario_x]
    mov al,ah
    mov ah,[mario_x+2]
    cmp ax,[camera_x]
    jge updatecamera_return
    mov ax,[camera_x]
    mov [mario_x+2],ah
    mov byte [mario_x+3],0
    mov ah,al
    xor al,al
    mov [mario_x],ax
    mov word [velocity_x],0
updatecamera_return:
    pop ax
    ret


; MAIN ENTRY AND STACK
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


; Menu text and bitmap data.
demo_time_label: db 'TIME',0
menu_title: db 'SUPER MARIO ENGINE',0
menu_start: db 'START GAME',0
menu_exit: db 'EXIT',0
menu_help: db 'UP DOWN - ENTER TO SELECT',0
menu_pause: db 'PAUSED',0
menu_resume: db 'P TO RESUME',0
menu_world: db 'WORLD 1-1',0
menu_lives: db 'LIVES LEFT:',0
menu_complete: db 'LEVEL COMPLETE',0
menu_score_label: db 'SCORE:',0
menu_coins: db 'COINS:',0
menu_time: db 'TIME LEFT:',0
menu_bonus: db 'TIME BONUS:',0
menu_continue: db 'ENTER TO RETURN',0
menu_over: db 'GAME OVER',0
menu_final: db 'FINAL SCORE:',0
menu_return: db 'ENTER TO RETURN',0
menu_lives_digits: db '000',0
menu_coins_digits: db '000',0
menu_time_digits: db '000',0
menu_score_digits: db '000000',0
menu_bonus_digits: db '00000',0
menu_font:
    db 0,0,0,0,0,0,0 ; ASCII 32
    db 0,0,0,0,0,0,0 ; ASCII 33
    db 0,0,0,0,0,0,0 ; ASCII 34
    db 0,0,0,0,0,0,0 ; ASCII 35
    db 0,0,0,0,0,0,0 ; ASCII 36
    db 0,0,0,0,0,0,0 ; ASCII 37
    db 0,0,0,0,0,0,0 ; ASCII 38
    db 0,0,0,0,0,0,0 ; ASCII 39
    db 0,0,0,0,0,0,0 ; ASCII 40
    db 0,0,0,0,0,0,0 ; ASCII 41
    db 0,0,0,0,0,0,0 ; ASCII 42
    db 0,4,4,31,4,4,0 ; ASCII 43
    db 0,0,0,0,0,0,0 ; ASCII 44
    db 0,0,0,31,0,0,0 ; ASCII 45
    db 0,0,0,0,0,0,0 ; ASCII 46
    db 0,0,0,0,0,0,0 ; ASCII 47
    db 14,17,19,21,25,17,14 ; ASCII 48
    db 4,12,4,4,4,4,14 ; ASCII 49
    db 14,17,1,2,4,8,31 ; ASCII 50
    db 30,1,1,14,1,1,30 ; ASCII 51
    db 2,6,10,18,31,2,2 ; ASCII 52
    db 31,16,16,30,1,1,30 ; ASCII 53
    db 14,16,16,30,17,17,14 ; ASCII 54
    db 31,1,2,4,8,8,8 ; ASCII 55
    db 14,17,17,14,17,17,14 ; ASCII 56
    db 14,17,17,15,1,1,14 ; ASCII 57
    db 0,4,4,0,4,4,0 ; ASCII 58
    db 0,0,0,0,0,0,0 ; ASCII 59
    db 0,0,0,0,0,0,0 ; ASCII 60
    db 0,0,0,0,0,0,0 ; ASCII 61
    db 0,0,0,0,0,0,0 ; ASCII 62
    db 0,0,0,0,0,0,0 ; ASCII 63
    db 0,0,0,0,0,0,0 ; ASCII 64
    db 14,17,17,31,17,17,17 ; ASCII 65
    db 30,17,17,30,17,17,30 ; ASCII 66
    db 15,16,16,16,16,16,15 ; ASCII 67
    db 30,17,17,17,17,17,30 ; ASCII 68
    db 31,16,16,30,16,16,31 ; ASCII 69
    db 31,16,16,30,16,16,16 ; ASCII 70
    db 15,16,16,23,17,17,15 ; ASCII 71
    db 17,17,17,31,17,17,17 ; ASCII 72
    db 31,4,4,4,4,4,31 ; ASCII 73
    db 7,2,2,2,18,18,12 ; ASCII 74
    db 17,18,20,24,20,18,17 ; ASCII 75
    db 16,16,16,16,16,16,31 ; ASCII 76
    db 17,27,21,21,17,17,17 ; ASCII 77
    db 17,25,21,19,17,17,17 ; ASCII 78
    db 14,17,17,17,17,17,14 ; ASCII 79
    db 30,17,17,30,16,16,16 ; ASCII 80
    db 14,17,17,17,21,18,13 ; ASCII 81
    db 30,17,17,30,20,18,17 ; ASCII 82
    db 15,16,16,14,1,1,30 ; ASCII 83
    db 31,4,4,4,4,4,4 ; ASCII 84
    db 17,17,17,17,17,17,14 ; ASCII 85
    db 17,17,17,17,17,10,4 ; ASCII 86
    db 17,17,17,21,21,27,17 ; ASCII 87
    db 17,17,10,4,10,17,17 ; ASCII 88
    db 17,17,10,4,4,4,4 ; ASCII 89
    db 31,1,2,4,8,16,31 ; ASCII 90

sprite_w: dw 0
sprite_h: dw 0
hero_screen_x: dw 0
hero_screen_y: dw 0
hero_piece_dy: dw 0
map_end_col: dw 0

; Level layout, 60 columns x 12 rows, row-major, 16x16 tiles (960x192 px).
; Tile codes follow Appendix A.2, with 13 = decorative flag top (non-solid).
; Two pits, two pipes, blocks, coins and stairs.
original_map:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; row 0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; row 1
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,13,0,0 ; row 2
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0 ; row 3
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0 ; row 4
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0 ; row 5
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,0,0,12,0,0 ; row 6
    db 0,0,0,0,0,4,0,0,0,0,0,0,11,11,0,0,2,2,2,3,3,0,11,11,0,0,0,0,0,0,0,0,0,0,11,11,11,0,0,0,2,2,2,3,4,0,6,7,0,0,0,0,0,10,10,0,0,12,0,0 ; row 7
    db 0,0,0,0,0,0,0,0,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,0,10,10,10,0,0,12,0,0 ; row 8
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,10,10,10,10,0,0,10,0,0 ; row 9
    db 1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1 ; row 10
    db 1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1 ; row 11
working_map: times 720 db 0

; Tile graphics: boxes of (dx,dy,w,h,colour), terminated by 0xff.
tile_table: dw tile_list_empty,tile_list_ground,tile_list_brick,tile_list_question
            dw tile_list_question,tile_list_used,tile_list_pipe_tl,tile_list_pipe_tr
            dw tile_list_pipe_bl,tile_list_pipe_br,tile_list_solid,tile_list_coin
            dw tile_list_pole,tile_list_flagtop
tile_list_empty: db 0xff
tile_list_used: db 0,0,16,16,6, 1,1,14,14,8, 0xff
tile_list_coin: db 6,2,4,12,14, 4,4,8,8,14, 6,5,2,6,6, 0xff
tile_list_ground: db 0,0,16,4,2, 0,4,16,12,6, 3,8,2,2,0, 10,11,3,2,0, 0xff
tile_list_brick: db 0,0,16,16,6, 0,0,16,1,0, 0,5,16,1,0, 0,10,16,1,0, 0,15,16,1,0
                 db 7,1,1,4,0, 3,6,1,4,0, 11,6,1,4,0, 7,11,1,4,0, 0xff
tile_list_question: db 0,0,16,16,6, 1,1,14,14,14, 5,3,6,2,6, 9,5,2,2,6, 7,7,2,2,6, 7,11,2,2,6, 0xff
tile_list_solid: db 0,0,16,16,8, 1,1,14,14,7, 3,3,10,10,8, 0xff
tile_list_pipe_tl: db 0,0,16,16,0, 1,1,15,14,2, 3,1,3,14,10, 0xff
tile_list_pipe_tr: db 0,0,16,16,0, 0,1,15,14,2, 8,1,2,14,10, 0xff
tile_list_pipe_bl: db 1,0,15,16,2, 1,0,1,16,0, 4,0,3,16,10, 0xff
tile_list_pipe_br: db 0,0,15,16,2, 14,0,1,16,0, 8,0,2,16,10, 0xff
tile_list_pole: db 7,0,2,16,2, 0xff
tile_list_flagtop: db 7,4,2,12,2, 5,0,6,6,14, 0,5,7,5,15, 0xff

; Enemy and item sprites used for graphics testing before gameplay integration.
goomba_walk_sprite: db 16,16
    db 0,0,0,0,0,0,6,6,6,6,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,6,6,0,0,0,0,0
    db 0,0,0,0,6,6,6,6,6,6,6,6,0,0,0,0
    db 0,0,0,6,6,6,14,14,14,14,6,6,6,0,0,0
    db 0,0,6,6,14,6,14,14,14,6,14,6,6,6,0,0
    db 0,0,6,14,6,14,14,14,14,14,6,14,6,6,0,0
    db 0,0,6,14,6,6,14,14,14,6,6,14,6,6,0,0
    db 0,0,0,6,6,14,14,14,14,14,6,6,6,0,0,0
    db 0,0,6,6,6,6,6,6,6,6,6,6,6,6,0,0
    db 0,6,6,6,6,6,6,6,6,6,6,6,6,6,6,0
    db 0,6,6,0,0,6,6,6,6,6,6,0,0,6,6,0
    db 0,0,0,0,6,6,0,0,0,0,6,6,0,0,0,0
    db 0,0,0,6,6,6,0,0,0,0,6,6,6,0,0,0
    db 0,0,6,6,6,0,0,0,0,0,0,6,6,6,0,0
    db 0,0,6,6,0,0,0,0,0,0,0,0,6,6,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
goomba_flat_sprite: db 16,16
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,6,6,6,6,6,6,6,6,0,0,0,0
    db 0,0,0,6,6,14,14,14,14,14,14,6,6,0,0,0
    db 0,0,6,6,14,6,14,14,14,14,6,14,6,6,0,0
    db 0,0,6,14,6,14,14,14,14,14,14,6,14,6,0,0
    db 0,0,6,6,6,6,6,6,6,6,6,6,6,6,0,0
    db 0,6,6,6,6,6,6,6,6,6,6,6,6,6,6,0
    db 0,6,0,0,6,6,0,0,0,0,6,6,0,0,6,0
koopa_sprite: db 16,16
    db 0,0,0,0,0,0,0,2,2,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,2,14,14,2,0,0,0,0,0,0
    db 0,0,0,0,0,2,14,14,14,14,2,0,0,0,0,0
    db 0,0,0,0,2,14,14,14,14,14,14,2,0,0,0,0
    db 0,0,0,2,2,2,2,10,10,2,2,2,2,0,0,0
    db 0,0,2,10,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,2,10,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,2,10,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,2,10,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,0,2,10,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,0,0,2,2,2,2,2,2,2,2,2,0,0,0,0
    db 0,0,0,0,6,6,0,0,0,0,6,6,0,0,0,0
    db 0,0,0,0,6,6,0,0,0,0,6,6,0,0,0,0
    db 0,0,0,6,6,0,0,0,0,0,0,6,6,0,0,0
    db 0,0,6,6,0,0,0,0,0,0,0,0,6,6,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
shell_sprite: db 16,16
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0
    db 0,0,0,0,0,2,10,10,10,10,2,0,0,0,0,0
    db 0,0,0,0,2,10,10,10,10,10,10,2,0,0,0,0
    db 0,0,0,2,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,0,2,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,2,10,10,10,10,15,15,15,15,10,10,10,10,2,0
    db 0,2,10,10,10,15,15,15,15,15,15,10,10,10,2,0
    db 0,2,10,10,10,15,15,15,15,15,15,10,10,10,2,0
    db 0,2,10,10,10,10,15,15,15,15,10,10,10,10,2,0
    db 0,0,2,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,0,0,2,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,0,0,0,2,10,10,10,10,10,10,2,0,0,0,0
    db 0,0,0,0,0,2,2,2,2,2,2,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
mushroom_sprite: db 16,16
    db 0,0,0,0,0,0,4,4,4,4,0,0,0,0,0,0
    db 0,0,0,0,0,4,4,4,4,4,4,0,0,0,0,0
    db 0,0,0,0,4,4,15,15,15,15,4,4,0,0,0,0
    db 0,0,0,4,4,15,15,15,15,15,15,4,4,0,0,0
    db 0,0,4,4,4,4,4,4,4,4,4,4,4,4,0,0
    db 0,4,4,15,15,4,4,4,4,4,4,15,15,4,4,0
    db 0,4,15,15,15,15,4,4,4,4,15,15,15,15,4,0
    db 0,4,15,15,15,15,15,4,4,15,15,15,15,15,4,0
    db 0,0,0,0,0,14,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,14,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,0,0,0,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,0,0,0,0
    db 0,0,0,0,14,14,0,0,0,0,14,14,0,0,0,0
    db 0,0,0,14,14,0,0,0,0,0,0,14,14,0,0,0
    db 0,0,14,14,0,0,0,0,0,0,0,0,14,14,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Hero sprites (drawn facing right; mirrored when facing left).
; Palette: 0 black, 1 blue, 4 red, 6 brown, 14 skin; tt = transparent.
; Hero = head (8 rows) + body pieces (4 rows each) + legs (4 rows).
hero_head: db 16,8
    db tt,tt,tt,tt,tt,4,4,4,4,4,tt,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,4,4,4,4,4,4,4,4,4,tt,tt,tt
    db tt,tt,tt,6,6,6,14,14,6,14,tt,tt,tt,tt,tt,tt
    db tt,tt,6,14,6,14,14,14,6,14,14,14,tt,tt,tt,tt
    db tt,tt,6,14,6,6,14,14,14,6,14,14,14,tt,tt,tt
    db tt,tt,tt,6,6,14,14,14,14,6,6,6,6,tt,tt,tt
    db tt,tt,tt,tt,tt,14,14,14,14,14,14,14,tt,tt,tt,tt
    db tt,tt,tt,4,4,4,1,4,4,1,4,4,4,tt,tt,tt
hero_body: db 16,4
    db tt,14,14,4,4,1,1,1,1,1,1,4,4,14,14,tt
    db tt,tt,14,1,1,1,1,1,1,1,1,1,1,14,tt,tt
    db tt,tt,tt,1,1,1,1,1,1,1,1,1,1,tt,tt,tt
    db tt,tt,tt,1,1,14,1,1,1,1,14,1,1,tt,tt,tt
hero_legs_stand: db 16,4
    db tt,tt,tt,1,1,1,1,tt,tt,1,1,1,1,tt,tt,tt
    db tt,tt,tt,6,6,6,6,tt,tt,6,6,6,6,tt,tt,tt
    db tt,tt,6,6,6,6,6,tt,tt,6,6,6,6,6,tt,tt
    db tt,tt,6,6,6,6,tt,tt,tt,tt,6,6,6,6,tt,tt
hero_legs_run: db 16,4
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,1,tt,tt
    db tt,6,6,6,tt,tt,tt,tt,tt,tt,6,6,6,6,tt,tt
    db tt,6,6,6,6,tt,tt,tt,tt,tt,6,6,6,tt,tt,tt
    db tt,6,6,6,tt,tt,tt,tt,tt,tt,tt,6,6,6,tt,tt
hero_legs_jump: db 16,4
    db tt,tt,tt,1,1,1,1,1,1,1,1,1,1,6,6,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,6,6,6,tt
    db tt,6,6,6,tt,tt,tt,tt,tt,tt,tt,tt,6,6,6,tt
    db tt,tt,6,6,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt



; Super Mario: one torso and extended legs, total height 32 pixels.
super_body: db 16,12
    db tt,tt,tt,4,4,4,4,4,4,4,4,4,tt,tt,tt,tt
    db tt,tt,4,4,4,1,1,1,1,4,4,4,4,tt,tt,tt
    db tt,tt,4,4,1,1,1,1,1,1,4,4,4,tt,tt,tt
    db tt,tt,4,4,1,1,1,1,1,1,4,4,4,tt,tt,tt
    db tt,tt,4,4,1,14,1,1,14,1,4,4,4,tt,tt,tt
    db tt,tt,4,4,1,1,1,1,1,1,4,4,4,tt,tt,tt
    db tt,tt,4,4,1,1,1,1,1,1,4,4,4,tt,tt,tt
    db tt,tt,14,14,1,1,1,1,1,1,14,14,14,tt,tt,tt
    db tt,tt,14,14,1,1,1,1,1,1,14,14,14,tt,tt,tt
    db tt,tt,tt,14,1,1,1,1,1,1,14,14,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,1,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,1,1,1,1,tt,tt,tt,tt,tt
super_legs_stand: db 16,12
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,1,1,1,tt,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,tt,6,6,6,tt,6,6,6,tt,tt,tt,tt,tt
    db tt,tt,tt,6,6,6,6,tt,6,6,6,6,tt,tt,tt,tt
    db tt,tt,6,6,6,6,6,tt,6,6,6,6,6,tt,tt,tt
super_legs_run: db 16,12
    db tt,tt,tt,1,1,1,1,tt,1,1,1,1,tt,tt,tt,tt
    db tt,tt,tt,1,1,1,tt,tt,tt,1,1,1,tt,tt,tt,tt
    db tt,tt,1,1,1,1,tt,tt,tt,1,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,1,1,1,tt,tt,tt,tt,tt,tt,tt,1,1,1,tt,tt
    db tt,1,1,1,tt,tt,tt,tt,tt,tt,tt,1,1,1,tt,tt
    db tt,1,1,1,tt,tt,tt,tt,tt,tt,tt,1,1,1,tt,tt
    db tt,6,6,6,tt,tt,tt,tt,tt,tt,tt,6,6,6,tt,tt
    db tt,6,6,6,tt,tt,tt,tt,tt,tt,tt,6,6,6,tt,tt
    db 6,6,6,6,tt,tt,tt,tt,tt,tt,tt,6,6,6,6,tt
    db 6,6,6,6,tt,tt,tt,tt,tt,tt,tt,6,6,6,6,tt
super_legs_jump: db 16,12
    db tt,tt,tt,tt,1,1,1,1,1,1,1,tt,tt,tt,tt,tt
    db tt,tt,tt,1,1,1,1,1,1,1,1,1,tt,tt,tt,tt
    db tt,tt,1,1,1,1,tt,tt,tt,1,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,tt,1,1,1,tt,tt,tt,tt,tt,1,1,1,tt,tt,tt
    db tt,tt,6,6,6,tt,tt,tt,tt,tt,6,6,6,tt,tt,tt
    db tt,tt,6,6,6,tt,tt,tt,tt,tt,6,6,6,tt,tt,tt
    db tt,tt,6,6,6,6,tt,tt,tt,6,6,6,6,tt,tt,tt
    db tt,tt,tt,6,6,6,tt,tt,tt,6,6,6,tt,tt,tt,tt
    db tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt,tt

; Gameplay records and private scratch data.
initial_entities:
    dd 40960,36864
    dw -128,0
    db 1,1,0,0
    dd 69632,36864
    dw -128,0
    db 1,1,0,0
    dd 90112,36864
    dw -192,0
    db 2,1,0,0
    dd 131072,36864
    dw -128,0
    db 1,1,0,0
    dd 167936,36864
    dw -128,0
    db 1,1,0,0
    dd 204800,36864
    dw -192,0
    db 2,1,0,0
    dd 0,0
    dw 0,0
    db 3,0,0,0
    dd 0,0
    dw 0,0
    db 3,0,0,0
entities: times entity_size*entity_count db 0
player_left: dw 0
player_right: dw 0
player_top: dw 0
player_bottom: dw 0
previous_feet: dw 0
hero_height: dw 16
coin_first_col: dw 0
coin_last_col: dw 0
stomp_points: dw 100,200,400,500,800,1000,2000,4000,5000,8000
hud_score: db 'SCORE',0
hud_coins: db 'COINS',0
hud_world: db 'WORLD',0
hud_world_value: db '1-1',0
hud_time: db 'TIME',0
hud_lives: db 'LIVES',0
hud_hp: db 'HP',0
hud_x: db 'X',0
heart_full_sprite: db 7,7
    db 0,4,4,0,4,4,0
    db 4,12,4,4,12,4,4
    db 4,4,4,4,4,4,4
    db 0,4,4,4,4,4,0
    db 0,0,4,4,4,0,0
    db 0,0,0,4,0,0,0
    db 0,0,0,0,0,0,0
heart_empty_sprite: db 7,7
    db 0,7,7,0,7,7,0
    db 7,0,0,7,0,0,7
    db 7,0,0,0,0,0,7
    db 0,7,0,0,0,7,0
    db 0,0,7,0,7,0,0
    db 0,0,0,7,0,0,0
    db 0,0,0,0,0,0,0

; Optional bonus routines. All parameters are stack words; registers preserved.
; BonusTone(duration,divisor): program PIT channel 2, leaving channel 0 untouched.
BonusTone:
    push bp
    mov bp,sp
    push ax
    pushf
    cli
    mov al,0xb6
    out 0x43,al
    mov ax,[bp+6]
    out 0x42,al
    mov al,ah
    out 0x42,al
    in al,0x61
    or al,3
    out 0x61,al
    mov ax,[bp+4]
    mov [cs:bonus_sound_time],ax
    popf
    pop ax
    pop bp
    ret 4
BonusSilence:
    push ax
    pushf
    cli
    mov word [cs:bonus_sound_time],0
    in al,0x61
    and al,0xfc
    out 0x61,al
    popf
    pop ax
    ret
; BonusScoreEvent(points): save popup in world coordinates, select a short tone.
BonusScoreEvent:
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push di
    mov ax,[mario_x+1]
    mov [bonus_popup_x],ax
    mov ax,[mario_y+1]
    sub ax,10
    mov [bonus_popup_y],ax
    mov word [bonus_popup_time],24
    mov ax,[bp+4]
    mov di,bonus_popup_text+5
    mov bx,10
    mov cx,5
bonus_digits:
    xor dx,dx
    div bx
    add dl,'0'
    mov [di],dl
    dec di
    loop bonus_digits
    mov di,bonus_popup_text+1
bonus_trim:
    cmp di,bonus_popup_text+5
    jae bonus_trim_done
    cmp byte [di],'0'
    jne bonus_trim_done
    inc di
    jmp bonus_trim
bonus_trim_done:
    dec di
    mov byte [di],'+'
    mov [bonus_popup_ptr],di
    mov ax,1600
    cmp word [bp+4],200
    jne bonus_not_coin
    mov ax,1000
bonus_not_coin:
    cmp word [bp+4],1000
    jne bonus_tone_ready
    mov ax,750
bonus_tone_ready:
    push ax
    mov ax,4
    push ax
    call BonusTone
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 2
BonusAgePopup:
    push ax
    mov ax,[elapsed_ticks]
    cmp ax,[bonus_popup_time]
    jb bonus_age_sub
    mov word [bonus_popup_time],0
    jmp bonus_age_done
bonus_age_sub:
    sub [bonus_popup_time],ax
bonus_age_done:
    pop ax
    ret
; MenuText has no clipping: skip offscreen labels and keep above the HUD.
BonusDrawPopup:
    push ax
    push bx
    cmp word [bonus_popup_time],0
    je bonus_draw_done
    mov bx,[bonus_popup_x]
    sub bx,[camera_x]
    cmp bx,0
    jl bonus_draw_done
    cmp bx,284
    ja bonus_draw_done
    mov ax,24
    sub ax,[bonus_popup_time]
    shr ax,1
    neg ax
    add ax,[bonus_popup_y]
    cmp ax,16
    jge bonus_popup_y_ok
    mov ax,16
bonus_popup_y_ok:
    cmp ax,193
    ja bonus_draw_done
    push cx
    mov cx,14
    push cx
    push word [bonus_popup_ptr]
    push ax
    push bx
    call MenuText
    pop cx
bonus_draw_done:
    pop bx
    pop ax
    ret

bonus_sound_time: dw 0
bonus_popup_time: dw 0
bonus_popup_x: dw 0
bonus_popup_y: dw 0
bonus_popup_ptr: dw bonus_popup_text
bonus_popup_text: db '+00000',0

; Private stack, retained when DOS memory is resized.
times 2048 db 0
stack_top:
program_end:
