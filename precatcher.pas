unit precatcher;

interface

uses Classes, Contnrs, slmasks, encinifile, kb, kb.releaseinfo;

type
  TSection = class
    eventtype: TKBEventType;
    section: String;
    words: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  TSiteChan = class
    sitename: String;
    sections: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  huntartunk_tipus = (sehun, racetool, ignorelist, replace, hunsections, mappings, channels, pretime);

  TMap = class
    origsection: String;
    newsection: String;
    mask: TslMask;
    constructor Create(const origsection, newsection, mask: String);
    destructor Destroy; override;
  end;

function precatcherauto: boolean;

function Precatcher_Sitehasachan(const sitename: String): boolean;
procedure Precatcher_DelSiteChans(const sitename: String);
function PrecatcherReload: String;
procedure PrecatcherRebuild();
procedure PrecatcherStart;
procedure PrecatcherProcessB(net, chan, nick, Data: String);
procedure PrecatcherProcess(const net, chan, nick, Data: String);
function precatcher_logfilename: String;
procedure Precatcher_Init;
procedure Precatcher_Uninit;
function PrecatcherSectionMapping(const rls, section: String; x_count: integer = 0): String;

function ExtractReleasename(ts_data: TStringList): String;

{ Tries to extract the section from the given sitebot announce by iterating through the [sections] items
  @param(aCleanSitebotAnnounce Sitebot announce with additional characters removed and section enclosed by whitespaces)
  @returns(First occurring section name of the mapping if section is listed, otherwise empty string) }
function FindSection(const aCleanSitebotAnnounce: String): String;
function ProcessDoReplace(const s: String): String;

var
  precatcher_debug: boolean = False;
  precatcher_ircdebug: boolean = False;
  precatcher_debug_netname, precatcher_debug_channel: String;
  //  precatcher_auto: Boolean;
  catcherFile: TEncStringlist;
  mappingslist: TObjectList;
  minimum_rlsname: integer = 10;

implementation

uses
  SysUtils, sitesunit, Dateutils, irc, queueunit, mystrings, precatcher.helpers,
  inifiles, DebugUnit, StrUtils, configunit, Regexpr, globalskipunit, dbaddpre,
  console, mrdohutils, SyncObjs, taskautodirlist, IdGlobal {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  ;

const
  rsections = 'precatcher';

var
  catcherFilename, replacefromline: String;
  cd, skiprlses: THashedStringList;
  tagline, irclines_ignorewords, replacefrom, replaceto: TStringList;
  huntartunk: huntartunk_tipus;

  debug_f: TextFile;
  precatcher_debug_lock: TCriticalSection;
  precatcher_lock: TCriticalSection;

  glSectionList: TStringList; //< List of all entries of the [sections] category

procedure mydebug(const s: String); overload;
var
  nowstr: String;
begin
  Debug(dpSpam, rsections, s);
  if precatcher_ircdebug then
  begin
    try
      precatcher_debug_lock.Enter;
      try
        DateTimeToString(nowstr, 'mm-dd hh:nn:ss.zzz', Now());
        WriteLn(debug_f, Format('%s %s', [nowstr, s]));
        Flush(debug_f);
      finally
        precatcher_debug_lock.Leave;
      end;
    except
      on e: Exception do
      begin
        Debug(dpError, rsections, Format('[EXCEPTION] mydebug: Exception : %s', [e.Message]));
        irc_Adderror(Format('<c4>[EXCEPTION]</c> mydebug: Exception : %s', [e.Message]));
      end;
    end;
  end;
  if (precatcher_debug) then
  begin
    irc_Addtext(precatcher_debug_netname, precatcher_debug_channel, s);
  end;
end;

procedure mydebug(const s: String; args: array of const); overload;
begin
  myDebug(Format(s, args));
end;

function ExtractReleasename(ts_data: TStringList): String;
var
  k, i: integer;
  maxi: integer;
  maxs: String;
begin
  Result := '';

  // no need to go further if it's empty
  if ts_data.Count = 0 then
    exit;

  // detect longest entry with '-' --> our releasename
  maxi := 0;
  maxs := '';
  for i := 0 to ts_data.Count - 1 do
  begin
    if ((Length(ts_data[i]) > maxi) and (0 <> Pos('-', ts_data[i]))) then
    begin
      maxi := Length(ts_data[i]);
      maxs := ts_data[i];
    end;
  end;

  Result := maxs;

  // remove '.' from the end of detected releasename if there is one
  k := Length(Result);
  if (k > 0) and (Result[k] = '.') then
  begin
    Dec(k);
    SetLength(Result, k);
  end;

  if (k < minimum_rlsname) then
    Result := '';

  Result := Trim(Result);
end;

function MainStripping(const idata: String): String;
begin
  Result := idata;
  try
    Result := RemoveSpecialCharsAndBareIt(Result);
  except
    on e: Exception do
    begin
      Debug(dpError, rsections, Format('[EXCEPTION] RemoveSpecialCharsAndBareIt : %s', [e.Message]));
      irc_Adderror(Format('<c4>[EXCEPTION]</c> RemoveSpecialCharsAndBareIt : %s', [e.Message]));
      Result := '';
      exit;
    end;
  end;

{
  // this part doesn't change the result at all (reason see below)
  // above we only allow a-z, A-Z, Numbers and StrippingChars - else we replace the char with ' '
  // then we check the response in StripNoValidChars against ValidChars which includes a lot more chars but our
  // response won't have them in it because it's already replaced with ' '
  try
    Result := StripNoValidChars(Result);
  except
    on e: Exception do
    begin
      Debug(dpError, rsections, Format('[EXCEPTION] StripNoValidChars : %s', [e.Message]));
      irc_Adderror(Format('<c4>[EXCEPTION]</c> StripNoValidChars : %s', [e.Message]));
      Result := '';
      exit;
    end;
  end;
}
end;

function PrecatcherSectionMapping(const rls, section: String; x_count: integer = 0): String;
var
  i: integer;
  x: TMap;
begin
  MyDebug(Format('PrecatcherSectionMapping start testing %s in %s', [rls, section]));

  Inc(x_count);
  if (x_count > 500) then
  begin
    Debug(dpError, rsections, Format('[ERROR] in PrecatcherSectionMapping: big loop %s', [rls]));
    Result := '';
    exit;
  end;

  Result := section;

  for i := 0 to mappingslist.Count - 1 do
  begin
    try
      if i > mappingslist.Count then
        Break;
      x := mappingslist[i] as TMap;
      if (((x.origsection = '') and (x_count = 1)) or (x.origsection = Result)) then
      begin
        MyDebug(Format('PrecatcherSectionMapping testing %s for %s', [rls, x.newsection]));
        if (x.mask.Matches(rls)) then
        begin
          if ((config.ReadBool(rsections, 'recursiv_mapping', False)) and (x.newsection <> 'TRASH')) then
          begin
            Result := PrecatcherSectionMapping(rls, x.newsection, x_count);
            exit;
          end
          else
          begin
            Result := x.newsection;
            MyDebug(Format('PrecatcherSectionMapping %s mapped to %s', [rls, x.newsection]));
            exit;
          end;
        end;
      end;
    except
      on E: Exception do
      begin
        Debug(dpError, rsections, Format('[EXCEPTION] in PrecatcherSectionMapping: %s', [e.Message]));
        break;
      end;
    end;
  end;

end;

function FindSection(const aCleanSitebotAnnounce: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to glSectionList.Count - 1 do
  begin
    if ContainsText(aCleanSitebotAnnounce, glSectionList.ValueFromIndex[i]) then
    begin
      Result := glSectionList.Names[i];
      break;
    end;
  end;
end;

function ProcessDoReplace(const s: String): String;
var
  i: integer;
  rep_s: String;
begin
  rep_s := s;

  if replacefrom.Count = replaceto.Count then
  begin
    for i := 0 to replacefrom.Count - 1 do
    begin
      MyDebug('ProcessDoReplace %s to %s', [replacefrom[i], replaceto[i]]);
      rep_s := ReplaceText(rep_s, replacefrom[i], replaceto[i]);
    end;
  end
  else
    Debug(dpError, rsections, 'replacefrom count is <> replaceto count!');

  Result := rep_s;
end;

procedure ProcessReleaseVege(net, chan, nick, sitename: String; kb_event: TKBEventType; section, rls: String; ts_data: TStringList);
var
  genre, s, oldsection, event: String;
begin
  event := KBEventTypeToString(kb_event);
  MyDebug('ProcessReleaseVege %s %s %s %s', [rls, sitename, event, section]);
  Debug(dpSpam, rsections, Format('--> ProcessReleaseVege %s %s %s %s', [rls, sitename, event, section]));

  if (kb_event <> kbeREQUEST) then
  begin

    if CheckIfGlobalSkippedGroup(rls) then
    begin
      MyDebug('<c4>[GLOBAL SKIPPED GROUP]</c> detected!: ' + rls);
      Debug(dpSpam, rsections, 'Global skipped group detected!: ' + rls);
      if ((not precatcher_debug) and (spamcfg.ReadBool('precatcher', 'global_skip_group', True))) then
        irc_addadmin('<b><c14>Info</c></b>: Global skipped group detected!: ' + rls);
      skiprlses.Add(rls);
      exit;
    end;

  end;

  // removing double spaces
  s := ts_data.DelimitedText;

  MyDebug('Cleaned up line with rlsname: %s', [s]);
  Debug(dpSpam, rsections, 'Cleaned up line with rlsname: %s', [s]);
  s := ' ' + s + ' ';

  if section = '' then
  begin
    section := FindSection(s);
  end;
  MyDebug('Section: %s', [section]);

  if section <> 'REQUEST' then
  begin

    oldsection := section;
    try
      section := PrecatcherSectionMapping(rls, section);
    except
      on e: Exception do
      begin
        section := '';
        Debug(dpError, rsections, Format('[EXCEPTION] PrecatcherSectionMapping: %s', [e.Message]));
      end;
    end;
  end;

  if oldsection <> section then
  begin
    MyDebug('Mapped section: %s', [section]);
    Debug(dpSpam, rsections, 'Mapped section: %s', [section]);
  end;

  if ((section = '') and (not (kb_event in [kbeCOMPLETE, kbeNUKE]))) then
  begin
    irc_Addadmin('<c14><b>Info</c></b>: Section on %s for %s was not found. Add Sectionname to slftp.precatcher under [sections] and/or [mappings].', [sitename, rls]);
    MyDebug('No section?! ' + sitename + '@' + rls);
    exit;
  end;

  genre := '';
  if ((kb_event <> kbeNEWDIR) and (FindSectionHandler(section).Name = 'TMP3Release')) then
  begin
    // TODO: add an extra event for GENRE and/or do a proper way of parsing genre

    // removes rlsname from irc line to avoid detecting genre Noise for e.g. Systemic_Noise_-_Show_Me-(FU122)-WEB-2018-ZzZz
    genre := TryToExtractMP3GenreFromSitebotAnnounce(StringReplace(s, rls, '', [rfReplaceAll, rfIgnoreCase]));
    if genre <> '' then
    begin
      MyDebug('Genre: %s', [genre]);
      Debug(dpSpam, rsections, Format('Genre found via IRC announce: %s', [genre]));
    end;
  end;

  MyDebug('Event: %s', [event]);
  Debug(dpSpam, rsections, 'Event: %s', [event]);

  Debug(dpSpam, rsections, Format('-- ProcessReleaseVege %s %s %s %s', [rls, sitename, event, section]));
  if not precatcher_debug then
  begin
    try
      if spamcfg.ReadBool('precatcher', 'announce_event', True) then
      begin
        irc_Addtext_by_key('PRECATCHSTATS', Format('<c7>[%s]</c> %s %s @ <b>%s</b>', [event, section, rls, sitename]));
      end;
      kb_Add('', '', sitename, section, genre, kb_event, rls, '');
    except
      on e: Exception do
      begin
        Debug(dpError, rsections, Format('[EXCEPTION] ProcessReleaseVege kb_Add: %s', [e.Message]));
      end;
    end;
  end;

  Debug(dpSpam, rsections, Format('<-- ProcessReleaseVege %s %s %s %s', [rls, sitename, event, section]));
end;

procedure PrecatcherProcessB(net, chan, nick, Data: String);
var
  igindex, i, j: integer;
  sc: TSiteChan;
  ss: TSection;
  mind: boolean;
  ts_data: TStringList;
  rls, s: String;
  fRequestDirlistTask: TAutoDirlistTask;
begin
  MyDebug('Process %s %s %s %s', [net, chan, nick, Data]);

  net := UpperCase(net);
  chan := LowerCase(chan);
  nick := LowerCase(nick);
  i := cd.IndexOf(net + chan + nick);
  if i <> -1 then
  begin
    MyDebug('Ok %s %s %s is valid for check', [net, chan, nick]);
    try
      sc := TSiteChan(cd.Objects[i]);
    except
      exit;
    end;

    ts_data := TStringList.Create;
    try
      ts_data.CaseSensitive := False;
      ts_data.Delimiter := ' ';
      ts_data.QuoteChar := '"';

      try
        Data := MainStripping(Data); //main Stripping
      except
        on e: Exception do
        begin
          Debug(dpError, rsections, Format('[EXCEPTION] MainStripping : %s', [e.Message]));
          exit;
        end;
      end;

      ts_data.DelimitedText := Data;
      MyDebug('After main stripping line is: %s', [ts_data.DelimitedText]);


      MyDebug('Checking main stripped line for ignore words.');
      // ignorewords check
      // word by word check for single words
      for i := 0 to ts_data.Count - 1 do
      begin
        igindex := irclines_ignorewords.IndexOf(ts_data.Strings[i]);
        if igindex > -1 then
        begin
          MyDebug('Ignoreword ' + irclines_ignorewords[igindex] + ' found in ' + Data);
          Debug(dpSpam, rsections, 'Ignoreword ' + irclines_ignorewords.strings[igindex] + ' found in ' + Data);
          exit;
        end;
      end;

      // fulltext check for quoted phrases (that contains at least one space)
      for i := 0 to irclines_ignorewords.Count - 1 do
      begin
        if AnsiContainsText(irclines_ignorewords[i],' ') and AnsiContainsText(ts_data.DelimitedText, irclines_ignorewords[i]) then
        begin
          MyDebug('Ignoreword (phrase) "' + irclines_ignorewords[i] + '" found in ' + Data);
          Debug(dpSpam, rsections, 'Ignoreword (phrase) "' + irclines_ignorewords[i] + '" found in ' + Data);
          exit;
        end;
      end;



      // Extract the release name, returns '' when no rlsname found
      try
        rls := ExtractReleasename(ts_data);
      except
        on e: Exception do
        begin
          Debug(dpError, rsections, Format('[EXCEPTION] ExtractReleasename : %s (%s)', [e.Message, ts_data.DelimitedText]));
          exit;
        end;
      end;

      if (rls = '') then
      begin
        Debug(dpSpam, rsections, Format('PrecatcherProcessB: Releasename is empty! (%s)', [ts_data.DelimitedText]));
        exit;
      end;

      if (skiprlses.IndexOf(rls) <> -1) then
      begin
        MyDebug('Release found in SkipRlses ...');
        Debug(dpSpam, rsections, Format('Release %s found in SkipRlses (%s) ...', [rls, skiprlses.ValueFromIndex[skiprlses.IndexOf(rls)]]));
        exit;
      end;


      // do the [replace] from slftp.precatcher
      s := ReplaceText(ts_data.DelimitedText, rls, '${RELEASENAMEPLACEHOLDER}$');
      s := ProcessDoReplace(s);
      s := ReplaceText(s, '${RELEASENAMEPLACEHOLDER}$', rls);
      ts_data.DelimitedText := s;

      MyDebug('After replace line is: %s', [ts_data.DelimitedText]);


      // Find section name
      for i := 0 to sc.sections.Count - 1 do
      begin
        ss := TSection(sc.sections[i]);
        mind := True;
        for j := 0 to ss.words.Count - 1 do
        begin
          if (ts_data.IndexOf(ss.words[j]) = -1) then
          begin
            mind := False;
            Break;
          end;
        end;

        if (ss.section = 'REQUEST') or (ss.eventtype = kbeREQUEST) then
        begin
          MyDebug('Event: ' + KBEventTypeToString(ss.eventtype));
          if not precatcher_debug then
          begin
            fRequestDirlistTask := TAutoDirlistTask.Create(net, chan, sc.sitename, rls);
            AddTask(fRequestDirlistTask);
          end;
          exit;
        end;

        if (mind) then
        begin
          try

            if ss.eventtype = kbeADDPRE then
            begin
              MyDebug('Event: ' + KBEventTypeToString(ss.eventtype));
              if not precatcher_debug then
              begin
                dbaddpre_ADDPRE(net, chan, nick, rls, kbeADDPRE);
              end;
              exit;
            end;

            precatcher_lock.Enter;
            try
               ProcessReleaseVege(net, chan, nick, sc.sitename, ss.eventtype, ss.section, rls, ts_data);
            finally
              precatcher_lock.Leave;
            end;

          except
            on e: Exception do
            begin
              MyDebug('[EXCEPTION] ProcessReleaseVegeB mind = true : %s', [e.Message]);
              Debug(dpError, rsections, Format('[EXCEPTION] ProcessReleaseVegeB mind = true: %s || net: %s, chan: %s, nick: %s || site: %s, event: %s, section: %s, rls: %s || ts_data: %s', [e.Message, net, chan, nick, sc.sitename, KBEventTypeToString(ss.eventtype), ss.section, rls, ts_data.Text]));
              exit;
            end;
          end;
          exit;
        end;
      end;

      MyDebug('No matching catcher event found.');

    finally
      ts_data.Free;
    end;

  end
  else
  begin
    MyDebug('No catchline found for %s %s %s', [net, chan, nick]);
  end;
end;

procedure PrecatcherProcess(const net, chan, nick, Data: String);
begin
  if not precatcherauto then
    Exit;

{
  precatcher_lock.Enter;
  try
}
    try
      PrecatcherProcessB(net, chan, nick, Data);
    except
      on e: Exception do
      begin
        Debug(dpError, rsections, Format('[EXCEPTION] PrecatcherProcess : %s', [e.Message]));
      end;
    end;
{
  finally
    precatcher_lock.Leave;
  end;
}

end;

function ProcessChannels(s: String): boolean;
var
  network, chan, nick, sitename, words, event, forced_section: String;
  sci: integer;
  sc: TSiteChan;
  section: TSection;
  i, j: integer;
  nickc: integer;
  nickt: String;
begin
  Result := False;
  if (length(s) = 0) then
    exit;

  if (Count(';', s) < 6) then
    exit;

  network := UpperCase(SubString(s, ';', 1));
  chan := LowerCase(SubString(s, ';', 2));
  nickt := LowerCase(SubString(s, ';', 3));
  sitename := SubString(s, ';', 4);
  event := SubString(s, ';', 5);
  words := SubString(s, ';', 6);
  forced_section := SubString(s, ';', 7);

  if (chan[1] <> '#') then
    exit;
  if (event = '') then
    exit;

  nickc := Count(',', nickt);

  for j := 1 to nickc + 1 do
  begin
    nick := SubString(nickt, ',', j);
    sci := cd.IndexOf(network + chan + nick);
    if (sci = -1) then
    begin
      sc := TSiteChan.Create();
      sc.sitename := sitename;
      cd.AddObject(network + chan + nick, sc);
    end
    else
      sc := TSiteChan(cd.Objects[sci]);

    section := TSection.Create;
    section.section := forced_section;
    section.eventtype := EventStringToTKBEventType(event);

    if (words <> '') then
      for i := 1 to Count(',', words) + 1 do
        section.words.Add(SubString(words, ',', i));

    sc.sections.Add(section);
  end;
  Result := True;
end;

procedure cdClear;
var
  i: integer;
begin
  for i := 0 to cd.Count - 1 do
  begin
    if cd.Objects[i] <> nil then
    begin
      cd.Objects[i].Free;
      cd.Objects[i] := nil;
    end;
  end;
  cd.Clear;
end;

procedure PrecatcherRebuild();
var
  i: integer;
  S: String;
var
  f: TextFile;
begin
  cdClear;
  i := 0;
  while (i < catcherFile.Count) do
  begin
    if not ProcessChannels(catcherFile[i]) then
    begin
      catcherFile.Delete(i);
      Dec(i);
    end;
    Inc(i);
  end;

  if (config.ReadBool('sites', 'split_site_data', False)) then
  begin

    for i := 0 to catcherFile.Count - 1 do // delete all old files first
    begin
      S := catcherFile[i];
      S := SubString(s, ';', 4);
      S := ExtractFilePath(ParamStr(0)) + 'rtpl' + PathDelim + S + '.chans';
      if FileExists(S) then
        {$IFDEF MSWINDOWS}
          {$IFDEF UNICODE}
            DeleteFile(PChar(S));
          {$ELSE}
            DeleteFile(PAnsiChar(S));
          {$ENDIF}
        {$ELSE}
          DeleteFile(S);
        {$ENDIF}
    end;

    for i := 0 to catcherFile.Count - 1 do // create if needed and append lines
    begin
      S := catcherFile[i];
      S := SubString(s, ';', 4);
      S := ExtractFilePath(ParamStr(0)) + 'rtpl' + PathDelim + S + '.chans';
      AssignFile(f, S);
      if (FileExists(S)) then
        Append(f)
      else
        Rewrite(f);
      WriteLn(f, catcherFile[i]);
      CloseFile(f);
    end;

    if FileExists(catcherFilename) then // convert to split format
      {$IFDEF MSWINDOWS}
        {$IFDEF UNICODE}
          DeleteFile(PChar(catcherFilename));
        {$ELSE}
          DeleteFile(PAnsiChar(catcherFilename));
        {$ENDIF}
      {$ELSE}
        DeleteFile(catcherFilename);
      {$ENDIF}
  end
  else
  begin
    catcherFile.SaveToFile(catcherFilename);
  end;
end;

procedure ProcessRaceTool(s: String);
begin
  if (SubString(s, '=', 1) = 'minimum_rlsname') then
    minimum_rlsname := StrToIntDef(SubString(s, '=', 2), 10);
end;

procedure ProcessIgnoreList(s: String);
begin
  if (SubString(s, '=', 1) = 'ignorewords') then
    irclines_ignorewords.DelimitedText := SubString(s, '=', 2)
  else if (SubString(s, '=', 1) = 'tagline') then
    tagline.DelimitedText := SubString(s, '=', 2);

end;

procedure ProcessReplace(s: String);
var
  i, db: integer;
  replacetoline: String;
begin
  if IsLineCommentedOut(s) then
  begin
    exit;
  end;

  if (SubString(s, '=', 1) = 'replacefrom') then
  begin
    replacefromline := trim(SubString(s, '=', 2))
  end
  else if (SubString(s, '=', 1) = 'replaceto') then
  begin
    replacetoline := trim(SubString(s, '=', 2));
    replacetoline := ReplaceText(replacetoline, '[:space:]', ' ');
    db := Count(';', replacefromline);
    for i := 1 to db + 1 do
    begin
      replacefrom.Add(SubString(replacefromline, ';', i));
      replaceto.Add(replacetoline);
    end;
  end;

end;

procedure ProcessSections(s: String);
var
  v, vv, section: String;
begin
  if IsLineCommentedOut(s) then
  begin
    exit;
  end;

  section := UpperCase(SubString(s, '=', 1));
  if (section <> '') then
  begin
    v := SubString(s, '=', 2);
    while (True) do
    begin
      vv := Trim(Fetch(v, ',', True, False));
      if ((vv = '') and (v = '')) then
        break;
      if (vv <> '') then
        glSectionList.Add(section + '= ' + vv + ' ');
    end;
  end;

end;

procedure ProcessMappings(s: String);
var
  db, i: integer;
  ss: String;
  rx: TRegExpr;
begin
  if IsLineCommentedOut(s) then
  begin
    exit;
  end;

  rx := TRegExpr.Create;
  try
    rx.ModifierI := True;

    if Count(';', s) = 2 then
    begin
      ss := SubString(s, ';', 3);
      rx.Expression := '(\/.*?\/i?)';
      if rx.Exec(ss) then
      begin
        repeat
          mappingslist.Add(TMap.Create(UpperCase(SubString(s, ';', 1)), UpperCase(SubString(s, ';', 2)), rx.Match[1]));
        until not rx.ExecNext;
      end
      else
      begin
        db := Count(',', ss);
        for i := 1 to db + 1 do
          mappingslist.Add(TMap.Create(UpperCase(SubString(s, ';', 1)), UpperCase(SubString(s, ';', 2)), SubString(ss, ',', i)));
      end;
    end;

  finally
    rx.Free;
  end;
end;

procedure ProcessConfigLine(s: String);
begin
  if s = '[racetool]' then
    huntartunk := racetool
  else if s = '[ignorelist]' then
    huntartunk := ignorelist
  else if s = '[replace]' then
    huntartunk := replace
  else if s = '[sections]' then
    huntartunk := hunsections
  else if s = '[mappings]' then
    huntartunk := mappings
  else if s = '[channels]' then
    huntartunk := channels
  else if s = '[pretime]' then
    huntartunk := pretime;

  case huntartunk of
    racetool: ProcessRaceTool(s);
    ignorelist: ProcessIgnoreList(s);
    replace: ProcessReplace(s);
    hunsections: ProcessSections(s);
    mappings: ProcessMappings(s);
  end;
end;

function Precatcher_Sitehasachan(const sitename: String): boolean;
var
  i: integer;
  sc: TSiteChan;
begin
  Result := False;
  for i := 0 to cd.Count - 1 do
  begin
    sc := TSiteChan(cd.Objects[i]);
    if sc.sitename = sitename then
    begin
      Result := True;
      break;
    end;
  end;
end;

procedure Precatcher_DelSiteChans(const sitename: String);
var
  i: integer;
  s: String;
begin
  i := 0;

  while (i < catcherFile.Count) do
  begin
    s := catcherFile[i];
    s := SubString(s, ';', 4);

    if s = sitename then
    begin
      catcherFile.Delete(i);
      Dec(i);
    end;

    Inc(i);
  end;
end;

function precatcher_logfilename: String;
begin
  Result := ExtractFilePath(ParamStr(0)) + config.ReadString(rsections, 'debugfile', 'precatcher.log');
end;

procedure Precatcher_Init;
begin
  cd := THashedStringList.Create;
  cd.CaseSensitive := False;

  irclines_ignorewords := TStringList.Create;
  irclines_ignorewords.Delimiter := ' ';
  irclines_ignorewords.QuoteChar := '"';
  irclines_ignorewords.Sorted := True;
  irclines_ignorewords.Duplicates := dupIgnore;

  precatcher_lock := TCriticalSection.Create;

  tagline := TStringList.Create;
  tagline.Delimiter := ' ';
  tagline.QuoteChar := '"';
  glSectionList := TStringList.Create;
  mappingslist := TObjectList.Create;
  skiprlses := THashedStringList.Create;

  replacefrom := TStringList.Create;
  replacefrom.Duplicates := dupAccept;
  replaceto := TStringList.Create;
  replaceto.Duplicates := dupAccept;

  huntartunk := sehun;

  // ezt itt most csak azert hogy jo sorrendben hivodjanak meg az inicializaciok -- Now it here just so that good order should call the initialization ??
  catcherFilename := ExtractFilePath(ParamStr(0)) + 'slftp.chans';
  catcherFile := TEncStringList.Create(passphrase);

  precatcher_ircdebug := config.ReadBool(rsections, 'precatcher_debug', False);

  precatcher_debug_lock := TCriticalSection.Create();
  Assignfile(debug_f, precatcher_logfilename);
  try
    if FileExists(precatcher_logfilename) then
      Append(debug_f)
    else
      Rewrite(debug_f);
  except
    begin
      Writeln('Couldnt open logfile! It might be too huge?');
      halt;
    end;
  end;
end;

procedure Precatcher_UnInit;
begin
  Debug(dpSpam, rsections, 'Uninit1');

  irclines_ignorewords.Free;

  precatcher_lock.Free;

  glSectionList.Free;
  mappingslist.Free;
  skiprlses.Free;
  tagline.Free;
  replacefrom.Free;
  replaceto.Free;

  catcherFile.Free;

  cdClear;
  cd.Free;

  precatcher_debug_lock.Free;
  Closefile(debug_f);

  Debug(dpSpam, rsections, 'Uninit2');
end;

{ TMap }

constructor TMap.Create(const origsection, newsection, mask: String);
begin
  self.origsection := origsection;
  self.newsection := newsection;
  self.mask := TslMask.Create(mask);
end;

destructor TMap.Destroy;
begin
  Mask.Free;
  inherited;
end;

constructor TSection.Create;
begin
  words := TStringList.Create;
end;

destructor TSection.Destroy;
begin
  words.Free;
  inherited;
end;

constructor TSiteChan.Create;
begin
  sections := TObjectList.Create;
end;

destructor TSiteChan.Destroy;
begin
  sections.Free;
  inherited;
end;

procedure LoadSplitChanFiles;
var
  fst: TStringList;
  S: String;
  i: Integer;
  intFound: Integer;
  SearchRec: TSearchRec;
  rules_path: String;
begin
  catcherFile.Clear;
  rules_path := ExtractFilePath(ParamStr(0)) + 'rtpl' + PathDelim;

  intFound := FindFirst(rules_path + '*.chans', faAnyFile, SearchRec);
  while intFound = 0 do
  begin
    fst := TStringList.Create();
    try
      fst.LoadFromFile(rules_path + SearchRec.Name);
      for i := 0 to fst.Count - 1 do
      begin
        S := fst[i];
        catcherFile.Add(S);
      end;
    finally
      fst.Free;
    end;
    intFound := FindNext(SearchRec);
  end;

{$IFDEF MSWINDOWS}
  SysUtils.FindClose(SearchRec);
{$ELSE}
  FindClose(SearchRec);
{$ENDIF}
end;

procedure PrecatcherStart;
begin
  // Actually starting precatcher is an initial reload
  PrecatcherReload;
end;

function PrecatcherReload:String;
var
  f: TextFile;
  s: String;

begin
  // clear in-memory data
  mappingslist.Clear;
  glSectionList.Clear;
  irclines_ignorewords.Clear;
  replacefrom.Clear;
  replaceto.Clear;
  catcherFile.Clear;

  // load slftp.chans
  catcherFile.LoadFromFile(catcherFileName);

  // load rtpl/<site>.chans if split_site_data is enabled
  if (config.ReadBool('sites', 'split_site_data', False)) then
    LoadSplitChanFiles;

  result := 'Precatcher reload FAILED!';
  try
    AssignFile(f, ExtractFilePath(ParamStr(0)) + 'slftp.precatcher');
{$I-}
    Reset(f);
{$I+}
    if IOResult = 0 then
    begin
      while (not EOF(f)) do
      begin
        ReadLn(f, s);
        ProcessConfigLine(s);
      end;
    end;
    kb_reloadsections;

  finally
    CloseFile(f);
  end;

  // Rewrite files to disk
  PrecatcherRebuild;

  result := 'Precatcher reloaded successfully.' + sLineBreak;
  result := result + 'Minimum_rlsname: ' + IntToStr(minimum_rlsname) + sLineBreak;
  result := result + Format('Sections (%d) - Mapping (%d) - Replace|from/to: (%d/%d) - Ignorelist (%d)', [kb_sections.Count, mappingslist.Count, replacefrom.Count, replaceto.Count, irclines_ignorewords.Count]);
end;

function precatcherauto: boolean;
begin
  Result := sitesdat.ReadBool('precatcher', 'auto', False);
end;

end.

