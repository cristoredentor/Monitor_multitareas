; MONITEUR
;
                .PROC MNT

; DONNEES FICTIVES

NIL             .EQU    00H
FAUX            .EQU    00H
VRAI            .EQU    01H
                                        ; ETATS DES TACHES
NONCREE         .EQU    00H
PRET            .EQU    01H
ACTIF           .EQU    02H
BLOQUEO          .EQU    03H

                                        ; CONSTANTES DES CTX
                                        ; LG INFO CTX
LONGCTX         .EQU    6
LONGPIL         .EQU    30
LONGDCTX        .EQU    LONGPIL + LONGCTX
                                        ; LG PILE
                                        ; LG CTX
                                        ; CHAMPS DES CTX
CHTPMS          .EQU    0               ; CHAINE PRETES OU A SEMAPHORE
STATUS          .EQU    2               ; ETAT DE LA TACHE
SEMAT           .EQU    3               ; SEMAPHORE BLOQUANT
GARSP           .EQU    4               ; GARAGE SP
                                        ; CONSTANTES DU MONITEUR
NBMCTX          .EQU    20              ; NB MAX CTX
NBSEM           .EQU    20              ; NB MAX SEMAPHORES
NBES            .EQU    8               ; NB MAX E/S
SEMPES          .EQU    NBSEM + NBES

                                        ; 3 PERIPHERIQUES
H0              .EQU    7C0H            ; TIMER 0 CTC
TT              .EQU    0064H           ; CONSTANT T.D.
                                        ; TRANCHE = TT A 25 MS

                .ORG    1000H - 3
                .WORD   INICTX
                .WORD   FINAL
NBIOIO          .EQU    $
                JP      DEBMON

; DONNEES UTILES

                                        ; TABLE CENTRALE
PTRCTXL         .WORD                   ; POINTEUR CTX LIBRE CREATION
NBCTX           .WORD                   ; NB CTX CREES
PTRDTP          .WORD                   ; PTR CTX DEBUT TACHES PRETES
PTRFTP          .WORD                   ;       FIN
PTRTA           .WORD                   ; PTR CTX TACHE EN COURS
                                        ; ZONE MEMOIRE SEMAPHORES
BSEM            .BLOCK  8*SEMPES

                                        ; ZONE MEMOIRE CTX
INICTX          .BLOCK  LONGCTX*NBMCTX

INREVM          .BLOCK  NBES            ; INDICATEURS REVEIL (V/F)

PILSYS          .BLOCK  30              ; PILE SYSTEME
PPILSYS         .BLOCK  1

; TABLE D'ADRESSES DES ROUTINES DE TRAITEMENT D'IT

;***************************************************************************
;
; PRIMITIVES
;
;***************************************************************************

; PRIMITIVE P(#SEMAPHORE)
                LD      A,#SEMAPHORE
                CALL    P
;
P               DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC

                LD      B,A

                CALL    RECHSEM                 ; HL POINTE SEMAPHORE

                LD      A,(HL)
                DEC     A
                LD      (HL),A                   ; OPTEUR = OPTEUR - 1

                JP      M,WAIT                   ; SI OPTEUR < 0 ALORS WAIT

                POP     BC                       ; NON BLOQUEE, CONTINUER
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


WAIT            PUSH    IX                       ; BLOCAGE TACHE EXECUTANT P
                PUSH    IY

                EX      DE,HL
                PUSH    DE
                POP     IY                       ; DE,IY POINTENT SEMAPHORE

                LD      IX,(PTRTA)               ; IX POINTE CTX TACHE EN COURS

                LD      L,(IX + CHTPMS)          ; EXTRAIRE TETE TACHES PRETES
                LD      H,(IX + CHTPMS + 1)
                LD      (PTRDTP),HL

                LD      (IX + CHTPMS),NIL        ; AJOUTER A TETE ATTENTE SEM
                LD      (IX + CHTPMS + 1),NIL
                LD      (IX + STATUS),BLOQUEO
                LD      (IX + SEMAT),B

                LD      A,(IY + 1)
                AND     A                        ; A = A-T-IL FALLU BLOQUER ?
                JR      NZ,NOVIDER

                LD      (IY + 1),E               ; FILE VIDE
                LD      (IY + 2),D               ; PTR DEBUT FILE
                JR      CONTW
NOVIDER         LD      L,(IY + 3)
                LD      H,(IY + 4)
                PUSH    HL
                POP     IX
                LD      (IX + CHTPMS),E
                LD      (IX + CHTPMS + 1),D      ; CHAINAGE
CONTW           LD      (IY + 3),E
                LD      (IY + 4),D               ; PTR FIN FILE

                JP      DISP


;
; SOUSPROGRAMME RECHSEM     ENTREE   A=#SEMAPHORE
;                           SORTIE   HL=@ SEMAPHORE
;
RECHSEM         RLCA
                RLCA
                RLCA                             ; MULT. PAR 8
                LD      E,A
                LD      D,0
                LD      HL,BSEM
                ADD     HL,DE
                RET


;***************************************************************************
;
; PRIMITIVE V(#SEMAPHORE)
                LD      A,#SEMAPHORE
                CALL    V
;
V               DI

                PUSH    AF
                PUSH    HL
                PUSH    DE

                CALL    RECHSEM                  ; HL POINTE SEMAPHORE

                LD      A,(HL)
                INC     A
                LD      (HL),A                   ; OPTEUR = OPTEUR + 1

                JP      M,SIGNAL
                JP      Z,SIGNAL                 ; DEBLOCAGE D'UNE TACHE

                JP      FINV                     ; CONTINUER

SIGNAL          PUSH    HL
                POP     IY                       ; IY POINTE SEMAPHORE

                LD      E,(IY + 1)
                LD      D,(IY + 2)               ; EXTRAIRE 1 CTX FILE SEM
                PUSH    DE
                POP     IX                       ; DE,IX POINTENT TACHE DEBLOQ

                LD      A,(HL)
                CP      0
                JR      NZ,NOVIDEV
                LD      (IY + 1),NIL
                LD      (IY + 2),NIL
                LD      (IY + 3),NIL
                LD      (IY + 4),NIL             ; LA FILE EST VIDE
                JR      CONTV
NOVIDEV         LD      L,(IX + CHTPMS)
                LD      H,(IX + CHTPMS + 1)      ; LA FILE N'EST PAS VIDE
                LD      (IY + 1),L
                LD      (IY + 2),H               ; CHAINAGE FILE

CONTV           LD      (IX + CHTPMS),NIL        ; AJOUTER A FILE TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL
                LD      (IX + STATUS),PRET

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
                LD      B,CPTE
                LD      A,#SEMAPHORE
                CALL    INISEM
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
                LD      (IX + 2),NIL
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
; DISPATCHER
;
; APPELLE PAR :  PRIMITIVE P LORS D'UN BLOCAGE
;                PRIMITIVE PASS SI FILE TACHES PRETES NON VIDE
;
STOSP           .WORD                            ; GARAGE TEMPORAL SP

DISP            DI

                LD      IX,(PTRTA)               ; SAUVEGARDER CTX TACHE COURS
                LD      (STOSP),SP               ;   SEULEMENT SP
                LD      HL,(STOSP)
                LD      (IX + GARSP),L
                LD      (IX + GARSP + 1),H

DISPP           LD      HL,(PTRDTP)              ; RESTAURER CTX 1ERE TACHE PRETE
                LD      (PTRTA),HL
                PUSH    HL
                POP     IX
                LD      (IX + STATUS),ACTIF
                LD      L,(IX + GARSP)
                LD      H,(IX + GARSP + 1)
                LD      SP,HL                    ; RESTAURATION SP
                POP     IY
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF                       ; RESTAURATION REGISTRES

                EI
                RET


;***************************************************************************
;
; PRIMITIVE PASS                    ; PASSE LA MAIN
                CALL    PASS
;
; SI ON VEUT UTILISER "TIME SLICING", IL FAUT ACTIVER "UNITE E/S #0"
; LA ROUTINE DE TRAITEMENT D'IT DE L'HORLOGE FERA PASS POUR QUITTER LE
; PROCESSEUR A LA TACHE EN COURS

PASS            PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX
                PUSH    IY

                LD      IX,(PTRTA)               ; REGARDER FILE TACHES PRETES
                LD      L,(IX + CHTPMS)          ; IX POINTE TACHE ACTIVE
                LD      H,(IX + CHTPMS + 1)      ; HL POINTE SUIVANTE TACHE PRETE
                LD      A,NIL
                CP      L
                JR      NZ,CONPASS
                CP      H
                JR      NZ,CONPASS

FINPASS         POP     IY                       ; FILE TACHES PRETES VIDE
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RET                              ; CONTINUER

CONPASS         LD      (PTRDTP),HL              ; EXTRAIRE TETE TACHES PRETES

                LD      DE,(PTRTA)
                LD      (IX + CHTPMS),NIL        ; AJOUTER FIN TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL
                LD      (IX + STATUS),PRET
                LD      HL,(PTRFTP)
                PUSH    HL
                POP     IY                       ; IY POINTE FIN TACHES PRETES
                LD      (IY + CHTPMS),E
                LD      (IY + CHTPMS + 1),D
                LD      (PTRFTP),DE

                JP      DISP                     ; REND LA MAIN


;***************************************************************************
;
; PRIMITIVE DEMES(#UNITE)                        DEMANDE E/S
                LD      A,#UNITE
                CALL    DEMES

DEMES           DI

                ADD     A,NBSEM+NBES

                JP      P                        ; PRIMITIVE P


;***************************************************************************
;                                                 SIGNAL NON MEMORISE
                LD      A,#UNITE
                CALL    FINES
;                                                 A NON DETRUIT A LA SORTIE
FINES           DI

                PUSH    HL
                PUSH    DE
                PUSH    IX

                LD      E,A
                LD      D,0
                LD      HL,INREVM
                ADD     HL,DE
                LD      (HL),FAUX                ; NON REVEILLE PAR HORLOGE

                ADD     A,NBSEM
                PUSH    AF
                CALL    RECHSEM
                PUSH    HL
                POP     IX                       ; IX POINTE SEMAPHORE
                LD      (IX + 5),FAUX            ; INHIBITION T.D.
                LD      A,(IX + 0)               ; A = OPTEUR SEMAPHORE
                CP      0
                JP      Z,APV

                POP     AF
                POP     IX
                POP     DE
                POP     HL

                EI
                RET

APV             POP     AF
                POP     IX
                POP     DE
                POP     HL

                JP      V


;***************************************************************************
;
; PRIMITIVE INIES(#UNITE)                        INITIALISATION SEMAPHORE E/S A 0
                LD      A,#UNITE
                CALL    INIES

INIES           DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                LD      E,A
                LD      D,0
                LD      HL,INREVM
                ADD     HL,DE
                LD      (HL),FAUX                ; NON REVEILLE PAR HORLOGE

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX                       ; IX POINTE SEMAPHORE

                LD      (IX + 0),0               ; OPTEUR = 0
                LD      (IX + 1),NIL
                LD      (IX + 2),NIL
                LD      (IX + 3),NIL
                LD      (IX + 4),NIL
                LD      (IX + 5),FAUX            ; INHIBITION T.D.

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE ARMERH(COMPTE,#UNITE)                 INITIALISATION OPTEUR T.D.
                LD      C,COMPTE.L
                LD      B,COMPTE.H
                LD      A,#UNITE
                CALL    ARMERH

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
                LD      (HL),FAUX                ; NON REVEILLE PAR HORLOGE

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX
                LD      (IX + 5),FAUX
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
                LD      A,#UNITE
                CALL    ACTIVH

ACTIVH          DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX

                LD      (IX + 5),VRAI

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE SUSPH(#UNITE)                         SUSPENSION TEMPORAL T.D.
                LD      A,#UNITE
                CALL    SUSPH

SUSPH           DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    IX

                ADD     A,NBSEM
                CALL    RECHSEM
                PUSH    HL
                POP     IX

                LD      (IX + 5),FAUX            ; INHIBITION T.D.

                POP     IX
                POP     DE
                POP     HL
                POP     AF

                EI
                RET


;***************************************************************************
;
; PRIMITIVE CREER(@DEBUT,ACTX)                    CREATION CTX
                LD      HL,@DEBUT PGM
                CALL    CREER

CREER           DI

                PUSH    IX
                PUSH    HL
                PUSH    DE
                PUSH    HL

                LD      IX,(PTRCTXL)             ; IX POINTE CTX LIBRE

                LD      HL,(PTRCTXL)
                LD      E,LONGDCTX
                LD      D,0
                ADD     HL,DE                    ; HL POINTE CTX SUIVANT
                LD      (PTRCTXL),HL             ; ACTUALISATION PTRCTXL

                DEC     HL                       ; HL POINTE FOND FILE
                EX      DE,HL
                POP     HL
                PUSH    HL                       ; @ DEBUT PGM
                EX      DE,HL
                LD      (HL),D                   ; DE = @ DEBUT PGM
                DEC     HL
                LD      (HL),E                   ; @ DEBUT AU FOND PILE
                LD      B,6                      ; INITIALISATION REGISTRES A 0
INIREG          DEC     HL
                LD      (HL),0
                DEC     HL
                LD      (HL),0
                DJNZ    INIREG

                LD      (IX + GARSP),L
                LD      (IX + GARSP + 1),H      ; INITIALISATION SP

                LD      (IX + STATUS),PRET       ; ETAT = PRET

                LD      (IX + CHTPMS),NIL        ; CHAINAGE TACHES PRETES
                LD      (IX + CHTPMS + 1),NIL
                LD      A,(NBCTX)
                CP      0                        ; FILE VIDE ?
                JR      NZ,FTPNV
                LD      (PTRDTP),IX              ; FILE VIDE
                LD      (PTRFTP),IX
                JR      SUITCREAR
FTPNV           PUSH    IX                       ; FILE NON VIDE
                POP     DE                       ; DE POINTE CTX A CREER
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
                LD      (NBCTX),A

                EI
                RET


;***************************************************************************
;
                LD      A,#CTX
                CALL    DETRUIX
                                                  ; #CTX > 0
DETRUIX         DI

                PUSH    AF
                PUSH    HL
                PUSH    DE
                PUSH    BC
                PUSH    IX
                PUSH    IY

                LD      HL,INICTX                ; RECHERCHE CTX
                LD      E,LONGCTX
                LD      D,0
                LD      B,A
BUSCTX          ADD     HL,DE
                DJNZ    BUSCTX                    ; HL POINTE CTX A DETRUIRE
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
                CP      NIL
                JR      NZ,FINDET
                LD      A,(IX + CHTPMS + 1)
                CP      NIL
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

                LD      A,(IY + 0)
                INC     A
                LD      (IY + 0),A                ; OPTEUR = OPTEUR + 1

                CP      0
                JR      NZ,NOVIDBL                ; FILE VIDE ?

                LD      (IY + 1),NIL              ; FILE VIDE
                LD      (IY + 2),NIL
                LD      (IY + 3),NIL
                LD      (IY + 4),NIL
                LD      (IY + 5),FAUX
                JR      FINDET

NOVIDBL         LD      L,(IY + 1)                ; FILE NON VIDE
                LD      H,(IY + 2)                ; EN TETE ?
                LD      A,L
                CP      0
                JR      NZ,STELIM

                LD      A,(IX + CHTPMS)           ; EN TETE
                LD      (IY + 1),A
                LD      A,(IX + CHTPMS + 1)
                LD      (IY + 1),A                ; DECHAINAGE
                JR      ULTFIL

STELIM          PUSH    IY                        ; PAS EN TETE, GARDER PTR SEM
                CALL    DECHAIN                    ; DECHAINAGE

ULTFIL          LD      A,(IX + CHTPMS)            ; DERNIERE ?
                CP      NIL
                JR      NZ,FINDET1
                LD      A,(IX + CHTPMS + 1)
                CP      NIL
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
                LD      E,LONGCTX
                LD      D,0

BOUX            LD      L,(IY + CHTPMS)             ; RECHERCHE CTX QUI POINTE
                LD      H,(IY + CHTPMS + 1)         ;   CTX A DECHAINER
                LD      A,C
                CP      L
                JR      NZ,ADDIX
                LD      A,B
                CP      H
                JR      Z,TROUVE
ADDIX           ADD     IY,DE
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

                LD      SP,PPILSYS                ; INITIALISATION SP

                LD      A,0
                LD      (NBCTX),A                 ; INITIALISATION NB CTX

                LD      HL,INICTX
                LD      (PTRCTXL),HL              ; INITIALISATION PTR CTX

                LD      (PTRTA),HL                ; TACHE ACTIVE = TACHE FOND
                LD      HL,TACHFON                ; CREATION TACHE FOND
                CALL    CREER

                JP      DISP                      ; ACTIVATION TACHE FOND


;***************************************************************************
;
; TACHE DE FOND
;
TACHFON         CALL    INIPER                    ; INIT PERIPHERIQUES

                LD      BC,0002H
                LD      A,0
                CALL    ARMERH                    ; TIME SLICING
                CALL    ACTIVH

                LD      HL,T1                      ; CREATION TACHE 1
                CALL    CREER
                LD      HL,T2                      ; CREATION TACHE 2
                CALL    CREER
                LD      HL,T3                      ; CREATION TACHE 3
                CALL    CREER

SIEMPRE         CALL    PASS                       ; BOUCLE TOUJOURS
                JR      SIEMPRE


;
INIPER          LD      HL,TARTIT                  ; INITIALISATION REGISTRE I
                LD      A,H
                LD      I,A

                CALL    INICTC                     ; INITIALISATION CTC
                CALL    INVSIO                     ; INVALIDATION IT SIO

                IM      2
                EI
                RET


;
; INVALIDATION IT SIO
;
INVSIO          LD      A,0D0H
                OUT     (079H),A
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

                LD      IX,BSEM
                LD      E,0
                LD      D,0
                LD      B,SEMPES
FS              LD      (IX + 5),FAUX              ; T.D. INACTIFS
                ADD     IX,DE
                DJNZ    FS

                LD      A,0
                OUT     (H0),A                     ; VECTEUR IT AU CTC
                                                     ; L = 0
                LD      A,0B7H
                OUT     (H0),A                      ; MODE D'OPERATION

                LD      A,0
                OUT     (H0),A                      ; CONSTANT DE TEMPS

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
                RLCA
                LD      E,A
                LD      D,0
                ADD     IX,DE
                PUSH    IX
                POP     IY                          ; IY POINTE SEM E/S 0

                LD      E,8
                LD      D,0
                ADD     IX,DE
                LD      HL,INREVM
                INC     HL
                LD      B,NBES - 1
                LD      C,1                          ; IX POINTE SEM E/S 1
                                                       ; HL POINTE IND. DE REVEIL

REVISAR         LD      A,(IX + 5)                   ; EN ATTENTE DE REVEIL ?
                CP      FAUX
                JR      Z,SUSEMES

                LD      E,(IX + 6)                   ; OUI
                LD      D,(IX + 7)
                DEC     DE
                LD      (IX + 6),E
                LD      (IX + 7),D                   ; T.D. ?
                LD      A,0
                CP      E
                JR      NZ,SUSEMES
                CP      D
                JR      NZ,SUSEMES

                LD      A,C                          ; OUI
                CALL    FINES                        ; REVEIL
                LD      (HL),VRAI                    ; REVEILLE PAR L'HORLOGE
                LD      (IX + 5),FAUX

SUSEMES         INC     HL                           ; CONTINUER A VERIFIER T.D.
                LD      E,8
                LD      D,0
                ADD     IX,DE
                INC     C
                DJNZ    REVISAR

                LD      A,(IY + 5)                   ; TIME SLICING ?
                CP      VRAI
                JR      NZ,FINITH

                LD      E,(IY + 6)                   ; OUI
                LD      D,(IY + 7)
                DEC     DE
                LD      (IY + 6),E
                LD      (IY + 7),D                   ; FIN TRANCHE ?
                LD      A,0
                CP      E
                JR      NZ,FINITH
                CP      D
                JR      NZ,FINITH

                LD      DE,TT                        ; OUI
                LD      (IY + 6),E
                LD      (IY + 7),D
                JR      TEMPART

FINITH          POP     IY
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                EI
                RETI

TEMPART         LD      HL,TIMSLIC                   ; FAIRE PASS
                PUSH    HL
                RETI

TIMSLIC         POP     IY
                POP     IX
                POP     BC
                POP     DE
                POP     HL
                POP     AF

                JP      PASS


;***************************************************************************

                EI
                RET


;***************************************************************************
;
; TACHE 1
;
T1              LD      C,41H
                CALL    014H
                LD      A,1
                CALL    INIES
T12             LD      A,1
                LD      BC,0014H
                CALL    ARMERH
                CALL    ACTIVH
                CALL    DEMES
                LD      C,41H
                CALL    014H
                JR      T12


; TACHE 2
;
T2              LD      C,42H
                CALL    014H
                LD      A,2
                CALL    INIES
T21             LD      A,2
                LD      BC,0007H
                CALL    ARMERH
                CALL    ACTIVH
                CALL    DEMES
                LD      C,42H
                CALL    014H
                JR      T21


; TACHE 3
;
T3              LD      L,43H
                LD      C,L
                CALL    014H
                LD      A,3
                CALL    INIES
T31             LD      A,3
                LD      BC,0014H
                CALL    ARMERH
                CALL    ACTIVH
                CALL    DEMES
                LD      C,43H
                CALL    014H
                JR      T31


;***************************************************************************
;
FINAL           .EQU    $
                .END