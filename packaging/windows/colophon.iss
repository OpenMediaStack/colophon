; Colophon's installer for Windows, built with Inno Setup once Colophon is built in release
; (scripts/build.sh release, which puts SDL3.dll beside colophon.exe in build\):
;   iscc /DAppVersion=<version> packaging\windows\colophon.iss
; It writes build\installer\Colophon-<version>-setup.exe. Paths are relative to this file.

#ifndef AppVersion
  #error Give the version with /DAppVersion=<version>
#endif
#define Root "..\.."
; The numbers of the version, which the file's version resource needs: 2.0.0 of 2.0.0-rc.1.
#define Numbers Copy(AppVersion, 1, Pos("-", AppVersion + "-") - 1)

[Setup]
; Identifies Colophon across versions, for upgrades and uninstalling: never change it.
AppId={{3870FA1E-7118-4250-9261-32743ACCF83E}
AppName=Colophon
AppVersion={#AppVersion}
AppVerName=Colophon {#AppVersion}
AppPublisher=Florent Sorel
AppPublisherURL=https://github.com/OpenMediaStack/colophon
AppSupportURL=https://github.com/OpenMediaStack/colophon/issues
AppCopyright=© 2026 Florent Sorel
VersionInfoVersion={#Numbers}
DefaultDirName={autopf}\Colophon
DisableProgramGroupPage=yes
; Installs for the current user without asking for administrator rights, or for every user.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Root}\build\installer
OutputBaseFilename=Colophon-{#AppVersion}-setup
SetupIconFile={#Root}\assets\icon\Colophon.ico
UninstallDisplayIcon={app}\Colophon.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Root}\build\colophon.exe"; DestDir: "{app}"; DestName: "Colophon.exe"; Flags: ignoreversion
Source: "{#Root}\build\SDL3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"

[Icons]
Name: "{autoprograms}\Colophon"; Filename: "{app}\Colophon.exe"
Name: "{autodesktop}\Colophon"; Filename: "{app}\Colophon.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Colophon.exe"; Description: "{cm:LaunchProgram,Colophon}"; Flags: nowait postinstall skipifsilent
