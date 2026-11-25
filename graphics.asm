
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

