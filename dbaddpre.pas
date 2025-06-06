unit dbaddpre;

interface

uses
  Classes, kb, kb.releaseinfo;

type
  TPretimeResult = record
    pretime: Int64; //< UTC pretime
    mode: String; //< method from @link(TPretimeLookupMode) which was used to get pretime
  end;

  {
  @value(plmNone no saving and no lookup of pretimes)
  @value(plmHTTP read pretime over HTTP)
  @value(plmMYSQL read pretime from MySQL/MariaDB)
  @value(plmSQLITE read pretime from local SQLite database)
  }
  TPretimeLookupMode = (plmNone, plmHTTP, plmMYSQL, plmSQLITE);
  {
  @value(apmMemory uses a run-time filled list of pretimes)
  @value(apmSQLITE SQLite database)
  @value(apmMYSQL MySQL/MariaDB)
  @value(apmNone no saving and no lookup)
  }
  TAddPreMode = (apmMemory, apmSQLITE, apmMYSQL, apmNone);

function dbaddpre_ADDPRE(const netname, channel, nickname, params: String; event: TKBEventType): boolean;
function dbaddpre_GetRlz(const rls: String): Int64;
function dbaddpre_InsertRlz(const rls, rls_section, Source: String; const aSkipDbCleanup: boolean = False): boolean;
function dbaddpre_GetCount: integer;
function dbaddpre_GetPreduration(const rlz_pretime: Int64): String;
function dbaddpre_Status: String;

function dbaddpre_Process(const net, chan, nick: String; msg: String): boolean;

procedure dbaddpreInit;
procedure dbaddpreStart;
procedure dbaddpreUnInit;

function getPretime(const rlz: String): TPretimeResult;

function ReadPretimeOverHTTP(const rls: String): Int64;
function ReadPretimeOverMYSQL(const rls: String): Int64;
function ReadPretimeOverSQLITE(const rls: String): Int64;

function GetPretimeMode: TPretimeLookupMode;
{ Convert Pretime Lookup Mode to String
  @param(aPretimeLookupMode Pretime mode from @link(TPretimeLookupMode))
  @returns(Pretime mode as String without prefix) }
function pretimeModeToString(aPretimeLookupMode: TPretimeLookupMode): String;
{ Convert Addpre Mode to String
  @param(aAddPreMode Addpre mode from @link(TAddPreMode))
  @returns(Addpre mode as String without prefix) }
function addPreModeToString(aAddPreMode: TAddPreMode): String;

procedure setPretimeMode_One(mode: TPretimeLookupMode);
procedure setPretimeMode_Two(mode: TPretimeLookupMode);

procedure setAddPretimeMode(mode: TAddPreMode);

function AddPreDbAlive: boolean;

implementation

uses
  DateUtils, SysUtils, StrUtils, configunit, mystrings, console, sitesunit, FLRE, IniFiles,
  irc, debugunit, precatcher, SyncObjs, taskpretime, dbhandler, http, mormot.db.sql, mormot.db.sql.sqlite3, mormot.db.sql.zeos,
  IdThreadSafe;

const
  section = 'dbaddpre';
  DBCLEANUP_INTERVAL = 50;
  DBCLEANUP_NUM_ENTRIES_TO_KEEP = 300;

var
  addpreSQLite3DBCon: TSQLDBSQLite3ConnectionProperties = nil; //< SQLite3 database connection

  addprecmd: TStringList;
  kbadd_addpre: boolean;

  dbaddpre_mode: TAddPreMode = TAddPreMode(3);
  dbaddpre_plm1: TPretimeLookupMode;
  dbaddpre_plm2: TPretimeLookupMode;

  config_taskpretime_url: String;
  config_taskpretime_regexp: String;
  FDbCleanupCounter: TIdThreadSafeInt32;

procedure setPretimeMode_One(mode: TPretimeLookupMode);
begin
  dbaddpre_plm1 := mode;
end;

procedure setPretimeMode_Two(mode: TPretimeLookupMode);
begin
  dbaddpre_plm2 := mode;
end;

procedure setAddPretimeMode(mode: TAddPreMode);
begin
  dbaddpre_mode := mode;
end;

function GetPretimeMode: TPretimeLookupMode;
begin
  Result := dbaddpre_plm1;
end;

function pretimeModeToString(aPretimeLookupMode: TPretimeLookupMode): String;
begin
  Result := ReplaceText(TEnum<TPretimeLookupMode>.ToString(aPretimeLookupMode), 'plm', '');
end;

function addPreModeToString(aAddPreMode: TAddPreMode): String;
begin
  Result := ReplaceText(TEnum<TAddPreMode>.ToString(aAddPreMode), 'apm', '');
end;

function GetPretimeURL: String;
begin
  Result := config.readString(section, 'url', '');
end;

function ReadPretimeOverHTTP(const rls: String): Int64;
var
  response: String;
  rx_pretime: TFLRE;
  rx_captures: TFLREMultiCaptures;
  url: String;
  aPretimePos: integer;
  aPreTimeStr: String;
  fHttpGetErrMsg: String;
begin
  Result := 0;
  if rls = '' then
    irc_adderror('No Releasename as parameter!');

  url := config_taskpretime_url;
  if url = '' then
  begin
    debug(dpSpam, section, 'URL value is empty');
    exit;
  end;

  try
    rx_pretime := TFLRE.Create(config_taskpretime_regexp, []);

    if not HttpGetUrl(Format(url, [rls]), response, fHttpGetErrMsg) then
    begin
      Debug(dpError, section, Format('[FAILED] HTTP Pretime for %s --> %s ', [rls, fHttpGetErrMsg]));
      irc_Adderror(Format('<c4>[FAILED]</c> HTTP Pretime for %s --> %s', [rls, fHttpGetErrMsg]));
      exit;
    end;

    Debug(dpSpam, section, 'Pretime results for %s' + #13#10 + '%s', [rls, response]);
    if rx_pretime.MatchAll(response, rx_captures, 1, 1) then
    begin
      Debug(dpMessage, section, 'ReadPretimeOverHTTP : %s', [response]);
      aPretimePos := rx_pretime.NamedGroupIndices['pretime'];
      if aPretimePos < 0 then
      begin
        irc_addtext('CONSOLE','ADMIN','named capture group: pretime not found');
        exit;
      end;
      aPreTimeStr := Copy(response, rx_captures[0][aPretimePos].Start, rx_captures[0][aPretimePos].Length);
      if (aPretimePos >= 0) and (StrToIntDef(aPreTimeStr, 0) <> 0) then
      begin
        Result := StrToIntDef(aPreTimeStr, 0);
        if ((DaysBetween(Now(), UnixToDateTime(Result, False)) > 30) and
          config.ReadBool('kb', 'skip_rip_older_then_one_month', False)) then
        begin
          irc_addtext('CONSOLE','ADMIN','Days higher then 30 days');
          Result := 0;
        end;
      end
      else
      begin
        irc_addtext('CONSOLE','ADMIN','regex does not match');
        Result := 0;
      end;
    end;
  finally
    SetLength(rx_captures, 0);
    rx_pretime.Free;
  end;
end;

function ReadPretimeOverSQLITE(const rls: String): Int64;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := 0;
  if rls = '' then
    irc_adderror('No Releasename as parameter!');

  fQuery := TSqlDBSQLite3Statement.Create(addpreSQLite3DBCon.ThreadSafeConnection);
  try
    fQuery.Prepare('SELECT ts FROM addpre WHERE rlz = ?');
    fQuery.BindTextS(1, rls);
    try
      fQuery.ExecutePrepared;
      if fQuery.Step then
        Result := fQuery.ColumnInt(0);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] ReadPretimeOverSQLITE: %s', [e.Message]));
        exit;
      end;
    end;
  finally
    fQuery.free;
  end;
end;

function ReadPretimeOverMYSQL(const rls: String): Int64;
var
  fQuery: TSqlDBZeosStatement;
  fTimeField, fTableName, fReleaseField: String;
begin
  Result := 0;
  if rls = '' then
    irc_adderror('No Releasename as parameter!');

  fTimeField := config.ReadString('taskmysqlpretime', 'rlsdate_field', 'ts');
  fTableName := config.ReadString('taskmysqlpretime', 'tablename', 'addpre');
  fReleaseField := config.ReadString('taskmysqlpretime', 'rlsname_field', 'rls');

  fQuery := TSqlDBZeosStatement.Create(MySQLCon.ThreadSafeConnection);
  try
    fQuery.Prepare('SELECT `' + fTimeField + '` FROM `' + fTableName + '` WHERE `' + fReleaseField + '` = ?');
    fQuery.BindTextS(1, rls);
    try
      fQuery.ExecutePrepared;
      if fQuery.Step then
        Result := fQuery.ColumnInt(fTimeField);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] ReadPretimeOverMYSQL: %s', [e.Message]));
        exit;
      end;
    end;
  finally
    fQuery.free;
  end;
end;

function getPretime(const rlz: String): TPretimeResult;
begin
  Result.pretime := 0;
  Result.mode := pretimeModeToString(plmNone);
  if rlz = '' then
    irc_adderror('GETPRETIME --> No RLZ value!');

  case dbaddpre_plm1 of
    plmNone: Exit;
    plmHTTP: Result.pretime := ReadPretimeOverHTTP(rlz);
    plmMYSQL: Result.pretime := ReadPretimeOverMYSQL(rlz);
    plmSQLITE: Result.pretime := ReadPretimeOverSQLITE(rlz);
  else
    begin
      Debug(dpMessage, section, 'GetPretime unknown pretime mode : %d',
        [config.ReadInteger('taskpretime', 'mode', 0)]);
      Result.pretime := 0;
    end;
  end;

  if (Result.pretime > 0) then
  begin
    Result.mode := pretimeModeToString(dbaddpre_plm1);
    exit;
  end;

  case dbaddpre_plm2 of
    plmNone: Exit;
    plmHTTP: Result.pretime := ReadPretimeOverHTTP(rlz);
    plmMYSQL: Result.pretime := ReadPretimeOverMYSQL(rlz);
    plmSQLITE: Result.pretime := ReadPretimeOverSQLITE(rlz);
  else
    begin
      Debug(dpMessage, section, 'GetPretime unknown pretime mode_2 : %d',
        [config.ReadInteger('taskpretime', 'mode_2', 0)]);
      Result.pretime := 0;
    end;
  end;

  if Result.pretime > 0 then
  begin
    Result.mode := pretimeModeToString(dbaddpre_plm2);
  end;
end;

function kb_Add_addpre(const rls, section: String; event: TKBEventType): integer;
var
  rls_section: String;
  fSection: String;
begin
  Result := -1;

  fSection := ProcessDoReplace(section);
  rls_section := '';
  rls_section := FindSection(' ' + fSection + ' ');
  rls_section := PrecatcherSectionMapping(rls, rls_section);

  if (rls_section = 'TRASH') then
  begin
    exit;
  end;

  if (rls_section = '') then
  begin
    irc_Addstats(Format('<c7>[ADDPRE]</c> %s %s (%s) : <b>No Sites</b>', [rls, rls_section, fSection]));
    exit;
  end;

  Result := kb_Add('', '', getAdminSiteName, rls_section, '', event, rls, '');
end;

function dbaddpre_ADDPRE(const netname, channel, nickname, params: String; event: TKBEventType): boolean;
var
  rls: String;
  rls_section: String;
  kb_entry: String;
  p: Integer;
begin
  Result := False;

  rls := '';
  rls := SubString(params, ' ', 1);
  if ((rls <> '') and (length(rls) > minimum_rlsname)) then
  begin
    if dbaddpre_mode <> apmNone then
    begin
      if dbaddpre_InsertRlz(rls, '', netname + '-' + channel + '-' + nickname) then
      begin
        // we just inserted the pre time, find out if there's already a KB entry
        rls_section := FindReleaseInLatestKBList(rls);

        //send event to kb_add to trigger race evaluation
        if rls_section <> '' then
          kb_Add(netname, channel, getAdminSiteName, rls_section, '', event, rls, '');
      end;
    end;

    if ((event = kbeADDPRE) and (kbadd_addpre)) then
    begin
      kb_entry := FindReleaseInKbList('-' + rls);

      // TODO: might not work correctly if sections are TV-SD, TV-720P-FR, etc
      // introduced with merge-req #315
      if kb_entry <> '' then
      begin
        p := Pos('-', kb_entry);
        rls_section := Copy(kb_entry, 1, p - 1);
        if rls_section <> '' then
          kb_Add_addpre(rls, rls_section, event);
      end;
    end;
  end;

  Result := True;
end;

function dbaddpre_GetRlz(const rls: String): Int64;
begin
  Result := 0;

  case dbaddpre_mode of
    apmMemory, apmSQLITE:
      begin
        Result := ReadPretimeOverSQLITE(rls);
      end;
    apmMYSQL:
      begin
        Result := ReadPretimeOverMYSQL(rls);
      end;
  end;
end;

function dbaddpre_InsertRlz(const rls, rls_section, Source: String; const aSkipDbCleanup: boolean = False): boolean;
var
  fMySQLQuery: TSqlDBZeosStatement;
  fSQLiteQuery: TSqlDBSQLite3Statement;
  fTableName, fReleaseField, fSectionField, fTimeField, fSourceField: String;
begin
  Result := False;

  // no need to check for existing pre time because we use insert or ignore

  case dbaddpre_mode of
    apmMemory, apmSQLITE:
      begin
        fSQLiteQuery := TSqlDBSQLite3Statement.Create(addpreSQLite3DBCon.ThreadSafeConnection);
        try
          fSQLiteQuery.Prepare('INSERT OR IGNORE INTO addpre (rlz, section, ts, source) VALUES (?, ?, ?, ?)');
          fSQLiteQuery.BindTextS(1, rls);
          fSQLiteQuery.BindTextS(2, rls_section);
          fSQLiteQuery.Bind(3, DateTimeToUnix(Now(), False));
          fSQLiteQuery.BindTextS(4, Source);
          try
            fSQLiteQuery.ExecutePrepared;
            Result := fSqliteQuery.UpdateCount > 0; // only return true if the insert actually happened and has not been ignored
          except
            on e: Exception do
            begin
              Debug(dpError, section, Format('[EXCEPTION] dbaddpre_InsertRlz (sqlite): %s - values: %s %s %s', [e.Message, rls, rls_section, Source]));
              exit;
            end;
          end;
        finally
          fSQLiteQuery.free;
        end;
      end;
    apmMYSQL:
      begin
        fMySQLQuery := TSqlDBZeosStatement.Create(MySQLCon.ThreadSafeConnection);
        try
          fTableName := config.ReadString('taskmysqlpretime', 'tablename', 'addpre');
          fReleaseField := config.ReadString('taskmysqlpretime', 'rlsname_field', 'rls');
          fSectionField := config.ReadString('taskmysqlpretime', 'section_field', 'section');
          fTimeField := config.ReadString('taskmysqlpretime', 'rlsdate_field', 'ts');
          fSourceField := config.ReadString('taskmysqlpretime', 'source_field', '-1');

          if fSourceField = '-1' then
          begin
            fMySQLQuery.Prepare('INSERT IGNORE INTO `' + fTableName + '` (`' + fReleaseField + '`, `' + fSectionField + '`, `' + fTimeField + '`) VALUES (?, ?, ?);');
          end
          else
          begin
            fMySQLQuery.Prepare('INSERT IGNORE INTO `' + fTableName + '` (`' + fReleaseField + '`, `' + fSectionField + '`, `' + fTimeField + '`, `' + fSourceField + '`) VALUES (?, ?, ?, ?);');
            fMySQLQuery.BindTextS(4, Source);
          end;

          fMySQLQuery.BindTextS(1, rls);
          fMySQLQuery.BindTextS(2, rls_section);
          fMySQLQuery.Bind(3, DateTimeToUnix(Now(), False));
          try
            fMySQLQuery.ExecutePrepared;
            Result := fMySQLQuery.UpdateCount > 0; // only return true if the insert actually happened and has not been ignored
          except
            on e: Exception do
            begin
              Debug(dpError, section, Format('[EXCEPTION] dbaddpre_InsertRlz (mysql): %s - values: %s %s %s', [e.Message, rls, rls_section, Source]));
              exit;
            end;
          end;
        finally
          fMySQLQuery.free;
        end;
      end;
  end;

  // db cleanup currently only for in-memory DB
  if Result and (dbaddpre_mode = apmMemory) then
  begin
    FDbCleanupCounter.Increment;

    if (FDbCleanupCounter.Value >= DBCLEANUP_INTERVAL) and not aSkipDbCleanup then // we can skip the DB cleanup if we do not want to waste the time for it (e.g. sitepre)
    begin
      try
        FDbCleanupCounter.Value := 0;
        fSQLiteQuery := TSqlDBSQLite3Statement.Create(addpreSQLite3DBCon.ThreadSafeConnection);
        try
          fSQLiteQuery.Prepare('DELETE FROM addpre WHERE ts < (SELECT MIN(ts) FROM (SELECT ts FROM addpre ORDER BY ts DESC LIMIT ?));');
          fSQLiteQuery.Bind(1, DBCLEANUP_NUM_ENTRIES_TO_KEEP);
          try
            fSQLiteQuery.ExecutePrepared;
            if fSQLiteQuery.UpdateCount > 0 then
            begin
              debug(dpSpam, section, Format('Addpre DB cleanup: Cleaned %d entries from the Pre DB, keeping only the latest %d', [fSQLiteQuery.UpdateCount, DBCLEANUP_NUM_ENTRIES_TO_KEEP]));
            end;
          except
            on e: Exception do
            begin
              debug(dpError, section, Format('[EXCEPTION] dbaddpre_InsertRlz (sqlite): %s - values: %s %s %s', [e.Message, rls, rls_section, Source]));
              exit;
            end;
          end;
        finally
          fSQLiteQuery.Free;
        end;
      except
        on e: Exception do
        begin
          debug(dpError, section, Format('[EXCEPTION] DB Cleanup: %s ', [e.Message]));
        end;
      end;
    end;
  end;
end;

function dbaddpre_GetCount: integer;
var
  fMySQLQuery: TSqlDBStatementWithParamsAndColumns; // really not sure why but on FPC this must be a TSqlDBStatementWithParamsAndColumns and not TSqlDBZeosStatement, else we get this compile error: dbaddpre.pas(568,37) Error: Incompatible types: got "TSqlDBStatementWithParamsAndColumns" expected "TSqlDBZeosStatement"
  fSQLiteQuery: TSqlDBSQLite3Statement;
  fTableName: String;
begin
  Result := 0;
  case dbaddpre_mode of
    apmMemory, apmSQLITE:
      begin
        fSQLiteQuery := TSqlDBSQLite3Statement.Create(addpreSQLite3DBCon.ThreadSafeConnection);
        try
          fSQLiteQuery.Prepare('SELECT count(*) FROM addpre');
          fSQLiteQuery.ExecutePrepared;
          if not fSQLiteQuery.Step then
            Result := 0
          else
            Result := fSQLiteQuery.ColumnInt(0);

        finally
          fSQLiteQuery.Free;
        end;
      end;
    apmMYSQL:
      begin
          fMySQLQuery := TSqlDBZeosStatement.Create(MySQLCon.ThreadSafeConnection);
          try
            fTableName := config.ReadString('taskmysqlpretime', 'tablename', 'addpre');
            fMySQLQuery.Prepare('SELECT count(*) FROM `' + fTableName + '`', True);
            fMySQLQuery.ExecutePrepared;
            if not fMySQLQuery.Step then
              Result := 0
            else
              Result := fMySQLQuery.ColumnInt(0);

          finally
            fMySQLQuery.Free;
          end;
      end;
  end;
end;

function dbaddpre_GetPreduration(const rlz_pretime: Int64): String;
var
  preage: int64;
begin
  preage := DateTimeToUnix(Now(), False) - rlz_pretime;
  if preage >= 604800 then
    Result := Format('%2.2d Weeks %1.1d Days %2.2d Hour %2.2d Min %2.2d Sec',
      [preage div 604800, (preage div 86400) mod 7, (preage div 3600) mod
      24, (preage div 60) mod 60, preage mod 60])
  else if preage >= 86400 then
    Result := Format('%1.1d Days %2.2d Hour %2.2d Min %2.2d Sec',
      [preage div 86400, (preage div 3600) mod 24, (preage div 60) mod
      60, preage mod 60])
  else if preage >= 3600 then
    Result := Format('%2.2d Hour %2.2d Min %2.2d Sec',
      [preage div 3600, (preage div 60) mod 60, preage mod 60])
  else if preage >= 60 then
    Result := Format('%2.2d Min %2.2d Sec', [(preage div 60) mod 60, preage mod 60])
  else
    Result := Format('%2.2d Sec', [preage mod 60]);
end;

function dbaddpre_Process(const net, chan, nick: String; msg: String): boolean;
var
  ii: integer;
begin
  Result := False;
  ii := -1;
  try
    ii := addprecmd.IndexOf(substring(msg, ' ', 1));
  except
    on e: Exception do
      Debug(dpError, section, Format('[EXCEPTION] dbaddpre_Process: %s ', [e.Message]));
  end;

  if ii > -1 then
    //  if (1 = Pos(addprecmd, msg)) then
  begin
    Result := True;
    msg := Copy(msg, length(addprecmd.Strings[ii] + ' ') + 1, 1000);
    try
      dbaddpre_ADDPRE(net, chan, nick, msg, kbeADDPRE);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddpre_Process: %s ',
          [e.Message]));
      end;
    end;
  end;
end;

function dbaddpre_Status: String;
begin
  Result := '';
  Result := Format('<b>Dupe.db</b>: %d Rips', [dbaddpre_GetCount]);
end;

procedure dbaddpreInit;
begin
  addprecmd := TStringList.Create;
end;

procedure dbaddpreStart;
var
  db_pre_name: String;
begin
  addprecmd.CommaText := config.ReadString(section, 'addprecmd', '!addpre');
  kbadd_addpre := config.ReadBool(section, 'kbadd_addpre', False);

  dbaddpre_mode := TAddPreMode(config.ReadInteger(section, 'mode', 3));
  dbaddpre_plm1 := TPretimeLookupMode(config.ReadInteger('taskpretime', 'mode', 0));
  dbaddpre_plm2 := TPretimeLookupMode(config.ReadInteger('taskpretime', 'mode_2', 0));

  config_taskpretime_url := config.readString('taskpretime', 'url', '');
  config_taskpretime_regexp := config.readString('taskpretime', 'regexp', '(\S+) (?<pretime>\d+) (\S+) (\S+) (\S+)$');

  FDbCleanupCounter := TIdThreadSafeInt32.Create;

  if ( (dbaddpre_mode = apmSQLITE) or (dbaddpre_plm1 = plmSQLITE) or (dbaddpre_plm2 = plmSQLITE) ) then
  begin
    db_pre_name := Trim(config.ReadString(section, 'db_file', 'db_addpre.db'));

    try
      addpreSQLite3DBCon := CreateSQLite3DbConn(db_pre_name, '', dbaddpre_mode = apmMemory);

      addpreSQLite3DBCon.MainSQLite3DB.Execute(
        'CREATE TABLE IF NOT EXISTS addpre (rlz VARCHAR(255) NOT NULL, section VARCHAR(25) NOT NULL, ts INT(12) NOT NULL, source VARCHAR(255) NOT NULL)'
      );
      addpreSQLite3DBCon.MainSQLite3DB.Execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS addpre_index ON addpre (rlz)'
      );
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddpreStart: %s ',[e.Message]));
        exit;
      end;
    end;
  end;

  case Integer(dbaddpre_mode) of
    0: Console_Addline('', 'Memory PreDB started...');
    1: Console_Addline('', 'SQLite PreDB started...');
    2: Console_Addline('', 'MySQL/Maria PreDB started...');
    //3: Exit;
  end;
end;

function AddPreDbAlive: boolean;
begin
  if addpreSQLite3DBCon = nil then
    Result := false
  else
    Result := true;
end;

procedure dbaddpreUninit;
begin
  Debug(dpSpam, section, 'Uninit1');
  addprecmd.Free;
  FDbCleanupCounter.Free;

  if Assigned(addpreSQLite3DBCon) then
  begin
    FreeAndNil(addpreSQLite3DBCon);
  end;
  Debug(dpSpam, section, 'Uninit2');
end;

end.
