unit taskgame;

interface

uses
  Classes, pazo, taskrace, sltcp;

type
  TPazoGameTask = class(TPazoPlainTask)
  private
    ss: TStringStream;
    attempt: Integer;
    function Parse(const text: String): Boolean;
  public
    constructor Create(const netname, channel, site: String; pazo: TPazo; const attempt: Integer);
    destructor Destroy; override;
    function Execute(slot: Pointer): Boolean; override;
    function Name: String; override;
  end;

implementation

uses
  SysUtils, SyncObjs, Contnrs, irc, StrUtils, kb, kb.releaseinfo, debugunit, dateutils, queueunit, tags,
  configunit, tasksunit, dirlist, mystrings, sitesunit, RegExpr, sllanguagebase;

const
  section = 'taskgame';

{ TPazoGameTask }

constructor TPazoGameTask.Create(const netname, channel, site: String; pazo: TPazo; const attempt: Integer);
begin
  inherited Create(netname, channel, site, '', pazo);
  ss := TStringStream.Create('');
  self.attempt := attempt;
  wanted_dn := True;
end;

destructor TPazoGameTask.Destroy;
begin
  ss.Free;
  inherited;
end;

function TPazoGameTask.Parse(const text: String): Boolean;
{
var
  pgrx2, pgrx1, pgrx, pgrg: TRegExpr;
  ss, s: String;
  rg: TGameRelease;
}
begin
  Result := False;
(*
pgrx:=TRegExpr.Create;
pgrx.ModifierI:=True;
pgrx1:=TRegExpr.Create;
pgrx1.ModifierI:=True;
pgrx2:=TRegExpr.Create;
pgrx2.ModifierI:=True;

rg:=TGameRelease(mainpazo.rls);

pgrx.Expression:='Lang((uage)?s)?[^\n]+';
if pgrx.Exec(text) then begin
// SLLanguagesFindLanguage
end;

pgrx.Expression:='(REGiON|Origin|Platform|Playble\s\@|Regions|FORMAT)[^\n]+';
pgrx1.Expression:='(PAL|NSTC[\-\w]?|Not[\s]?Region(s)?[\s]?Free|Region(s)?[\s]?Free|RF)';
if pgrx.Exec(text) then begin
s:=pgrx.Match[0];
if pgrx1.Exec(s) then begin REPEAT
ss:=uppercase(pgrx1.Match[0]);
pgrx2.Expression:='PAL';
if pgrx2.Exec(ss) then begin
rg.region_pal:=True;
rg.region_ntsc:=False;
rg.region_rf:=False;
end;

pgrx2.Expression:='NTSC(\-\w)?';
if pgrx2.Exec(ss) then begin
rg.region_pal:=False;
rg.region_ntsc:=True;
rg.region_rf:=False;
end;

pgrx2.Expression:='Region(s)?[\s]?Free|RF';
if pgrx2.Exec(ss) then rg.region_rf:=True;

pgrx2.Expression:='Not[\s]?Region(s)?[\s]?Free';
if pgrx2.Exec(ss) then rg.region_rf:=False;
UNTIL not pgrx1.ExecNext;
end;
end;

pgrx.Expression:='Genre[^/w]+?([\w]+)';
if pgrx.Exec(text) then rg.game_genre.Add(pgrx.Match[1]);


pgrx.Free;
pgrx1.Free;
pgrx2.Free;
*)
end;

function TPazoGameTask.Execute(slot: Pointer): boolean;
label
  ujra;
var
  s: TSiteSlot;
  i: Integer;
  j, fTagCompleteType: TTagCompleteType;
  de: TDirListEntry;
  r: TPazoGameTask;
  d: TDirList;
  nfofile: String;
  event: TKBEventType;
begin
  Result := False;
  s := slot;

  if mainpazo.stopped then
  begin
    readyerror := True;
    exit;
  end;

  Debug(dpMessage, section, Name);

ujra:
  if s.status <> ssOnline then
    if not s.ReLogin then
    begin
      readyerror := True;
      exit;
    end;

    if not s.Dirlist(MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname)) then
    begin
      if s.status = ssDown then
        goto ujra;
      readyerror := True; // <- nincs meg a dir...
      exit;
    end;

    j := tctUNMATCHED;
    nfofile := '';
    d := TDirlist.Create(s.site.name, nil, nil, s.lastResponse);
    d.dirlist_lock.Enter;
    try
      for de in d.entries.Values do
      begin
        if ((not de.Directory) and (de.Extension = '.nfo') and (de.filesize < 32768)) then // 32kb-nal nagyobb nfoja csak nincs senkinek
          nfofile := de.filename;

        if ((de.Directory) or (de.filesize = 0)) then
        begin
          fTagCompleteType := TagComplete(de.FilenameLowerCased);
          if j = tctUNMATCHED then j := fTagCompleteType;
          if fTagCompleteType = tctCOMPLETE then j := fTagCompleteType;
        end;
      end;
    finally
      d.dirlist_lock.Leave;
      d.Free;
    end;

  if (nfofile = '') then
  begin
    if attempt < config.readInteger(section, 'readd_attempts', 5) then
    begin
      Debug(dpSpam, section, 'READD: nincs meg az nfo file...');

      r := TPazoGameTask.Create(netname, channel, ps1.name, mainpazo, attempt+1);
      r.startat := IncSecond(Now, config.ReadInteger(section, 'readd_interval', 60));
      AddTask(r);
    end
    else
    begin
      Debug(dpSpam, section, 'READD: nincs tobb readd...');
    end;
    ready := True;
    Result := True;
    exit;
  end;

  // try to get the nfo file
  i := s.LeechFile(ss, nfofile);

  if i < 0 then
  begin
    readyerror := True;
    exit;
  end;
  if i = 0 then
    goto ujra;
  // else siker

  if Parse(ss.DataString) then
  begin
    if j = tctCOMPLETE then
      event := kbeCOMPLETE
    else
      event := kbeNEWDIR;

    kb_add(netname, channel, ps1.name, mainpazo.rls.section, '', event, mainpazo.rls.rlsname, '');
  end;// else
//    debug(dpMessage, section, 'Couldnt find imdb url in nfo '+nfofile);

  Result := True;
  ready := True;
end;

function TPazoGameTask.Name: String;
begin
  try
    Result := Format('GameTask: %s (PazoID: %d) [Count: %d]', [mainpazo.rls.rlsname, pazo_id, attempt]);
  except
    Result := 'GameTask';
  end;
end;

end.
