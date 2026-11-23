# Componentes do Moonlight

O cliente Apollo do StormVR incorpora uma parte do [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios/tree/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a) sob a GPLv3, com o texto em `LICENSE.txt`. O código em `Client` foi adaptado para parear com um endereço informado no StormVR, listar aplicativos, decodificar vídeo H.264 com VideoToolbox e entregar quadros ao visor. As partes originais do StormVR conservam a licença na raiz. A combinação usa as permissões de combinação da GPLv3 e AGPLv3.

- `Core` contém código do [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c/tree/f900dd4767759c7b9d0e93bcea666b55c69ea62f), com as licenças fornecidas junto às fontes.
- `Audio` contém cabeçalhos e bibliotecas estáticas SDL2 e Opus para iOS e simulador, fornecidos pelo [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios/tree/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a/libs). Os scripts upstream identificam as fontes e compilam as bibliotecas. [Scripts de build](https://github.com/moonlight-stream/moonlight-ios/tree/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a/BuildScripts)
- O Xcode resolve o [OpenSSL-Package 3.6.3000](https://github.com/krzyzanowskim/OpenSSL-Package/tree/3.6.3000) para TLS e criptografia de sessão.
