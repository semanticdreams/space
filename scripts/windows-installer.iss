#define MyAppId "{{A0D8994C-6C07-4479-9E9E-A1D4B393C7E3}}"

#ifndef AppName
  #error AppName define is required
#endif
#ifndef AppVersion
  #error AppVersion define is required
#endif
#ifndef AppPublisher
  #error AppPublisher define is required
#endif
#ifndef AppExeName
  #error AppExeName define is required
#endif
#ifndef AppDirName
  #error AppDirName define is required
#endif
#ifndef AppGroupName
  #error AppGroupName define is required
#endif
#ifndef SourceDir
  #error SourceDir define is required
#endif
#ifndef OutputDir
  #error OutputDir define is required
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename define is required
#endif
#ifndef AppIconFile
  #error AppIconFile define is required
#endif

[Setup]
AppId={#MyAppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
SetupIconFile={#AppIconFile}
DefaultDirName={autopf}\{#AppDirName}
DefaultGroupName={#AppGroupName}
AllowNoIcons=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
DisableDirPage=no
DisableProgramGroupPage=no
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SolidCompression=yes
UninstallDisplayIcon={app}\{#AppExeName}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppGroupName}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#AppGroupName}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
