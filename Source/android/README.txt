StormVR Android (v0.4.1) - UM app, UMA sala VR
============================================
ATUALIZAÇÃO 0.4.1 (mãos no SteamVR)
  Build: JDK 17, Android SDK 35, Build Tools 34.0.0 e NDK 27.0.12077973. O Gradle Wrapper usa 8.9.
  Abra a pasta Source/android no Android Studio ou rode gradlew.bat :app:testDebugUnitTest :app:assembleDebug.
  O APK sai em app/build/outputs/apk/debug. Configure o SDK no Android Studio ou com ANDROID_HOME.
  Modelo de mãos incluído no APK. O rastreamento funciona sem baixar o modelo na primeira execução.
  Para Blade & Sorcery (SteamVR no PC), veja a configuração em ../../MAOS-STEAMVR.md.

O antigo app VR Room e a sala 3D do StormVR foram FUNDIDOS numa sala so (pacote com.stormvr.app.vrroom, VrRoomActivity),
usando o motor do VR Room (mais completo) e trazendo da sala do StormVR o que ele nao tinha.

TELA INICIAL
  Rastreamento (SteamVR)      envia a orientacao da cabeca ao driver do PC (UDP 5556).
  Sala VR                     a sala unica (abaixo).
  Modo controle               este celular vira um controle 3DoF: orientacao do celular + botoes na tela (analogico, Trigger,
                              R2, Grip, A, B, X, Y, Start, L3) + botoes de volume mapeaveis. Envia o mesmo pacote do ESP32
                              (KbtPacket) por UDP ao PC (porta 5555) e/ou ao celular que esta no headset.
  Permissoes Bluetooth        uma vez, para conectar os ESP32 por Bluetooth.

SALA VR - O QUE TEM (do VR Room)
  Navegador (WebView) numa tela virtual curva ou plana, teclado virtual que digita na pagina, estereo, 6DoF por camera (ARCore),
  rastreamento de maos (MediaPipe) com pinca = clique, modo camera/passthrough, modo leve, gamepad.
  Distancia entre os olhos (profundidade 3D), distancia entre o centro das 2 imagens e tolerancia/estabilizacao do clique.
SALA VR - O QUE VEIO DA SALA DO STORMVR
  Controles 3DoF: ate DOIS ao mesmo tempo (ESP32 por Bluetooth/Wi-Fi e/ou outros celulares), um por mao. Apontar = laser.
  BOTOES (tabela unica, igual no gamepad e nos controles; ver AUDITORIA_CONFIGURACOES.md):
      Trigger / R2 / L2 / pinca = clique e arrastar     analogico (controles) e L1/R1 (gamepad) = rolar a pagina
      B = voltar (fecha o teclado)  X = recarregar (apagar)  Y = centrar a vista (espaco)  Start = liga/desliga o 3D (Enter)
      clique do analogico (L3) = abre/fecha o teclado   A = tecla em foco do teclado
  TOQUE COM DOIS DEDOS: cada controle (ou cada mao com pinca) e um dedo. Os dois ao mesmo tempo na tela = pinca de zoom na pagina.
  TELA CHEIA (botao na tela inicial): so a pagina ocupando o celular inteiro, toque direto multidedo; "esticar" preenche as bordas.
      Sai com o botao Voltar do Android. Sem controles/sensores/camera (economiza bateria), exceto se o "Modo PC" estiver ligado.
  MODO PC (SteamVR): envia ao driver a cabeca (mesmo pacote do rastreamento) e as MAOS rastreadas pela camera (UDP 5557):
      POSICAO das maos e PINCA (= trigger no SteamVR), cada uma ligavel separadamente nas opcoes. Usa o IP do PC da tela inicial.
      Se o servico "Rastreamento (SteamVR)" ja estiver rodando, a sala manda so as maos (nao duplica a cabeca).
  Distorcao de lente (k1; k2 acompanha) e FOV ajustavel - mesma convencao do driver SteamVR. Desligada por padrao.
  Conteudo 3D lado a lado (SBS): cada olho ve uma metade da tela (para videos 3D no navegador).
  Clique por olhar: sem controle nem maos, o laser segue a cabeca e clica sozinho (~1,2 s) nos botoes, teclado e cantos.
  Todos os ajustes ficam na tela inicial da sala e sao salvos.
  MOONLIGHT: ainda nao embutido (ver MOONLIGHT_PLANO.md). A sala ja tem o ponto de ligacao (ScreenSource).

DOIS ESP32 / DOIS CELULARES
  Cada ESP32 anuncia StormVR-Ctl-R ou -L por Bluetooth; o app conecta os dois (um por vez). Se dois controles dizem a MESMA
  mao, o segundo vai para a mao livre. Mao do ESP32: segure GRIP+TRIGGER ao ligar (ver firmware) ou use o menu do SteamVR.
  Dependencias: ARCore e MediaPipe (Gradle baixa; internet no primeiro build); usa AndroidX.
  O modelo hand_landmarker.task vem no APK (veja assets/LEIA-ME-VRROOM.txt).

O QUE FOI REMOVIDO DA SALA ANTIGA DO STORMVR (honesto)
  - Modo TV, inclinacao/lado da tela, barra inferior e painel de configuracao dentro do VR: o VR Room tem sala, barra de
    ferramentas e ajustes proprios; os ajustes agora ficam na tela inicial da sala.
  - O gancho de video do Moonlight antigo (RoomBridge/SurfaceTextureSource) e a tela de teste: nunca foram testados. Foram
    substituidos pelo ponto de ligacao ScreenSource (ver MOONLIGHT_PLANO.md).
  - Cardboard SDK nao e usado.

Nada disto foi compilado nem rodado no celular por mim: teste e me mande os erros/prints.

COMPILAR (Android Studio)
  File > Open... pasta android; instale SDK 35, Build Tools 34.0.0 e NDK 27.0.12077973; Sync; Run com o celular conectado.
  Se o Studio disser "Unsupported Modules": remova os modulos listados e use File > Sync Project with Gradle Files.
