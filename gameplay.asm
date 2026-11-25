[org 0x0100]
jmp start

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
    pop ax
    pop bp
    ret 2

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



; Private stack, retained when DOS memory is resized.
times 2048 db 0
stack_top:
program_end:
