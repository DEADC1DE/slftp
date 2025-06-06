unit dbaddimdb;

interface

uses Classes, IniFiles, irc, Contnrs, SyncObjs, Generics.Collections;

type
  { @abstract(Class for information from each single line of the slftp.imdbcountries file) }
  TMapLanguageCountry = class
  private
    FLanguage: String; //< language
    FCountryCode: String; //< country code (for backward compatibility of the existing file, not really needed at the moment)
    FCountry: String; //< country name
  public
    { Creates a class with the given information }
    constructor Create(const aLanguage, aCountryCode, aCountry: String);

    { Returns the Countryname for a given Language
      @param(aLanguage Name of Language)
      @returns(Countryname @br @note(empty string if Language->Country does not exist)) }
    class function GetCountrynameByLanguage(const aLanguage: String): String;

    property Language: String read FLanguage;
    property CountryCode: String read FCountryCode;
    property Country: String read FCountry;
  end;

  TDbImdb = class
    rls: String;
    imdb_id: String;
    constructor Create(rls, imdb_id: String);
    destructor Destroy; override;
  end;

  TDbImdbData = class
    imdb_id: String;
    imdb_year: Integer;
    imdb_languages: TStringList;
    imdb_countries: TStringList;
    imdb_genres: TStringList;
    imdb_screens: Integer;
    imdb_rating: Integer;
    imdb_votes: Integer;
    imdb_cineyear:integer;
    imdb_ldt:boolean;
    imdb_wide:boolean;
    imdb_festival:boolean;
    imdb_stvm:boolean;
    imdb_stvs:String;
    imdb_type:String;
    // additional infos
    imdb_origtitle: String; //< original imdb/movie title
    constructor Create(imdb_id :String);
    destructor Destroy; override;
    procedure PostResults(rls : String = '');overload;
    procedure PostResults(const netname, channel: String; rls : String = '');overload;
  end;

{ Checks if Country should be excluded (doesn't exist in slftp.imdbcountries file)
  @param(aCountryname Name of Country to be checked)
  @returns(@true if no entry exists in file (exclude), @false otherwise) }
function ExcludeCountry(const aCountryname: String): Boolean;

function dbaddimdb_Process(net, chan, nick, msg: String): Boolean;
procedure dbaddimdb_SaveImdb(rls, imdb_id: String);
procedure dbaddimdb_SaveImdbData(rls: String; imdbdata: TDbImdbData);
procedure dbaddimdb_addimdb(params: String);
procedure dbaddimdb_ParseImdb(rls, imdb_id: String);
procedure dbaddimdb_FireKbAdd(rls : String);

function dbaddimdb_Status: String;
function dbaddimdb_checkid(const imdbid: String): Boolean;
function dbaddimdb_parseid(const text: String; out imdbid: String): Boolean;

procedure dbaddimdbInit;
procedure dbaddimdbStart;
procedure dbaddimdbUnInit;

var
  last_addimdb: THashedStringList;
  last_imdbdata: THashedStringList;
  dbaddimdb_cs: TCriticalSection;

implementation

uses DateUtils, SysUtils, configunit, mystrings, FLRE, kb, kb.releaseinfo,
  queueunit, RegExpr, debugunit, taskhttpimdb, pazo, mrdohutils, dbtvinfo;

const
  section = 'dbaddimdb';

var
  rx_imdbid: TFLRE;
  rx_captures: TFLREMultiCaptures;
  addimdbcmd: String;
  glLanguageCountryMappingList: TObjectList<TMapLanguageCountry>;

{ TMapLanguageCountry }

constructor TMapLanguageCountry.Create(const aLanguage, aCountryCode, aCountry: String);
begin
  FLanguage := aLanguage;
  FCountryCode := aCountryCode;
  FCountry := aCountry;
end;

class function TMapLanguageCountry.GetCountrynameByLanguage(const aLanguage: String): String;
var
  fItem: TMapLanguageCountry;
begin
  Result := '';
  for fItem in glLanguageCountryMappingList do
  begin
    if fItem.FLanguage = aLanguage then
      Exit(fItem.Country);
  end;
end;

{ TDbImdb }
constructor TDbImdb.Create(rls, imdb_id: String);
begin
  self.rls := rls;
  self.imdb_id := imdb_id;
end;

destructor TDbImdb.Destroy;
begin
  inherited;
end;

{ TDbImdbData }
constructor TDbImdbData.Create(imdb_id:String);
begin
  self.imdb_id := imdb_id;
  imdb_languages:= TStringList.Create;
  imdb_countries:= TStringList.Create;
  imdb_genres:= TStringList.Create;
end;

destructor TDbImdbData.Destroy;
begin
  imdb_languages.Free;
  imdb_countries.Free;
  imdb_genres.Free;
  inherited;
end;

procedure TDbImdbData.PostResults(rls : String = '');
var status:String;
begin

  if imdb_stvm then status := 'STV'
  else if imdb_festival then status := 'Festival'
  else if imdb_ldt then status := 'Limited'
  else if imdb_wide then status := 'Wide'
  else status :='Cine';

  irc_Addstats(Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c0><b>for : %s</b></c> .......: https://www.imdb.com/title/%s/',[rls, imdb_id]));
  irc_Addstats(Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c0><b>Original Title - Year</b></c> ...: %s (%d)',[imdb_origtitle, imdb_year]));
  irc_Addstats(Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <b><c9>Country - Languages</b></c> ..: %s - %s',[imdb_countries.DelimitedText,imdb_languages.DelimitedText]));
  irc_Addstats(Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <b><c5>Genres</b></c> .........: %s', [imdb_genres.DelimitedText]));
  irc_Addstats(Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c7><b>Rating</b>/<b>Type</b></c> ....: <b>%d</b> of 100 (%d) @ %d Screens (%s) | Type: %s',[imdb_rating,imdb_votes,imdb_screens,status,imdb_type]));
end;

procedure TDbImdbData.PostResults(const netname, channel: String; rls : String = '');
var status:String;
begin
  if imdb_stvm then status := 'STV'
  else if imdb_festival then status := 'Festival'
  else if imdb_ldt then status := 'Limited'
  else if imdb_wide then status := 'Wide'
  else status :='Cine';

  irc_AddText(netname, channel, Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c0><b>for : %s</b></c> .......: https://www.imdb.com/title/%s/',[rls, imdb_id]));
  irc_AddText(netname, channel, Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c0><b>Original Title - Year</b></c> ...: %s (%d)',[imdb_origtitle, imdb_year]));
  irc_AddText(netname, channel, Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <b><c9>Country - Languages</b></c> ..: %s - %s',[imdb_countries.DelimitedText,imdb_languages.DelimitedText]));
  irc_AddText(netname, channel, Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <b><c5>Genres</b></c> .........: %s', [imdb_genres.DelimitedText]));
  irc_AddText(netname, channel, Format('(<c9>i</c>).....<c2><b>IMDB</b></c>........ <c7><b>Rating</b>/<b>Type</b></c> ....: <b>%d</b> of 100 (%d) @ %d Screens (%s) | Type: %s',[imdb_rating,imdb_votes,imdb_screens,status,imdb_type]));
end;

function ExcludeCountry(const aCountryname: String): Boolean;
var
  fItem: TMapLanguageCountry;
begin
  Result := True;
  for fItem in glLanguageCountryMappingList do
  begin
    if (fItem.Country = 'UK') or (fItem.Country = 'USA') then
    begin
      // to avoid matching Ukraine with UK
      if aCountryname.StartsWith(fItem.Country, False) then
        Exit(False);
    end
    else
    begin
      // match things like 'Canada (French title)' and 'Canada (English title)'
      if aCountryname.StartsWith(fItem.Country, True) then
        Exit(False);
    end;
  end;
end;

function dbaddimdb_Process(net, chan, nick, msg: String): Boolean;
begin
  Result := False;
  if (1 = Pos(addimdbcmd, msg)) then
  begin
    msg := Copy(msg, length(addimdbcmd + ' ') + 1, 1000);
    dbaddimdb_addimdb(msg);
    Result := True;
  end;
end;

procedure dbaddimdb_addimdb(params: String);
var
  rls: String;
  imdb_id: String;
  i: Integer;
begin
  rls := '';
  rls := SubString(params, ' ', 1);
  imdb_id := '';
  imdb_id := SubString(params, ' ', 2);

  if not dbaddimdb_checkid(imdb_id) then
  begin
    Debug(dpSpam, section, '[ADDIMDB] Invalid IMDB ID for %s: %s', [rls, imdb_id]);
    exit;
  end;

  if ((rls <> '') and (imdb_id <> '')) then
  begin
    dbaddimdb_cs.Enter;
    try
      i:= last_addimdb.IndexOf(rls);
    finally
      dbaddimdb_cs.Leave;
    end;

    if i <> -1 then
    begin
      exit;
    end;

    try
      dbaddimdb_SaveImdb(rls, imdb_id);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('Exception in dbaddimdb_addimdb (SaveImdb): %s', [e.Message]));
        exit;
      end;
    end;
  end;
end;

procedure dbaddimdb_SaveImdb(rls, imdb_id: String);
var
  i: Integer;
  db_imdb: TDbImdb;
  showname: String;
  season: Integer;
  episode: int64;
begin
  if config.ReadBool(section, 'skip_tv_releases', false) then
  begin
    getShowValues(rls, showname, season, episode);
    (*
      if getShowValues does not find tv-related info for rls then showname will
      contain the same value as rls, otherwise it will contain a (shorter)
      showname. season and/or episode will be set if the release is tv-related.
    *)
    if (rls <> showname) and ((season > 0) or (episode > 0)) then
      exit;
  end;

  dbaddimdb_cs.Enter;
  try
    i:= last_addimdb.IndexOf(rls);
  finally
    dbaddimdb_cs.Leave;
  end;
  if i = -1 then
  begin
    db_imdb := TDbImdb.Create(rls, imdb_id);

    dbaddimdb_cs.Enter;
    try
      try
        last_addimdb.AddObject(rls, db_imdb);
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdb (AddObject): %s', [e.Message]));
          exit;
        end;
      end;
    finally
      dbaddimdb_cs.Leave;
    end;

    irc_AddInfo(Format('<c7>[iMDB]</c> for <b>%s</b> : %s', [rls, imdb_id]));
    irc_Addtext_by_key('ADDIMDBECHO', '!addimdb '+rls+' '+imdb_id);

    try
      dbaddimdb_ParseImdb(rls, imdb_id);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdb (Parse): %s', [e.Message]));
        exit;
      end;
    end;

    dbaddimdb_cs.Enter;
    try
      i:= last_addimdb.Count;
      try
        while i > 100 do
        begin
          last_addimdb.Delete(0);
          i:= last_addimdb.Count - 1;
        end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdb (cleanup): %s', [e.Message]));
          exit;
        end;
      end;
    finally
      dbaddimdb_cs.Leave;
    end;
  end;
end;

procedure dbaddimdb_SaveImdbData(rls: String; imdbdata: TDbImdbData);
var
  i: Integer;
begin
  dbaddimdb_cs.Enter;
  try
    i:= last_imdbdata.IndexOf(rls);
  finally
    dbaddimdb_cs.Leave;
  end;

  if i = -1 then
  begin
    dbaddimdb_cs.Enter;
    try
      try
        last_imdbdata.AddObject(rls, imdbdata);
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdbData (AddObject): %s', [e.Message]));
          exit;
        end;
      end;
    finally
      dbaddimdb_cs.Leave;
    end;

    if config.ReadBool(section, 'post_lookup_infos', false) then
    begin
      irc_AddInfo(Format('<c7>[iMDB Data]</c> for <b>%s</b> : %s', [rls, imdbdata.imdb_id]));
      imdbdata.PostResults(rls);
    end;

    try
      dbaddimdb_FireKbAdd(rls);
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdbData (FireKbAdd): %s', [e.Message]));
        exit;
      end;
    end;

    dbaddimdb_cs.Enter;
    try
      i:= last_imdbdata.Count;
      try
        while i > 100 do
        begin
          last_imdbdata.Delete(0);
          i:= last_imdbdata.Count - 1;
        end;
      except
        on e: Exception do
        begin
          Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_SaveImdbData (cleanup): %s', [e.Message]));
          exit;
        end;
      end;
    finally
      dbaddimdb_cs.Leave;
    end;
  end;
end;

procedure dbaddimdb_ParseImdb(rls, imdb_id: String);
begin
  try
    AddTask(TPazoHTTPImdbTask.Create(imdb_id, rls));
  except
    on e: Exception do
    begin
      Debug(dpError, section, Format('Exception in dbaddimdb_SaveImdbRls AddTask: %s', [e.Message]));
      exit;
    end;
  end;
end;

procedure dbaddimdb_FireKbAdd(rls : String);
var p : TPazo;
    ps: TPazoSite;
begin
  try
    p:= FindPazoByRls(rls);
    if (p <> nil) then
    begin
      if p.rls is TIMDBRelease then
      begin
        p.rls.Aktualizal(p);
        ps := FindMostCompleteSite(p);
        if ((ps = nil) and (p.PazoSitesList.Count > 0)) then
          ps:= TPazoSite(p.PazoSitesList[0]);

        if (ps <> nil) then
        begin
          if spamcfg.ReadBool('addinfo','imdbupdate',True) then
            irc_SendUPDATE(Format('<c3>[ADDIMDB]</c> %s %s now has iMDB infos (%s)', [p.rls.section, p.rls.rlsname, ps.name]));
          kb_Add('', '', ps.name, p.rls.section, '', kbeUPDATE, p.rls.rlsname, '');
        end;
      end;
    end;
  except
    on e: Exception do
    begin
      Debug(dpError, section, '[EXCEPTION] dbaddimdb_FireKbAdd : %s', [e.Message]);
    end;
  end;
end;

{ Checkid }
function dbaddimdb_checkid(const imdbid: String): Boolean;
begin
  Result := False;
  dbaddimdb_cs.Enter;
  try
    try
      if rx_imdbid.Find(imdbid) <> 0 then
        Result := True;
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_checkid: Exception : %s', [e.Message]));
        exit;
      end;
    end;
  finally
    dbaddimdb_cs.Leave;
  end;
end;

{ Parseid }
function dbaddimdb_parseid(const text: String; out imdbid: String): Boolean;
begin
  imdbid := '';
  Result := False;
  try
    dbaddimdb_cs.Enter;
    try
      if rx_imdbid.MatchAll(text, rx_captures, 1 ,1) then
      begin
        imdbid := Copy(text, rx_captures[0][0].Start, rx_captures[0][0].Length);
        Result := True;
      end;
    except
      on e: Exception do
      begin
        Debug(dpError, section, Format('[EXCEPTION] dbaddimdb_checkid: Exception : %s', [e.Message]));
        exit;
      end;
    end;
  finally
    SetLength(rx_captures, 0);
    dbaddimdb_cs.Leave;
  end;
end;


{ Status }
function dbaddimdb_Status: String;
begin
  Result := Format('<b>iMDB</b>: %d, <b>iMDB data</b>: %d',[last_addimdb.Count, last_imdbdata.Count]);
end;

{ Init }

procedure dbaddimdbInit;
var
  fStrList: TStringList;
  i, j: Integer;
  fLang, fCC, fCountry, fHelper: String;
  fItem: TMapLanguageCountry;
  fDupe: Boolean;
begin
  dbaddimdb_cs := TCriticalSection.Create;
  last_addimdb:= THashedStringList.Create;
  last_addimdb.CaseSensitive:= False;
  last_addimdb.OwnsObjects:= True;
  last_imdbdata:= THashedStringList.Create;
  last_imdbdata.CaseSensitive:= False;
  last_imdbdata.OwnsObjects := True;
  rx_imdbid := TFLRE.Create('tt(\d{6,8})', [rfIGNORECASE]);
  glLanguageCountryMappingList := TObjectList<TMapLanguageCountry>.Create(True);
  fStrList := TStringList.Create;
  try
    fStrList.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'slftp.imdbcountries');
    for i := 0 to fStrList.Count - 1 do
    begin
      (* ignore inifile section and comments *)
      if fStrList.Strings[i].StartsWith('[') then
        Continue;
      if fStrList.Strings[i].Contains('//') then
        Continue;
      if fStrList.Strings[i].Contains('#') then
        Continue;

      fLang := Trim(SubString(fStrList.Strings[i], '=', 1));
      fHelper := SubString(fStrList.Strings[i], '=', 2);
      fCC := Trim(SubString(fHelper, ',', 1));
      fCountry := Trim(SubString(fHelper, ',', 2));

      fDupe := False;
      for fItem in glLanguageCountryMappingList do
      begin
        // IMDb and BOM differ for that language, see config file
        if fLang = 'Czech' then
          Continue;
        if fItem.Language = fLang then
        begin
          Debug(dpError, section, Format('Ignoring language %s with country %s-%s from slftp.imdbcountries because it already exists', [fLang, fCC, fCountry]));
          fDupe := True;
        end;
      end;

      if fDupe then
        Continue;

      glLanguageCountryMappingList.Add(TMapLanguageCountry.Create(fLang, fCC, fCountry));
    end;
  finally
    fStrList.Free;
  end;
end;

procedure dbaddimdbStart;
begin
  addimdbcmd := config.ReadString(section, 'addimdbcmd', '!addimdb');
end;

procedure dbaddimdbUninit;
begin
  glLanguageCountryMappingList.Free;
  dbaddimdb_cs.Enter;
  try
    FreeAndNil(last_addimdb);
    FreeAndNil(last_imdbdata);
    FreeAndNil(rx_imdbid);
  finally
    dbaddimdb_cs.Leave;
  end;
  dbaddimdb_cs.Free;
end;

end.


