Unicode true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "StrFunc.nsh"
!include "x64.nsh"

${StrStr}
${UnStrStr}
${StrTrimNewLines}

!define PRODUCT "StormVR Driver 0.4.2"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\StormVRDriver"
!define STEAMVR_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 250820"

Name "${PRODUCT}"
OutFile "${STORMVR_OUTPUT}"
InstallDir "$LOCALAPPDATA\StormVR\SteamVRDriver"
VIProductVersion "0.4.2.0"
VIAddVersionKey /LANG=1046 "ProductName" "StormVR Driver"
VIAddVersionKey /LANG=1046 "FileDescription" "Instalador do driver StormVR para SteamVR"
VIAddVersionKey /LANG=1046 "FileVersion" "0.4.2"
VIAddVersionKey /LANG=1046 "ProductVersion" "0.4.2"
VIAddVersionKey /LANG=1046 "LegalCopyright" "StormVR contributors"

!ifdef STORMVR_ICON
  !define MUI_ICON "${STORMVR_ICON}"
  !define MUI_UNICON "${STORMVR_ICON}"
!endif

!insertmacro MUI_PAGE_WELCOME
Page custom SteamVRPage SteamVRLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"

Var SteamVR
Var RuntimeEdit
Var DriverPath
Var StagePath
Var BackupPath
Var CommandResult
Var CommandOutput

!macro Fail reason
  DetailPrint "${reason}"
  MessageBox MB_OK|MB_ICONSTOP "${reason}" /SD IDOK
  SetErrorLevel 1
  Abort
!macroend

!macro CleanDirectory path
  ${If} ${FileExists} "${path}\*.*"
    RMDir /r "${path}"
  ${EndIf}
!macroend

!macro InstallerLock
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\StormVRSteamVRDriver") p .r0 ?e'
  Pop $1
  ${If} $0 == 0
  ${OrIf} $1 == 183
    !insertmacro Fail "Já existe outra instalação do StormVR em andamento."
  ${EndIf}
!macroend

!macro RequireClosed context
  nsExec::ExecToStack /TIMEOUT=10000 '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq vrserver.exe" /NH /FO CSV'
  Pop $0
  Pop $1
  ${If} $0 != 0
    !insertmacro Fail "Não foi possível verificar se o SteamVR está fechado."
  ${EndIf}
  !if "${context}" == "uninstall"
    ${UnStrStr} $2 $1 "vrserver.exe"
  !else
    ${StrStr} $2 $1 "vrserver.exe"
  !endif
  ${If} $2 != ""
    !insertmacro Fail "Feche o SteamVR antes de continuar."
  ${EndIf}
!macroend

!macro SelectSteamVR
  SetRegView 64
  ReadRegStr $SteamVR HKCU "${UNINSTALL_KEY}" "SteamVRPath"
  ${IfNot} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
    ReadRegStr $SteamVR HKLM "${STEAMVR_KEY}" "InstallLocation"
  ${EndIf}
  ${IfNot} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
    SetRegView 32
    ReadRegStr $SteamVR HKLM "${STEAMVR_KEY}" "InstallLocation"
    ${IfNot} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
      ReadRegStr $0 HKCU "Software\Valve\Steam" "SteamPath"
      ${If} $0 != ""
        StrCpy $SteamVR "$0\steamapps\common\SteamVR"
      ${Else}
        StrCpy $SteamVR "$PROGRAMFILES32\Steam\steamapps\common\SteamVR"
      ${EndIf}
    ${EndIf}
    SetRegView 64
  ${EndIf}
!macroend

!macro InitPaths
  SetShellVarContext current
  !ifdef STORMVR_TEST
    ReadEnvStr $SteamVR "STORMVR_TEST_RUNTIME"
    ReadEnvStr $INSTDIR "STORMVR_TEST_DEST"
    ${If} $SteamVR == ""
    ${OrIf} $INSTDIR == ""
      Abort
    ${EndIf}
  !else
    StrCpy $INSTDIR "$LOCALAPPDATA\StormVR\SteamVRDriver"
    !insertmacro SelectSteamVR
  !endif
  StrCpy $DriverPath "$INSTDIR\stormvr"
  StrCpy $StagePath "$INSTDIR\.staging"
  StrCpy $BackupPath "$INSTDIR\.previous"
!macroend

Function .onInit
  ${IfNot} ${RunningX64}
    !insertmacro Fail "O driver StormVR exige Windows de 64 bits."
  ${EndIf}
  !insertmacro InstallerLock
  !insertmacro InitPaths
FunctionEnd

Function SteamVRPage
  !insertmacro MUI_HEADER_TEXT "Pasta do SteamVR" "Escolha a instalação em que o StormVR será registrado."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateLabel} 0 2u 100% 28u "Abra o SteamVR pelo menos uma vez para preparar o OpenVR. Em seguida, feche-o antes de instalar."
  Pop $0
  ${NSD_CreateText} 0 37u 74% 14u "$SteamVR"
  Pop $RuntimeEdit
  ${NSD_CreateBrowseButton} 76% 36u 24% 16u "Procurar..."
  Pop $0
  ${NSD_OnClick} $0 BrowseSteamVR
  nsDialogs::Show
FunctionEnd

Function BrowseSteamVR
  Pop $0
  ${NSD_GetText} $RuntimeEdit $SteamVR
  nsDialogs::SelectFolderDialog "Selecione a pasta do SteamVR" "$SteamVR"
  Pop $0
  ${If} $0 != error
    ${NSD_SetText} $RuntimeEdit $0
  ${EndIf}
FunctionEnd

Function SteamVRLeave
  ${NSD_GetText} $RuntimeEdit $SteamVR
  ${IfNot} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
    MessageBox MB_OK|MB_ICONEXCLAMATION "Escolha a pasta do SteamVR que contém bin\win64\vrpathreg.exe."
    Abort
  ${EndIf}
  GetFullPathName $SteamVR "$SteamVR"
FunctionEnd

Section "StormVR"
  ${IfNot} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
    !insertmacro Fail "Instale ou localize o SteamVR antes de instalar o StormVR."
  ${EndIf}
  !insertmacro RequireClosed "install"

  ${If} ${FileExists} "$SteamVR\drivers\stormvr\driver.vrdrivermanifest"
    !insertmacro Fail "Foi encontrada uma instalação manual em $SteamVR\drivers\stormvr. Mova a pasta stormvr para fora da pasta drivers e rode o instalador novamente."
  ${EndIf}

  SetOutPath "$SteamVR\bin\win64"
  nsExec::ExecToStack /TIMEOUT=10000 '"$SteamVR\bin\win64\vrpathreg.exe" finddriver stormvr'
  Pop $CommandResult
  Pop $CommandOutput
  ${If} $CommandResult == 0
    ${StrTrimNewLines} $CommandOutput $CommandOutput
    ${If} $CommandOutput != $DriverPath
    ${AndIf} $CommandOutput != "$DriverPath\"
    ${AndIf} $CommandOutput != "$DriverPath\driver.vrdrivermanifest"
      !insertmacro Fail "Já existe outro StormVR registrado. Desinstale a cópia anterior antes de continuar.$\r$\n$CommandOutput"
    ${EndIf}
  ${ElseIf} $CommandResult == 2
    !insertmacro Fail "O SteamVR tem múltiplas cópias externas do StormVR registradas. Remova as cópias anteriores antes de continuar."
  ${ElseIf} $CommandResult != 1
    !insertmacro Fail "Não foi possível consultar o OpenVR. Abra e feche o SteamVR e tente novamente."
  ${EndIf}

  ClearErrors
  SetOutPath "$INSTDIR"
  ${If} ${FileExists} "$BackupPath\driver.vrdrivermanifest"
    ${IfNot} ${FileExists} "$DriverPath\driver.vrdrivermanifest"
      Rename "$BackupPath" "$DriverPath"
    ${Else}
      !insertmacro CleanDirectory "$BackupPath"
    ${EndIf}
  ${EndIf}
  !insertmacro CleanDirectory "$StagePath"
  ${If} ${Errors}
    !insertmacro Fail "Não foi possível preparar a pasta do driver. Feche programas que estejam usando a pasta e tente novamente."
  ${EndIf}

  ClearErrors
  SetOutPath "$StagePath"
  File /r "${STORMVR_PAYLOAD}\stormvr\*"
  SetOutPath "$INSTDIR"
  ${If} ${Errors}
    !insertmacro CleanDirectory "$StagePath"
    !insertmacro Fail "Não foi possível gravar os arquivos do StormVR."
  ${EndIf}

  ClearErrors
  ${If} ${FileExists} "$DriverPath\driver.vrdrivermanifest"
    Rename "$DriverPath" "$BackupPath"
    ${If} ${Errors}
      !insertmacro CleanDirectory "$StagePath"
      !insertmacro Fail "A cópia do driver anterior está em uso. Feche o SteamVR e tente novamente."
    ${EndIf}
  ${EndIf}
  ClearErrors
  Rename "$StagePath" "$DriverPath"
  ${If} ${Errors}
    ${If} ${FileExists} "$BackupPath\driver.vrdrivermanifest"
      Rename "$BackupPath" "$DriverPath"
    ${EndIf}
    !insertmacro Fail "Não foi possível ativar os novos arquivos do driver."
  ${EndIf}

  ; An update to the same registered path does not add another registry entry.
  ${If} $CommandResult == 1
    SetOutPath "$SteamVR\bin\win64"
    nsExec::ExecToStack /TIMEOUT=10000 '"$SteamVR\bin\win64\vrpathreg.exe" adddriver "$DriverPath"'
    Pop $CommandResult
    Pop $CommandOutput
    SetOutPath "$INSTDIR"
    ${If} $CommandResult != 0
      !insertmacro CleanDirectory "$DriverPath"
      ${If} ${FileExists} "$BackupPath\driver.vrdrivermanifest"
        Rename "$BackupPath" "$DriverPath"
      ${EndIf}
      !insertmacro Fail "O SteamVR recusou o registro do driver. Abra e feche o SteamVR e tente novamente.$\r$\n$CommandOutput"
    ${EndIf}
  ${EndIf}

  !insertmacro CleanDirectory "$BackupPath"
  SetOutPath "$INSTDIR"
  File "${STORMVR_PAYLOAD}\MAOS-STEAMVR.md"
  File "${STORMVR_PAYLOAD}\LICENSE"
  File "${STORMVR_PAYLOAD}\LICENSE-OpenVR.txt"
  WriteUninstaller "$INSTDIR\Desinstalar.exe"
  !ifndef STORMVR_TEST
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "StormVR Driver"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "0.4.2"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "SteamVRPath" "$SteamVR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Desinstalar.exe"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$DriverPath\bin\win64\stormvr_config.exe"
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  !endif
SectionEnd

Function un.onInit
  !insertmacro InstallerLock
  !insertmacro InitPaths
FunctionEnd

Section "Uninstall"
  !insertmacro RequireClosed "uninstall"
  ${If} ${FileExists} "$SteamVR\bin\win64\vrpathreg.exe"
    SetOutPath "$SteamVR\bin\win64"
    nsExec::ExecToStack /TIMEOUT=10000 '"$SteamVR\bin\win64\vrpathreg.exe" removedriver "$DriverPath"'
    Pop $CommandResult
    Pop $CommandOutput
    ${If} $CommandResult != 0
      !insertmacro Fail "O OpenVR não conseguiu remover o registro do StormVR.$\r$\n$CommandOutput"
    ${EndIf}
  ${EndIf}
  SetOutPath "$TEMP"
  ClearErrors
  !insertmacro CleanDirectory "$DriverPath"
  !insertmacro CleanDirectory "$StagePath"
  !insertmacro CleanDirectory "$BackupPath"
  ${If} ${Errors}
    !insertmacro Fail "Ainda há arquivos do driver em uso. Feche o SteamVR e tente de novo."
  ${EndIf}
  Delete "$INSTDIR\MAOS-STEAMVR.md"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\LICENSE-OpenVR.txt"
  Delete "$INSTDIR\Desinstalar.exe"
  RMDir "$INSTDIR"
  !ifndef STORMVR_TEST
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
  !endif
SectionEnd
