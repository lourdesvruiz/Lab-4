 ; Archivo:	int_tmr0.s
 ; Dispositivo:	PIC16F887
 ; Autor:	José Morales
 ; Compilador:	pic-as (v2.32), MPLABX V5.45
 ;                
 ; Programa:	contador de 4 bits automático que incrementa cada 1 segundo 
 ; presentado en 1 display de 7 segmentos, contador de decenas de segundos 
 ; en un segundo display y contador ascendente y descendente de 4 bits controlado
 ; por 2 pushbuttons 
 ; Hardware:	LEDs en puerto A, pushbuttons con pull ups internas en puerto B,
 ; displays en puertos C y D. 
 ;                       
 ; Creado: 12 ago, 2021
 ; Última modificación: 18 ago, 2021
 
 PROCESSOR 16F887
 #include <xc.inc>
 
 ;configuration word 1
  CONFIG FOSC=INTRC_NOCLKOUT	// Oscillador Interno sin salidas, XT
  CONFIG WDTE=OFF   // WDT disabled (reinicio repetitivo del pic)
  CONFIG PWRTE=OFF   // PWRT enabled  (espera de 72ms al iniciar)
  CONFIG MCLRE=OFF  // El pin de MCLR se utiliza como I/O
  CONFIG CP=OFF	    // Sin protección de código
  CONFIG CPD=OFF    // Sin protección de datos
  
  CONFIG BOREN=OFF  // Sin reinicio cuándo el voltaje de alimentación baja de 4V
  CONFIG IESO=OFF   // Reinicio sin cambio de reloj de interno a externo
  CONFIG FCMEN=OFF  // Cambio de reloj externo a interno en caso de fallo
  CONFIG LVP=OFF        // programación en bajo voltaje permitida
 
 ;configuration word 2
  CONFIG WRT=OFF    // Protección de autoescritura por el programa desactivada
  CONFIG BOR4V=BOR40V // Reinicio abajo de 4V, (BOR21V=2.1V)

  
;------------------macros-------------------  
;--------calculos de temporizador--------
;temporizador = 4*TOSC*TMR0*Prescaler 
;TOSC = 1/FOSC 
;TMR0 = 256 - N (el cual indica el valor a cargar en TMR0)
;¿valor necesario para 0.01s? 
;(4*(1/4MHz))*TMR0*256 = 0.01s
;TMR0 = 39
;256-39 = 217 / N=217
reinicio_timer0   macro  ;macro para reiniciar el contador del timer0
    banksel  PORTA 
    movlw    217
    movwf    TMR0
    bcf      T0IF    ;se apaga la bandera luego del reinicio
    endm 
    
;---------------variables--------------------    
 PSECT udata_bank0 ;common memory
 contador1:      DS 1
 contador2:      DS 1
 contador3:      DS 1
        
 PSECT udata_shr ;common memory
    W_TEMP:	 DS  1 ;1 byte
    STATUS_TEMP: DS  1 ;1 byte
        
 PSECT resVect, class=CODE, abs, delta=2
 ;--------------vector reset------------------
 ORG 00h	;posición 0000h para el reset
 resetVec:
     PAGESEL main
     goto main
 
 PSECT intVect, class=CODE, abs, delta=2
 ;--------------interrupt vector------------------
 ORG 04h	      ;posición 0004h para las interrupciones (vector de interrupciones)
 push:                ;guardar las variables actuales a registros temporales, pasa la interrupción, y luego volvemos a cargarlos
    movwf   W_TEMP
    swapf   STATUS, W ;swap para no tocar las banderas (pero con valores cambiados)
    movwf   STATUS_TEMP
    
 isr:
    btfsc   RBIF       ;si la bandera esta prendida entra a la siguiente instruccion
    call    interrupt_oc_b
    btfsc   T0IF       ;si la bandera esta prendida entra a la siguiente instruccion
    call    interrupt_tmr0
    
 pop:                  ;regresamos a los registros originales sin modificar banderas 
    swapf   STATUS_TEMP, W
    movwf   STATUS
    swapf   W_TEMP, F
    swapf   W_TEMP, W  ;se hace un doble swap 
    retfie             ;regreso de interrupción 
 
 ;-------------subrutinas de interrupcion-----
interrupt_oc_b:                ;subrutina para interrupción en el Puerto B 
    banksel  PORTA
    btfss    PORTB, 0
    call     inc_porta
    btfss    PORTB, 1
    call     dec_porta
    bcf      RBIF 
    return

interrupt_tmr0:                ;subrutina para la interrupción en el contador del timer0
    reinicio_timer0
    incf     contador1
    movf     contador1, W 
    sublw    100
    btfsc    STATUS, 2
    call     cont_1sec
    return
 
 PSECT code, delta=2, abs
 ORG 100h	; posición para el código
 
 ;configuración de tablas de 7 segmentos
 seg_7_tablas:
    clrf   PCLATH
    bsf    PCLATH, 0   ; PCLATH = 01 PCL = 02
    andlw  0x0f        ; limitar a numero "f", me va a poner en 0 todo lo superior y lo inferior, lo deja pasar (cualquier numero < 16)
    addwf  PCL         ; PC = PCLATH + PCL + W (PCL apunta a linea 103) (PC apunta a la siguiente linea + el valor que se sumo)
    retlw  00111111B   ;return que tambien me devuelve una literal (cuando esta en 0, me debe de devolver ese valor)
    retlw  00000110B   ;1
    retlw  01011011B   ;2
    retlw  01001111B   ;3
    retlw  01100110B   ;4
    retlw  01101101B   ;5
    retlw  01111101B   ;6
    retlw  00000111B   ;7
    retlw  01111111B   ;8
    retlw  01101111B   ;9
    retlw  01110111B   ;A
    retlw  01111100B   ;B
    retlw  00111001B   ;C
    retlw  01011110B   ;D
    retlw  01111001B   ;E
    retlw  01110001B   ;F
 
 
 ;-------------configuración------------------
 main:
    call    config_io
    call    config_clock
    call    config_timer0
    call    config_interrupt_oc_b
    call    config_int_enable
    banksel PORTA
    
  
;------------loop principal---------          
 loop:
   
    call   cont_10secs 
    
    
    goto    loop        ; loop forever

 ;------------sub rutinas------------ 
   
config_clock:
    banksel OSCCON 
    bsf     IRCF2   ;IRCF = 110 4MHz 
    bsf     IRCF1
    bcf     IRCF0
    bsf     SCS     ;configurar reloj interno
    return

config_timer0:
    banksel TRISA 
    ;configurar OPTION_REG
    bcf     T0CS   ;reloj interno (utlizar ciclo de reloj)
    bcf     PSA    ;asignar el Prescaler a TMR0
    bsf     PS2
    bsf     PS1 
    bsf     PS0    ;PS = 111 (1:256)
    reinicio_timer0
    return

    
config_interrupt_oc_b:
    banksel TRISA
    bsf     IOCB, 0
    bsf     IOCB, 1  ;habilitar el interrupt on-change
    
    banksel PORTA 
    movf    PORTB, W ;al leer termina la condicion de "mismatch" (de ser distintos)
    bcf     RBIF     ;se settea la bandera 
    return
 
config_io:
    banksel ANSEL   ;nos lleva a banco 3 (11)
    clrf    ANSEL   ;configuración de pines digitales 
    clrf    ANSELH
    
    banksel TRISA    ;nos lleva a banco 1 (01)
    clrf    TRISA    ;salida para LEDs (contador)
    bsf     TRISB, 0 ; RB0 como entrada para pushbutton
    bsf     TRISB, 1 ; RB1 como entrada para pushbutton
    clrf    TRISC    ; salida para contador del TMR0 ;cada segundo 
    clrf    TRISD    ;salida para contador de 10 segundos 
    
    ;----------------------CONFIGURACIÓN WEAK PULL UPS-------------------
    bcf     OPTION_REG, 7 ;bit con lógica negada (RBPU) para habilitar pull ups 
    bsf     WPUB, 0
    bsf     WPUB, 1       ;habilitar weak pull ups de RB0 Y RB1 (entradas)
    
    ;---------------------valores iniciales en banco 00--------------------------
    banksel PORTA   ;nos lleva a banco 0 (00)
    clrf    PORTA 
    clrf    PORTB 
    clrf    PORTC
    clrf    PORTD
    
    return 
    
config_int_enable: 
    bsf     GIE    ;Intcon (interrupciones globales habilitadas)
    bsf     RBIE
    bcf     RBIF
    
    bsf     T0IE 
    bcf     T0IF 
    return 
    
inc_porta:          ;subrutina de incrementar 
    incf   PORTA
    btfsc  PORTA, 4
    clrf   PORTA
    return

dec_porta:          ;subrutina de decrementar  
   decf  PORTA
   btfsc PORTA, 7
   call  four            ;llama a la subrutina four
   return 
 
 four:                   ;se hace un clear en los 4 bits más signifactivos 
    bcf    PORTA, 4
    bcf    PORTA, 5
    bcf    PORTA, 6
    bcf    PORTA, 7
    return
    
cont_1sec:              ;incrementar el contador del display cada 1 segundo  
   clrf     contador1
   incf     contador2 
   btfsc    contador2, 4 ;limitar a 4 bits 
   clrf     contador2  
   return  
    
cont_10secs:
    movf     contador2, W  ;mostrar el contador de segundos en el display de 7 segs
    call     seg_7_tablas
    movwf    PORTC 
    movf     contador2, W   ;volver a mover el valor del contador a W 
    sublw    10             ;restarle 10 y ver si el resultado da 0
    btfsc    ZERO           ;si Z=0 entonces el bit se "settea" y llama a la subrutina 
    call     reinicio
    return 
    
reinicio:                    ;incrementa al tercer contador (contador de decena de segundos)
    clrf      contador2
    incf      contador3
   
    movf      contador3, W 
    call      seg_7_tablas   ;muestra el contador en un segundo display
    movwf     PORTD 
    call      oneminute
    return 
    
oneminute:
    movf     contador3, W     ;se limita el contador a que solo cuenta 1 minuto 
    sublw    6
    btfsc    ZERO
    clrf     contador3
    return 
END 



