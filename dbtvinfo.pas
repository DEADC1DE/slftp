unit dbtvinfo;

interface

uses
  Classes, IniFiles, irc, kb.releaseinfo, Contnrs;

type
  { @abstract(Possible return values for special cases in getShowValues procedure)
    @value(tvInitialValue Initial value which is set as default value)
    @value(tvNotMatched For cases where main regex matched but single matches don't contain useful values)
    @value(tvConversionError Value if StrToIntDef failed to convert input)
    @value(tvDatedShow Season value for dated shows)
    @value(tvRegularSerieWithoutSeason Season value for shows which only have an episode tag)
    @value(tvNoExplicitShowTag Shows without season/episode/dated tag (mostly tv movies or sports))
    @value(tvNoEpisodeTag Shows without episode tag (mostly full season releases)) }
  TTVGetShowValuesIdentifier = (tvInitialValue = -50, tvNotMatched = -60, tvConversionError = -70,
    tvDatedShow = -80, tvRegularSerieWithoutSeason = -90, tvNoExplicitShowTag = -100, tvNoEpisodeTag = -110);

  { @abstract(Possible 'error' values for season and episode info lookups on the web)
    @value(tvSeEpInitialValue Initial value which is set as default value)
    @value(tvSeEpAirdatePrevAndNextOnSameDay Airdate of previous and next episode are on the same day)
    @value(tvSeEpShowEnded Show ended)
    @value(tvSeEpNoNextOrPrev No information about the next episode and next season) }
  TTVSeasonEpisodeWebInfo = (tvSeEpInitialValue = -3, tvSeEpAirdatePrevAndNextOnSameDay = -4, tvSeEpShowEnded = -5, tvSeEpNoNextOrPrev = -6);

  TTVInfoDB = class
  public
    ripname: String;
    rls_showname: String;
    tvmaze_id: String;
    thetvdb_id: String;
    tvrage_id: String;

    tv_showname: String;
    tv_country: String;
    tv_url: String;
    tv_status: String;
    tv_classification: String;
    tv_genres: TStringList;
    tv_days: TStringList;
    tv_network: String;
    tv_language: String;
    tv_premiered_year: integer;
    tv_endedyear: integer;
    tv_running: boolean;
    tv_scripted: boolean;
    tv_next_season: integer;
    tv_next_ep: integer;
    tv_next_date: integer;
    tv_rating: integer; //< tv rating value (max score is 100, min score is 0)
    last_updated: integer;
    tv_daily: boolean;
    constructor Create(const rls_showname: String); //overload;
    destructor Destroy; override;
    function Name: String;
    procedure Save;

    procedure PostResults(rls: String = ''; netname: String = ''; channel: String = '');
    procedure SetTVDbRelease(tr: TTVRelease);
    function Update(fromIRC:Boolean = False): boolean;

    function executeUpdate: boolean;

    procedure setTheTVDbID(const aID: integer);
    procedure setTVRageID(const aID: integer);
  end;

function getTVInfoCount: integer;
function getTVInfoSeriesCount: integer;

function TheTVDbStatus: String;

procedure dbTVInfoInit;
procedure dbTVInfoStart;
procedure dbTVInfoUnInit;

function getTVInfoByShowName(const aRls_Showname: String): TTVInfoDB;
function getTVInfoByReleaseName(const aRLS: String): TTVInfoDB;

function getTVInfoByShowID(const aTVMazeID: String): TTVInfoDB;

procedure saveTVInfos(const TVMazeID: String; tvrage: TTVInfoDB; rls: String = ''; fireKb: boolean = True);

function deleteTVInfoByID(const aID: String): Integer;
function deleteTVInfoByRipName(const aName: String): Integer;

procedure addTVInfos(const aParams: String);

procedure TVInfoFireKbAdd(const aRls: String; msg: String = '<c3>[TVInfo]</c> %s %s now has TV infos (%s)');

function dbTVInfo_Process(const aNet, aChan, aNick: String; aMSG: String): boolean;

{ Removes scene tagging for TV releases like languages or tvtags and tries to extract showname
  @param(aRlsname Releasename with scene tagging)
  @param(showName Plain TV showname from @link(aRlsname) without any scene tags) }
procedure getShowValues(const aRlsname: String; out showName: String); overload;

{ Removes scene tagging for TV releases like languages or tvtags and tries to extract showname, season and episode from releasename
  @param(aRlsname Releasename with scene tagging)
  @param(showName Plain TV showname from @link(aRlsname) without any scene tags)
  @param(season Extracted season number from @link(aRlsname))
  @param(episode Extracted episode number from @link(aRlsname)) }
procedure getShowValues(const aRlsname: String; out showName: String; out season: integer; out episode: int64); overload;

{ Replaces TV showname words (and, at) with (&, @) and replaces whitespaces with dots
  @param(aName TV showname)
  @param(forWebFetch If set to @true, it replaces whitespaces, dots and underscores with '+'' for better web search results)
  @returns(TV showname with replaced chars) }
function replaceTVShowChars(const aName: String; forWebFetch: boolean = false): String;

function TVInfoDbAlive: boolean;

implementation

uses
  DateUtils, SysUtils, Math, configunit, StrUtils, mystrings, console, sitesunit, queueunit, slmasks, http, RegExpr,
  debugunit, tasktvinfolookup, pazo, mrdohutils, uLkJSON, dbhandler, SyncObjs, sllanguagebase, mormot.db.sql.sqlite3,
  Generics.Collections, news, kb;

const
  section = 'tasktvinfo';

var
  tvinfoSQLite3DBCon: TSQLDBSQLite3ConnectionProperties = nil; //< SQLite3 database connection for tv info
  SQLite3Lock: TCriticalSection = nil; //< Critical Section used for read/write blocking as concurrently does not work flawless
  addtinfodbcmd: String; //< irc command for addtvmaze channel, default: !addtvmaze
  LastAddtvmazeIDs: TList<String>; // ugly way to prevent looping of !addtvmaze announces when info is already stored with different ID

function replaceTVShowChars(const aName: String; forWebFetch: boolean = false): String;
var
  fHelper: String;
begin
  // this is a protection!!!! Dispatches will not end up in Disp@ches
  fHelper := ReplaceText(aName, ' ', '.');
  fHelper := ReplaceText(fHelper, '.and.', '.%26.');
  fHelper := ReplaceText(fHelper, '_and_', '_%26_');
  fHelper := ReplaceText(fHelper, '', Chr(39));
  fHelper := ReplaceText(fHelper, '''', '');

  if forWebFetch then
  begin
    fHelper := ReplaceText(fHelper, ' ', '+');
    fHelper := ReplaceText(fHelper, '.', '+');
    fHelper := ReplaceText(fHelper, '_', '+');
  end;

  // do not end up with 'tv.show.name.' or 'tv+show+name+'
  if fHelper[Length(fHelper)] in ['.', '+'] then
    SetLength(fHelper, Length(fHelper) - 1);

  Result := fHelper;
end;

procedure getShowValues(const aRlsname: String; out showName: String);
var
  fSeason: integer;
  fEpisode: int64;
begin
  getShowValues(aRlsname, showName, fSeason, fEpisode);
end;

procedure getShowValues(const aRlsname: String; out showName: String; out season: integer; out episode: int64);
var
  rx: TRegexpr;
  ttags, ltags: TStringlist;
  showDate: TDateTime;

  procedure SetNotMatchedValues;
  begin
    season := Ord(tvNotMatched);
    episode := Ord(tvNotMatched);
  end;

begin
  showName := aRlsname;

  // default values for not parsed/matched
  season := Ord(tvInitialValue);
  episode := Ord(tvInitialValue);

  rx := TRegexpr.Create;
  try
    rx.ModifierI := True;
    rx.ModifierG := True;


    (* dated shows like Stern.TV.2016.01.27.GERMAN.Doku.WS.dTV.x264-FiXTv *)
    (* YYYY/MM/DD *)
    rx.Expression := '(.*)[\._-](\d{4})[\.\-](\d{2})[\.\-](\d{2}|\d{2}[\.\-]\d{2}[\.\-]\d{4})[\._-](.*)';
    if rx.Exec(aRlsname) then
    begin
      showName := rx.Match[1];
      SetNotMatchedValues;

      {$IFDEF DEBUG}
        Debug(dpSpam, section, Format('getShowValues-case-1 - matches: %s %s %s %s', [rx.Match[1], rx.Match[2], rx.Match[3], rx.Match[4]]));
      {$ENDIF}

      if DateUtils.IsValidDate(StrToInt(rx.Match[2]), StrToInt(rx.Match[3]), StrToInt(rx.Match[4]))
       and TryEncodeDateTime(StrToInt(rx.Match[2]), StrToInt(rx.Match[3]), StrToInt(rx.Match[4]), 0, 0 , 0, 0 , showDate) then
      begin
        season := Ord(tvDatedShow);
        episode := DateTimeToUnix(showDate);
      end
      else
      begin
        irc_Adderror('<c4><b>getShowValues ERROR</c></b>: ' + rx.Match[4] + '-' + rx.Match[3] + '-' + rx.Match[2] + ' is no valid date.');
        Debug(dpError, section, 'getShowValues ERROR: ' + rx.Match[4] + '-' + rx.Match[3] + '-' + rx.Match[2] + ' is no valid date.');
      end;

      {$IFDEF DEBUG}
        Debug(dpSpam, section, Format('getShowValues-case-1 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
      {$ENDIF}

      exit;
    end;


    (* regular series tagging like S01E02 and 1x02 *)
    rx.Expression := '(.*?)[._-](S(\d{1,3})(E(\d{1,3}))?|(\d+)x(\d+))';
    if rx.Exec(aRlsname) then
    begin
      showName := rx.Match[1];
      SetNotMatchedValues;

      {$IFDEF DEBUG}
        Debug(dpSpam, section, Format('getShowValues-case-2 - matches: %s %s %s %s %s', [rx.Match[1], rx.Match[3], rx.Match[5], rx.Match[6], rx.Match[7]]));
      {$ENDIF}

      if StrToIntDef(rx.Match[3], 0) > 0 then
      begin
        season := StrToIntDef(rx.Match[3], Ord(tvConversionError));

        if StrToIntDef(rx.Match[5], -1) = -1 then
          episode := Ord(tvNoEpisodeTag)
        else
          episode := StrToIntDef(rx.Match[5], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-2-1 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}

        exit;
      end;

      if StrToIntDef(rx.Match[6], 0) > 0 then
      begin
        season := StrToIntDef(rx.Match[6], Ord(tvConversionError));
        episode := StrToIntDef(rx.Match[7], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-2-2 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}

        exit;
      end;
    end;


    rx.Expression := '(.*?)[._-]((S(taffel)?)(\d{1,3}))?[._]?(D|E|EP|Episode|DVD[._]?|Part[_.]?)(\d{1,3})(.*?)';
    if rx.Exec(aRlsname) then
    begin
      showName := rx.Match[1];
      SetNotMatchedValues;

      {$IFDEF DEBUG}
        Debug(dpSpam, section, Format('getShowValues-case-3 - matches: %s %s %s', [rx.Match[1], rx.Match[5], rx.Match[7]]));
      {$ENDIF}

      season := Ord(tvRegularSerieWithoutSeason);
      episode := StrToIntDef(rx.Match[7], Ord(tvConversionError));

      if StrToIntDef(rx.Match[5], 0) > 0 then
      begin
        episode := StrToIntDef(rx.Match[5], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-3-1 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}
      end
      else
      begin
        episode := StrToIntDef(rx.Match[7], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-3-2 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}
      end;

      exit;
    end;


    rx.Expression := '(.*?)[._-]((W|V|S(taffel|eason|aison))[._]?(\d{1,3})[._]?)?(SE|DIS[CK]|Y|E|EPS?|VOL(UME)?)[._]?(\d{1,3}).*?';
    if rx.Exec(aRlsname) then
    begin
      showName := rx.Match[1];
      SetNotMatchedValues;

      {$IFDEF DEBUG}
        Debug(dpSpam, section, Format('getShowValues-case-4 - matches: %s %s %s', [rx.Match[1], rx.Match[4], rx.Match[7]]));
      {$ENDIF}

      if StrToIntDef(rx.Match[4], 0) > 0 then
      begin
        episode := StrToIntDef(rx.Match[4], Ord(tvConversionError));
        season := StrToIntDef(rx.Match[4], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-4-1 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}
      end
      else
      begin
        episode := StrToIntDef(rx.Match[7], Ord(tvConversionError));
        season := StrToIntDef(rx.Match[7], Ord(tvConversionError));

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-4-2 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}
      end;

      exit;
    end;


    (* remove scene/language/tv tags from releasename *)
    ttags := TStringlist.Create;
    try
      ttags.Assign(GlTvTags);
      ttags.Delimiter := '|';

      ltags := TStringlist.Create;
      try
        SLGetLanguagesExpression(ltags);
        ltags.Delimiter := '|';

        // language and tvtags (needs to be removed first due to enforcing of .<lang|tag>.)
        rx.Expression := '[._\-\s](' + ltags.DelimitedText + '|' + ttags.DelimitedText + ')[._\-\s].*$';
        showName := rx.Replace(showName, '', False);
        // scene specific tags for <showname>.REAL.<scenetags>
        rx.Expression := '[._\-\s]REAL[._\-\s]((480|720|1080|1440|2160)(p|i)|REPACK|PROPER|INTERNAL|(DIR|NFO|SFV|PROOF|SAMPLE)[._]?FIX).*$';
        showName := rx.Replace(showName, '', False);
        // scene specific tags
        rx.Expression := '[._\-\s]((19|20)\d{2}|(480|720|1080|1440|2160)(p|i)|REPACK|PROPER|INTERNAL|(DIR|NFO|SFV|PROOF|SAMPLE)[._]?FIX).*$';
        showName := rx.Replace(showName, '', False);

        season := Ord(tvNoExplicitShowTag);
        episode := Ord(tvNoExplicitShowTag);

        {$IFDEF DEBUG}
          Debug(dpSpam, section, Format('getShowValues-case-5 - rls: %s, showname: %s, season: %d, episode: %d', [aRlsname, showName, season, episode]));
        {$ENDIF}

      finally
        ltags.free;
      end;
    finally
      ttags.free;
    end;

  finally
    rx.free;
  end;
end;

{ TTVInfoDB }

procedure TTVInfoDB.setTheTVDbID(const aID: integer);
var
  fQuery: TSqlDBSQLite3Statement;
begin
  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('UPDATE infos set tvdb_id = ? WHERE tvmaze_id = ?');
      fQuery.Bind(1, aID);
      fQuery.BindTextS(2, tvmaze_id);
      try
        fQuery.ExecutePrepared;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] setTheTVDbID: %s, ID: %d, TVMAZE-ID: %s', [e.Message, aID, tvmaze_id]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

procedure TTVInfoDB.setTVRageID(const aID: integer);
var
  fQuery: TSqlDBSQLite3Statement;
begin
  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('UPDATE infos set tvrage_id = ? WHERE tvmaze_id = ?');
      fQuery.Bind(1, aID);
      fQuery.BindTextS(2, tvmaze_id);
      try
        fQuery.ExecutePrepared;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] setTVRageID: %s, ID: %d, TVMAZE-ID: %s', [e.Message, aID, tvmaze_id]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

procedure TTVInfoDB.Save;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('INSERT OR IGNORE INTO infos ' +
        '(tvdb_id, premiered_year, country, status, classification, network, genre, ended_year, last_updated, tvrage_id, tvmaze_id, airdays, next_date, next_season, next_episode, tv_language, rating) VALUES ' +
        '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');

      fQuery.Bind(1, StrToIntDef(thetvdb_id, -1));
      fQuery.Bind(2, tv_premiered_year);
      fQuery.BindTextS(3, tv_country);
      fQuery.BindTextS(4, tv_status);
      fQuery.BindTextS(5, tv_classification);
      fQuery.BindTextS(6, tv_network);
      fQuery.BindTextS(7, tv_genres.CommaText);
      fQuery.Bind(8, tv_endedyear);
      fQuery.Bind(9, DateTimeToUnix(now()));
      fQuery.Bind(10, StrToIntDef(tvrage_id, -1));
      fQuery.Bind(11, StrToIntDef(tvmaze_id, -1));
      fQuery.BindTextS(12, tv_days.CommaText);
      fQuery.Bind(13, tv_next_date);
      fQuery.Bind(14, tv_next_season);
      fQuery.Bind(15, tv_next_ep);
      fQuery.BindTextS(16, tv_language);
      fQuery.Bind(17, tv_rating);
      try
        fQuery.ExecutePrepared;
         If fQuery.UpdateCount > 0 then
          last_updated := DateTimeToUnix(now())
        else
          last_updated := 3817;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] TTVInfoDB.Save infos: %s', [e.Message]));
          exit;
        end;
      end;

      // release the SQL statement, results and bound parameters before reopen
      fQuery.Reset;

      fQuery.Prepare('INSERT OR IGNORE INTO series (rip, showname, id, tvmaze_url) VALUES (?, ?, ?, ?)');
      fQuery.BindTextS(1, rls_showname);
      fQuery.BindTextS(2, tv_showname);
      fQuery.Bind(3, StrToInt(tvmaze_id));
      fQuery.BindTextS(4, tv_url);
      try
         fQuery.ExecutePrepared;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] TTVInfoDB.Save series: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

procedure TTVInfoDB.SetTVDbRelease(tr: TTVRelease);
begin
  tr.showname := rls_showname;
  tr.thetvdbid := thetvdb_id;
  tr.tvrageid := tvrage_id;
  tr.showid := tvmaze_id;
  tr.premier_year := tv_premiered_year;
  tr.country := tv_country;
  tr.status := tv_status;
  tr.classification := tv_classification;
  tr.genres.Assign(tv_genres);
  tr.network := tv_network;
  tr.running := tv_running;
  tr.ended_year := tv_endedyear;
  tr.scripted := tv_scripted;
  tr.daily := Boolean(tv_days.Count > 1);
  tr.currentseason := false;
  tr.currentepisode := false;
  tr.currentair := false;
  tr.tvlanguage := tv_language;
  tr.tvrating := tv_rating;

  if YearOf(now) = tv_next_season then
  begin
    tv_next_season := tr.season;
  end;

  case tv_next_season of
    Ord(tvSeEpAirdatePrevAndNextOnSameDay):
      begin
        //Prev and Next are on the same day.
        tv_next_ep := tr.episode;
        tv_next_season := tr.season;
        tr.currentseason := true;
        tr.currentepisode := true;
        tr.currentair := true;
      end;
    Ord(tvSeEpShowEnded):
      begin
        //show is ended.
        tv_next_ep := 0;
        tv_next_season := 0;
        tr.currentseason := False;
        tr.currentepisode := False;
        tr.currentair := False;
      end;
    Ord(tvSeEpNoNextOrPrev):
      begin
        //neither next nor prev

        if tr.episode > 031337 then
        begin
          // looks like a date tag was found.
          tr.season := YearOf(UnixToDateTime(tr.episode));
          self.tv_next_season := tr.season;
          tr.currentseason := Boolean(CurrentYear = tr.season);
          tr.currentepisode := Boolean(tr.currentseason and (UnixToDateTime(tr.episode + 86400) >= now));
          tr.currentair := tr.currentepisode;
        end;
        self.tv_next_ep := 0;
        tr.episode := 0;
      end;
    Ord(tvDatedShow): // probably set by TTVRelease.Create
      begin
        // dated show
        tr.season := YearOf(UnixToDateTime(tr.episode));
        tv_next_season := YearOf(UnixToDateTime(tv_next_date));
        tr.episode := self.tv_next_ep; // no episode tag, so we must trust tvmaze
        tr.currentseason := Boolean(CurrentYear = tr.season);
        tr.currentepisode := Boolean((CurrentYear = tr.season) and (tv_next_ep = tr.episode));
        tr.currentair := Boolean((tv_next_season = tr.season) and (tv_next_ep = tr.episode));
      end
  else
    begin
      tr.currentseason := Boolean(tv_next_season = tr.season);
      tr.currentepisode := Boolean((tv_next_season = tr.season) and (tv_next_ep = tr.episode));
      tr.currentair := Boolean((tv_next_season = tr.season) and (tv_next_ep = tr.episode));
    end;
  end;

  tr.FLookupDone := True;

  if config.ReadBool(section, 'post_lookup_infos', False) then
    PostResults(rls_showname);
end;

constructor TTVInfoDB.Create(const rls_showname: String);
begin
  self.rls_showname := rls_showname;
  self.tv_genres := TStringList.Create;
  self.tv_genres.QuoteChar := '"';
  self.tv_days := TStringList.Create;
  self.tv_days.QuoteChar := '"';
  self.tv_endedyear := -1;
  self.tv_rating := 0;
  self.last_updated:= 3817;
  self.tv_next_ep := Ord(tvSeEpInitialValue);
  self.tv_next_season := Ord(tvSeEpInitialValue);
end;

destructor TTVInfoDB.Destroy;
begin
  self.tv_genres.Free;
  self.tv_days.free;
  inherited;
end;

function TTVInfoDB.Name: String;
begin
  try
    Result := 'TVInfo :' + rls_showname + ' : ';
  except
    Result := 'TVInfo';
  end;
end;

procedure TTVInfoDB.PostResults(rls: String = ''; netname: String = ''; channel: String = '');
var
  toAnnounce: TStringlist;
  toStats: boolean;
  I: Integer;
begin
  toAnnounce := TStringlist.Create;
  toStats := Boolean((netname = '') and (channel = ''));
  if ((rls = '') or (tvmaze_id = rls)) then
    rls := rls_showname;

  try
    if config.ReadBool(section, 'use_new_announce_style', True) then
    begin
      if tv_endedyear > 0 then
        toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>%s</b> (%d - %d) - <b>TVMaze info</b> %s', [rls, tv_premiered_year, tv_endedyear, tv_url]))
      else
        toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>%s</b> - <b>Premiere Year</b> %d - <b>TVMaze info</b> %s', [rls, tv_premiered_year, tv_url]));

      if ((tv_next_season > 0) and (tv_next_ep > 0)) then
        toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>Season</b> %d - <b>Episode</b> %d - <b>Date</b> %s', [tv_next_season, tv_next_ep, FormatDateTime('yyyy-mm-dd', UnixToDateTime(tv_next_date))]));

      toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>Genre</b> %s - <b>Classification</b> %s - <b>Status</b> %s', [tv_genres.CommaText, tv_classification, tv_status]));
      toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>Country</b> %s - <b>Network</b> %s - <b>Language</b> %s - <b>Rating</b> %d/100', [tv_country, tv_network, tv_language, tv_rating]));
      toAnnounce.Add(Format('<c10>[<b>TVInfo</b>]</c> <b>Last update</b> %s', [DateTimeToStr(UnixToDateTime(last_updated))]));
    end
    else
    begin
      if tv_endedyear > 0 then
        toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>....... <c0><b>info for</c></b> ...........: <b>%s</b> (%s - %s) - %s', [rls, IntToStr(tv_premiered_year), IntToStr(tv_endedyear), tv_url]))
      else
        toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>....... <c0><b>info for</c></b> ...........: <b>%s</b> (%s) - %s', [rls, IntToStr(tv_premiered_year), tv_url]));

      if ((tv_next_season > 0) and (tv_next_ep > 0)) then
        toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>....... <c9><b>Season/Episode (Date)</c></b> ...........: <b>%d.%d</b> (%s)', [tv_next_season, tv_next_ep, FormatDateTime('yyyy-mm-dd', UnixToDateTime(tv_next_date))]));

      toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>.. <c9><b>Genre (Class) @ Status</c></b> ..: %s (%s) @ %s', [tv_genres.CommaText, tv_classification, tv_status]));
      toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>....... <c4><b>Country/Channel</c></b> ....: <b>%s</b> (%s) ', [tv_country, tv_network]));
      toAnnounce.Add(Format('(<c9>i</c>)....<c7><b>TVInfo (db)</b></c>....... <c4><b>Last update</c></b> ....: <b>%s</b>', [FormatDateTime('yyyy-mm-dd hh:nn:ss', UnixToDateTime(last_updated))]));
    end;

    for I := 0 to toAnnounce.Count - 1 do
    begin
      if toStats then
        irc_Addstats(toAnnounce.Strings[i])
      else
        irc_addtext(Netname, Channel, toAnnounce.Strings[i]);
    end;
  finally
    toAnnounce.free;
  end;
end;

function TTVInfoDB.executeUpdate: Boolean;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := False;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('UPDATE infos SET ' +
        'tvdb_id = ?, tvrage_id = ?, status = ?, country = ?, tv_language = ?, network = ?, ' +
        'classification = ?, genre = ?, airdays = ?, premiered_year = ?, ended_year = ?, next_date = ?, ' +
        'next_season = ?, next_episode = ?, rating = ?, last_updated = ? WHERE tvmaze_id = ?');

      fQuery.Bind(1, StrToIntDef(thetvdb_id, -1));
      fQuery.Bind(2, StrToIntDef(tvrage_id, -1));
      fQuery.BindTextS(3, tv_status);
      fQuery.BindTextS(4, tv_country);
      fQuery.BindTextS(5, tv_language);
      fQuery.BindTextS(6, tv_network);
      fQuery.BindTextS(7, tv_classification);
      fQuery.BindTextS(8, tv_genres.CommaText);
      fQuery.BindTextS(9, tv_days.CommaText);
      fQuery.Bind(10, tv_premiered_year);
      fQuery.Bind(11, tv_endedyear);
      fQuery.Bind(12, tv_next_date);
      fQuery.Bind(13, tv_next_season);
      fQuery.Bind(14, tv_next_ep);
      fQuery.Bind(15, tv_rating);
      fQuery.Bind(16, DateTimeToUnix(now()));
      fQuery.Bind(17, StrToInt(tvmaze_id));
      try
        fQuery.ExecutePrepared;
        if fQuery.UpdateCount > 0 then
          Result := True;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] TTVInfoDB.executeUpdate: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function TTVInfoDB.Update(fromIRC: boolean = False): boolean;
var
  rls_name: String;
  respo: String;
  fHttpGetErrMsg: String;
  url: String;
begin
  Result := False;
  // Update asked from irc. Update and exit.
  if fromIRC then
  begin
    try
      Result := executeUpdate;
    except on E: Exception do
      irc_Adderror(Format('<c4>[EXCEPTION]</c> TTVInfoDB.Update (from IRC): %s', [e.Message]));
    end;
    exit;
  end;

  // Update from event
  // Note: variable will be overwriten by parseTVMazeInfos
  rls_name := self.ripname;
  Result := False;

  url := Format('https://api.tvmaze.com/shows/%s?embed[]=nextepisode&embed[]=previousepisode', [tvmaze_id]);
  if not HttpGetUrl(url, respo, fHttpGetErrMsg) then
  begin
    Debug(dpError, section, Format('[FAILED] TVMaze API Update: --> %s ', [fHttpGetErrMsg]));
    irc_Adderror(Format('<c4>[FAILED]</c> TVMaze API Update --> %s', [fHttpGetErrMsg]));
    exit;
  end;

  if ((respo = '') or (respo = '[]')) then
  begin
    irc_Adderror(Format('<c4>TTVInfoDB</c>: No Result from TVMaze API when updating %s', [tvmaze_id]));
    Exit;
  end;

  try
    self := parseTVMazeInfos(respo, '', url);
  except on e: Exception do
    begin
      irc_Adderror(Format('<c4>[EXCEPTION]</c> TTVInfoDB.Update: %s', [e.Message]));
      Debug(dpError, section, 'TTVInfoDB.Update: %s', [e.Message]);
      exit;
    end;
  end;

  try
    Result := executeUpdate;
  except on E: Exception do
    irc_Adderror(Format('<c4>[EXCEPTION]</c> TTVInfoDB.Update: %s', [e.Message]));
  end;

  try
    if Result then
      TVInfoFireKbAdd(rls_name, '<c9>[TVInfo]</c> Updated -> %s %s (%s)');
  except on E: Exception do
    begin
      Debug(dpError, section, Format('[EXCEPTION] TTVInfoDB.Update.fireKB: %s ', [e.Message]));
      irc_Adderror(Format('<c4>[EXCEPTION]</c> TTVInfoDB.Update.fireKB: %s', [e.Message]));
    end;
  end;
end;

{   misc                                       }

function getTVInfoCount: integer;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := 0;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('SELECT count(*) FROM infos');
      try
        fQuery.ExecutePrepared;
        if fQuery.Step then
          Result := fQuery.ColumnInt(0);
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] getTVInfoCount: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function getTVInfoSeriesCount: integer;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := 0;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('SELECT count(*) FROM series');
      try
        fQuery.ExecutePrepared;
        if fQuery.Step then
          Result := fQuery.ColumnInt(0);
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] getTVInfoSeriesCount: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function TheTVDbStatus: String;
begin
  Result := Format('<b>TVInfo.db</b>: %d Series, with %d infos', [getTVInfoSeriesCount, getTVInfoCount]);
end;

function deleteTVInfoByID(const aID: String): Integer;
var
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := 1;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('DELETE FROM infos WHERE tvmaze_id = ?');
      fQuery.BindTextS(1, aID);
      try
        fQuery.ExecutePrepared;
        if fQuery.UpdateCount = 0 then
          begin
            Result := 10;
            Exit;
          end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] deleteTVInfoByID infos: %s', [e.Message]));
          exit;
        end;
      end;

      // release the SQL statement, results and bound parameters before reopen
      fQuery.Reset;

      fQuery.Prepare('DELETE FROM series WHERE id = ?');
      fQuery.BindTextS(1, aID);
      try
        fQuery.ExecutePrepared;
        if fQuery.UpdateCount = 0 then
          begin
            Result := 11;
            Exit;
          end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] deleteTVInfoByID series: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function deleteTVInfoByRipName(const aName: String): Integer;
var
  fCount: integer;
  fQuery: TSqlDBSQLite3Statement;
begin
  fCount := 0;
  Result := 1;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('SELECT COUNT(*) FROM series WHERE rip = ?');
      fQuery.BindTextS(1, aName);
      try
        fQuery.ExecutePrepared;
        if fQuery.Step then
          Result := fQuery.ColumnInt(0);
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] deleteTVInfoByRipName COUNT(*): %s', [e.Message]));
          exit;
        end;
      end;

      // release the SQL statement, results and bound parameters before reopen
      fQuery.Reset;

      case fCount of
        0:
          begin
            result := 0;
            Exit;
          end;
        1:
          begin
            fQuery.Prepare('DELETE FROM series WHERE rip = ?');
            fQuery.BindTextS(1, aName);
            try
              fQuery.ExecutePrepared;
              if fQuery.UpdateCount = 0 then
                result := 12
              else
                result := 1;
            except
              on e: Exception do
              begin
                Debug(dpError, section, Format('[EXCEPTION] deleteTVInfoByRipName series: %s', [e.Message]));
              end;
            end;
            Exit;
          end;
        else
          begin
            fQuery.Prepare('SELECT id FROM series WHERE rip = ?');
            fQuery.BindTextS(1, aName);
            try
              fQuery.ExecutePrepared;
              if fQuery.Step then
                result := deleteTVInfoByID(fQuery.ColumnUtf8('id'))
              else
                result := 13;
            except
              on e: Exception do
              begin
                Debug(dpError, section, Format('[EXCEPTION] deleteTVInfoByRipName series: %s', [e.Message]));
              end;
            end;
            Exit;
          end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function getTVInfoByShowName(const aRls_Showname: String): TTVInfoDB;
var
  tvi: TTVInfoDB;
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := nil;

  if (aRls_Showname = '') then
  begin
    Debug(dpError, section, '[EXCEPTION] getTVInfoByShowName: rls_showname is empty');
    exit;
  end;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      // able to handle the aka's
      fQuery.Prepare('SELECT * FROM series LEFT JOIN infos ON infos.tvmaze_id = series.id WHERE rip LIKE ?');
      fQuery.BindTextS(1, aRls_Showname);
      try
        fQuery.ExecutePrepared;
        if fQuery.Step then
        begin
          if (LowerCase(aRls_Showname) <> LowerCase(fQuery.ColumnUtf8('rip'))) then
          begin
            Debug(dpError, section, 'getTVInfoByShowName LowerCase(%s) <> LowerCase(%s)', [aRls_Showname, fQuery.ColumnUtf8('rip')]);
            exit;
          end;

          tvi := TTVInfoDB.Create(aRls_Showname);

          tvi.tv_showname := fQuery.ColumnUtf8('showname');
          tvi.tv_url := fQuery.ColumnUtf8('tvmaze_url');
          tvi.tvmaze_id := fQuery.ColumnUtf8('id');
          tvi.thetvdb_id := fQuery.ColumnUtf8('tvdb_id');
          tvi.tvrage_id := fQuery.ColumnUtf8('tvrage_id');
          tvi.tv_premiered_year := StrToIntDef(fQuery.ColumnUtf8('premiered_year'), -1);
          tvi.tv_country := fQuery.ColumnUtf8('country');
          tvi.tv_status := fQuery.ColumnUtf8('status');
          tvi.tv_classification := fQuery.ColumnUtf8('classification');
          tvi.tv_network := fQuery.ColumnUtf8('network');
          tvi.tv_genres.CommaText := fQuery.ColumnUtf8('genre');
          tvi.tv_endedyear := StrToIntDef(fQuery.ColumnUtf8('ended_year'), -1);
          tvi.last_updated := StrToIntDef(fQuery.ColumnUtf8('last_updated'), -1);
          tvi.tv_next_date := StrToIntDef(fQuery.ColumnUtf8('next_date'), -1);
          tvi.tv_next_season := StrToIntDef(fQuery.ColumnUtf8('next_season'), -1);
          tvi.tv_next_ep := StrToIntDef(fQuery.ColumnUtf8('next_episode'), -1);
          tvi.tv_days.CommaText := fQuery.ColumnUtf8('airdays');
          tvi.tv_rating := StrToIntDef(fQuery.ColumnUtf8('rating'), 0);
          tvi.tv_language:= fQuery.ColumnUtf8('tv_language');

          tvi.tv_running := Boolean( (lowercase(tvi.tv_status) = 'running') or (lowercase(tvi.tv_status) = 'in development') );
          tvi.tv_scripted := Boolean(lowercase(tvi.tv_classification) = 'scripted');

          Result := tvi;
        end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] getTVInfoByShowName: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

function getTVInfoByReleaseName(const aRLS: String): TTVInfoDB;
var
  showname: String;
begin
  Result := nil;
  showname := aRLS;
  getShowValues(aRLS, showname);
  showname := ReplaceText(showname, '.', ' ');
  showname := ReplaceText(showname, '_', ' ');

  if (showname <> '') then
  begin
    Result := getTVInfoByShowName(showname);
  end;
end;

function getTVInfoByShowID(const aTVMazeID: String): TTVInfoDB;
var
  tvi: TTVInfoDB;
  fQuery: TSqlDBSQLite3Statement;
begin
  Result := nil;

  if (aTVMazeID = '') then
  begin
    Debug(dpError, section, '[EXCEPTION] getTVInfoByShowID: TVMaze ID is empty');
    exit;
  end;

  SQLite3Lock.Enter;
  try
    fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
    try
      fQuery.Prepare('SELECT * FROM series LEFT JOIN infos ON infos.tvmaze_id = series.id WHERE id = ?');
      fQuery.BindTextS(1, aTVMazeID);
      try
        fQuery.ExecutePrepared;
        if fQuery.Step then
        begin
          tvi := TTVInfoDB.Create(fQuery.ColumnUtf8('rip'));

          tvi.tv_showname := fQuery.ColumnUtf8('showname');
          tvi.tv_url := fQuery.ColumnUtf8('tvmaze_url');
          tvi.tvmaze_id := fQuery.ColumnUtf8('id');
          tvi.thetvdb_id := fQuery.ColumnUtf8('tvdb_id');
          tvi.tvrage_id := fQuery.ColumnUtf8('tvrage_id');
          tvi.tv_premiered_year := StrToIntDef(fQuery.ColumnUtf8('premiered_year'), -1);
          tvi.tv_country := fQuery.ColumnUtf8('country');
          tvi.tv_status := fQuery.ColumnUtf8('status');
          tvi.tv_classification := fQuery.ColumnUtf8('classification');
          tvi.tv_network := fQuery.ColumnUtf8('network');
          tvi.tv_genres.CommaText := fQuery.ColumnUtf8('genre');
          tvi.tv_endedyear := StrToIntDef(fQuery.ColumnUtf8('ended_year'), -1);
          tvi.last_updated := StrToIntDef(fQuery.ColumnUtf8('last_updated'), -1);
          tvi.tv_next_date := StrToIntDef(fQuery.ColumnUtf8('next_date'), 0); // why 0, -1 in getTVInfoByShowName?
          tvi.tv_next_season := StrToIntDef(fQuery.ColumnUtf8('next_season'), 0); // why 0, -1 in getTVInfoByShowName?
          tvi.tv_next_ep := StrToIntDef(fQuery.ColumnUtf8('next_episode'), 0); // why 0, -1 in getTVInfoByShowName?
          tvi.tv_days.CommaText := fQuery.ColumnUtf8('airdays');
          tvi.tv_rating := StrToIntDef(fQuery.ColumnUtf8('rating'), 0);
          tvi.tv_language:= fQuery.ColumnUtf8('tv_language');

          tvi.tv_running := Boolean( (lowercase(tvi.tv_status) = 'running') or (lowercase(tvi.tv_status) = 'in development') );
          tvi.tv_scripted := Boolean(lowercase(tvi.tv_classification) = 'scripted');

          Result := tvi;
        end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] getTVInfoByShowID: %s', [e.Message]));
          exit;
        end;
      end;
    finally
      fQuery.free;
    end;
  finally
    SQLite3Lock.Leave;
  end;
end;

procedure addTVInfos(const aParams: String);
var
  rls: String;
  tv_showid: String;
  dbtvinfo: TTVInfoDB;
begin
  rls := '';
  rls := SubString(aParams, ' ', 1);
  tv_showid := '';
  tv_showid := SubString(aParams, ' ', 2);

  if ((rls <> '') and (tv_showid <> '')) then
  begin
    dbtvinfo := getTVInfoByShowID(tv_showid);
    try
      if (dbtvinfo = nil) then
      begin
        if not LastAddtvmazeIDs.Contains(tv_showid) then
        begin
          // if the list grow to more than 50 items, delete the first 25
          if LastAddtvmazeIDs.Count > 50 then
          begin
            LastAddtvmazeIDs.DeleteRange(0, 25);
          end;
          LastAddtvmazeIDs.Add(tv_showid);

          // create an INSERT task for non existing show
          try
            AddTask(TPazoHTTPTVInfoTask.Create(tv_showid, rls));
          except
            on e: Exception do
            begin
              Debug(dpError, section, Format('[EXCEPTION] addTVInfos: %s', [e.Message]));
              exit;
            end;
          end;
        end
        else
        begin
          SlftpNewsAdd('TVMAZE', Format('Possible mismatch for <b>%s</b> with TVMaze ID <b>%s</b>', [rls, tv_showid]), True);
        end;
      end
      else if (DaysBetween(UnixToDateTime(dbtvinfo.last_updated), Now()) >= config.ReadInteger(section, 'days_between_last_update', 6)) then
      begin
        // UPDATE the show because our infos are too old
        if not dbtvinfo.Update then
        begin
          Debug(dpMessage, section, Format('[ERROR] updating of %s with ID %s failed.', [rls, tv_showid]));
        end;
      end;
    finally
      dbtvinfo.Free;
    end;
  end;
end;

procedure saveTVInfos(const TVMazeID: String; tvrage: TTVInfoDB; rls: String = ''; fireKb: boolean = True);
var
  save_tvrage: TTVInfoDB;
begin
    // add the tvinfo
    save_tvrage := TTVInfoDB(tvrage);
    try
      if (rls <> '') then
        irc_Addtext_by_key('ADDTVMAZEECHO', Format('%s %s %s', [addtinfodbcmd, rls, TVMazeID]));
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] saveTVInfos irc_Addtext_by_key: %s', [e.Message]));
        exit;
      end;
    end;

    try
      save_tvrage.Save;
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] saveTVInfos Save: %s ', [e.Message]));
      end;
    end;

    if ((rls <> '') and (fireKb)) then
      TVInfoFireKbAdd(rls);
end;

procedure TVInfoFireKbAdd(const aRls: String; msg: String = '<c3>[TVInfo]</c> %s %s now has TV infos (%s)');
var
  p: TPazo;
  ps: TPazoSite;
begin
  p := FindPazoByRls(aRls);
  if (p <> nil) then
  begin
    ps := FindMostCompleteSite(p);
    if ((ps = nil) and (p.PazoSitesList.Count > 0)) then
      ps := TPazoSite(p.PazoSitesList[0]);

    if (ps <> nil) then
    begin
      try
        if spamcfg.ReadBool('addinfo', 'tvinfoupdate', True) then
          irc_SendUPDATE(Format(msg, [p.rls.section, p.rls.rlsname, ps.Name]));

        kb_Add('', '', ps.Name, p.rls.section, '', kbeUPDATE, p.rls.rlsname, '');
      except
        on e: Exception do
        begin
          Debug(dpError, section, '[EXCEPTION] TVInfoFireKbAdd kb_Add: %s', [e.Message]);
        end;
      end;
    end;
  end;
end;

procedure dbTVInfoStart;
const
  CurrentDbVersion: integer = 4;
var
  fDBName: String;
  fUserVersion: integer;
  fQuery: TSqlDBSQLite3Statement;
begin
  fUserVersion := -1;
  SQLite3Lock := TCriticalSection.Create;

  fDBName := Trim(config.ReadString(section, 'database', 'tvinfos.db'));
  tvinfoSQLite3DBCon := CreateSQLite3DbConn(fDBName, '');

  {* db version code *}
  fQuery := TSqlDBSQLite3Statement.Create(tvinfoSQLite3DBCon.ThreadSafeConnection);
  try
    // retrieve current db version
    fQuery.Prepare('PRAGMA user_version');
    try
      fQuery.ExecutePrepared;
      if fQuery.Step then
        fUserVersion := StrToIntDef(fQuery.ColumnUtf8(0), -1);

      // release the SQL statement, results and bound parameters before reopen
      fQuery.Reset;

      // decide whether we have to update the db version
      case fUserVersion of
       -1:
          begin
            Debug(dpError, section, Format('Cannot load PRAGMA user_version from %s', [fDBName]));
            exit;
          end;
        0:
          begin
            fQuery.Prepare(Format('PRAGMA user_version = %d', [CurrentDbVersion]));
            fQuery.ExecutePrepared;
          end;
        2:
          begin
            fQuery.Prepare('ALTER TABLE infos ADD COLUMN tv_language TEXT');
            fQuery.ExecutePrepared;

            // release the SQL statement, results and bound parameters before reopen
            fQuery.Reset;

            fQuery.Prepare('PRAGMA user_version = 3');
            fQuery.ExecutePrepared;
          end;
        3:
          begin
            fQuery.Prepare('ALTER TABLE infos ADD COLUMN rating INTEGER');
            fQuery.ExecutePrepared;

            // release the SQL statement, results and bound parameters before reopen
            fQuery.Reset;

            fQuery.Prepare('PRAGMA user_version = 4');
            fQuery.ExecutePrepared;
          end;
      end;
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbTVInfoStart: %s', [e.Message]));
        exit;
      end;
    end;
  finally
    fQuery.free;
  end;

  {* Create tables and indexes if they don't exist (new file) *}
  // series table
  tvinfoSQLite3DBCon.MainSQLite3DB.Execute(
    'CREATE TABLE IF NOT EXISTS series(' +
      'rip TEXT NOT NULL,' +
      'showname TEXT NOT NULL,' +
      'rip_country TEXT,' +
      'tvmaze_url TEXT,' +
      'id INTEGER NOT NULL,' +
      'PRIMARY KEY (rip)' +
    ');'
  );

  // infos table
  tvinfoSQLite3DBCon.MainSQLite3DB.Execute(
    'CREATE TABLE IF NOT EXISTS infos(' +
      'tvdb_id INTEGER,' +
      'tvrage_id INTEGER,' +
      'tvmaze_id INTEGER NOT NULL,' +
      'premiered_year INTEGER NOT NULL,' +
      'country TEXT NOT NULL DEFAULT unknown,' +
      'status  TEXT NOT NULL DEFAULT unknown,' +
      'classification TEXT NOT NULL DEFAULT unknown,' +
      'network TEXT NOT NULL DEFAULT unknown,' +
      'genre TEXT NOT NULL DEFAULT unknown,' +
      'ended_year INTEGER,' +
      'last_updated INTEGER NOT NULL DEFAULT -1,' +
      'next_date INTEGER,' +
      'next_season INTEGER,' +
      'next_episode INTEGER,' +
      'rating INTEGER,' +
      'airdays TEXT,' +
      'tv_language TEXT,' +
      'PRIMARY KEY (tvmaze_id ASC)' +
    ');'
  );

  // indexes
  tvinfoSQLite3DBCon.MainSQLite3DB.Execute('CREATE UNIQUE INDEX IF NOT EXISTS main.tvinfo ON infos (tvmaze_id ASC);');
  tvinfoSQLite3DBCon.MainSQLite3DB.Execute('CREATE UNIQUE INDEX IF NOT EXISTS main.Rips ON series (rip ASC);');

  LastAddtvmazeIDs := TList<String>.Create;

  Console_Addline('', Format('TVInfo db loaded. %d Series, with %d infos', [getTVInfoSeriesCount, getTVInfoCount]));
end;

procedure dbTVInfoInit;
begin
  addtinfodbcmd := config.ReadString(section, 'addcmd', '!addtvmaze');
end;

procedure dbTVInfoUninit;
begin
  if Assigned(SQLite3Lock) then
  begin
    FreeAndNil(SQLite3Lock);
  end;

  if Assigned(tvinfoSQLite3DBCon) then
  begin
    FreeAndNil(tvinfoSQLite3DBCon);
  end;

  if Assigned(LastAddtvmazeIDs) then
  begin
    FreeAndNil(LastAddtvmazeIDs);
  end;
end;

function dbTVInfo_Process(const aNet, aChan, aNick: String; aMSG: String): boolean;
begin
  Result := False;
  if (1 = Pos(addtinfodbcmd, aMSG)) then
  begin
    aMSG := Copy(aMSG, length(addtinfodbcmd + ' ') + 1, 1000);
    addTVInfos(aMSG);
    Result := True;
  end;
end;

function TVInfoDbAlive: boolean;
begin
  if tvinfoSQLite3DBCon = nil then
    Result := false
  else
    Result := true;
end;

end.

