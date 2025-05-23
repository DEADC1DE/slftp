unit taskrace;

interface

uses SyncObjs, tasksunit, pazo;

type
  TPazoPlainTask = class(TTask) // no announce
    pazo_id: integer;
    mainpazo: TPazo;
    ps1, ps2: TPazoSite; //< ps1 is sourcesite, ps2 is dstsite for TPazoRaceTask
    constructor Create(const netname, channel, site1, site2: String; pazo: TPazo);
    destructor Destroy; override;
  end;

  TPazoTask = class(TPazoPlainTask) // announce
    constructor Create(const netname, channel, site1, site2: String; pazo: TPazo);
    destructor Destroy; override;
  end;

  TPazoDirlistTask = class(TPazoTask)
    dir: String;
    is_pre: boolean;
    FDoIncFilling: boolean; //< @true if created to do incomplete filling, @false otherwise
    constructor Create(const netname, channel, site: String; pazo: TPazo; const dir: String; is_pre: boolean; aIsFromIncompleteFiller: boolean = False);
    function Execute(slot: Pointer): boolean; override;
    function Name: String; override;
  end;

  TPazoMkdirTask = class(TPazoTask)
    dir: String;
    constructor Create(const netname, channel, site: String; pazo: TPazo; const dir: String);
    function Execute(slot: Pointer): boolean; override;
    function Name: String; override;
  end;

  TWaitTask = class(TTask)
  public
    event: TEvent;
    wait_for: String;
    destructor Destroy; override;
    constructor Create(const netname, channel, site1: String);
    function Execute(slot: Pointer): boolean; override;
    function Name: String; override;
  end;

  TPazoRaceTask = class(TPazoTask)
  private
    { Finds out if the given response contains phrases that indicate the file is a dupe.
       @param(aResponse the response message)
       @returns(@true if the response means the file is a dupe, @false otherwise.)
    }
    function ResponseContainsDupeKeyword(const aResponse: String): boolean;

    { Finds out if the given response contains phrases that indicate the file is a dupe and the file is already complete.
       @param(aResponse the response message)
       @returns(@true if the response means the file is a dupe and already complete, @false otherwise.)
    }
    function ResponseContainsDupeKeywordComplete(const aResponse: String): boolean;
  public
    dir: String;
    filename: String;
    FFilenameForSTORCommand: String; //< filename used for transfering in STOR cmd, automatically lowercased if config convert_filenames_to_lowercase value is @true
    rank: integer;
    filesize: Int64;
    isSfv, IsNfo: Boolean;
    isSample, isProof, isCovers, isSubs: Boolean;
    dst: TWaitTask;
    constructor Create(const netname, channel, site1, site2: String; pazo: TPazo; const dir, filename: String; const filesize: Int64; const rank: integer);
    function Execute(slot: Pointer): boolean; override;
    function Name: String; override;
  end;

implementation

uses
  Classes, Contnrs, StrUtils, kb, sitesunit, configunit, taskdel, DateUtils,
  SysUtils, mystrings, statsunit, slstack, DebugUnit, queueunit, irc, dirlist,
  midnight, speedstatsunit, rulesunit, mainthread, mrdohutils, news, dirlist.helpers,
  Generics.Collections;

const
  c_section = 'taskrace';


constructor TPazoPlainTask.Create(const netname, channel, site1, site2: String; pazo: TPazo);
begin
  // egy taszk letrehozasakor es felszabaditasakor a queue lock mindig aktiv
  //tasks can create a queue and release the lock still active
  mainpazo := pazo; //FindPazoById(pazo_id);
  if mainpazo = nil then
    raise Exception.Create('Pazo not found');
  self.pazo_id := mainpazo.pazo_id;
  mainpazo.lastTouch := Now();

  ps1 := mainpazo.FindSite(site1);
  //  if ps1 = nil then raise Exception.Create('PazoSite1 not found');
  ps2 := nil;
  if site2 <> '' then
  begin
    ps2 := mainpazo.FindSite(site2);
    //    if ps2 = nil then raise Exception.Create('PazoSite2 not found');
  end;

  inherited Create(netname, channel, site1, site2);
end;

destructor TPazoPlainTask.Destroy;
begin
  if readyerror then
    mainpazo.readyerror := True;

  inherited;
end;

constructor TPazoTask.Create(const netname, channel, site1, site2: String; pazo: TPazo);
begin
  inherited Create(netname, channel, site1, site2, pazo);

  mainpazo.queuenumber.Increase;

  if ClassType = TPazoRaceTask then
  begin
    mainpazo.racetasks.Increment;
    ps1.s_racetasks.Increment;
  end;
  if ClassType = TPazoMkdirTask then
  begin
    mainpazo.mkdirtasks.Increment;
    ps1.s_mkdirtasks.Increment;
  end;
  if ClassType = TPazoDirlistTask then
  begin
    mainpazo.dirlisttasks.Increment;
    ps1.s_dirlisttasks.Increment;
  end;
end;

destructor TPazoTask.Destroy;
begin
  mainpazo.queuenumber.Decrease;

  if ClassType = TPazoRaceTask then
  begin
    mainpazo.racetasks.Decrement;
    ps1.s_racetasks.Decrement;
  end;
  if ClassType = TPazoMkdirTask then
  begin
    mainpazo.mkdirtasks.Decrement;
    ps1.s_mkdirtasks.Decrement;
  end;
  if ClassType = TPazoDirlistTask then
  begin
    mainpazo.dirlisttasks.Decrement;
    ps1.s_dirlisttasks.Decrement;
  end;

  inherited;
end;


{ TPazoDirlistTask }
constructor TPazoDirlistTask.Create(const netname, channel, site: String; pazo: TPazo; const dir: String; is_pre: boolean; aIsFromIncompleteFiller: boolean = False);
begin
  self.dir := dir;
  self.is_pre := is_pre;
  self.FDoIncFilling := aIsFromIncompleteFiller;
  inherited Create(netname, channel, site, '', pazo);
end;

function TPazoDirlistTask.Execute(slot: Pointer): boolean;
label
  TryAgain;
var
  s: TSiteSlot;
  de: TDirListEntry;
  r, r_dst: TPazoDirlistTask;
  fSubDirlistTasks: TList<TPazoDirlistTask>;
  d: TDirList;
  aktdir, fAbsoluteDir: String;
  itwasadded: boolean;
  numerrors: integer;
  tname: String;
  ps: TPazoSite;
  fDestination: TDestinationRank;
  secondsWithNoChange, secondsSinceStart, secondsSinceCompleted: Int64;
begin
  numerrors := 0;
  Result := False;
  s := slot;
  tname := Name;
  fSubDirlistTasks := nil;

  if mainpazo.stopped then
  begin
    readyerror := True;
    mainpazo.errorreason := 'Mainpazo stopped.';
    exit;
  end;

  Debug(dpSpam, c_section, '--> ' + tname);

  mainpazo.lastTouch := Now();

  // Check if we should abandon using PS1
  TryAgain:
  if ((ps1.error) or (ps1.dirlistgaveup and not FDoIncFilling) or (ps1.status = rssNuked) or (slshutdown)) then
  begin
    readyerror := True;

    if ps1.error then
      mainpazo.errorreason := 'ERROR PS1';

    if ps1.dirlistgaveup then
      mainpazo.errorreason := 'ERROR PS1: Dirlist gave up.';

    if ps1.status = rssNuked then
      mainpazo.errorreason := 'ERROR PS1: Release is nuked.';

    Debug(dpSpam, c_section, '<-- ' + tname);
    exit;
  end;

  // Count errors and exit if too many
  try
    Inc(numerrors);
    if numerrors > 3 then
    begin
      readyerror := True;
      mainpazo.errorreason := ' TPazoDirlistTask: Too many consecutive errors happened.';
      irc_Adderror(Format('<c4>[ERROR]</c> [%s]: %s', [tname, s.lastResponse]));
      Debug(dpMessage, c_section, '<-- ERROR ' + tname + ' ' + s.lastResponse);
      exit;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask error: %s', [e.Message]));
      readyerror := True;
      exit;
    end;
  end;

  // Check if we can relogin if we're offline
  try
    if s.status <> ssOnline then
    begin
      if not s.ReLogin(0, False, 'TPazoDirlistTask') then
      begin
        mainpazo.errorreason := 'Cant login. ';
        readyerror := True;
        Debug(dpMessage, c_section, '<-- No LOGIN ' + tname);
        exit;
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask relogin: %s',
        [e.Message]));
      readyerror := True;
      exit;
    end;
  end;

  // Check if we can CWD successfully into the dir
  if ((not ps1.midnightdone) and (IsMidnight(mainpazo.rls.section))) then
  begin
    if not s.Cwd(ps1.maindir, True) then
    begin
      if s.Status <> ssOnline then
        goto TryAgain;

      //fix drftpd messed up working directory by reconnect
      if s.site.sw = sswDrftpd then
      begin
        s.QuitAndRelogin('TPazoDirlistTask');
        goto TryAgain;
      end;

      ps1.MarkSiteAsFailed(Format('Section dir %s does not seem to exists (PWD).', [ps1.maindir]));
      mainpazo.errorreason := Format('Section dir %s on %s does not seem to exists (CWD). Site marked as failed.', [ps1.maindir, site1]);
      readyerror := True;
      Debug(dpMessage, c_section, '<-- ' + tname);
      exit;
    end;

    if not s.Pwd(ps1.maindir) then
    begin
      if s.Status <> ssOnline then
        goto TryAgain;

      //fix drftpd messed up working directory by reconnect
      if s.site.sw = sswDrftpd then
      begin
        s.QuitAndRelogin('TPazoDirlistTask');
        goto TryAgain;
      end;

      ps1.MarkSiteAsFailed(Format('Section dir %s does not seem to exists (PWD).', [ps1.maindir]));
      mainpazo.errorreason := Format('Section dir %s on %s does not seem to exists (PWD). Site marked as failed.', [ps1.maindir, site1]);
      readyerror := True;
      Debug(dpMessage, c_section, '<-- ' + tname);
      exit;
    end;

    ps1.midnightdone := True;
  end;

  fAbsoluteDir := MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir;
  // Trying to get the dirlist
  if not s.Dirlist(fAbsoluteDir) then
  begin
    mainpazo.errorreason := Format('Cannot get the dirlist for source dir %s on %s.', [MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir, site1]);

    case s.lastResponseCode of
      421:
        begin
          s.DestroySocketAndRelogin('TPazoDirlistTask');
          goto TryAgain;
        end;

      550:
        begin
          if ( s.lastResponse.Contains('FileNotFound') OR s.lastResponse.Contains('File not found')
            OR s.lastResponse.Contains('No such file or directory') OR s.lastResponse.Contains('Directory not found')) then
          begin
            Debug(dpMessage, c_section, '<- ' + s.lastResponse + ' ' + tname);

            try
              d := ps1.dirlist.FindDirlist(dir);
            except
              on e: Exception do
                Debug(dpError, c_section, '[EXCEPTION] (dirlist no such directory handling): %s', [e.Message]);
            end;
            if (d = nil) Or (d.need_mkdir and not d.error) then
            begin
              //we're too early, mkdir is not done yet ... the site is slow?
              //continue to create a new dirlist task below
              Debug(dpMessage, c_section, 'DIRLIST: mkdir not ready: ' + tname);
            end
            else
            begin
              //fix drftpd messed up working directory by reconnect
              if s.site.sw = sswDrftpd then
              begin
                s.Quit;
                if not s.ReLogin(0, False, 'TPazoDirlistTask') then
                begin
                  mainpazo.errorreason := 'Site ' + s.site.Name + ' is offline';
                  readyerror := True;
                  Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
                  exit;
                end;

                if not s.Cwd(fAbsoluteDir, True) then
                begin
                  irc_Adderror(Format('<c4>[ERROR]</c> %s : %s', [tname, 'Dir ' + fAbsoluteDir + ' on ' + site1 + ' does not exist']));
                  if (dir = '') then
                  begin
                    ps1.MarkSiteAsFailed('cant cwd (dirlist)');
                  end;
                  readyerror := True;
                  mainpazo.errorreason := 'cant cwd (dirlist)';
                  Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
                  exit;
                end;

                //this should have fixed our drftpd slot, retry
                goto TryAgain;
              end;

              if (dir = '') then
              begin
                ps1.MarkSiteAsFailed('No such directory (dirlist)');
              end
              else
              begin
                //avoid flood of "550 No such file or directory." for subdirs
                irc_Adderror(Format('<c4>[DIRLIST SUBDIR]</c> [%s]: %s %s', [tname, dir, s.lastResponse]));
                begin
                  d.need_mkdir := True;
                  d.error := True;
                end;
              end;

              readyerror := True;

              //no more dirlist
              exit;
            end;
          end
          else
          begin
            Debug(dpSpam, c_section, '[DIRLIST FAILED] %s: %d %s', [tname, s.lastResponseCode, s.lastResponse]);
            goto TryAgain;
          end;
        end;

      else
        begin
          Debug(dpSpam, c_section, '[DIRLIST FAILED] %s: %d %s', [tname, s.lastResponseCode, s.lastResponse]);
          goto TryAgain;
        end;
    end;
  end
  else
  begin
    try
      itwasadded := ps1.ParseDirlist(netname, channel, dir, s.lastResponse, is_pre);
    except
      on e: Exception do
      begin
        Debug(dpError, c_section, '[EXCEPTION] ParseDirlist: %s', [e.Message]);
        mainpazo.errorreason := 'Cannot parse the dirlist';
        readyerror := True;
        exit;
      end;
    end;
  end;

  d := nil;
  try
    try
      d := ps1.dirlist.FindDirlist(dir);
    except
      on e: Exception do
        Debug(dpError, c_section, '[EXCEPTION] d := ps1.dirlist.FindDirlist(dir): %s', [e.Message]);
    end;

    // set the dirlist full path. Used mainly for debug outputing.
    if d <> nil then
      d.FullPath := MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir;

    // Search for sub directories
    fSubDirlistTasks := TList<TPazoDirlistTask>.Create;
    if ((d <> nil) and (d.entries <> nil) and (d.entries.Count > 0)) then
    begin
      d.dirlist_lock.Enter;
      try
        for de in d.entries.Values do
        begin
          try
            if ((de.directory) and (not de.skiplisted)) then
            begin
              if ((de.subdirlist <> nil) and (de.subdirlist.dirlistadded)) then
                Continue;

              aktdir := dir;
              if aktdir <> '' then
                aktdir := aktdir + '/';
              aktdir := aktdir + de.filename;
              Debug(dpSpam, c_section, 'READD: adding dirlist task to subdir ' + aktdir);
              irc_Addtext_by_key('PRECATCHSTATS',
                Format('<c7>[DIRLIST]</c> %s %s %s Dirlist (SUBDIR) added to : %s',
                [mainpazo.rls.section, mainpazo.rls.rlsname, aktdir, site1]));
              try
                fSubDirlistTasks.Add(TPazoDirlistTask.Create(netname, channel, site1, mainpazo, aktdir, is_pre));
                if (de.subdirlist <> nil) then
                  de.subdirlist.dirlistadded := True;
              except
                on e: Exception do
                begin
                  Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask Create: %s', [e.Message]));
                end;
              end;
            end;
            except
              on e: Exception do
              begin
                Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask Subdir loop: %s', [e.Message]));
              end;
            end;
        end;
      finally
        d.dirlist_lock.Leave;
      end;

      //add task outside the dirlist lock to avoid deadlocks with the queue lock
      for r in fSubDirlistTasks do
      begin
        AddTask(r);
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask: %s', [e.Message]));
    end;
  end;

  FreeAndNil(fSubDirlistTasks);

  if ((not is_pre) and (d <> nil) and (d.Complete) and (ps1.status <> rssComplete)) then
  begin
    if (dir <> '') then
    begin
      ps1.SetComplete(dir);
    end
    else
    begin
      ps1.status := rssComplete;
    end;
  end;

  // don't check the part below if it's an incomplete fill because we would stop there
  if (not FDoIncFilling) then
  begin

    //check if we should give up with empty/incomplete/long release
    if ( (d <> nil) AND (not d.Complete) AND (d.entries <> nil) AND not d.DirlistGaveUp ) then
    begin
      secondsWithNoChange := SecondsBetween(Now, d.LastChanged);

      if ((d.entries.Count = 0) and (secondsWithNoChange > GetNewdirMaxEmptyValue())) then
      begin
        if spamcfg.readbool(c_section, 'incomplete', True) then
        begin
          irc_Addstats(Format('<c11>[EMPTY]</c> %s: %s %s %s is still empty after %d seconds, giving up...', [site1, mainpazo.rls.section, mainpazo.rls.rlsname, dir, secondsWithNoChange]));
        end;
        d.DirlistGaveUp := True;
        Debug(dpSpam, c_section, Format('EMPTY PS1 %s : LastChange(%d) > newdir_max_empty(%d)', [ps1.Name, secondsWithNoChange, GetNewdirMaxEmptyValue()]));
      end;

      if ((d.entries.Count > 0) and (secondsWithNoChange > GetNewdirMaxUnchangedValue())) then
      begin
        if spamcfg.readbool(c_section, 'incomplete', True) then
        begin
          irc_Addstats(Format('<c11>[iNCOMPLETE]</c> %s: %s %s %s is still incomplete after %d seconds with no change, giving up...', [site1, mainpazo.rls.section, mainpazo.rls.rlsname, dir, secondsWithNoChange]));
        end;
        d.DirlistGaveUp := True;
        Debug(dpSpam, c_section, Format('INCOMPLETE PS1 %s : LastChange(%d) > newdir_max_unchanged(%d)', [ps1.Name, secondsWithNoChange, GetNewdirMaxUnchangedValue()]));
      end;

      secondsSinceCompleted := SecondsBetween(Now, d.CompletedTime);

      if (is_pre) then
      begin
        if ( (d.CompletedTime <> 0) and (secondsSinceCompleted > GetNewdirMaxCompletedValue()) ) then
        begin
          if spamcfg.readbool(c_section, 'incomplete', True) then
          begin
            irc_Addstats(Format('<c11>[PRE]</c> %s: %s %s %s, giving up %d seconds after max. should be completed time...', [site1, mainpazo.rls.section, mainpazo.rls.rlsname, dir, secondsSinceCompleted]));
          end;
          d.DirlistGaveUp := True;
          Debug(dpSpam, c_section, Format('PRE PS1 %s : LastChange(%d) > newdir_max_completed(%d)', [ps1.Name, secondsSinceCompleted, GetNewdirMaxCompletedValue()]));
        end;
      end
      else
      begin
        secondsSinceStart := SecondsBetween(Now, d.StartedTime);

        if ( (d.StartedTime <> 0) AND (secondsSinceStart > GetNewdirMaxCreatedValue()) ) then
        begin
          if spamcfg.readbool(c_section, 'incomplete', True) then
          begin
            irc_Addstats(Format('<c11>[LONG]</c> %s: %s %s %s, giving up %d seconds after it started...', [site1, mainpazo.rls.section, mainpazo.rls.rlsname, dir, secondsSinceStart]));
          end;
          d.DirlistGaveUp := True;
          Debug(dpSpam, c_section, Format('LONG PS1 %s : LastChange(%d) > newdir_max_created(%d)', [ps1.Name, secondsSinceStart, GetNewdirMaxCreatedValue()]));
        end;

        if ( (d.CompletedTime <> 0) AND (secondsSinceCompleted > GetNewdirMaxCompletedValue()) ) then
        begin
          if spamcfg.readbool(c_section, 'incomplete', True) then
          begin
            irc_Addstats(Format('<c11>[FULL]</c> %s: %s %s %s is complete, giving up %d seconds after max. should be completed time...', [site1, mainpazo.rls.section, mainpazo.rls.rlsname, dir, secondsSinceCompleted]));
          end;
          d.DirlistGaveUp := True;
          Debug(dpSpam, c_section, Format('FULL PS1 %s : LastChange(%d) > newdir_max_completed(%d)', [ps1.Name, secondsSinceCompleted, GetNewdirMaxCompletedValue()]));
        end;
      end;

    end;

  end;

  // check if need more dirlist
  itwasadded := False;
  if (d <> nil) and not d.dirlistgaveup and not d.error then
  begin
    // check if still incomplete
    if ((d <> nil) and (not is_pre) and (not d.Complete)) then
    begin
      // do more dirlist
      r := TPazoDirlistTask.Create(netname, channel, ps1.Name, mainpazo, dir, is_pre);
      r.startat := IncMilliSecond(Now(), GetNewdirDirlistReaddValue());

      try
        AddTask(r);
        itwasadded := True;
      except
        on e: Exception do
        begin
          Debug(dpError, c_section, Format('[EXCEPTION] TPazoDirlistTask AddTask: %s',
            [e.Message]));
        end;
      end;
    end;

    // check if one dst need more dirlist
    if (not itwasadded) then
    begin
      for fDestination in ps1.destinations do
      begin
        if itwasadded then
          Break;

        try
          ps := fDestination.PazoSite;

          if (ps.error) then
            Continue;
          if (ps.dirlistgaveup) then
            Continue;
          if (ps.dirlist = nil) then
            Continue;
          if (ps.dirlist.error) then
            Continue;
          if not (ps.status in [rssAllowed]) then
            Continue;
          if ps.dirlist.Complete then
            Continue;

          if (dir <> '') then
          begin
            d := ps.dirlist.FindDirlist(dir);
            if (d <> nil) and (d.error or d.Complete) then
              Continue;
          end;

          if is_pre or (ps.dirlist.entries.Count > 0)  then
          begin
            // do more dirlist
            r := TPazoDirlistTask.Create(netname, channel, ps1.Name, mainpazo, dir, is_pre);
            r.startat := IncMilliSecond(Now(), GetNewdirDirlistReaddValue());
            r_dst := TPazoDirlistTask.Create(netname, channel, ps.Name, mainpazo, dir, False);
            r_dst.startat := IncMilliSecond(Now(), GetNewdirDirlistReaddValue());

            try
              AddTask(r);
              AddTask(r_dst);
              itwasadded := True;
              Break;
            except
              on e: Exception do
              begin
                Debug(dpError, c_section,
                  Format('[EXCEPTION] TPazoDirlistTask AddTask: %s', [e.Message]));
              end;
            end;
          end;
        except
          on e: Exception do
          begin
            Debug(dpError, c_section,
              Format('[EXCEPTION] TPazoDirlistTask CheckDestinations: %s', [e.Message]));
          end;
        end;
      end;
    end;
  end;

  Debug(dpSpam, c_section, '<-- ' + tname);

  Result := True;
  ready := True;
end;

function TPazoDirlistTask.Name: String;
begin
  try
    if is_pre then
      Result := Format('DIRLIST : %d <b>%s</b> <b>PRE</b> %s %s %s %s', [pazo_id, site1, mainpazo.rls.section,
        mainpazo.rls.rlsname, dir, ScheduleText])
    else
      Result := Format('DIRLIST : %d <b>%s</b> %s %s %s %s', [pazo_id, site1, mainpazo.rls.section,
        mainpazo.rls.rlsname, dir, ScheduleText]);
  except
    Result := 'DIRLIST';
  end;
end;


{ TPazoMkdirTask }
constructor TPazoMkdirTask.Create(const netname, channel, site: String; pazo: TPazo; const dir: String);
begin
  self.dir := dir;
  inherited Create(netname, channel, site, '', pazo);
end;

function TPazoMkdirTask.Execute(slot: Pointer): boolean;
label
  TryAgain;
var
  s: TSiteSlot;
  aktdir: String;
  failure: boolean;
  bIsMidnight: boolean;
  r: TRule;
  rule_err: String;
  numerrors: integer;
  tname: String;

  function checkForSiteFailure: boolean;
  var
    fulldir: String;
  begin
    Result := False;
    fulldir := MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir;
    if not s.Cwd(fulldir, True) then
    begin
      irc_Adderror(Format('<c4>[ERROR]</c> %s %s', [tname, s.lastResponse]));
      ps1.MkdirError(dir);
      if (dir = '') then
      begin
        ps1.MarkSiteAsFailed('cant CWD');
      end;
      Result := True;
      readyerror := True;
    end;
  end;

begin
  numerrors := 0;
  Result := False;
  s := slot;
  tname := Name;

  if mainpazo.stopped then
  begin
    mainpazo.errorreason := 'MainPazo Stopped';
    readyerror := True;
    exit;
  end;

  Debug(dpMessage, c_section, '--> ' + tname);

  mainpazo.lastTouch := Now();

  TryAgain:
  if ((ps1.error) or (slshutdown)) then
  begin
    readyerror := True;
    mainpazo.errorreason := 'ERROR PS1 or PS2';
    Debug(dpSpam, c_section, '<-- ' + tname);
    exit;
  end;

  try
    Inc(numerrors);
    if numerrors > 3 then
    begin
      irc_Adderror(Format('<c4>[ERROR] loop</c> %s', [tname]));
      mainpazo.errorreason := 'MKDir Pazo errornum > 3';
      if checkForSiteFailure then
      begin
        exit;
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoMkdirTask error: %s', [e.Message]));
      readyerror := True;
      exit;
    end;
  end;

  if s.status <> ssOnline then
    if not s.ReLogin(0, False, 'TPazoMkdirTask') then
    begin
      irc_Adderror(Format('<c4>[ERROR] site down</c> %s', [tname]));
      mainpazo.errorreason := 'Site Down';
      readyerror := True;
      exit;
    end;

  bIsMidnight := IsMidnight(mainpazo.rls.section);

  //change working directory
  failure := False;
  try
    failure := not s.Cwd(ps1.maindir, bIsMidnight);
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoMkdirTask Section dir does not exist: %s', [e.Message]));
      readyerror := True;
      exit;
    end;
  end;

  if failure then
  begin
    irc_Adderror(Format('<c4>[ERROR] cant CWD</c> %s', [tname]));

    //fix drftpd messed up working directory by reconnect
    if s.site.sw = sswDrftpd then
    begin
      s.QuitAndRelogin('TPazoMkdirTask');
      goto TryAgain;
    end
    else
    begin
      ps1.MarkSiteAsFailed('cant CWD');
      mainpazo.errorreason := ps1.Name + ' marked as failed';
      readyerror := True;
      exit;
    end;
  end;

  //print working directory
  try
    if bIsMidnight then
    begin
      if not s.Pwd(ps1.maindir) then
      begin
        ps1.MarkSiteAsFailed('cant PWD');
        mainpazo.errorreason := ps1.Name + ' marked as failed';
        readyerror := True;
        exit;
      end;

      ps1.midnightdone := True;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, Format('[EXCEPTION] TPazoMkdirTask Section dir does not exist:%s', [e.Message]));
      readyerror := True;
      exit;
    end;
  end;

  aktdir := MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir;
  if not s.Mkdir(aktdir) then
    goto TryAgain;

  failure := False;


  // 257 "PATHNAME" created.
  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (s.lastResponseCode <> 257) AND ( (s.lastResponseCode < 100) OR (s.lastResponseCode > 299) ) ) then
  begin

    failure := True;

    case s.lastResponseCode of

      400:
        begin
          if (0 <> Pos('DUPE:', s.lastResponse)) then // 400 DUPE: /MP3/1028/Danza_Fuego-Flamenco_Andalucia-WEB-2016-ANGER/
          begin
            failure := False;
          end;
        end;

      421:
        begin
          //COMPLETE MSG: 421 Timeout (60 seconds): closing control connection.
          if (0 < Pos('Timeout', s.lastResponse)) then
          begin
            goto TryAgain; //just try again, should hopefully resolve this issue
          end;
        end;


      426:
        begin
          //COMPLETE MSG: 426 ban.slow.upload
          if (0 < Pos('ban.slow.upload', s.lastResponse)) then
          begin
            // should setdown this crapsite because they should kick you from site when you get banned
            goto TryAgain;
          end;
        end;

      450:
        begin
          //COMPLETE MSG: 450 No transfer-slave(s) available
          if (0 < Pos('No transfer-slave', s.lastResponse)) then
          begin
            // maybe disable site...but for now we just try again
            goto TryAgain;
          end;
        end;

      530:
        begin
          //COMPLETE MSG: 530 Access denied (The string "/TV-SD/The.Price.Is.Right.S46E77.WEB.x264-W4F" not allowed in this directory name)
          if (0 <> Pos('not allowed in this directory name', s.lastResponse)) then
          begin
            failure := True;
          end
          //COMPLETE MSG: 530 Make Directory Access denied - Due to Regexp configuration
          //COMPLETE MSG: 530 Access denied
          else if (0 <> Pos('Access denied', s.lastResponse)) then
          begin
            failure := True;
          end
          else
          begin
            Debug(dpError, c_section, 'TPazoMkdirTask unhandled 530 response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]);
            irc_Addadmin(Format('TPazoMkdirTask unhandled 530 response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]));
            failure := True;  // we don't know if it's a really error or not, so we better say it's failed
          end;
        end;

      533:
        begin
          if (0 <> Pos('This file looks like a dupe!', s.lastResponse)) then
          begin
            failure := True;
          end;
          if (0 <> Pos('File name not allowed', s.lastResponse)) then
          begin
            if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
            begin
              irc_Adderror(s.todotask, '<c4>[NOT ALLOWED]</c> %s', [tname]);
            end;
            failure := True;
          end;
        end;

      550:
        begin
          //Usage of 'if ... else if ... else' is needed for TPazoMkdirTask response error - without we don't create this announce
          if (0 <> Pos('File exists', s.lastResponse)) then
          begin
            failure := False;
          end
          else if (0 <> Pos('already exists', s.lastResponse)) then
          begin
            failure := False;
          end

          else if ((0 <> Pos('it was last created at', s.lastResponse)) and (dir <> '')) then
          begin
            // to hopefully avoid loops with 550- Sample already exists in the dupelog, it was last created at 030116
            // also for Proofs, Covers, ...
            failure := True;
          end

          else if (0 <> Pos('Dupe detected', s.lastResponse)) then
          begin
            failure := True;
          end
          else if (0 <> Pos('is already on site', s.lastResponse)) then
          begin
            failure := True;
          end
          else if ((0 <> Pos('the parent of that directory does not exist', s.lastResponse)) and (dir <> '')) then
          begin
            failure := True;
          end

          else if ((0 <> Pos('Parent directory does not exist', s.lastResponse)) and (dir <> '')) then
          begin
            failure := True;
          end

          else if (0 <> Pos('Dirscript could not be executed', s.lastResponse)) then
          begin
            failure := True;
          end

          else if ((0 <> Pos('the parent of that directory does not exist', s.lastResponse)) and (dir = '')) then
          begin
            //sectiondir removed/not accessible? Need to get more info
            Debug(dpError, c_section, 'TPazoMkdirTask 550 response: %s: %s --- dir: %s (%s) %s', [s.Name, s.lastResponse, dir, aktdir, ps1.maindir]);
            failure := True;
          end

          else if (0 <> Pos('No such file or directory', s.lastResponse)) then
          begin
            // 550 No such file or directory.
            failure := True;
          end

          else if (0 <> Pos('Not allowed to make directories here', s.lastResponse)) then
          begin
            if spamcfg.ReadBool('taskrace', 'cant_create_dir', True) then
            begin
              irc_Adderror(s.todotask, '<c4>[MKDIR Denied]</c> TPazoMkdirTask %s: %s for %s',[s.Name, s.lastResponse, Trim(aktdir)]);
            end;
            failure := True;
          end

          // 550 System Error- /MP3/0413/Mirror-Mirror-CD-FLAC-20: Read-only file system.
          // 550 System Error- /incoming/games/pc/Lara.Croft.GO-R: Permission denied.
          // 550 System Error- /TV-BLURAY/Magnum.P.I.S01E11.720p.: Input/output error.
          // 550 System Error- /GAMES/Mass.Effect.Andromeda.Updat: No space left on device.
          else if ( (0 <> Pos('System Error', s.lastResponse)) and ( (0 <> Pos('Read-only file system', s.lastResponse)) OR (0 <> Pos('Permission denied', s.lastResponse)) OR (0 <> Pos('Input/output error', s.lastResponse)) OR (0 <> Pos('No space left', s.lastResponse)) )  ) then
          begin
            if spamcfg.ReadBool('taskrace', 'cant_create_dir', True) then
            begin
              irc_Adderror(s.todotask, '<c4>[MKDIR Denied]</c> TPazoMkdirTask %s: %s for %s',[s.Name, s.lastResponse, Trim(aktdir)]);
            end;
            // TODO for Read-only file system: setdown site, no transfer possible but more checking needed if it's only for current directory or for whole site
            // TODO for No space left on device: Setdown site
            // if only current directory, we should not setdown site - but we can find out with some testing ;)
            failure := True;
          end

          // 550- can't find package msgcat 1.6 while executing
          else if (0 <> Pos('t find package', s.lastResponse)) then
          begin
            // just a silly site error...
            failure := True;
          end

          else if (0 <> Pos('Denying creation of', s.lastResponse)) or (0 <> Pos('BLOCKED:', s.lastResponse)) or (0 <> Pos('Denied by dirscript', s.lastResponse)) then
          begin
            if config.ReadBool(c_section, 'autoruleadd', True) then
            begin
              if (0 <> Pos('releases are not accepted here', s.lastResponse)) or (0 <> Pos('This group is BANNED', s.lastResponse)) or (0 <> Pos('This group is not wanted', s.lastResponse)) then
              begin
                SlftpNewsAdd('FTP', Format('[RULES] Adding rule to DROP group <b>%s</b> on <b>%s</b>', [mainpazo.rls.groupname, site1]));
                irc_Addadmin(Format('Adding rule to DROP group <b>%s</b> on <b>%s</b>', [mainpazo.rls.groupname, site1]));
                rule_err := '';
                AddRule(Format('%s %s if group = %s then DROP',[site1, mainpazo.rls.section, mainpazo.rls.groupname]), rule_err);
              end;
            end;
            if spamcfg.ReadBool('taskrace', 'cant_create_dir', True) then
            begin
              irc_Adderror(s.todotask, '<c4>[MKDIR Denied]</c> TPazoMkdirTask %s: %s for %s',[s.Name, s.lastResponse, Trim(aktdir)]);
            end;
            failure := True;
          end
          else
          begin
            Debug(dpError, c_section, 'TPazoMkdirTask unhandled 550 response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]);
            irc_Addadmin(Format('TPazoMkdirTask unhandled 550 response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]));
            failure := True;  // we don't know if it's a really error or not, so we better say it's failed
          end;
        end;

      553:
        begin
          if (0 <> Pos('out of disk space', s.lastResponse)) then // 553 Error: out of disk space, contact the siteop!
          begin
            s.site.SetOutofSpace;
            failure := True;
          end;
        end;

      else
        begin
          if spamcfg.ReadBool('taskrace', 'denying_creation_of', True) then
          begin
            irc_Adderror(s.todotask, '<c4>[ERROR MKDIR]</c> TPazoMkdirTask %s: %s',[tname, s.lastResponse]);
          end;
          Debug(dpError, c_section, 'TPazoMkdirTask unhandled response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]);
          irc_Addadmin(Format('TPazoMkdirTask unhandled response, tell your developer about it! %s: %s --- dir: %s %s', [s.Name, s.lastResponse, aktdir, ps1.maindir]));
          failure := True;  // we don't know if it's a really error or not, so we better say it's failed
        end;
    end;

  end;

  try
    if (failure) then
    begin
      if checkForSiteFailure then
      begin
        Result := True;
        exit;
      end;
    end;

    ps1.MkdirReady(dir);
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] TPazoSite.MkdirReady : %s', [e.Message]);
      mainpazo.errorreason := ps1.Name + ' marked as failed';
      readyerror := True;
      exit;
    end;
  end;

  try
    // echo race info
    irc_SendRACESTATS(tname);
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] TPazoMkdirTask Stats : %s', [e.Message]);
    end;
  end;

  Debug(dpMessage, c_section, '<-- ' + tname);

  readyerror := failure;
  ready := True;
  Result := True;
end;

function TPazoMkdirTask.Name: String;
begin
  try
    Result := Format('MKDIR : %d <b>%s</b> %s %s', [pazo_id, site1, mainpazo.rls.rlsname, dir]);
  except
    Result := 'MKDIR';
  end;
end;

{ TPazoRaceTask }
constructor TPazoRaceTask.Create(const netname, channel, site1, site2: String; pazo: TPazo; const dir, filename: String; const filesize: Int64; const rank: integer);
begin
  inherited Create(netname, channel, site1, site2, pazo);
  self.dir := dir;
  self.rank := rank;
  self.filename := filename;
  if config.ReadBool('taskrace', 'convert_filenames_to_lowercase', True) then
    self.FFilenameForSTORCommand := lowercase(filename)
  else
    self.FFilenameForSTORCommand := filename;

  self.filesize := filesize;
end;

function TPazoRaceTask.Execute(slot: Pointer): boolean;
label
  TryAgain;
var
  ssrc, sdst, fPassiveSlot, fActiveSlot: TSiteSlot;
  RequireSSL, fUseReverseFXP, fNeedsImmediateRETR: boolean;
  host: String;
  port: integer;
  FileSendByMe: boolean;
  numerrors: integer;
  started, ended: TDateTime;
  time_race: integer;
  todir1, todir2: String;
  rss, rsd: boolean;
  tname: String;
  speed_stat: String;
  fsize, racebw: double;
  lastResponseCode: integer;
  lastResponse: String;
  fDiffSec: integer;
  fDiffMSec: Int64;
  fDirlist: TDirlist;
  fDirlistEntry: TDirlistEntry;

  procedure _setOutOfSpace(const aSlot: TSiteSlot; const aErrorReason: String);
  begin
    aSlot.site.SetOutofSpace;
    if aSlot.site.SetDownOnOutOfSpace then
      aSlot.DestroySocket(True);
    readyerror := True;
    mainpazo.errorreason := aErrorReason;
    Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
  end;

  procedure _handleErrorRETR();
  begin
    if (
      ( (lastResponseCode = 550) AND (
        (0 < Pos('No such file or directory', lastResponse)) or (0 < Pos('Unable to load your own user file', lastResponse)) or
        (0 < Pos('File not found', lastResponse)) or (0 < Pos('File unavailable', lastResponse)) ) )
      OR
      ( (lastResponseCode = 426) AND (
        (0 < Pos('File has been deleted on the master', lastResponse)) or (0 < Pos('is being deleted', lastResponse)) or
        (0 < Pos('found in any root', lastResponse)) or (0 < Pos('Transfer was aborted', lastResponse)) or
        (0 < Pos('Slave is offline', lastResponse)) ) )
    ) then
    begin
      if spamcfg.readbool(c_section, 'no_such_file_or_directory', True) then
      begin
        irc_Adderror(ssrc.todotask, '<c4>[ERROR No Such File]</c> TPazoRaceTask %s', [tname]);
      end;
    end
    else
    begin
      irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
    end;
  end;

begin
  Result := False;
  ssrc := slot1;
  sdst := slot2;
  numerrors := 0;
  tname := Name;

  if mainpazo.stopped then
  begin
    mainpazo.errorreason := 'Mainpazo stopped!';
    readyerror := True;
    exit;
  end;

  if (ps2.badcrcevents >= config.ReadInteger('taskrace', 'badcrcevents', 15)) then
  begin
    mainpazo.errorreason := 'Too many CRC errors!';
    readyerror := True;
    exit;
  end;

  mainpazo.lastTouch := Now();
  Debug(dpMessage, c_section, '--> ' + tname);

  TryAgain:
  if ((ps1.error) or (ps2.error) or (ps1.status = rssNuked) or (ps2.status = rssNuked) or (slshutdown)) then
  begin
    readyerror := True;
    mainpazo.errorreason := 'ERROR PS1 or PS2';
    Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;

  try
    Inc(numerrors);
    if numerrors > 3 then
    begin
      if ssrc.status <> ssOnline then
        ssrc.DestroySocket(True);
      if sdst.status <> ssOnline then
        sdst.DestroySocket(True);

      irc_Adderror(Format('<c4>[ERROR] Protocol</c> %s', [tname]));
      mainpazo.errorreason := 'PazoRaceTask numerror > 3';
      readyerror := True;
      Debug(dpMessage, c_section, '<- ' + tname);
      exit;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] Taskrace Protocol errors: %s', [e.Message]);
      mainpazo.errorreason := 'PazoRaceTask numerror > 3';
      readyerror := True;
      exit;
    end;
  end;

  if ssrc.status <> ssOnline then
    if not ssrc.ReLogin(0, False, 'TPazoRaceTask') then
    begin
      mainpazo.errorreason := 'Site ' + ssrc.site.Name + ' is offline';
      readyerror := True;
      Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;
  if sdst.status <> ssOnline then
    if not sdst.ReLogin(0, False, 'TPazoRaceTask') then
    begin
      mainpazo.errorreason := 'Site ' + sdst.site.Name + ' is offline';
      readyerror := True;
      Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;

  if mainpazo.rls <> nil then
    todir1 := MyIncludeTrailingSlash(ps1.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir
  else
    todir1 := MyIncludeTrailingSlash(ps1.maindir) + dir;

  try
    if not ssrc.Cwd(todir1) then
    begin
      //fix drftpd messed up working directory by reconnect
      if ssrc.site.sw = sswDrftpd then
      begin
        ssrc.Quit;
        if not ssrc.ReLogin(0, False, 'TPazoRaceTask') then
        begin
          mainpazo.errorreason := 'Site ' + ssrc.site.Name + ' is offline';
          readyerror := True;
          Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
          exit;
        end;
      end;

      if not ssrc.Cwd(todir1) then
      begin
        irc_Adderror(Format('<c4>[ERROR]</c> %s : %s', [tname, 'Src ' + todir1 + ' on ' + site1 + ' does not exist']));
        if (dir = '') then
        begin
          ps1.MarkSiteAsFailed('cant cwd on src');
        end;
        readyerror := True;
        mainpazo.errorreason := 'cant cwd on src';
        Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
        exit;
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] Taskrace Src dir  does not exist: %s', [e.Message]);
      mainpazo.errorreason := 'cant cwd on src';
      readyerror := True;
      exit;
    end;
  end;

  if mainpazo.rls <> nil then
    todir2 := MyIncludeTrailingSlash(ps2.maindir) + MyIncludeTrailingSlash(mainpazo.rls.rlsname) + dir
  else
    todir2 := MyIncludeTrailingSlash(ps2.maindir) + dir;

  try
    if not sdst.Cwd(todir2) then
    begin
      //fix drftpd messed up working directory by reconnect
      if sdst.site.sw = sswDrftpd then
      begin
        sdst.Quit;
        if not sdst.ReLogin(0, False, 'TPazoRaceTask') then
        begin
          mainpazo.errorreason := 'Site ' + sdst.site.Name + ' is offline';
          readyerror := True;
          Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
          exit;
        end;
      end;

      if not sdst.Cwd(todir2) then
      begin
        irc_Adderror(Format('<c4>[ERROR]</c> %s : %s', [tname, 'Dst ' + todir2 + ' on ' + site2 + ' does not exist']));
        if (dir = '') then
        begin
          ps2.MarkSiteAsFailed('cant cwd on dst');
        end;
        readyerror := True;
        mainpazo.errorreason := 'cant cwd on dst';
        Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
        exit;
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] Taskrace Dst dir  does not exist: %s', [e.Message]);
      mainpazo.errorreason := 'cant cwd on dest';
      readyerror := True;
      exit;
    end;
  end;

  if ((ssrc.site.sslfxp = srNeeded) and (sdst.site.sslfxp = srUnsupported)) then
  begin
    Debug(dpSpam, c_section, 'SSLFXP on site %s is not supported', [sdst.site.Name]);
    irc_Adderror(Format('<c4>[ERROR]</c> SSLFXP on site %s is not supported', [sdst.site.Name]));
    mainpazo.errorreason := 'SSLFXP on site ' + sdst.site.Name + ' is not supported';
    readyerror := True;
    Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;

  if ((ssrc.site.sslfxp = srUnsupported) and (sdst.site.sslfxp = srNeeded)) then
  begin
    Debug(dpSpam, c_section, 'SSLFXP on site %s is not supported', [ssrc.site.Name]);
    mainpazo.errorreason := 'SSLFXP on site ' + ssrc.site.Name + ' is not supported';
    irc_Adderror(Format('<c4>[ERROR]</c> SSLFXP on site %s is not supported', [ssrc.site.Name]));
    readyerror := True;
    Debug(dpMessage, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;

  // from https://wiki.filezilla-project.org/FTP_over_TLS
  // Communication encrypted: PROT C
  // Communication + Data encrypted: PROT P
  if ((ssrc.site.sslfxp = srNeeded) or (sdst.site.sslfxp = srNeeded)) then
  begin
    RequireSSL := True;
    if not ssrc.SendProtP() then
      goto TryAgain;
    if not sdst.SendProtP() then
      goto TryAgain;
  end
  else
  begin
    RequireSSL := False;
    if not ssrc.SendProtC() then
      goto TryAgain;
    if not sdst.SendProtC() then
      goto TryAgain;
  end;

  if (ssrc.site.sw = sswDrftpd) then
  begin
    if not ssrc.Send('PRET RETR %s', [ssrc.TranslateFilename(filename)]) then
      goto TryAgain;
    if not ssrc.Read('PRET RETR') then
      goto TryAgain;


    lastResponseCode := ssrc.lastResponseCode;
    lastResponse := ssrc.lastResponse;

    if ( (lastResponseCode <> 200) AND ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) ) then
    begin
      case lastResponseCode of
      421:
        begin
          //421 - Service not available, closing control connection. This may be a reply to any command if the service knows it must shut down.
          Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
          ssrc.QuitAndRelogin('TPazoRaceTask');
          goto TryAgain;
        end;
      426:
        begin
          //426- Accept timed out
          if (0 <> Pos('Accept timed out', lastResponse)) then
          begin
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;
      530:
        begin
          //530 - Not logged in.

          //530 No transfer-slave(s) available
          if (0 <> Pos('No transfer-slave(s) available', lastResponse)) then
          begin
            _setOutOfSpace(ssrc, 'No transfer-slave(s) available');
            exit;
          end;

          Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
          ssrc.QuitAndRelogin('TPazoRaceTask');
          goto TryAgain;
        end;
      end;

      Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
      _handleErrorRETR();
      readyerror := True;
      mainpazo.errorreason := 'PRET RETR failed on ' + site1;
      Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;
  end;

  if (sdst.site.sw = sswDrftpd) then
  begin
    if not sdst.Send('PRET STOR %s', [sdst.TranslateFilename(FFilenameForSTORCommand)]) then
      goto TryAgain;
    if not sdst.Read('PRET STOR', True, True, 0, 5000) then
      goto TryAgain;


    lastResponseCode := sdst.lastResponseCode;
    lastResponse := sdst.lastResponse;

    if ( (lastResponseCode <> 200) AND ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) ) then
    begin
      case lastResponseCode of
        530:
        begin
          if (0 < Pos('No transfer-slave(s) available', lastResponse)) then
          begin
            _setOutOfSpace(sdst, 'No transfer-slave(s) available');
            exit;
          end;
        end;
        553:
        begin
          if (ResponseContainsDupeKeyword(lastResponse)) then
          begin
            ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
            ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            Debug(dpMessage, c_section, '<-- DUPE ' + lastResponse + ' ' + tname);
            ready := True;
            Result := True;
            exit;
          end;

          //553 means: Requested action not taken. File name not allowed.
          //therefore don't try to send that file again
          if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
          begin
            irc_Adderror(Format('<c4>[NOT ALLOWED]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
          end;
          readyerror := True;
          ps2.SetFileError(netname, channel, dir, filename);
          exit;
        end;
        550:
        begin
          if (ResponseContainsDupeKeyword(lastResponse)) then
          begin
            ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
            ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            Debug(dpMessage, c_section, '<-- DUPE ' + lastResponse + ' ' + tname);
            ready := True;
            Result := True;
            exit;
          end;
        end;
        421:
        begin
          //421 - Service not available, closing control connection. This may be a reply to any command if the service knows it must shut down.
          irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
          Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
          sdst.QuitAndRelogin('TPazoRaceTask');
          goto TryAgain;
        end;
        426:
        begin
          //COMPLETE MSG: 426 Connection closed; transfer aborted.
          if (0 < Pos('transfer aborted', lastResponse)) then
          begin
            //try again
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;
      end;

      irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
      Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
      readyerror := True;
      mainpazo.errorreason := 'PRET STOR failed on ' + site2;
      Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;
  end;

  //if one site requires reverse FXP, use reverse FXP
  fUseReverseFXP := sdst.site.UseReverseFxpDestination or ssrc.site.UseReverseFxpSource;

  //in case of reverse FXP, if glFTPD is the destination, glFTPd requires the RETR command to be issued at the source before it acts
  //else we cannot read a response from STOR (will timeout and cause "can't open data connection")
  fNeedsImmediateRETR := fUseReverseFXP and (sdst.site.sw = sswGlftpd);

  if fUseReverseFXP then
  begin
    fPassiveSlot := sdst;
    fActiveSlot := ssrc;
  end
  else
  begin
    fPassiveSlot := ssrc;
    fActiveSlot := sdst;
  end;

  (* we prefer CPSV over SSCN because it takes care of the encrypted connection
     in one command instead of two *)
  if (RequireSSL) and (sfCPSV in fPassiveSlot.site.features) then
  begin
    if not fPassiveSlot.Send('CPSV') then
      goto TryAgain;
  end
  else
  begin
    if (sfSSCN in fPassiveSlot.site.features) then
    begin
      if (RequireSSL) and (not fPassiveSlot.SendSSCNEnable()) then
        goto TryAgain;
      if (not RequireSSL) and (not fPassiveSlot.SendSSCNDisable()) then
	goto TryAgain;
    end;

    if not fPassiveSlot.Send('PASV') then
      goto TryAgain;
  end;
  if not fPassiveSlot.Read('PASV') then
    goto TryAgain;

  //guess we need this for responses which are longer than one line, so it won't be changed of it reads further response
  lastResponseCode := fPassiveSlot.lastResponseCode;
  lastResponse := fPassiveSlot.lastResponse;

  Debug(dpSpam, 'taskrace', '--> SENT: CPSV/PASV');
  Debug(dpSpam, 'taskrace', '<-- RECEIVED: %s', [lastResponse]);

  // 227 Entering Passive Mode.
  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (lastResponseCode <> 227) AND ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) ) then
  begin

    case lastResponseCode of
      421:
        begin

          //COMPLETE MSG: 421 Timeout (10 seconds): closing control connection.
          if (0 < Pos('Timeout', lastResponse)) then
          begin
            irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fPassiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain; //just try again, should hopefully resolve this issue
          end;
        end;


      425:
        begin
          //COMPLETE MSG: 425 Can't open passive connection!
          //COMPLETE MSG: 425 Can't open passive connection: Address already in use.
          //COMPLETE MSG: 425 Can't open data connection.
          if ((0 <> Pos('t open passive connection', lastResponse)) OR (0 <> Pos('t open data connection', lastResponse))) then
          begin
            irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fPassiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      426:
        begin
          //COMPLETE MSG: 426 Data connection: Broken pipe
          //COMPLETE MSG: 426 Data connection: Connection reset by peer.
          //COMPLETE MSG: 426 Sendfile error: Broken pipe.
          if ((0 <> Pos('Data connection', lastResponse)) OR (0 <> Pos('Sendfile error', lastResponse))) then
          begin
            irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fPassiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      450, 530:
        begin
          //COMPLETE MSG: 450 No transfer-slave(s) available
          //COMPLETE MSG: 530 No transfer-slave(s) available
          if (0 <> Pos('No transfer-slave(s) available', lastResponse)) then
          begin
            // no available transfer-slave(s) on drftpd means that you can't upload/download (latter is the case here, srcsite) because drftpd has no slave to use,
            // so it's out of space. iirc drftpd also shows less space then when typing !df in sitechan when slaves are offline
            _setOutOfSpace(fPassiveSlot, 'No transfer-slave(s) available');
            exit;
          end;

          //COMPLETE MSG: 450 No data connection available
          if (0 <> Pos('No data connection available', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[No data connection available]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            mainpazo.errorreason := 'No data connection available';
            readyerror := True;
            fPassiveSlot.QuitAndRelogin('TPazoRaceTask');
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;
        end;

      500:
        begin
          if (0 <> Pos('You need to use a client supporting PRET', lastResponse)) then
          begin
            irc_AddINFO('[iNFO] PRET needed for: ' + fPassiveSlot.Name);
            fPassiveSlot.site.sw := sswDrftpd;
            goto TryAgain;
          end;
          if ((RequireSSL) and (0 < Pos('understood', lastResponse))) then
          begin
            irc_AddINFO('[iNFO] SSLFXP not supported for: ' + fPassiveSlot.Name);
            fPassiveSlot.site.sslfxp := srUnsupported;
            goto TryAgain;
          end;

          //500 Unsupported command during transfer.
          if (0 <> Pos('Unsupported command', lastResponse)) then
          begin
            irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fPassiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;

      550:
        begin
          //COMPLETE MSG: 550 Requested action not taken. File unavailable.
          if (0 <> Pos('Requested action not taken', lastResponse)) then
          begin
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            goto TryAgain;
          end;

          //COMPLETE MSG: 550 file.rar: No such file or directory.
          if (0 <> Pos('No such file or directory', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'no_such_file_or_directory', True) then
            begin
              irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR No Such File]</c> TPazoRaceTask %s', [tname]);
            end;
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            mainpazo.errorreason := 'No such file';
            readyerror := True;
            exit;
          end;
        end;

      553:
        begin
          //COMPLETE MSG: 553- X-DUPE: sr-kqtcc.r22
          if (0 < Pos('X-DUPE', lastResponse)) then
          begin
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            ps1.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            goto TryAgain;
          end;
        end;
    end;


    Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
    irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fPassiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
    readyerror := True;
    mainpazo.errorreason := 'PASV/CPSV failed on ' + fPassiveSlot.site.Name;
    Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;

  try
    ParsePASVString(fPassiveSlot.lastResponse, host, port);
  except
    on e: Exception do
    begin
      Debug(dpError, c_section, '[EXCEPTION] Taskrace ParsePASVString: %s', [e.Message]);
      readyerror := True;
      exit;
    end;
  end;


  if not fActiveSlot.Send('PORT %s,%d,%d', [ReplaceText(host, '.', ','), port div 256, port mod 256]) then
    goto TryAgain;
  if not fActiveSlot.Read('PORT') then
    goto TryAgain;

  lastResponseCode := fActiveSlot.lastResponseCode;
  lastResponse := fActiveSlot.lastResponse;

  if ((lastResponseCode = 500) and (0 <> Pos('You need to use a client supporting PRET', lastResponse))) then
  begin
    irc_AddINFO('[iNFO] PRET needed for: ' + fActiveSlot.Name);
    fActiveSlot.site.sw := sswDrftpd;
    goto TryAgain;
  end;

  if ((lastResponseCode < 100) Or (lastResponseCode >= 300)) then
  begin
    irc_Adderror(fPassiveSlot.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [fActiveSlot.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
    goto TryAgain;
  end;

  if not sdst.Send('STOR %s', [sdst.TranslateFilename(FFilenameForSTORCommand)]) then
    goto TryAgain;

  if fNeedsImmediateRETR then
  begin
    if not ssrc.Send('RETR %s', [ssrc.TranslateFilename(filename)]) then
      goto TryAgain;
  end;

  if not sdst.Read('STOR', True, True, 0, 5000) then
  begin
    sdst.QuitAndRelogin('TPazoRaceTask');
    if fNeedsImmediateRETR then
      ssrc.DestroySocketAndRelogin('TPazoRaceTask');

    goto TryAgain;
  end;


  lastResponseCode := sdst.lastResponseCode;
  lastResponse := sdst.lastResponse;

  Debug(dpSpam, 'taskrace', '--> SENT: STOR %s', [sdst.TranslateFilename(FFilenameForSTORCommand)]);
  Debug(dpSpam, 'taskrace', '<-- RECEIVED: %s', [lastResponse]);


  // 150 File status okay; about to open data connection.
  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (lastResponseCode <> 150) AND ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) ) then
  begin

    if fNeedsImmediateRETR then
    begin

      //STOR produced an error, but RETR has already been sent to the source site. We need to ABOR that.

      if not ssrc.Send('ABOR') then
        ssrc.DestroySocketAndRelogin('TPazoRaceTask');

      rss := False; //reset flag. used to remember if 150 response was read (150 File status okay; about to open send data connection.)

      //there may be any kind or amount of responses coming after sending ABOR. Read until 'ABOR command successful'.
      repeat
        ssrc.Read('ABOR', False, True, 1000);
        if ssrc.error <> '' then
        begin
          ssrc.DestroySocketAndRelogin('TPazoRaceTask');
          rss := True;
          break;
        end;

        if ssrc.lastResponseCode = 150 then
          rss := True;

        //response code should be 226, might also be 225
        //glFTPd: ABOR command successful.
        //glFTPd: Abort successful
        //DrFTPD: ABOR command successful
        //ioFTPD: ABOR command successful.
        //RaidenFTPD: Abort successful.
        until ((ssrc.lastResponseCode > 199) and (ssrc.lastResponseCode < 300) and
          ((ssrc.lastResponse.Contains('ABOR')) or (ssrc.lastResponse.Contains('Abort successful'))));

      if ssrc.site.sw = sswDrftpd then
      begin
        //drftpd sometimes sends 150 response even after "ABOR command successful". So wait for that a bit.
        if not rss then
          ssrc.Read('ABOR', False, True, 10);

        //ok and sometimes the ABOR command destroys the session for drftpd (following commands do not send a response -> timeout)
        //send a command and see if there is a response. if not, invoke DestroySocket.
        if not ssrc.Send('NOOP') then
        begin
          ssrc.DestroySocketAndRelogin('TPazoRaceTask');
        end
        else if not ssrc.Read('NOOP', False, True, 20) then
        begin
          Debug(dpMessage, c_section, 'Slot seems broken after ABOR: ' + ssrc.Name);
          ssrc.DestroySocketAndRelogin('TPazoRaceTask');
        end;
      end;
    end;

    case lastResponseCode of
      400:
        begin
          if (0 < Pos('SFVFile still transferring', lastResponse)) then
          begin
            readyerror := True;
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;
        end;

      421:
        begin
          //COMPLETE MSG: 421 Connection closing
          if (0 < Pos('Connection closing', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[Connection closing]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            ssrc.QuitAndRelogin('TPazoRaceTask');
            sdst.QuitAndRelogin('TPazoRaceTask');
            goto TryAgain;
          end;

          //COMPLETE MSG: 421 Timeout (90 seconds): closing control connection.
          if (0 < Pos('closing control connection', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[Connection closing]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            sdst.QuitAndRelogin('TPazoRaceTask');
            goto TryAgain;
          end;
        end;

      425:
        begin
          if (0 < Pos('Connection refused', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[REFUSED]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            ssrc.QuitAndRelogin('TPazoRaceTask');
            sdst.QuitAndRelogin('TPazoRaceTask');
            goto TryAgain;
          end;

          //425 Can't open data connection.
          if (0 < Pos('Can''t open data connection', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
              irc_Adderror(Format('<c4>[Can''t open data connection]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));

            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            mainpazo.errorreason := 'Can''t open data connection';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;

          //COMPLETE MSG: 425 Can't build data connection
          if (0 < Pos('t build data connection', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
              irc_Adderror(sdst.todotask, '<c4>[ERROR Cant build]</c> TPazoRaceTask %s', [tname]);

            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            mainpazo.errorreason := 'Timeout or building data connection problem';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;
        end;

      426:
        begin
          if (0 < Pos('Broken pipe', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[Broken pipe]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            ssrc.QuitAndRelogin('TPazoRaceTask');
            sdst.QuitAndRelogin('TPazoRaceTask');
            goto TryAgain;
          end;

          //426 Sendfile error: Connection reset by peer.
          if (0 < Pos('Connection reset by peer', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            //just retry
            goto TryAgain;
          end;
        end;

      427, 530:
        begin
          if ( (0 < Pos('Use SSL FXP',lastResponse)) or (0 < Pos('USE SECURE DATA CONNECTION', lastResponse)) ) then
          begin //427 .. Use SSL FXP                                    //530 .. USE SECURE DATA CONNECTION
            sdst.site.sslfxp := srNeeded;
            irc_AddINFO('[iNFO] SSLFXP Need for: ' + sdst.Name);
            goto TryAgain;
          end;

          if (0 < Pos('not allowed in this file name', lastResponse)) then
          begin   //530 .. not allowed in this file name
            if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
            begin
              irc_Adderror(Format('<c4>[NOT ALLOWED]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            end;
            readyerror := True;
            ps2.SetFileError(netname, channel, dir, filename);
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          //COMPLETE MSG: 530 Access denied
          if (0 < Pos('Access denied', lastResponse)) then
          begin
            irc_Adderror(ssrc.todotask, '<c4>[ERROR] Access denied</c> %s', [tname]);
            readyerror := True;
            //access denied - don't try again
            ps2.SetFileError(netname, channel, dir, filename);
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;
        end;

      435:
        begin
          //COMPLETE MSG: 435 Failed TLS negotiation on data channel (using SSL_accept()), disconnected
          if (0 < Pos('Failed TLS negotiation', lastResponse)) then
          begin
            //try again and hopefully it'll work then. Else try to disable SSL/sslfxp and try again. Or setdown with reason of some SSL problem (maybe too old SSL version)
            //maybe relogin needed because response says something about disconnect!
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, AnsiLeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;

      450, 452, 533, 553:
        begin
          if ( (0 < Pos('out of disk space', lastResponse))
            or (0 < Pos('No space left on device', lastResponse))
            or (0 < Pos('Error writing file', lastResponse))
            or (0 < Pos('No transfer-slave(s) available', lastResponse)) ) then
          begin       //553 .. out of disk space                            //452 .. No space left on device                      //450 .. No transfer-slave(s) available
            _setOutOfSpace(sdst, 'No freespace or slave');
            exit;
          end;

          //COMPLETE MSG: 533 Requested action not taken. Multiple SFV files not allow(ed)? [guess DRFTPD]
          //              553 Multiple SFV files not allowed. [GLFTPD] -- I guess it's from glftpd and maybe not the complete response
          //              553 Max sim UP per dir/sfv reached [GLFTPD] -- I guess it's from glftpd and maybe not the complete response
          if ( (0 < Pos('Multiple SFV files not allow', lastResponse)) OR (0 < Pos('Max sim UP per dir/sfv reached', lastResponse)) ) then
          begin
            readyerror := True;
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          if (0 < Pos('Upload denied by pre_check script', lastResponse)) then
          begin     //553 .. Upload denied by pre_check script
            readyerror := True;
            ps2.SetFileError(netname, channel, dir, filename);
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          if ((0 < Pos('does not exist in the sfv', lastResponse)) OR (0 < Pos('File not found in sfv', lastResponse)) OR (0 < Pos('File not found in SFV', lastResponse))) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR NOT IN SFV]</c> %s', [Name]);
            readyerror := True;
            ps2.SetFileError(netname, channel, dir, filename);
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          if ((0 < Pos('You must upload sfv first', lastResponse)) OR (0 < Pos('You must upload SFV first', lastResponse))) then
          begin
            ready := True;
            Result := True;
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          if ( (0 < Pos('maximum simultaneous uploads', lastResponse)) or (0 < Pos('Your have reached your maximum of', lastResponse)) ) then
          begin
            if spamcfg.readbool(c_section, 'reached_max_sim_up', True) then
              irc_Adderror(sdst.todotask, '<c4>[ERROR] Maxsim up (confed max_up: %d)</c> %s (%s)', [sdst.site.max_up, tname, lastResponse]);

            mainpazo.errorreason := 'Maximum of simultaneous uploads reached';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;

          //COMPLETE MSG: 450 No data connection available
          if (0 <> Pos('No data connection available', lastResponse)) then
          begin
            irc_Adderror(Format('<c4>[No data connection available]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            mainpazo.errorreason := 'No data connection available';
            readyerror := True;
            sdst.QuitAndRelogin('TPazoRaceTask');
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;

          // we still have an error with sdst.lastResponseCode = 553
          if (lastResponseCode = 553) then
          begin
            if (ResponseContainsDupeKeyword(lastResponse)) then
            begin
              ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
              ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
              Debug(dpMessage, c_section, '<-- DUPE ' + lastResponse + ' ' + tname);
              ready := True;
              Result := True;
              exit;
            end;

            //553 means: Requested action not taken. File name not allowed.
            //therefore don't try to send that file again
            if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
            begin
              irc_Adderror(Format('<c4>[NOT ALLOWED]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
            end;
            readyerror := True;
            ps2.SetFileError(netname, channel, dir, filename);
            exit;
          end;
        end;

      500, 550:
        begin
          if (0 < Pos('No such directory', lastResponse)) then
          begin   //550 .. No such directory
            irc_Adderror(Format('<c4>[ERROR]</c> %s %s', [tname, lastResponse]));

            if (dir = '') then
            begin
              ps2.MarkSiteAsFailed('No such directory');
            end
            else
            begin
             //some sites let you create a subfolder (e.g. Proof) just to then delete it which results in a flood of "550 No such directory."
             //do not retry the file in that case
             ps2.SetFileError(netname, channel, dir, filename);
            end;

            readyerror := True;
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            exit;
          end;

          //550 Requested action not taken. File unavailable (e.g., file not found, no access)
          if (0 < Pos('File unavailable', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            readyerror := True;
            exit;
          end;

          //500 Unsupported command during transfer.
          //500 No text
          if ((0 < Pos('Unsupported command', lastResponse))
            OR (0 < Pos('No text', lastResponse))) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            //just retry
            goto TryAgain;
          end;

          //550 System Error- file.rar: No space left on device.
          if (0 < Pos('No space left on device', lastResponse)) then
          begin
            _setOutOfSpace(sdst, 'No space left on device');
            exit;
          end;

          //550 Your have reached your maximum of 3 simultaneous uploads. Transfer denied.
          if 0 < Pos('Your have reached your maximum of', lastResponse) then
          begin
            if spamcfg.readbool(c_section, 'reached_max_sim_up', True) then
              irc_Adderror(sdst.todotask, '<c4>[ERROR] Maxsim up (confed max_up: %d)</c> %s (%s)', [sdst.site.max_up, tname, lastResponse]);

            mainpazo.errorreason := 'Maximum of simultaneous uploads reached';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;

          if (ResponseContainsDupeKeyword(lastResponse)) then
          begin
            ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
            ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            Debug(dpMessage, c_section, '<-- DUPE ' + lastResponse + ' ' + tname);
            ready := True;
            Result := True;
            exit;
          end
        end;


      503:
        begin

          //COMPLETE MSG: 503 Bad sequence of commands.
          if (0 < Pos('Bad sequence of commands', lastResponse)) then
          begin
            // something went wrong while sending commands, try again should solve it
            irc_Adderror(sdst.todotask, '<c4>[ERROR] Bad sequence of commands</c> %s', [tname]);
            goto TryAgain;
          end;

        end;

      540:
        begin
          //COMPLETE MSG: 540 Command execution failed
          if (0 < Pos('Command execution failed', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, AnsiLeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;
      end;

      Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
      irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);

      mainpazo.errorreason := Format('Unhandled error %s after STOR (%s) : %d %s', [sdst.site.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
      sdst.DestroySocketAndRelogin('TPazoRaceTask');
      readyerror := True;
      Debug(dpMessage, c_section, '<- ' + tname);
      exit;
  end;

  if not fNeedsImmediateRETR then
  begin
    if not ssrc.Send('RETR %s', [ssrc.TranslateFilename(filename)]) then
      goto TryAgain;
  end;

  if not ssrc.Read('RETR') then
  begin
    // breastfed, the dst to run because it works at all. closes the login will fuck up again.
    sdst.QuitAndRelogin('TPazoRaceTask');
    goto TryAgain;
  end;

  lastResponseCode := ssrc.lastResponseCode;
  lastResponse := ssrc.lastResponse;

  Debug(dpSpam, 'taskrace', '--> SENT: RETR %s', [ssrc.TranslateFilename(filename)]);
  Debug(dpSpam, 'taskrace', '<-- RECEIVED: %s', [lastResponse]);

  started := Now;

  // 150 File status okay; about to open data connection.
  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (lastResponseCode <> 150) AND ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) ) then
  begin

    case lastResponseCode of
      421:
        begin
          //COMPLETE MSG: 421 Timeout (10 second .... ?
          if (0 < Pos('Timeout', lastResponse)) then
          begin
            //try again or just exit, because timeout -> bad routing, offline?
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;

      425, 426:
        begin
          //COMPLETE MSG: 425 Can't open data connection.
          //COMPLETE MSG: 426 Read timed out
          if ( (0 < Pos('t open data connection', lastResponse)) or (0 < Pos('Read timed out', lastResponse)) ) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
              irc_Adderror(ssrc.todotask, '<c4>[ERROR Cant open]</c> TPazoRaceTask %s', [tname]);

              sdst.DestroySocketAndRelogin('TPazoRaceTask');
              mainpazo.errorreason := 'Timeout or opening data connection problem';
              readyerror := True;
              Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
              exit;
          end;


          //COMPLETE MSG: 425 Transfers to 3rd party addresses are not supported.
          if ( 0 < Pos('addresses are not supported', lastResponse) ) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
              irc_Adderror(ssrc.todotask, '<c4>[ERROR Cant open]</c> TPazoRaceTask %s', [tname]);


              // maybe remove the source from race because fxp isn't allowed?
              sdst.DestroySocketAndRelogin('TPazoRaceTask');
              mainpazo.errorreason := 'Opening data connection problem';
              readyerror := True;
              Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
              exit;
          end;
        end;

      427, 530:
        begin
          if ((0 < Pos('Use SSL FXP', lastResponse)) or (0 < Pos('USE SECURE DATA CONNECTION', lastResponse))) then
          begin   //427 .. Use SSL FXP                               //530 .. USE SECURE DATA CONNECTION
            ssrc.site.sslfxp := srNeeded;
            // must do one read on destination
            if not sdst.Read() then
              goto TryAgain;

            // must do two read on source
            if not ssrc.Read() then
              goto TryAgain;
            if not ssrc.Read() then
              goto TryAgain;

            irc_AddINFO('[iNFO] SSLFXP needed on Source: ' + ssrc.Name);
            goto TryAgain;
          end;

          //COMPLETE MSG: 530 Access denied
          if (0 < Pos('Access denied', lastResponse)) then
          begin
            // not sure what happend, maybe try again or disable site because downloading (fxping) is not allowed?
            irc_Adderror(ssrc.todotask, '<c4>[ERROR] Access denied</c> %s', [tname]);
            goto TryAgain;
          end;
        end;


      503:
        begin

          //COMPLETE MSG: 503 Bad sequence of commands.
          if (0 < Pos('Bad sequence of commands', lastResponse)) then
          begin
            // something went wrong while sending commands, try again should solve it
            irc_Adderror(ssrc.todotask, '<c4>[ERROR] Bad sequence of commands</c> %s', [tname]);
            goto TryAgain;
          end;
        end;


      550, 553:
        begin
          //COMPLETE MSG: 550 Insufficient credits.
          if (0 < Pos('credit', LowerCase(lastResponse))) then //Find out complete response and maybe remove the lowercase | add longer text to match with
          begin
            // TODO: Modificate 'procedure TSite.SetKredits;' to write a value to config with old max_dl_slots
            // and if credits > 10gb remove this value and set used max_dl_slots back to old saved value
            // need to have first coded TSite.LastCredits to get it work somehow
            ssrc.site.SetKredits;

            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            mainpazo.errorreason := 'Out of credits';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;

          if (0 < Pos('Taglines Enforced', lastResponse)) then
          begin
            if not ssrc.Send('SITE TAGLINE %s', ['SLFTP.4tw']) then
              goto TryAgain;
            if not ssrc.Read('SITE TAGLINE') then
              goto TryAgain;

            goto TryAgain;
          end;

          //COMPLETE MSG: 553 Permission Denied: not allowed to download from this directory!
          if ((0 < Pos('Permission denied', lastResponse)) or (0 < Pos('Permission Denied', lastResponse))) then
          begin
            if spamcfg.readbool(c_section, 'permission_denied', True) then
              irc_Adderror(ssrc.todotask, '<c4>[ERROR] Permission denied</c> %s', [tname]);

            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            mainpazo.errorreason := 'Permission denied';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;


          //COMPLETE MSG: 550 Permission Denied: 300.0GB bandwidth usage detected. Current Ratio:(0.46/0.5).
          if (0 < Pos('bandwidth usage detected', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'permission_denied', True) then
              irc_Adderror(ssrc.todotask, '<c4>[ERROR] Permission denied</c> %s', [tname]);

            //TODO: Disable downloading for this site for some time until you uploaded more stuff to download again
            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            mainpazo.errorreason := 'Permission denied - limit of bandwidth usage detected';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;


          //COMPLETE MSG: 550 You have downloaded the same file too often. Please check your AUTO retry setti ... ?
          if (0 < Pos('downloaded the same file too often', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'reached_max_sim_down', True) then
              irc_Adderror(ssrc.todotask, '<c4>[ERROR] You have downloaded the same file too often</c> %s', [tname]);

            sdst.DestroySocket(False);
            mainpazo.errorreason := 'downloaded the same file too often';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;


          //COMPLETE MSG: 550 Your have reached your maximum of 4 simultaneous downloads. Transfer denied. [DRFTPD]
          //              553 You have reached your maximum simultaneous downloads allowed. [GLFTPD]
          if ( (0 < Pos('You have reached your maximum simultaneous downloads allowed', lastResponse)) or (0 < Pos('Your have reached your maximum of', lastResponse)) ) then
          begin
            if spamcfg.readbool(c_section, 'reached_max_sim_down', True) then
              irc_Adderror(sdst.todotask, '<c4>[ERROR] Maxsim down (confed max_dn/max_pre_dn: %d/%d)</c> %s (%s)', [ssrc.site.max_dn, ssrc.site.max_pre_dn, tname, lastResponse]);
              // on glftpd we could try to kill ghosts if it occurs over and over and on drftpd only setdown the site helps if it occurs over and over

            sdst.DestroySocket(False);
            mainpazo.errorreason := 'Maximum of simultaneous downloads reached';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;
        end;
    end;


    _handleErrorRETR();


    // ilyenkor a dst szalon a legjobb ha lezarjuk a geci a socketet mert az ABOR meg a sok szar amugy sem hasznalhato.
    // es majd ugyis automatan ujrabejelentkezik a cumo
    // This is the best salon dst If you close the socket because of spunk ABOR a lot of crap anyway be used.
    // And then anyway Automatic redial occurs in the CumC3
    sdst.DestroySocket(False);

    mainpazo.errorreason := 'No free slots?';
    readyerror := True;
    Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;

  //add this file as incomplete, transfer is running at this point
  ps2.ParseDupe(netname, channel, dir, filename, False, False);

  Debug(dpSpam, 'taskrace', '--> WAIT');

  rss := False;
  rsd := False;
  while (True) do
  begin
    if not rsd then
      rsd := sdst.Read('WAIT', False, True, 100);
    if ((sdst.error <> '') and (sdst.error <> 'timeout')) then
    begin
      ssrc.DestroySocket(False);
      mainpazo.errorreason := 'sdst WAIT';
      readyerror := True;
      Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;

    if not rss then
      rss := ssrc.Read('WAIT', False, True, 100);
    if ((ssrc.error <> '') and (ssrc.error <> 'timeout')) then
    begin
      sdst.DestroySocket(False);
      mainpazo.errorreason := 'ssrc WAIT';
      readyerror := True;
      Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
      exit;
    end;

    if ((rsd) and (rss)) then
      Break;

    if sdst.site.KillConnectionOnStalledTransferSeconds > 0 then
    begin
      fDiffSec := SecondsBetween(Now, started);
      if fDiffSec > sdst.site.KillConnectionOnStalledTransferSeconds then
      begin
        fDirlist := ps2.dirlist.FindDirlist(dir);
        fDirlist.dirlist_lock.Enter;
        try
          fDirlistEntry := fDirlist.Find(filename);
          fDiffMSec := MillisecondsBetween(Now, fDirlist.LastUpdated);
        finally
          fDirlist.dirlist_lock.Leave;
        end;

        // if the dirlist is fairly up to date and shows a file size of 0 bytes,
        // kill the connection to abort the transfer. the ABOR command does not
        // work (at least on glftpd)
        begin
          if (fDiffMSec < 200) and (fDirlistEntry.filesize = 0) then
          begin
            irc_Adderror(Format('<c4>[STALLED]</c> [%s]: File size 0 for %d seconds - kill connection', [tname, fDiffSec]));
            sdst.DestroySocketAndRelogin('TPazoRaceTask');
            ssrc.DestroySocketAndRelogin('TPazoRaceTask');
            readyerror := True;
            exit;
          end;
        end;
      end;
    end;

    if (SecondsBetween(Now, started) > 600) then
    begin
      Debug(dpError, c_section, Format('[iNFO] Long race break: %s %s %s', [Name, ssrc.lastResponse, sdst.lastResponse]));
      ssrc.DestroySocket(False);
      sdst.DestroySocket(False);
      mainpazo.errorreason := 'Long race break';
      readyerror := True;
      exit;
    end;
  end;

  Debug(dpSpam, 'taskrace', '<-- WAIT');

  //TODO: [ERROR FXP] TPazoRaceTask DST/0, RACE 4727 SRC->DST: Mortal.Kombat.XL-PLAZA plaza-mortal.kombat.xl.s04 (36) 421 421 Timeout (60 seconds): closing control connection.
  //      RACE 4727 SRC->DST: Mortal.Kombat.XL-PLAZA plaza-mortal.kombat.xl.s04 (36) 238.42mB @ 1.16mB/s <-- shouldn't be there, wasn't transfered because a timeout occur
  //  so exit above or goto urja? Or relogin needed?

  //TODO: [ERROR FXP] TPazoRaceTask SRC/2: RACE 4727 SRC->DST: Mortal.Kombat.XL-PLAZA plaza-mortal.kombat.xl.s07 (36) 426 426- Slow transfer: 0B/s too slow for section GAMES, at leas
  // maybe lower routing if this occur several times on same routes (Issue #46)

  lastResponseCode := ssrc.lastResponseCode;
  lastResponse := ssrc.lastResponse;

  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) then
  begin

    case lastResponseCode of

      421:
        begin

          //COMPLETE MSG: 421 Timeout (60 seconds): closing control connection.
          if (0 < Pos('Timeout', lastResponse)) then
          begin
            //try again or just exit, because timeout -> bad routing, offline?
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      425:
        begin
          //COMPLETE MSG: 425 Can't open data connection.
          if (0 <> Pos('t open data connection', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
            begin
              irc_Adderror(ssrc.todotask, '<c4>[ERROR Cant open]</c> TPazoRaceTask %s', [tname]);
            end;

            goto TryAgain;
          end;
        end;


      426:
      begin

        //COMPLETE MSG: 426 Sendfile error: Broken pipe.
        //COMPLETE MSG: 426 Data connection: Broken pipe.
        if ((0 < Pos('Sendfile error', lastResponse)) OR (0 < Pos('Broken pipe', lastResponse))) then
        begin
          //try again
          irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
          goto TryAgain;
        end;

        //COMPLETE MSG: 426- Transfer was aborted - File has been deleted on the master
        //              426 Transfer was aborted - File has been deleted on the master
        if (0 < Pos('File has been deleted on the master', lastResponse)) then
        begin
          //exit here, try again won't help if file don't get traded just again after deleting
          if spamcfg.readbool(c_section, 'no_such_file_or_directory', True) then
          begin
            irc_Adderror(ssrc.todotask, '<c4>[ERROR No Such File]</c> TPazoRaceTask %s', [tname]);
          end;

          Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
          mainpazo.errorreason := 'File has been deleted on the master';
          readyerror := True;
          exit;
        end;

        //COMPLETE MSG: 426- Transfer was aborted - File filename.rar is being deleted
        if (0 < Pos('is being deleted', lastResponse)) then
        begin
          //exit here, try again won't help if file don't get traded just again after deleting
          if spamcfg.readbool(c_section, 'no_such_file_or_directory', True) then
          begin
            irc_Adderror(ssrc.todotask, '<c4>[ERROR No Such File]</c> TPazoRaceTask %s', [tname]);
          end;

          mainpazo.errorreason := 'File is being deleted';
          readyerror := True;
          exit;
        end;

        //COMPLETE MSG: 426- filename.rar wasn't found in any root
        if (0 < Pos('wasn''t found in any root', lastResponse)) then
        begin
          //exit here, try again won't help if file don't get traded just again after deleting
          if spamcfg.readbool(c_section, 'no_such_file_or_directory', True) then
          begin
            irc_Adderror(ssrc.todotask, '<c4>[ERROR No Such File]</c> TPazoRaceTask %s', [tname]);
          end;

          mainpazo.errorreason := 'File wasn''t found in any root';
          readyerror := True;
          exit;
        end;

        //COMPLETE MSG: 426- Slow transfer: 0B/s too slow for section 0DAY, at least 1000B/s required.
        //              426- Transfer was aborted - Slow transfer: 0B/s too slow for section 0DAY
        //              426 Transfer was aborted - Slow transfer: 0B/s too slow for section 0DAY
        if (0 < Pos('Slow transfer', lastResponse)) then
        begin
          //try again, TODO: if failed again maybe lowering route or remove it (banned IP block?)
          irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
          goto TryAgain;
        end;

        //COMPLETE MSG: 426- Connection closed by remote host
        //              426 Transfer failed
        //COMPLETE MSG: 426 Accept timed out
        //COMPLETE MSG: 426 Received fatal alert: handshake_failure
        //COMPLETE MSG: 426 Socket closed
        //COMPLETE MSG: 426 Connection closed by remote host
        //COMPLETE MSG: 426 Data connection: Success.
        //COMPLETE MSG: 426 Timeout while sending data
        //COMPLETE MSG: 426 Sendfile error: Bad message
        if ((0 < Pos('Transfer failed', lastResponse)) OR
          (0 < Pos('Accept timed out', lastResponse)) OR
          (0 < Pos('fatal alert', lastResponse)) OR
          (0 < Pos('Socket closed', lastResponse)) OR
          (0 < Pos('Data connection', lastResponse)) OR
          (0 < Pos('Connection closed', lastResponse)) OR
          (0 < Pos('Sendfile error: Bad message', lastResponse)) OR
          (0 < Pos('Timeout while sending data', lastResponse))) then
        begin
          //try again
          irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
          goto TryAgain;
        end;
      end;


      435:
        begin

          //COMPLETE MSG: 435 Failed TLS negotiation on data channel (SSL_accept(): (5) error:00000000:lib(0):func(0):reason(0)), disconnected
          if (0 < Pos('Failed TLS negotiation', lastResponse)) then
          begin
            //try again and hopefully it'll work then. Else try to disable SSL/sslfxp and try again. Or setdown with reason of some SSL problem (maybe too old SSL version)
            //maybe relogin needed because response says something about disconnect!
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      500:
        begin
          //COMPLETE MSG: 500 No text
          if (0 < Pos('No text', lastResponse)) then
          begin
            //try again and hopefully it'll work then.
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      522:
        begin
          if (0 < Pos('You have to turn on secure data connection', lastResponse)) then
          begin
            ssrc.site.sslfxp := srNeeded;
            if spamcfg.readbool(c_section, 'turn_on_sslfxp', True) then
            begin
              irc_Adderror(ssrc.todotask, '<c4>[ERROR SSLFXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            end;
            goto TryAgain;
          end;
        end;

      550:
        begin
          //COMPLETE MSG: 550 ASSERT: (0) in file sigfix.c line 81 inside function delay_signaling
          if (0 < Pos('ASSERT', lastResponse)) then
          begin
            //try again (maybe will help) or setdown site - some ftpd problem..
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;

      551:
        begin
          //COMPLETE MSG: 551 Error on input file: Input/output error.
          if (0 < Pos('Error on input', lastResponse)) then
          begin
            //try again (maybe will help) or setdown site - some ftpd problem..
            irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;
    end;


    Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
    irc_Adderror(ssrc.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [ssrc.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);

    mainpazo.errorreason := 'ssrc WAIT: Unhandled error response';
    readyerror := True;
    Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;



  lastResponseCode := sdst.lastResponseCode;
  lastResponse := sdst.lastResponse;

  // 1xx Positive Preliminary reply
  // 2xx Positive Completion reply
  if ( (lastResponseCode < 100) OR (lastResponseCode > 299) ) then
  begin

    case lastResponseCode of

      421:
      begin

        //COMPLETE MSG: 421 Timeout (60 seconds): closing control connection.
        if (0 < Pos('Timeout', lastResponse)) then
        begin
          //try again or just exit, because timeout -> bad routing, offline?
          irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
          goto TryAgain;
        end;
      end;


      425:
        begin
          //COMPLETE MSG: 425 Can't build data connection
          if (0 < Pos('t build data connection', lastResponse)) then
          begin
            if spamcfg.readbool(c_section, 'cant_open_data_connection', True) then
              irc_Adderror(sdst.todotask, '<c4>[ERROR Cant build]</c> TPazoRaceTask %s', [tname]);

            sdst.DestroySocket(False);
            mainpazo.errorreason := 'Timeout or building data connection problem';
            readyerror := True;
            Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
            exit;
          end;
        end;


      426:
        begin

          //COMPLETE MSG: 426- Slow transfer: 0B/s too slow for section GAMES, at leas
          if (0 < Pos('Slow transfer', lastResponse)) then
          begin
            //try again, maybe lower routing from srcsite to dstsite
            Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;

          //COMPLETE MSG: 426- Read timed out
          //              426 Transfer failed, deleting file
          if ((0 < Pos('Read timed out', lastResponse)) OR (0 < Pos('Transfer failed', lastResponse))) then
          begin
            //try again
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;

          //COMPLETE MSG: 426- Socket closed
          //              426- Socket is closed
          if ((0 < Pos('Socket closed', lastResponse)) OR (0 < Pos('Socket is closed', lastResponse))) then
          begin
            //try again, maybe lower routing if happens again
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;

          //COMPLETE MSG: 426 Connection closed; transfer aborted.
          //COMPLETE MSG: 426- Transfer was aborted - File has been deleted on the master
          if ((0 < Pos('transfer aborted', lastResponse)) OR (0 < Pos('Transfer was aborted', lastResponse))) then
          begin
            //try again
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;

          //COMPLETE MSG: 426 Data connection: Connection reset by peer.
          //COMPLETE MSG: 426 Data Connection: Success.
          if ((0 < Pos('Connection reset by peer', lastResponse)) OR
            (0 < Pos('Data connection', lastResponse)) OR
            (0 < Pos('Data Connection', lastResponse))) then
          begin
            //try again
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      427:
        begin
          //COMPLETE MSG: 427 Use SSL FXP!
          if (0 < Pos('Use SSL FXP', lastResponse)) then
          begin
            sdst.site.sslfxp := srNeeded;
            // must do one read on source
            if not ssrc.Read() then
              goto TryAgain;

            // must do two read on destination
            if not sdst.Read() then
              goto TryAgain;
            if not sdst.Read() then
              goto TryAgain;

            irc_AddINFO('[iNFO] SSLFXP needed on Destination: ' + sdst.Name);
            goto TryAgain;
          end;
        end;


      435:
        begin

          //COMPLETE MSG: 435 Failed TLS negotiation on data channel (SSL_accept(): (1) error:1408A0C1:SSL routines:SSL3_GET_CLIENT_HELLO:no shared cipher), disconnected
          //COMPLETE MSG: 435 Failed TLS negotiation on data channel (SSL_accept(): (1) error:140760FC:SSL routines:SSL23_GET_CLIENT_HELLO:unknown protocol), disconnected
          //COMPLETE MSG: 435 Failed TLS negotiation on data channel, disconnected: No such file or directory.
          if (0 < Pos('Failed TLS negotiation', lastResponse)) then
          begin
            //try again and hopefully it'll work then. Else try to disable SSL/sslfxp and try again. Or setdown with reason of some SSL problem (maybe too old SSL version)
            //maybe relogin needed because response says something about disconnect!
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;



      450:
        begin
          //COMPLETE MSG: 450 net.sf.drftpd.NoAvailableSlaveException: Requested Transfer Unavailable
          if (0 < Pos('Requested Transfer Unavailable', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;



      452:
        begin
          //COMPLETE MSG: 452 Error writing file: Success.
          if (0 < Pos('Error writing file', lastResponse)) then
          begin
            _setOutOfSpace(sdst, 'No freespace or slave');
            exit;
          end;

          //COMPLETE MSG: 452 Transfer terminated by external program
          if (0 < Pos('Transfer terminated by external program', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[TRANSFER TERMINATED] slowkick?</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, AnsiLeftStr(lastResponse, 90)]);
            readyerror := True;
            exit;
          end;
        end;


      500:
        begin
          //COMPLETE MSG: 500 Unsupported command during transfer.
          if (0 < Pos('Unsupported command during transfer', lastResponse)) then
          begin
            irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            goto TryAgain;
          end;
        end;


      522:
        begin
          if (0 < Pos('You have to turn on secure data connection', lastResponse)) then
          begin
            sdst.site.sslfxp := srNeeded;
            if spamcfg.readbool(c_section, 'turn_on_sslfxp', True) then
            begin
              irc_Adderror(sdst.todotask, '<c4>[ERROR SSLFXP]</c> TPazoRaceTask %s, %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);
            end;
            goto TryAgain;
          end;
        end;

      550:
        begin
          if (ResponseContainsDupeKeyword(lastResponse)) then
          begin
            ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
            ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            ready := True;
            Result := True;
            Debug(dpMessage, c_section, '<-- DUPE AFTER RETR ' + tname);
            exit;
          end;
        end;

      553:
        begin
          if (ResponseContainsDupeKeyword(lastResponse)) then
          begin
            ps2.ParseDupe(netname, channel, dir, filename, False, ResponseContainsDupeKeywordComplete(lastResponse));
            ps2.ProcessXDupeResponse(netname, channel, dir, lastResponse);
            ready := True;
            Result := True;
            Debug(dpMessage, c_section, '<-- DUPE AFTER RETR ' + tname);
            exit;
          end;

          //553 means: Requested action not taken. File name not allowed.
          //therefore don't try to send that file again

          if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
          begin
            irc_Adderror(Format('<c4>[NOT ALLOWED]</c> %s : %d %s', [tname, lastResponseCode, LeftStr(lastResponse, 90)]));
          end;

          readyerror := True;
          ps2.SetFileError(netname, channel, dir, filename);
          exit;
        end;
      end;

    Debug(dpMessage, c_section, '<- ' + lastResponse + ' ' + tname);
    irc_Adderror(sdst.todotask, '<c4>[ERROR FXP]</c> TPazoRaceTask %s: %s %d %s', [sdst.Name, tname, lastResponseCode, LeftStr(lastResponse, 90)]);

    mainpazo.errorreason := 'sdst WAIT: Unhandled error response';
    readyerror := True;
    Debug(dpSpam, c_section, '<- ' + mainpazo.errorreason + ' ' + tname);
    exit;
  end;


  // *** transfer was successful! ***
  debug(dpSpam, c_section, 'File transfer ready %s->%s %s', [site1, site2, filename]);
  ended := Now;
  time_race := MilliSecondsBetween(ended, started);
  response := IntToStr(time_race);



  FileSendByMe := False;
  if (ssrc.lastResponseCode = 226) and (sdst.lastResponseCode = 226) then
  begin
    // file transfer was successful
    FileSendByMe := True;
  end;

  //this is a very fucked-up case, we'll try again.
  if ( (mainpazo.rls <> nil) and (FileSendByMe) and
    ( (sdst.lastResponse.Contains('CRC-Check: SFV first')) or
      (sdst.lastResponse.Contains('ZiP-Integrity: BAD!')) or
      (sdst.lastResponse.Contains('CRC-Check: BAD!')) or
      (sdst.lastResponse.Contains('CRC-Check: Not in sfv!')) or
      (sdst.lastResponse.Contains('-file: Not allowed')) or
      (sdst.lastResponse.Contains('NFO-File: DUPE!')) or
      (sdst.lastResponse.Contains('SFV-file: BAD!')) ) ) then
  begin
    Debug(dpSpam, c_section, 'Broken transfer event!');

    if sdst.lastResponse.Contains('CRC-Check: SFV first') then
    begin
      //do nothing
    end

    else if (sdst.lastResponse.Contains('CRC-Check: BAD!') or sdst.lastResponse.Contains('ZiP-Integrity: BAD!')) then
    begin
      if spamcfg.readbool(c_section, 'crc_error', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[ERROR CRC]</c> %s: %d/%d', [Name, ps2.badcrcevents, config.ReadInteger(c_section, 'badcrcevents', 15)]);
      end;
      Inc(ps2.badcrcevents);
    end

    else if (sdst.lastResponse.Contains('SFV-file: BAD!')) then
    begin
      if spamcfg.readbool(c_section, 'crc_error', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[ERROR BAD SFV]</c> %s: %d/%d', [Name, ps2.badcrcevents, config.ReadInteger(c_section, 'badcrcevents', 15)]);
      end;
      Inc(ps2.badcrcevents);
    end


    else if sdst.lastResponse.Contains('0byte-file: Not allowed') then
    begin
      if spamcfg.readbool(c_section, 'crc_error', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[ERROR 0BYTE]</c> %s: %d/%d', [Name, ps2.badcrcevents, config.ReadInteger(c_section, 'badcrcevents', 15)]);
      end;
      Inc(ps2.badcrcevents);
    end

    else if sdst.lastResponse.Contains('CRC-Check: Not in sfv!') then
    begin
      if spamcfg.readbool(c_section, 'crc_error', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[ERROR NOT IN SFV]</c> %s', [Name]);
      end;
      ps2.SetFileError(netname, channel, dir, filename);
    end

    else if sdst.lastResponse.Contains('NFO-File: DUPE!') then
    begin
      if spamcfg.readbool(c_section, 'crc_error', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[NFO DUPE]</c> %s', [Name]);
      end;
      ps2.SetFileError(netname, channel, dir, filename);
    end

    else if sdst.lastResponse.Contains('-file: Not allowed') then
    begin
      if spamcfg.ReadBool('taskrace', 'filename_not_allowed', True) then
      begin
        irc_Adderror(sdst.todotask, '<c4>[NOT ALLOWED]</c> %s', [Name]);
      end;
      ps2.SetFileError(netname, channel, dir, filename);
    end;

    ready := True;
    Result := True;
    Debug(dpSpam, c_section, '<-- Broken? ' + sdst.lastResponse + '' + tname);
    Exit;
  end;

  if mainpazo.rls = nil then
  begin
    Debug(dpMessage, c_section, '<- ' + tname);
    Result := True;
    ready := True;
    exit;
  end;

  if (fileSendByMe) then
  begin

    //dupe responses are already handeled, so only add the file if we actually sent it (fileSendByMe)
    ps2.ParseDupe(netname, channel, dir, filename, True, True);

    filesize := mainpazo.PFileSize(dir, filename);

    if (time_race > 0) then
    begin
      try
        if (filesize > config.ReadInteger('speedstats', 'min_filesize', 5000000)) then
        begin
          SpeedStatAdd(site1, site2, filesize * 1000 / time_race, mainpazo.rls.section, mainpazo.rls.rlsname);
        end;
      except
        on E: Exception do
        begin
          Debug(dpError, c_section, '[EXCEPTION] mainpazo.PFileSize/SpeedStatAdd: %s', [e.Message]);
        end;
      end;
    end;

    // echo race info
    try
      if not MatchText(filename, AsciiFiletypes) then
      begin
        // to avoid announcing a speed_stat line without info what happend
        speed_stat := 'ZERO FILESIZE!';
        if (filesize > 0) and (time_race > 0) then
        begin
          racebw := filesize * 1000 / time_race / 1024;
          fsize := filesize / 1024;

          if (filesize > 1024) then
          begin
            if (racebw > 1024) then
              speed_stat := Format('<b>%f</b>mB @ <b>%f</b>mB/s', [fsize / 1024, racebw / 1024])
            else
              speed_stat := Format('<b>%f</b>mB @ <b>%f</b>kB/s', [fsize / 1024, racebw]);
          end
          else
          begin
            if (racebw > 1024) then
              speed_stat := Format('<b>%f</b>kB @ <b>%f</b>mB/s', [fsize, racebw / 1024])
            else
              speed_stat := Format('<b>%f</b>kB @ <b>%f</b>kB/s', [fsize, racebw]);
          end;
        end;
        irc_SendRACESTATS(tname + ' ' + speed_stat);

        // add stats to database
        statsProcessRace(site1, site2, mainpazo.rls.section, mainpazo.rls.rlsname, filename, filesize);
      end;
    except
      on e: Exception do
      begin
        Debug(dpError, c_section, Format('[EXCEPTION] Exception in echo: %s', [e.Message]));
      end;
    end;
  end;

  Debug(dpMessage, c_section, '<-- ' + tname);

  Result := True;
  ready := True;
end;

function TPazoRaceTask.Name: String;
begin
  try
    if mainpazo.rls = nil then
      Result := Format('RACE : %d <b>%s</b>-><b>%s</b>: %s (%d)',
        [pazo_id, site1, site2, filename, rank])
    else
      Result := Format('RACE : %d <b>%s</b>-><b>%s</b>: %s %s (%d)',
        [pazo_id, site1, site2, mainpazo.rls.rlsname, filename, rank]);
  except
    Result := 'RACE';
  end;
end;

function TPazoRaceTask.ResponseContainsDupeKeyword(const aResponse: String): boolean;
begin
  Result := (ResponseContainsDupeKeywordComplete(aResponse) OR

  //553 File is being uploaded by
  (0 < Pos('File is being uploaded', aResponse)) OR

  //COMPLETE MSG: 553- X-DUPE: sr-kqtcc.r22
  (0 < Pos('X-DUPE', aResponse)) OR

  //COMPLETE MSG: 500 filename.rar already exists.
  (0 < Pos('already exists', aResponse)) OR

  //553 Error: You have no rights to overwrite in this directory.
  (0 < Pos('You have no rights to overwrite', aResponse)));
end;

function TPazoRaceTask.ResponseContainsDupeKeywordComplete(const aResponse: String): boolean;
begin
  Result := (0 < Pos('File exists', aResponse)) OR

  //553- sr-kqtcc.r30: This file looks like a dupe
  (0 < Pos('This file looks like a dupe', aResponse));
end;

{ TWaitTask }
constructor TWaitTask.Create(const netname, channel, site1: String);
begin
  inherited Create(netname, channel, site1);
  event := TEvent.Create(nil, False, False, '');
end;

destructor TWaitTask.Destroy;
begin
  event.Free;
  inherited;
end;

function TWaitTask.Execute(slot: Pointer): boolean;
begin
  Result := True;
  event.WaitFor($FFFFFFFF);
  (*
  case event.WaitFor(15 * 60 * 1000) of
    wrSignaled : { Event fired. Normal exit. }
    begin

    end;
    else { Timeout reach }
    begin
      irc_Adderror('TWaitTask.Execute: <c2>Force Leave</c>:'+Name+' TWaitTask 15min');
      Debug(dpSpam, c_section,'TWaitTask.Execute: <c2>Force Leave</c>:'+Name+' TWaitTask 15min');
    end;
  end;
  *)
  ready := True;
end;

function TWaitTask.Name: String;
begin
  try
    Result := Format('WAITTASK : %s', [wait_for]);
  except
    Result := 'WAITTASK';
  end;
end;

end.
