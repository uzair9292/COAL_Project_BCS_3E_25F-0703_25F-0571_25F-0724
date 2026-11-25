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

tile_empty equ 0
tile_ground equ 1
tile_brick equ 2
tile_question equ 3
tile_solid equ 4
tile_pipe_tl equ 5
tile_pipe_tr equ 6
tile_pipe_bl equ 7
tile_pipe_br equ 8
tile_pole equ 9
tile_flagtop equ 10
tile_count equ 11
cam_center equ 152          ; hero centre (x+8) sits at screen column 160
cam_max equ map_w*tile_size-screen_w   ; 640
tt equ 0xff                 ; transparent palette byte inside sprites

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

; Draw simple coloured bars to verify the engine independently.
ResetEntities:
    ret
UpdateEnemies:
    ret
UpdateItems:
    ret
CheckCollisions:
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
    cmp byte [keys_pressed+0x20],0
    je updateplayer_win
    mov byte [death_request],1
updateplayer_win:
    cmp byte [keys_pressed+0x11],0
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

; Stack convention: first argument is nearest the return address
; ([bp+4]), later arguments follow at [bp+6], [bp+8] ...; callee RET n.

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
    push di
    push es
    mov ax,[bp+6]
    cmp ax,screen_h         ; unsigned compare also rejects negatives
    jae putpixel_done
    mov bx,[bp+4]
    cmp bx,screen_w
    jae putpixel_done
    mov dx,screen_w
    mul dx                  ; ax = y*320 (dx is saved above)
    add ax,bx
    mov di,ax
    mov es,[framebuffer_seg]
    mov al,[bp+8]
    mov [es:di],al
putpixel_done:
    pop es
    pop di
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
; then row-major palette bytes). Palette byte 0xff is transparent.
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
    test word [invuln_timer],4
    jnz drawhero_done
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
    mov cx,1                ; small: one body piece
    cmp byte [form],0
    je drawhero_body
    mov cx,5                ; big: five body pieces
drawhero_body:
    mov word [hero_piece_dy],8
drawhero_body_loop:
    mov ax,hero_body
    push ax
    call DrawHeroPiece
    add word [hero_piece_dy],4
    loop drawhero_body_loop
    mov ax,hero_legs_stand  ; legs sit just below the body pieces
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
    pop ax
    ret

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

sprite_w: dw 0
sprite_h: dw 0
hero_screen_x: dw 0
hero_screen_y: dw 0
hero_piece_dy: dw 0
map_end_col: dw 0

; Level layout, 60 columns x 12 rows, row-major, 16x16 tiles (960x192 px).
; Tile codes: 0 empty, 1 ground, 2 brick, 3 question, 4 solid block,
; 5/6 pipe top left/right, 7/8 pipe body left/right, 9 flag pole, 10 flag top.
; Rows 10-11 are ground (feet of the hero start at y=160), with one pit at
; columns 34-35.
original_map:
    times 60 db 0                                       ; row 0
    times 60 db 0                                       ; row 1
    times 57 db 0                                       ; row 2
    db 10
    times 2 db 0
    times 57 db 0                                       ; row 3
    db 9
    times 2 db 0
    times 57 db 0                                       ; row 4
    db 9
    times 2 db 0
    times 57 db 0                                       ; row 5
    db 9
    times 2 db 0
    times 57 db 0                                       ; row 6
    db 9
    times 2 db 0
    times 16 db 0                                       ; row 7
    db 2,3,2,3,2
    times 19 db 0
    db 3,2,3
    times 10 db 0
    db 4
    times 3 db 0
    db 9
    times 2 db 0
    times 28 db 0                                       ; row 8
    db 5,6
    times 16 db 0
    db 5,6
    times 4 db 0
    db 4,4
    times 3 db 0
    db 9
    times 2 db 0
    times 28 db 0                                       ; row 9
    db 7,8
    times 16 db 0
    db 7,8
    times 3 db 0
    db 4,4,4
    times 3 db 0
    db 9
    times 2 db 0
    times 34 db 1                                       ; row 10
    times 2 db 0
    times 24 db 1
    times 34 db 1                                       ; row 11
    times 2 db 0
    times 24 db 1
working_map: times 720 db 0

; Tile graphics: boxes of (dx,dy,w,h,colour), terminated by 0xff.
tile_table: dw tile_list_empty,tile_list_ground,tile_list_brick,tile_list_question
            dw tile_list_solid,tile_list_pipe_tl,tile_list_pipe_tr,tile_list_pipe_bl
            dw tile_list_pipe_br,tile_list_pole,tile_list_flagtop
tile_list_empty: db 0xff
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

; Private stack, retained when DOS memory is resized.
times 2048 db 0
stack_top:
program_end:
