# Instalador do StormVR Driver para Windows

Compile e organize o driver Windows como em [../LEIA-ME.txt](../LEIA-ME.txt). Monte uma pasta de entrada contendo a subpasta `stormvr` com o driver, a interface e os recursos. Copie `web` e `painel_python` para dentro da subpasta `stormvr`. Na raiz da pasta de entrada, inclua `MAOS-STEAMVR.md`, `LICENSE` e o arquivo de licença do OpenVR com o nome `LICENSE-OpenVR.txt`.

Use o compilador NSIS 3.12 para gerar o executável.

```powershell
& $makensis /INPUTCHARSET UTF8 "/DSTORMVR_PAYLOAD=$payload" "/DSTORMVR_OUTPUT=$output" "./StormVR.nsi"
```

O instalador grava os arquivos no perfil local do usuário e usa o `vrpathreg.exe` do próprio SteamVR. Em **Aplicativos instalados**, procure **StormVR Driver** para desinstalar. Uma instalação manual na pasta `SteamVR\drivers\stormvr` precisa ser movida antes de registrar o novo driver.
