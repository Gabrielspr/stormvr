# StormVR para iPhone

O cliente nativo para iOS 17 ou superior usa o protocolo do driver StormVR para Windows. O headset 3DoF usa o giroscópio. O headset 6DoF usa ARKit para acompanhar rotação e deslocamento. O modo controle 3DoF envia a orientação, o analógico e os botões de toque para uma das mãos.

## Configurar o SteamVR

1. Instale o driver StormVR do repositório e habilite o headset no painel StormVR. Selecione o monitor que recebe a imagem do compositor e reinicie o SteamVR.
2. Coloque o PC e o iPhone na mesma rede. Permita no firewall as portas UDP usadas pelo modo selecionado, 5556 para a cabeça, 5557 para as mãos e 5555/5558 para o modo controle direito/esquerdo. Use a porta do painel se tiver alterado a porta da cabeça.
3. Abra o StormVR no iPhone, informe o IPv4 do PC e inicie uma sessão. Autorize o acesso à rede local. Monte o iPhone com o topo à esquerda e toque em **Recentrar** olhando para frente.
4. No painel do driver, verifique se a pose chega e se mover a cabeça para os lados e para cima gira a imagem no sentido correto. No 6DoF, autorize a câmera, mantenha a lente livre e use um ambiente iluminado. Inclinar o corpo ou dar um passo deve mover a posição no SteamVR.

O HUD mostra a taxa de pacotes aceitos pelo sistema de rede do iPhone. Confira o recebimento no painel do driver. Toque na imagem para ocultar ou mostrar o HUD.

## Mãos e pinça

No **Headset 6DoF**, ligue **Rastrear mãos e pinça**. Habilite **Posição da mão** e **Direção da mão** na aba **Controles** do driver. Com o driver atualizado, selecione **Pinça = segurar (Grip)** por mão para pegar objetos no SteamVR. Para usar a pinça como gatilho, desative Grip e deixe **Pinça = trigger** marcada. A mão precisa abrir antes de fechar a primeira pinça após voltar ao quadro.

O Vision identifica até duas mãos. A profundidade é estimada pelo tamanho da palma na imagem. A estimativa varia com a distância, o ângulo da mão e a iluminação. O cliente transmite posição da palma, direção estimada e estado da pinça. Como teste no SteamVR, mantenha uma mão visível, retire a outra da câmera durante uma pinça e confirme que o gatilho da mão retirada solta.

No Android, o prazo de perda passou a ser independente para cada mão, e o fechamento da pinça precisa aparecer em dois quadros consecutivos.

## Exibir a imagem do PC

No Windows, com Python 3 e FFmpeg disponíveis, execute na raiz do repositório:

```powershell
python Source/pc_driver/tools/stream_ios.py --bind 192.168.1.20 --size 1920x1080 --x 1920 --y 0
```

Substitua o IPv4, a resolução e as coordenadas pelo seu monitor SteamVR. O exemplo usa um monitor à direita de outro que tem 1920 pixels de largura. Se o FFmpeg não estiver no PATH, informe o caminho com `--ffmpeg`. Permita TCP 8089 para esse PC na rede privada. A transmissão local é MJPEG por HTTP e usa um código temporário exibido no terminal. Use em uma rede confiável.

No iPhone, ative **Exibir vídeo do PC** e informe o código exibido. Mantenha **Imagem lado a lado (SBS)** marcada para a saída estereoscópica do SteamVR. No modo mono, a mesma imagem é repetida nos dois olhos. O transmissor entrega sempre o quadro mais recente e não carrega áudio. A qualidade e a latência dependem da captura do monitor e da rede. Este port cobre o cliente SteamVR. Sala VR, Bluetooth ESP32 no celular e Moonlight integrado são recursos da versão Android que ainda não foram portados.

## Compilar e exportar o IPA

Com um Mac e Xcode 16 ou superior, abra `Source/ios/StormVR.xcodeproj`. Em **Signing & Capabilities**, selecione seu **Team** e use um **Bundle Identifier** disponível para ele. Selecione um iPhone conectado e use **Product → Run** para testar. Para gerar um IPA assinado para teste em um aparelho provisionado, selecione **Any iOS Device**, use **Product → Archive** e exporte no Organizer com **Distribute App → Release Testing**. Consulte o [guia da Apple para distribuição em aparelhos registrados](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices/).

Para gerar o IPA sem assinatura:

```bash
bash Source/ios/scripts/package-unsigned.sh
```

Também é possível acessar **Actions → StormVR iPhone → Run workflow** no GitHub depois de integrar a alteração no branch padrão do seu repositório. O job executa a verificação dos pacotes UDP e disponibiliza `StormVR-unsigned.ipa` no artefato da execução. O arquivo precisa de assinatura e provisionamento compatíveis para instalação no iPhone.

No Codemagic, conecte o repositório e selecione um dos workflows do [codemagic.yaml](../../codemagic.yaml). O workflow Ad Hoc usa um certificado e um perfil cadastrado em **Code signing identities**. Se o perfil usar outro bundle ID, ajuste o identificador no YAML e em `PRODUCT_BUNDLE_IDENTIFIER` nas duas configurações de build do projeto.
