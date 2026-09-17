; MONITEUR
;

; DONNEES FICTIVES

NIL             .EQU    00H
                                        ; valor "nulo" para punteros de 16 bits (fin de una lista)
FALSE            .EQU    00H             ;Ante falta de boolean ponemos un falso = 0
TRUE            .EQU    01H              ;True = 1


NONCREE         .EQU    00H           ; bloque de contexto libre: no representa ninguna tarea
PRET            .EQU    01H           ; tarea creada, lista para ejecutar, esperando su turno
ACTIF           .EQU    02H           ; la única tarea que tiene la CPU en este momento
BLOQUEO          .EQU    03H          ; tarea esperando un semáforo (P) o una E/S (DEMES)

                                        ; CONSTANTES DES CTX
                                        ; LG INFO CTX
LONGCTX         .EQU    6             ; tamaño en bytes del "header"/metadatos de una tarea
LONGPIL         .EQU    100           ; tamaño en bytes de la pila privada de cada tarea
                                        ; [FIX] Antes era 30. Cuando el reloj interrumpe justo
                                        ; mientras una tarea está corriendo, la rutina de interrupción
                                        ; (RTITCTC) usa la pila PROPIA de esa tarea (los procesadores
                                        ; Z80 no cambian de pila al entrar a una IT); si de paso
                                        ; expiró un watchdog, RTITCTC anida CALL FINES -> V() ->
                                        ; SIGNAL, cada uno con sus propios PUSH/CALL. Sumando la
                                        ; dirección de retorno de la IT, los 6 registros que guarda
                                        ; RTITCTC, y los PUSH/CALL de FINES y V(), esa cadena anidada
                                        ; necesita más de 30 bytes; con 30 la pila se desbordaba hacia
                                        ; atrás y pisaba el encabezado (CHTPMS/STATUS/SEMAT/GARSP) del
                                        ; propio bloque de contexto de la tarea, corrompiendo el
                                        ; scheduler (así terminaba una tarea con SP apuntando a
                                        ; 0000H/basura tras ser despertada). Se probó con el emulador:
                                        ; con 64 seguía fallando más adelante; con 100 corrió más de
                                        ; 60 millones de instrucciones sin corromperse.
LONGDCTX        .EQU    LONGPIL + LONGCTX ; tamaño TOTAL de un bloque de tarea = header + su pila
                                        ; LG PILE
                                        ; LG CTX
                                        ; CHAMPS DES CTX
CHTPMS          .EQU    0               ; CHAINE PRETES OU A SEMAPHORE
                                        ; puntero (2 bytes) a la SIGUIENTE tarea en la lista donde
                                        ; esté encadenada esta (cola de listas o cola de un semáforo)
STATUS          .EQU    2               ; ETAT DE LA TACHE
                                        ; 1 byte con uno de los 4 estados: NONCREE/PRET/ACTIF/BLOQUEO
SEMAT           .EQU    3               ; SEMAPHORE BLOQUANT
                                        ; número de semáforo donde quedó bloqueada
GARSP           .EQU    4               ; GARAGE SP
                                        ; aquí se guarda el SP (2 bytes) de la tarea cuando NO está
                                        ; corriendo, para poder restaurarlo en el cambio de contexto
                                        ; CONSTANTES DU MONITEUR
NBMCTX          .EQU    20              ; NB MAX CTX
                                        ; máximo de tareas simultáneas
NBSEM           .EQU    20              ; NB MAX SEMAPHORES
                                        ; máximo de semáforos "normales" (los que usan P/V)
NBES            .EQU    8               ; NB MAX E/S
                                        ; máximo de unidades de E/S simuladas (con watchdog)
SEMPES          .EQU    NBSEM + NBES
                                        ; total de entradas de la tabla BSEM: primero los NBSEM
                                        ; semáforos normales y luego los NBES semáforos de E/S

                                        ; 3 PERIPHERIQUES
H0              .EQU    7C0H            ; TIMER 0 CTC
                                        ; puerto de E/S del canal 0 del CTC (Counter/Timer Circuit):
                                        ; genera la interrupción periódica de reloj
TT              .EQU    0064H           ; CONSTANT T.D.
                                        ; cuántos "ticks" de reloj dura una rebanada de tiempo
                                        ; (time slice) para el reparto de CPU por time-slicing
                                        ; TRANCHE = TT A 25 MS

                .ORG    1000H - 3
                                        ; el código "real" empieza en 1000H; se dejan 3 bytes antes
                                        ; para un pequeño encabezado (las dos .WORD de abajo)
                .WORD   INICTX
                                        ; palabra de cabecera: dirección de la zona de contextos
                .WORD   FINAL
                                        ; palabra de cabecera: dirección de fin del programa
NBIOIO          .EQU    $
                                        ; aquí arranca el código ejecutable, en la dirección 1000H
                JP      DEBMON
                                        ; primera instrucción real: saltar a inicializar el monitor

; DONNEES UTILES

                                        ; TABLE CENTRALE
PTRCTXL         .BLOCK  2               ; POINTEUR CTX LIBRE CREATION
                                        ; dirección del próximo bloque de memoria libre donde CREER
                                        ; puede crear una tarea nueva
NBCTX           .BLOCK  2               ; NB CTX CREES
                                        ; cuántas tareas existen (creadas) hasta este momento
PTRDTP          .BLOCK  2               ; PTR CTX DEBUT TACHES PRETES
                                        ; cabeza de la cola de tareas listas (la próxima en correr)
PTRFTP          .BLOCK  2               ;       FIN
                                        ; cola (el final) de la cola de tareas listas
PTRTA           .BLOCK  2               ; PTR CTX TACHE EN COURS
                                        ; puntero a la tarea que se está ejecutando ahora mismo
                                        ; ZONE MEMOIRE SEMAPHORES
BSEM            .BLOCK  8*SEMPES
                                        ; tabla de TODOS los semáforos, 8 bytes cada uno:
                                        ; +0 contador (OPTEUR), +1/+2 cabeza cola de espera,
                                        ; +3/+4 cola (fin) de la cola de espera; solo para los de
                                        ; E/S además: +5 watchdog activo (V/F), +6/+7 cuenta regresiva

                                        ; ZONE MEMOIRE CTX
                                        ; cada bloque de tarea mide LONGDCTX bytes: header (LONGCTX)
                                        ; + su pila privada (LONGPIL)
INICTX          .BLOCK  LONGDCTX*NBMCTX

INREVM          .BLOCK  NBES            ; INDICATEURS REVEIL (V/F)
                                        ; un byte por unidad de E/S: ¿esta tarea fue despertada por
                                        ; el reloj (watchdog) o por un FINES manual?

PILSYS          .BLOCK  30              ; PILE SYSTEME
                                        ; pila usada solo durante el arranque (DEBMON), antes de que
                                        ; exista ninguna tarea todavía
PPILSYS         .BLOCK  1
                                        ; tope inicial de PILSYS (la pila crece hacia direcciones
                                        ; menores, por eso el SP arranca aquí, al final del bloque)

; TABLE D'ADRESSES DES ROUTINES DE TRAITEMENT D'IT

TARTIT          .BLOCK  2

CONSOLE_PORT    .EQU    0FFH            ; puerto de E/S por el que también se saca cada carácter;
                                    
CONSBUF         .BLOCK  200             ; aquí queda, en orden, cada carácter "impreso" por las
                                        ; tareas.
CONSPTR         .BLOCK  2               ; puntero al siguiente hueco libre de CONSBUF


;***************************************************************************
;
; PRIMITIVES
;
;***************************************************************************

; PRIMITIVE P(#SEMAPHORE)
                                        ; se usa el nombre "SEMP" en vez de "P": "P" es la condición
                                        ; de signo positivo del Z80 y choca con instrucciones como
                                        ; "JP P,..." (ver su uso en DEMES, más abajo)
SEMP            DI


                PUSH    AF                       ; se guardan los registros que esta rutina toca,
                PUSH    HL                       ; para poder restaurarlos intactos si al final
                PUSH    DE                       ; resulta que NO hubo que bloquear la tarea
                PUSH    BC

                LD      B,A                      ; guarda el número de semáforo en B, porque
                                        ; RECHSEM va a destruir el valor de A

                CALL    RECHSEM                  ; HL POINTE SEMAPHORE
                DEC (HL)
                JP      M,WAIT                   ; SI OPTEUR < 0 ALORS WAIT
                                                 ; si el contador quedó negativo, no había recurso libre:
                                                 ; bloquear la tarea actual (saltar a WAIT)

                POP     BC                       ; NON BLOQUEE, CONTINUER
                POP     DE                       ; sí había recurso disponible: se restauran los
                POP     HL                       ; registros tal cual estaban y se sigue de largo,
                POP     AF                       ; sin cambiar de tarea

                EI
                RET

WAIT            PUSH    IX                       ; BLOCAGE TACHE EXECUTANT P
                PUSH    IY

                EX      DE,HL                    ; ahora DE apunta al semáforo (antes en HL)
                PUSH    DE
                POP     IY                       ; DE,IY POINTENT SEMAPHORE

                LD      IX,(PTRTA)               ; IX POINTE CTX TACHE EN COURS

                PUSH    IX
                POP     DE                       ; [FIX] DE = dirección de la tarea que se bloquea.
                                        ; Antes DE seguía valiendo lo que dejó "EX DE,HL" más arriba
                                        ; (la dirección del PROPIO SEMÁFORO), así que las líneas de
                                        ; abajo que encadenan la tarea en la cola de espera del
                                        ; semáforo ((IY+1)/(IY+2), (IX+CHTPMS) de NOVIDER, (IY+3)/
                                        ; (IY+4)) terminaban enlazando la dirección del semáforo
                                        ; consigo mismo en vez de apuntar a esta tarea. Cuando V()/
                                        ; SIGNAL luego intenta despertarla, lee ese "puntero" y trata
                                        ; los bytes del semáforo como si fueran un bloque de tarea,
                                        ; corrompiendo memoria (así es como T2 terminaba saltando a
                                        ; SP=000CH tras ser "despertada").

                LD      L,(IX + CHTPMS)          ; EXTRAIRE TETE TACHES PRETES
                LD      H,(IX + CHTPMS + 1)      ; toma quién era "el siguiente" de la tarea actual
                LD      (PTRDTP),HL              ; y lo hace la nueva cabeza de la cola de listas

                LD      (IX + CHTPMS),NIL        ; AJOUTER A TETE ATTENTE SEM
                LD      (IX + CHTPMS + 1),NIL    ; (se limpia el puntero de encadenamiento; se fija
                LD      (IX + STATUS),BLOQUEO    ; según si la cola del semáforo está vacía o no,
                LD      (IX + SEMAT),B           ; más abajo). Guarda en qué semáforo quedó (B).

                LD      A,(IY + 1)               ; (IY+1) = byte bajo de la cabeza de la cola espera
                AND     A                        ; A = A-T-IL FALLU BLOQUER ? (en realidad prueba si
                JR      NZ,NOVIDER               ; la cola de espera del semáforo ya tenía tareas)

                LD      (IY + 1),E               ; FILE VIDE -> la cola estaba vacía: esta tarea
                LD      (IY + 2),D               ; PTR DEBUT FILE   pasa a ser cabeza Y cola a la vez
                JR      CONTW
NOVIDER         LD      L,(IY + 3)               ; la cola no estaba vacía: toma la última tarea que
                LD      H,(IY + 4)               ; ya esperaba en este semáforo...
                PUSH    HL
                POP     IX
                LD      (IX + CHTPMS),E
                LD      (IX + CHTPMS + 1),D      ; CHAINAGE  (...y hace que esa última apunte ahora
                                        ; a la tarea que se acaba de bloquear)
CONTW           LD      (IY + 3),E               ; PTR FIN FILE -> en ambos casos, actualiza el
                LD      (IY + 4),D               ; puntero "última de la cola" del semáforo

                JP      DISP                     ; cede la CPU a otra tarea (cambio de contexto)


;
; SOUSPROGRAMME RECHSEM     ENTREE   A=#SEMAPHORE
;                           SORTIE   HL=@ SEMAPHORE
;
RECHSEM         RLCA
                RLCA
                RLCA                             ; MULT. PAR 8
                                        ; (rotar 3 veces a la izquierda = multiplicar por 8; cada
                                        ; semáforo en BSEM ocupa 8 bytes)
                LD      E,A
                LD      D,0
                LD      HL,BSEM
                ADD     HL,DE                    ; HL = BSEM + (número de semáforo * 8)
                RET


;***************************************************************************
;
; PRIMITIVE V(#SEMAPHORE)                  -> operación V (signal) de Dijkstra
;
V               DI

                PUSH    AF
                PUSH    HL
                PUSH    DE

                CALL    RECHSEM                  ; HL POINTE SEMAPHORE

                INC     (HL)
                                          ; OPTEUR = OPTEUR + 1

                JP      M,SIGNAL
                JP      Z,SIGNAL                 ; DEBLOCAGE D'UNE TACHE
                                        ; si tras incrementar quedó negativo o -1 manda signal

                JP      FINV                     ; CONTINUER


SIGNAL          PUSH    HL
                POP     IY                       ; IY POINTE SEMAPHORE

                LD      E,(IY + 1)
                LD      D,(IY + 2)               ; EXTRAIRE 1 CTX FILE SEM
                PUSH    DE
                POP     IX                       ; DE,IX POINTENT TACHE DEBLOQ
                                        ; IX/DE = la tarea que estaba en la CABEZA de la cola de
                                        ; espera del semáforo: es la que se va a desbloquear

                LD      A,(HL)
                OR      A
                JR      NZ,NOVIDEV
                LD      (IY + 1),NIL
                LD      (IY + 2),NIL
                LD      (IY + 3),NIL
                LD      (IY + 4),NIL             ; LA FILE EST VIDE
                                        ; el contador quedó en 0: no queda nadie más esperando,
                                        ; se limpian todos los punteros de la cola de espera
                JR      CONTV
NOVIDEV         LD      L,(IX + CHTPMS)
                LD      H,(IX + CHTPMS + 1)      ; LA FILE N'EST PAS VIDE
                LD      (IY + 1),L
                LD      (IY + 2),H               ; CHAINAGE FILE
                                        ; todavía queda alguien esperando: avanza la cabeza de la
                                        ; cola de espera al que era "siguiente" de la tarea desbloq.

CONTV           LD      (IX + CHTPMS),NIL        ; AJOUTER A FILE TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL
                LD      (IX + STATUS),PRET
                                        ; la tarea desbloqueada se agrega al FINAL de la cola de
                                        ; tareas listas (vuelve a competir por CPU normalmente)

                LD      IX,(PTRFTP)              ; IX POINTE DERNIERE PRETE
                LD      (IX + CHTPMS),E
                LD      (IX + CHTPMS + 1),D
                LD      (PTRFTP),DE

FINV            POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE INISEM(#SEMAPHORE,CPTE)               INITIALISATION SEMAPHORE
;
INISEM          DI

                PUSH    AF
                PUSH    BC
                PUSH    DE
                PUSH    HL
                PUSH    IX

                CALL    RECHSEM                  ; HL POINTE SEMAPHORE

                PUSH    HL
                POP     IX
                LD      (IX + 0),B               ; INITIALISATION COMPTE
                LD      (IX + 1),NIL             ; INITIALISATION POINTEURS
                LD      (IX + 2),NIL             ; (cabeza y cola de la cola de espera = vacía)
                LD      (IX + 3),NIL
                LD      (IX + 4),NIL

                POP     IX
                POP     HL
                POP     DE
                POP     BC
                POP     AF

                EI
                RET


;***************************************************************************
;
; DISPATCHER                              -> aquí ocurre el cambio de contexto real entre tareas
;
; APPELLE PAR :  PRIMITIVE P LORS D'UN BLOCAGE
;                PRIMITIVE PASS SI FILE TACHES PRETES NON VIDE
;
STOSP           .BLOCK  2                        ; GARAGE TEMPORAL SP
DISP            DI

                LD      IX,(PTRTA)               ; SAUVEGARDER CTX TACHE COURS
                LD      (STOSP),SP               ;   SEULEMENT SP
                LD      HL,(STOSP)
                LD      (IX + GARSP),L           ; guarda el SP actual dentro del campo GARSP
                LD      (IX + GARSP + 1),H       ; del propio contexto de la tarea que se va

DISPP           LD      HL,(PTRDTP)              ; RESTAURER CTX 1ERE TACHE PRETE
                LD      (PTRTA),HL               ; la cabeza de la cola de listas pasa a ser
                PUSH    HL                       ; ahora "la tarea activa"
                POP     IX
                LD      (IX + STATUS),ACTIF
                LD      L,(IX + GARSP)           ; recupera SU stack pointer guardado
                LD      H,(IX + GARSP + 1)
                LD      SP,HL                    ; RESTAURATION SP -> aquí es donde el SP pasa a
                                        ; apuntar a la pila privada de la nueva tarea
                POP     IY                       ; se recuperan los registros que ESA tarea había
                POP     IX                       ; dejado guardados en su propia pila la última vez
                POP     BC                       ; que se detuvo (por eso todas las primitivas
                POP     DE                       ; empujan siempre los mismos 8 registros, en el
                POP     HL                       ; mismo orden, antes de llamar a DISP)
                POP     AF                       ; RESTAURATION REGISTRES

                EI
                RET


;***************************************************************************
;
; PRIMITIVE PASS                    ; PASSE LA MAIN  -> cede la CPU voluntariamente si hay otra
                                        ; tarea lista; si no hay ninguna, sigue corriendo igual
;
; SI ON VEUT UTILISER "TIME SLICING", IL FAUT ACTIVER "UNITE E/S #0"
; LA ROUTINE DE TRAITEMENT D'IT DE L'HORLOGE FERA PASS POUR QUITTER LE
; PROCESSEUR A LA TACHE EN COURS

; traducción: si se quiere usar "time slicing", hay que activar la "unidad
; de E/S #0"; la rutina de interrupción del reloj hará PASS para quitarle la
; CPU a la tarea en curso.
PASS            PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX
                PUSH    IY

                LD      IX,(PTRTA)               ; REGARDER FILE TACHES PRETES
                LD      L,(IX + CHTPMS)          ; IX POINTE TACHE ACTIVE
                LD      H,(IX + CHTPMS + 1)      ; HL POINTE SUIVANTE TACHE PRETE
                LD      A,L
                OR      H
                JR      NZ,CONPASS
                                        ; si el "siguiente" de la tarea activa es NIL, no hay
                                        ; ninguna otra tarea lista: no hace falta cambiar de tarea

FINPASS         POP     IY                       ; FILE TACHES PRETES VIDE
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RET                              ; CONTINUER

CONPASS         LD      (PTRDTP),HL              ; EXTRAIRE TETE TACHES PRETES
                                        ; sí había otra tarea lista: esa pasa a ser la nueva cabeza

                LD      DE,(PTRTA)
                LD      (IX + CHTPMS),NIL        ; AJOUTER FIN TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL    ; a la tarea que estaba activa se le agrega al
                LD      (IX + STATUS),PRET       ; final de la cola de listas (vuelve a la fila)
                LD      HL,(PTRFTP)
                PUSH    HL
                POP     IY                       ; IY POINTE FIN TACHES PRETES
                LD      (IY + CHTPMS),E
                LD      (IY + CHTPMS + 1),D
                LD      (PTRFTP),DE

                JP      DISP                     ; REND LA MAIN -> deja que DISP haga el cambio real


;***************************************************************************
;
; PRIMITIVE DEMES(#UNITE)                        DEMANDE E/S
                                        ; pide una E/S: equivale a un P() sobre el semáforo de esa
                                        ; unidad de E/S (los semáforos de E/S viven después de los
                                        ; NBSEM normales dentro de la misma tabla BSEM)
;
DEMES           DI

                ADD     A,NBSEM
                JP      SEMP                     ; PRIMITIVE P


;***************************************************************************
;                                                 SIGNAL NON MEMORISE
                                        ; señala que una E/S terminó: equivale a un V(), pero además
                                        ; apaga el watchdog de esa unidad y anota que no fue el reloj
                                        ; quien la despertó
;                                                 A NON DETRUIT A LA SORTIE
FINES           DI

                PUSH    HL
                PUSH    DE
                PUSH    IX

                LD      E,A
                LD      D,0
                LD      HL,INREVM
                ADD     HL,DE
                LD      (HL),FALSE                ; NON REVEILLE PAR HORLOGE
                                        ; marca que ESTA E/S no fue despertada por el reloj (sino
                                        ; por un FINES llamado a mano, como aquí)

                ADD     A,NBSEM
                PUSH    AF
                CALL    RECHSEM                  ; ubica el semáforo de E/S correspondiente
                PUSH    HL
                POP     IX                       ; IX POINTE SEMAPHORE
                LD      (IX + 5),FALSE            ; INHIBITION T.D. -> apaga su watchdog
                LD      A,(IX + 0)               ; A = OPTEUR SEMAPHORE
                OR      A
                JP      M,APV
                                        ; [FIX] Antes decía "JP Z,APV" (saltaba cuando el contador
                                        ; era EXACTAMENTE 0). Pero INIES arranca el contador en 0, y
                                        ; DEMES (P) lo deja en NEGATIVO cuando alguien queda esperando
                                        ; (0 -> -1 con el primer DEMES). O sea que "ya había una tarea
                                        ; esperando" se detecta con el contador NEGATIVO, no en 0: con
                                        ; la condición original, FINES hacía el V() completo (SIGNAL)
                                        ; justo cuando NADIE esperaba, e ignoraba la señal (sin llamar
                                        ; a SIGNAL) cuando SÍ había una tarea bloqueada esperándola -
                                        ; exactamente al revés de lo que dice el propio comentario y
                                        ; el nombre de la rutina (SIGNAL NON MEMORISE). Con "JP M,APV"
                                        ; se dispara SIGNAL cuando el contador es negativo (alguien
                                        ; esperando) y se descarta la señal cuando es 0 (nadie
                                        ; esperando), que es el comportamiento "no memorizado" real.

                POP     AF                       ; si no había nadie esperando, basta con
                POP     IX                       ; salir sin tocar las colas
                POP     DE
                POP     HL

                EI
                RET

APV             POP     AF
                POP     IX
                POP     DE
                POP     HL

                JP      V
                                        ; A ya trae el número de semáforo correcto: reutiliza V


;***************************************************************************
;
; PRIMITIVE INIES(#UNITE)                        INITIALISATION SEMAPHORE E/S A 0
                                        ; deja en 0 el semáforo/contador de la unidad de E/S #UNITE
;
INIES           DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                LD      E,A
                LD      D,0
                LD      HL,INREVM
                ADD     HL,DE
                LD      (HL),FALSE                ; NON REVEILLE PAR HORLOGE

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX                       ; IX POINTE SEMAPHORE

                LD      (IX + 0),0               ; OPTEUR = 0
                LD      (IX + 1),NIL
                LD      (IX + 2),NIL             ; (cabeza y cola de la cola de espera = vacía)
                LD      (IX + 3),NIL
                LD      (IX + 4),NIL
                LD      (IX + 5),FALSE            ; INHIBITION T.D.

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE ARMERH(COMPTE,#UNITE)                 INITIALISATION OPTEUR T.D.
                                        ; carga la cuenta regresiva del watchdog de una unidad de
                                        ; E/S, SIN activarlo todavía (eso lo hace ACTIVH aparte)
;
ARMERH          DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX

                LD      E,A
                LD      D,0
                LD      HL,INREVM
                ADD     HL,DE
                LD      (HL),FALSE                ; NON REVEILLE PAR HORLOGE

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX
                LD      (IX + 5),FALSE
                LD      (IX + 6),C               ; INITIALISATION OPTEUR
                LD      (IX + 7),B

                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE ACTIVH(#UNITE)                        ACTIVATION T.D.
                                        ; activa el watchdog de la unidad: a partir de ahora, en
                                        ; cada interrupción del reloj (RTITCTC) se le va a decrementar
                                        ; la cuenta que le cargó ARMERH

ACTIVH          DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX

                LD      (IX + 5),TRUE

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE SUSPH(#UNITE)                         SUSPENSION TEMPORAL T.D.
                                        ; suspende (desactiva) el watchdog de una unidad de E/S, sin
                                        ; tocar su cuenta (se puede reactivar más tarde con ACTIVH)

SUSPH           DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX

                LD      (IX + 5),FALSE            ; INHIBITION T.D.

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE CREER(@DEBUT,ACTX)                    CREATION CTX
                                        ; crea una tarea nueva a partir de una dirección de inicio de
                                        ; código (@DEBUT); usa el siguiente bloque libre de INICTX

CREER           DI

                PUSH    IX
                PUSH    HL
                PUSH    DE
                PUSH    HL                       ; se guarda @DEBUT dos veces: una para usarla ya,
                                        ; otra para recuperarla más abajo

                LD      IX,(PTRCTXL)             ; IX POINTE CTX LIBRE

                LD      HL,(PTRCTXL)
                LD      E,LONGDCTX
                LD      D,0
                ADD     HL,DE                    ; HL POINTE CTX SUIVANT
                LD      (PTRCTXL),HL             ; ACTUALISATION PTRCTXL

                DEC     HL                       ; HL POINTE FOND FILE
                                        ; HL queda apuntando al ÚLTIMO byte del bloque recién
                                        ; reservado (el fondo de la pila de esta tarea, ya que la
                                        ; pila del Z80 crece hacia direcciones menores)
                EX      DE,HL
                POP     HL
                PUSH    HL                       ; @ DEBUT PGM
                EX      DE,HL
                LD      (HL),D                   ; DE = @ DEBUT PGM
                DEC     HL
                LD      (HL),E                   ; @ DEBUT AU FOND PILE
                                        ; escribe la dirección de inicio del programa (@DEBUT) al
                                        ; fondo de la pila de la nueva tarea, para que el DISPATCHER
                                        ; "salte" ahí (con su POP+RET/POP AF final) la primera vez
                LD      B,6                      ; INITIALISATION REGISTRES A 0
INIREG          DEC     HL
                LD      (HL),0
                DEC     HL
                LD      (HL),0
                DJNZ    INIREG
                                        ; inicializa en 0 los 6 registros de 16 bits restantes
                                        ; (AF,BC,DE,HL,IX,IY) que DISP hará POP la primera vez

                LD      (IX + GARSP),L
                LD      (IX + GARSP + 1),H      ; INITIALISATION SP -> guarda el SP inicial de la
                                        ; tarea, apuntando al tope de su pila ya preparada

                LD      (IX + STATUS),PRET       ; ETAT = PRET -> la tarea nace lista para ejecutar

                LD      (IX + CHTPMS),NIL        ; CHAINAGE TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL
                LD      A,(NBCTX)
                OR      A                        ; FILE VIDE ?
                JR      NZ,FTPNV
                LD      (PTRDTP),IX              ; FILE VIDE -> es la primera tarea: ella misma es
                LD      (PTRFTP),IX              ; cabeza y cola de la cola de listas
                JR      SUITCREAR
FTPNV           PUSH    IX                       ; FILE NON VIDE -> ya había tareas: se agrega al
                POP     DE                       ; DE POINTE CTX A CREER   final de la cola
                LD      IX,(PTRFTP)              ; IX POINTE DERNIERE PRETE
                LD      (IX + CHTPMS),E
                LD      (IX + CHTPMS + 1),D
                LD      (PTRFTP),DE

SUITCREAR       POP     HL
                POP     DE
                POP     BC
                POP     IX

                LD      A,(NBCTX)
                INC     A
                LD      (NBCTX),A                ; incrementa el contador global de tareas creadas

                EI
                RET


;***************************************************************************
;
; PRIMITIVE DETRUIX(#CTX)                          -> destruye una tarea existente
                                                  ; #CTX > 0
DETRUIX         DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX
                PUSH    IY

                LD      HL,INICTX                ; RECHERCHE CTX
                LD      E,LONGDCTX
                LD      D,0
                LD      B,A
BUSCTX          ADD     HL,DE
                DJNZ    BUSCTX                    ; HL POINTE CTX A DETRUIRE
                                        ; recorre INICTX en pasos de LONGDCTX (tamaño total del bloque)
                                        ; para llegar al bloque de la tarea #A.
                LD      C,L
                LD      B,H
                PUSH    BC
                POP     IX                        ; BC,IX POINTENT A CTX

                LD      A,(IX + STATUS)
                LD      (IX + STATUS),NONCREE
                CP      BLOQUEO                    ; TACHE BLOQUEE ?
                JR      Z,TCHBLQ

                CALL    DECHAIN                   ; TACHE PRETE, DECHAINAGE
                LD      A,(IX + CHTPMS)           ; DERNIERE ?
                OR      (IX + CHTPMS + 1)
                JR      NZ,FINDET                 ; PAS DERNIERE
                PUSH    IY                        ; DERNIERE
                POP     DE
                LD      (PTRFTP),DE
                JR      FINDET

TCHBLQ          LD      A,(IX + SEMAT)            ; TACHE BLOQUEE
                CALL    RECHSEM
                EX      DE,HL
                PUSH    DE
                POP     IY                        ; DE,IY POINTENT SEMAPHORE

                INC     (IY + 0)                  ; OPTEUR = OPTEUR + 1
                JR      NZ,NOVIDBL                ; FILE VIDE ?

                LD      (IY + 1),NIL              ; FILE VIDE
                LD      (IY + 2),NIL
                LD      (IY + 3),NIL
                LD      (IY + 4),NIL
                LD      (IY + 5),FALSE
                JR      FINDET

NOVIDBL         LD      L,(IY + 1)                ; FILE NON VIDE
                LD      H,(IY + 2)                ; EN TETE ?
                LD      A,L
                CP      0
                JR      NZ,STELIM

                LD      A,(IX + CHTPMS)           ; EN TETE
                LD      (IY + 1),A
                LD      A,(IX + CHTPMS + 1)      ; (IY+1)/(IY+2) = puntero de 16 bits a la cabeza de
                LD      (IY + 2),A                ; la cola de espera: el byte alto va en (IY+2)
                JR      ULTFIL

STELIM          PUSH    IY                        ; PAS EN TETE, GARDER PTR SEM
                CALL    DECHAIN                    ; DECHAINAGE

ULTFIL          LD      A,(IX + CHTPMS)            ; DERNIERE ?
                OR      (IX + CHTPMS + 1)
                JR      NZ,FINDET1

                PUSH    IY                          ; DERNIERE
                POP     DE                          ; DE POINTE NOUVELLE DERNIERE
                POP     IY                          ; RECUPERATION PTR SEMAPHORE
                LD      (IY + 3),E
                LD      (IY + 4),D                  ; NOUVEAU CHAINAGE
                JR      FINDET

FINDET1         POP     IY                          ; RECUPERATION PTR SEMAPHORE

FINDET          POP     IY
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;
; SOUSPROGRAMME DECHAIN
;                         FAIT LE DECHAINAGE DE LA TACHE A DETRUIRE
;                         CETTE TACHE NE DOIT PAS ETRE AU DEBUT D'UNE FILE
;
;                         IX,BC DOIVENT POINTER TACHE A DECHAINER
;                         IY POINTE TACHE QUI POINTE TACHE A DETRUIRE
;                         A LA SORTIE
;                         AF,HL,DE SONT DETRUITS

DECHAIN         LD      IY,INICTX
                LD      E,LONGDCTX               ; paso entre bloques = tamaño TOTAL del bloque
                LD      D,0

BOUX            LD      L,(IY + CHTPMS)             ; RECHERCHE CTX QUI POINTE
                LD      H,(IY + CHTPMS + 1)         ;   CTX A DECHAINER
                LD      A,C
                CP      L
                JR      NZ,ADDIX
                LD      A,B
                CP      H
                JR      Z,TROUVE                    ; ¿el puntero "siguiente" de este bloque
                                        ; coincide con la dirección de la tarea buscada (BC)?
ADDIX           ADD     IY,DE                        ; si no, avanza al siguiente bloque de INICTX
                JR      BOUX

TROUVE          LD      A,(IX + CHTPMS)              ; TROUVE, DECHAINAGE
                LD      (IY + CHTPMS),A
                LD      A,(IX + CHTPMS + 1)
                LD      (IY + CHTPMS + 1),A

                RET


;***************************************************************************
;
; INITIALISATION MONITEUR
;
DEBMON          DI

                LD      SP,PPILSYS                ; INITIALISATION SP -> usa la pila de arranque
                                        ; del sistema (PILSYS), la única que existe antes de crear
                                        ; ninguna tarea

                LD      HL,CONSBUF
                LD      (CONSPTR),HL              ; INITIALISATION CONSOLA SIMULADA

                LD      A,0
                LD      (NBCTX),A                 ; INITIALISATION NB CTX -> todavía no hay tareas

                LD      HL,INICTX
                LD      (PTRCTXL),HL              ; INITIALISATION PTR CTX -> el primer bloque
                                        ; libre es el principio de la tabla de contextos

                LD      (PTRTA),HL                ; TACHE ACTIVE = TACHE FOND
                LD      HL,TACHFON                ; CREATION TACHE FOND
                CALL    CREER

                JP      DISPP                     ; ACTIVATION TACHE FOND -> arranca todo activando
                                        ; la primera (y única, por ahora) tarea que existe
                                        ; [FIX] Antes decía "JP DISP". DISP arranca guardando el
                                        ; contexto de "la tarea actual" (PTRTA) antes de restaurar el
                                        ; de la cabeza de la cola de listas (PTRDTP). Aquí, en el
                                        ; arranque, PTRTA y PTRDTP apuntan al MISMO bloque (la única
                                        ; tarea que existe hasta ahora), así que ese "guardado" pisaba
                                        ; el GARSP que CREER acababa de preparar (con la pila privada
                                        ; correcta de TACHFON) con el SP de arranque (PPILSYS, en
                                        ; ceros), y el RET final terminaba saltando a 0000H. Saltando
                                        ; directo a DISPP se evita ese guardado innecesario: no hay
                                        ; ninguna tarea previa real cuyo contexto haya que preservar.
                                        ; (Los otros dos "JP DISP", en WAIT y PASS, sí son correctos:
                                        ; ahí PTRTA y PTRDTP ya son bloques distintos.)


;***************************************************************************
;
; TACHE DE FOND                                    -> tarea de fondo: prepara periféricos,
;                                                     arma el time-slicing y crea las tareas T1..T3
;
TACHFON         CALL    INIPER                    ; INIT PERIPHERIQUES

                LD      BC,0002H
                LD      A,0
                CALL    ARMERH                    ; TIME SLICING -> arma (con cuenta chica) y activa
                CALL    ACTIVH                    ; el watchdog de la unidad 0, reservada para el
                                        ; reparto de CPU por tiempo (ver comentario en PASS y RTITCTC)

                LD      HL,T1                      ; CREATION TACHE 1
                CALL    CREER
                LD      HL,T2                      ; CREATION TACHE 2
                CALL    CREER
                LD      HL,T3                      ; CREATION TACHE 3
                CALL    CREER

SIEMPRE         CALL    PASS                       ; BOUCLE TOUJOURS
                JR      SIEMPRE
                                        ; la tarea de fondo se convierte en la tarea "idle": cede la
                                        ; CPU una y otra vez a quien esté listo, para siempre


;
INIPER          LD      HL,TARTIT                  ; INITIALISATION REGISTRE I
                LD      A,H                        ; carga en el registro I la página alta de la
                LD      I,A                        ; tabla de vectores (modo IM 2 del Z80)

                CALL    INICTC                     ; INITIALISATION CTC
                CALL    INVSIO                     ; INVALIDATION IT SIO

                IM      2                          ; modo de interrupción 2: usa tabla de vectores
                EI
                RET


;
; INVALIDATION IT SIO
;
INVSIO          LD      A,0D0H                    ; deshabilita las interrupciones del chip SIO
                OUT     (079H),A                   ; (no se usa en este programa)
                OUT     (07BH),A
                RET


;
; INITIALISATION CTC
;
INICTC          LD      HL,TARTIT
                LD      DE,RTITCTC
                LD      (HL),E                     ; @ ROUTINE TRAITEMENTS D'IT DU
                INC     HL                          ; CTC A LA TABLE D'ADRESSES IT
                LD      (HL),D
                                        ; registra la dirección de RTITCTC (la rutina de interrupción
                                        ; del CTC) en la tabla de vectores TARTIT

                LD      IX,BSEM
                LD      E,8                          ; cada entrada de BSEM mide 8 bytes
                LD      D,0
                LD      B,SEMPES
FS              LD      (IX + 5),FALSE              ; T.D. INACTIFS
                ADD     IX,DE
                DJNZ    FS
                                        ; deja todos los watchdogs (temporizadores) de todos los
                                        ; semáforos inactivos al arrancar

                LD      A,0
                OUT     (H0),A                     ; VECTEUR IT AU CTC
                                                     ; L = 0
                LD      A,0B7H
                OUT     (H0),A                      ; MODE D'OPERATION

                LD      A,0
                OUT     (H0),A                      ; CONSTANT DE TEMPS
                                        ; programa el canal 0 del CTC: vector de interrupción, modo
                                        ; de operación y la constante de tiempo (cuenta del timer)

                RET


;***************************************************************************
;
; ROUTINE DE TRAITEMENT D'IT DU CTC
;
; VERIFIER SI IL Y A DE TACHES A REVEILLER
; CONSULTER TEMPS DE TIMER ET DEMARRER

RTITCTC         PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX
                PUSH    IY

                LD      IX,BSEM                    ; RECHERCHE SEM E/S
                LD      A,NBSEM
                RLCA
                RLCA
                RLCA                                ; NBSEM*8 = dónde empiezan los semáforos de E/S
                LD      E,A
                LD      D,0
                ADD     IX,DE
                PUSH    IX
                POP     IY                          ; IY POINTE SEM E/S 0 (la reservada al
                                        ; time-slicing, ver TACHFON)

                LD      E,8
                LD      D,0
                ADD     IX,DE
                LD      HL,INREVM
                INC     HL
                LD      B,NBES - 1
                LD      C,1                          ; IX POINTE SEM E/S 1
                                                       ; HL POINTE IND. DE REVEIL
                                        ; recorre las unidades de E/S 1..NBES-1 (la 0 se trata aparte
                                        ; más abajo, sólo para time-slicing)

REVISAR         LD      A,(IX + 5)                   ; EN ATTENTE DE REVEIL ?
                CP      FALSE
                JR      Z,SUSEMES                    ; si su watchdog no está activo, sigue con la
                                        ; siguiente unidad

                LD      E,(IX + 6)                   ; OUI
                LD      D,(IX + 7)
                DEC     DE                           ; decrementa su cuenta regresiva de 16 bits
                LD      (IX + 6),E
                LD      (IX + 7),D                   ; T.D. ?
                LD      A,E
                OR      D
                JR      NZ,SUSEMES                   ; ¿llegó a 0?

                LD      A,C                          ; OUI
                CALL    FINES                        ; REVEIL -> "se acabó el tiempo" de esta unidad:
                LD      (HL),TRUE                    ; REVEILLE PAR L'HORLOGE   despierta a quien la
                LD      (IX + 5),FALSE               ; esperaba y apaga su watchdog

SUSEMES         INC     HL                           ; CONTINUER A VERIFIER T.D.
                LD      E,8
                LD      D,0
                ADD     IX,DE
                INC     C
                DJNZ    REVISAR

                LD      A,(IY + 5)                   ; TIME SLICING ?
                CP      TRUE
                JR      NZ,FINITH                    ; si el time-slicing no está activo, no hay
                                        ; nada más que hacer: regresar normal de la interrupción

                LD      E,(IY + 6)                   ; OUI
                LD      D,(IY + 7)
                DEC     DE                           ; decrementa el contador de la rebanada de tiempo
                LD      (IY + 6),E
                LD      (IY + 7),D                   ; FIN TRANCHE ?
                LD      A,E
                OR      D
                JR      NZ,FINITH                    ; ¿se acabó la rebanada?

                LD      DE,TT                        ; OUI
                LD      (IY + 6),E                   ; recarga el contador con una rebanada nueva
                LD      (IY + 7),D
                JR      TEMPART                      ; y fuerza un cambio de tarea (preemption)

FINITH          POP     IY                           ; caso normal: no hay que forzar cambio de
                POP     IX                           ; tarea, sólo restaurar registros y volver
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RETI

TEMPART         LD      HL,TIMSLIC                   ; FAIRE PASS
                PUSH    HL                           ; "engaña" al RETI empujando la dirección de
                RETI                                 ; TIMSLIC, para saltar ahí después de retornar

TIMSLIC         POP     IY                           ; se restauran los registros normalmente...
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                JP      PASS                         ; ...y se fuerza un PASS: cambio de tarea
                                        ; preventivo (esto es lo que hace real el time-slicing)


;***************************************************************************
;
; PRINTC                                   RUTINA DE CONSOLA SIMULADA
;                                           ENTREE  C = caracter a "imprimir"
;                                           No destruye ningún registro (salvo flags).
;
PRINTC          PUSH    AF
                PUSH    HL

                LD      A,C
                OUT     (CONSOLE_PORT),A          ; salida por puerto, para emuladores que lo simulen

                LD      HL,(CONSPTR)
                LD      (HL),A                    ; y además se guarda en CONSBUF, en orden
                INC     HL
                LD      (CONSPTR),HL

                POP     HL
                POP     AF
                RET


;***************************************************************************
;
; TACHE 1
;
;
T1              LD      C,41H
                CALL    PRINTC
                LD      A,1
                CALL    INIES                      ; inicializa su propio semáforo de E/S (unidad 1)

T12             LD      A,1
                LD      BC,0014H                   ; arma un temporizador con cuenta 0014H (20)
                CALL    ARMERH
                CALL    ACTIVH                     ; lo activa
                CALL    DEMES                      ; se bloquea esperando a que el reloj la despierte
                LD      C,41H                      ; al despertar, vuelve a imprimir 'A'
                CALL    PRINTC
                JR      T12                        ; y repite para siempre


; TACHE 2                                          -> tarea de demostración #2: imprime 'B' (42H),
;                                                     con un período más corto (~7 ticks) que T1/T3
;
T2              LD      C,42H
                CALL    PRINTC
                LD      A,2
                CALL    INIES                      ; semáforo de E/S de la unidad 2
T21             LD      A,2
                LD      BC,0007H                   ; cuenta más chica: se despierta más seguido
                CALL    ARMERH
                CALL    ACTIVH
                CALL    DEMES
                LD      C,42H
                CALL    PRINTC
                JR      T21


; TACHE 3                                          -> tarea de demostración #3: imprime 'C' (43H),
;                                                     mismo período que T1 (~20 ticks)
;
T3              LD      L,43H
                LD      C,L
                CALL    PRINTC
                LD      A,3
                CALL    INIES                      ; semáforo de E/S de la unidad 3
T31             LD      A,3
                LD      BC,0014H
                CALL    ARMERH
                CALL    ACTIVH
                CALL    DEMES
                LD      C,43H
                CALL    PRINTC
                JR      T31


;***************************************************************************
;
FINAL           .EQU    $                          ; marca el final del programa (dirección usada
                                        ; en la cabecera ".WORD FINAL" al principio del archivo)
                .END
