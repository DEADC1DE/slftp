unit eprecatcher;

interface

procedure EPrecatcherInit;
procedure EPrecatcherUnInit;
procedure EPrecatcherStop;
procedure EPrecatcherStart;

implementation

uses configunit, queueunit, debugunit, sltcp, mycrypto, kb, IdGlobal, SysUtils;

const
  rsections = 'eprecatcher';

type
  TEPrecatcherThread = class(TslTCPThread)
    constructor Create;
    procedure Execute; override;
  end;

var
  slUDP: TEPrecatcherThread = nil;

procedure EPrecatcherInit;
begin
  if config.ReadBool(rsections, 'enabled', False) then
    slUDP:= TEPrecatcherThread.Create;
end;

procedure EPrecatcherUnInit;
begin
  if slUDP <> nil then
  begin
    slUDP.Free;
    slUDP:= nil;
  end;
end;

procedure EPrecatcherStart;
begin
  if slUDP <> nil then
    slUDP.Start;
end;

procedure EPrecatcherStop;
begin
  if slUDP <> nil then
    slUDP.Stop;
end;

{ TEPrecatcherThread }

constructor TEPrecatcherThread.Create;
begin
  inherited Create('ExternalPreCatcher', True);

  if not BindHost(config.ReadString(rsections, 'bindhost', '')) then
    Debug(dpError, rsections, error);
  BindPort := config.ReadInteger(rsections, 'bindport', 16666);
  if not GetSocket(true) then
    Debug(dpError, rsections, error);
end;

procedure TEPrecatcherThread.Execute;
var
  ss: String;
  sitename, section, genre, event, rls, cdno: String;
  kb_event: TKBEventType;
begin

  while(true) do
  begin
    if not Read(ss, 60000) then//, 0, True
    begin
      if error <> 'timeout' then
      begin
        Debug(dpError, rsections, error);
        exit;
      end;
      Continue;
    end;

    ss:= Trim(DecryptUDP(ss));
    if ss = '' then Continue;

    debug(dpMessage, rsections, 'Got line: %s', [ss]);

    ss:= ReplaceText(ss, '||', '| |'); // fix for empty genre
    sitename:= Fetch(ss, '|', True, False);
    section:= Fetch(ss, '|', True, False);
    genre:= trim(Fetch(ss, '|', True, False));
    event:= Fetch(ss, '|', True, False);
    rls:= Fetch(ss, '|', True, False);
    cdno:= Fetch(ss, '|', True, False);

    kb_event := EventStringToTKBEventType(event);

    kb_add(
      '',
      '',
      sitename, section, genre, kb_event, rls, cdno
    );
  end;

end;

end.
