# Blade & Sorcery com o StormVR

Use a versão PC de Blade & Sorcery em modo SteamVR. O celular serve de visor e envia a orientação da cabeça, o movimento das mãos e o gesto de segurar. [Blade & Sorcery no Steam](https://store.steampowered.com/app/629730/Blade_and_Sorcery/)

1. Feche o SteamVR antes de executar o instalador do driver. Para instalação manual pelo ZIP, copie a pasta `stormvr` para `SteamVR\drivers`. Abra o SteamVR. No painel **Controles**, ative **Posição da mão**, **Direção da mão** e **Pinça = segurar (Grip)** para cada mão que vai pegar objetos. Se o objetivo da outra mão for acionar o gatilho, nessa mão deixe **Pinça = trigger** ativa e Grip desativado.
2. Deixe PC e celular na mesma rede e configure o IPv4 do PC no StormVR. O driver usa UDP 5556 para a cabeça e UDP 5557 para as mãos.
3. No Android, pareie com o Sunshine pelo menu **Moonlight**. Em **Sala VR → Mãos e 6DoF**, ative o rastreamento de duas mãos e o envio de posição e pinça no **Modo PC**. Use a saída estereoscópica do compositor SteamVR no Moonlight. Consulte o painel de diagnóstico da Sala VR para ver FPS da câmera, FPS da detecção e tempo de processamento.
4. No iPhone, selecione **Headset 6DoF** e ative **Rastrear mãos e pinça**. O port usa o transmissor de vídeo para iOS documentado em [Source/ios/README.md](Source/ios/README.md).
5. Deixe a câmera traseira descoberta. Abra uma mão à frente da lente, alcance um objeto no jogo e una o indicador ao polegar para segurá-lo. Abra a pinça para soltar. Se a mão sair do quadro e voltar fechada, abra-a antes de tentar segurar de novo.

O modo cobre rastreamento e Grip sem controle físico. Locomoção por analógico e ações de menu ainda usam os outros comandos do perfil SteamVR. A câmera estima a posição enquanto a mão está no campo de visão. Comece testando segurando e soltando um objeto parado antes de testar movimentos rápidos ou com uma mão encobrindo a outra.
