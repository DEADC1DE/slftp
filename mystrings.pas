{*****************************************************************************

 - Soulless robotic engine aka SLFTP
 - Version 1.3

 - Remarks:          Freeware, Copyright must be included

 - Original Author:  believe

 - Modifications:    aKRAUT aka dOH

 - Last change:      27/06/2010 - Added DateAsString(secs) give a pretime known result

 - Description:      Just a copy of the some std. delphi strings i guess........


 ****************************************************************************

 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY EXPRESS       *
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED        *
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE       *
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE        *
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR      *
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF     *
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR          *
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,    *
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE     *
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,        *
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                       *

*****************************************************************************}

{ @abstract(Implementations of own (sub-)functions)
  Mostly own implementations of functions which are not included in RTL }

unit mystrings;

interface

uses
  SysUtils, Classes, Generics.Defaults, Generics.Collections;

{$include htmlChars.inc}

type
  {
    @abstract(generic TEnum helper class for typesafe usage of enumerations
    from http://softwareonastring.com/147/how-to-store-enums-without-losing-your-coding-freedom)
  }
  TEnum<T> = class(TObject)
  public
  { Converts an enumeration element from the enumerated type to string
    @param(aEnumValue element of enumeration type)
    @returns(Name of enumeration as string) }
    class function ToString(const aEnumValue: T): string; reintroduce; inline; static;
  { Converts a string to an enumeration element from the enumerated type
    @param(aEnumString Name of enum element which should be converted)
    @param(aDefault element of enumeration type which should be used if conversion doesn't work)
    @returns(enumeration element from the enumerated type) }
    class function FromString(const aEnumString: string; const aDefault: T): T; inline; static;
  end;

{ Helper function to create a case-insensitive string comparer for classes like TDictionary
  NOTE: needed because current implementation on FPC causes access violation
  @returns(case-insensitive string comparer class) }
function GetCaseInsensitveStringComparer: IEqualityComparer<String>;

{ Creates a base64 encoded string from @link(aInput)
  @param(aInput String which should be encoded)
  @returns(Base64 encoded String (does an automatic UTF8 1-byte string conversion)) }
function DoBase64Encode(const aInput: String): String; overload; inline;

{ Creates a base64 encoded string from @link(aInput)
  @param(aInput Bytearray which should be encoded)
  @returns(Base64 encoded String (does an automatic UTF8 1-byte string conversion)) }
function DoBase64Encode(const aInput: TBytes): String; overload; inline;

{ Creates a base64 decoded string from @link(aInput)
  @param(aInput String which should be decoded)
  @returns(Base64 decoded String (does an automatic UTF8 1-byte string conversion)) }
function DoBase64DecodeToString(const aInput: String): String; inline;

{ Creates a base64 decoded Bytearray from @link(aInput)
  @param(aInput String which should be decoded (does an automatic UTF8 1-byte string conversion))
  @returns(Base64 decoded Bytearray) }
function DoBase64DecodeToBytes(const aInput: String): TBytes; inline;

{ Remove all non/special characters from String
  @param(S String which should be cleaned)
  @returns(String which only contains characters as [a-z] or [A-Z]) }
function onlyEnglishAlpha(const S: String): String;
function DateTimeAsString(const aThen: TDateTime; padded: boolean = False): String;

{ Normal RTL function RightStr('Hello, world!', 5): 'orld!''
  This function RightStr('Hello, world!', 5): ', world!' }
function RightStr(const Source: String; Count: integer): String;
function SubString(const s, seperator: String; index: integer): String;
function Count(const mi, miben: String): integer;
function RPos(const SubStr: Char; const Str: String): integer;
function MyStrToTime(const x: String): TDateTime;

{ Converts input Datetime to String with 'yyyy-mm-dd hh:nn:ss' formatting
  @param(x input TDateTime)
  @returns(String formatted as 'yyyy-mm-dd hh:nn:ss') }
function MyDateToStr(const x: TDateTime): String;
function MyStrToDate(const x: String): TDateTime;
function myStrToFloat(s: String; const def: double): double;
function ParseResponseCode(s: String): integer;

{ Adds '/' to end of dir if it's missing or returns '/' if empty string
  @param(s input dir)
  @returns(Input dir with appended '/' if it was missing or just '/' if empty string) }
function MyIncludeTrailingSlash(const s: String): String;

{ extracts data from ftpd PASV reply
  @param(s (ip,ip,ip,ip,port,port) reply)
  @param(host extracted host IP)
  @param(port extracted port)
  @returns(@true if host and port successful extracted, @false otherwise) }
function ParsePASVString(s: String; out host: String; out port: integer): boolean;

{ Extracts needed information from FTPd EPSV response to start a transfer
  @param(aFTPdResponse complete 229 EPSV response)
  @param(aHost extracted host address)
  @param(aPort extracted port)
  @param(aIPv4Transfermode @true if IP address is IPv4, @false if IPv6)
  @returns(@true if host, port and transfermode are successful extracted, @false otherwise) }
function ParseEPSVString(const aFTPdResponse: String; out aHost: String; out aPort: Integer; out aIPv4Transfermode: Boolean): Boolean;

{ Parses the X-DUPE response and writes the extracted filenames to a list
  @param(aResponseText X-DUPE response text from ftpd)
  @param(aFileList initialised list of strings where the filenames will be added to)
  @returns(@true if at least one filename was extracted, @false otherwise) }
function ParseXDupeResponseToFilenameList(const aResponseText: String; const aFileList: TList<String>): Boolean;

{ checks if c is a letter (case-insensitive)
  @param(c Character which should be checked)
  @returns(@true if it's a letter: [a-z] or [A-Z], @false otherwise) }
function IsALetter(const c: Char): boolean;
{ checks if c is a number
  @param(c Character which should be checked)
  @returns(@true if it's a number: [0-9], @false otherwise) }
function IsANumber(const c: Char): boolean;

{ Counts the number of occurrences of numbers in String
  @param(S String which should be used to search in)
  @returns(Count of occurrences of numbers) }
function OccurrencesOfNumbers(const S: string): Integer;

function FetchSL(var aInputText: String; const Args: array of Char): String;

{ Gets the first line from input by searching for \r and/or \n (newline indicators)
  @param(aInputText Input text where first line will be picked from and also removed)
  @returns(first line before \r and/or \n) }
function GetFirstLineFromTextViaNewlineIndicators(var aInputText: String): String;

{ Replaces datum identifiers like <yyyy>, <mm> or <dd> with the given value for aDatum (if zero, uses current time)
  @param(aSrcString source string with <yyyy>, <yy>, <mm>, <dd> or <ww>)
  @param(aDatum datetime value or if zero, uses Now() to create current time value)
  @returns(replaced datum identifier string with given paramters) }
function DatumIdentifierReplace(const aSrcString: String; aDatum: TDateTime = 0): String;

{ Clears Stringlist @link(Dest) and splits @link(Source) by @link(Delimiter) to add each String separately to Stringlist
  @param(Source String which should be splitted)
  @param(Delimiter String which should be used to split @link(Source))
  @param(Dest Stringlist with the separated Strings from @link(Source)) }
procedure SplitString(const Source: String; const Delimiter: String; const Dest: TStringList);

procedure RecalcSizeValueAndUnit(var size: double; out sizevalue: String; StartFromSizeUnit: Integer = 0);

{ Parses a FTP stat line finding and splitting Credits and Ratio
  @param(aStatLine "site stat" line which should be parsed to extract credits and ratio)
  @param(aCredits Credits (two decimal places) with unit, removes locale delimited and replaces it with a dot)
  @param(aRatio Ratio as seen in the "site stat" output with the exception of 1:0 being returned as the string "Unlimited") }
procedure ParseSTATLine(const aStatLine: String; out aCredits, aRatio: String);

{ Parses a FTP "site search" result returning the found paths
  @param(aSearchResult FTP response from a "site search" command)
  @param(aRlsToSearch The rls name it was searched for)
  @returns(Paths on the site where the given release was found.) }
function ParsePathFromSiteSearchResult(const aSearchResult, aRlsToSearch: String): String;

{ Converts the punctuation, international and other special characters in a moviename into scene-notation used for release tagging
  @param(aInput Name of the Movie)
  @returns(Moviename in scene notation) }
function InternationalCharsToAsciiSceneChars(const aInput: String): String;

function ParseSFV(aSFV: string): TDictionary<string, integer>;
function IsRarExtension(const aExtension: string): boolean;

{ Decodes HTML tags like &amp; to the actual chars
  @param(aText HTML text to decode)
  @returns(Decoded HTML text) }
function HTMLDecode(const aText: string): string;

implementation

uses
  {$IFDEF FPC}
    base64,
  {$ELSE}
    NetEncoding,
  {$ENDIF}
  Math, StrUtils, typinfo, rtti,
  {$IFDEF MSWINDOWS}
    registry, Windows,
  {$ENDIF}
  DateUtils, IdGlobal, debugunit, RegExpr, configunit;

const
  section = 'mystrings';

class function TEnum<T>.ToString(const aEnumValue: T): string;
begin
  {$IFDEF FPC}
    Result := GetEnumName(TypeInfo(T), integer(aEnumValue));
  {$ELSE}
    Result := GetEnumName(TypeInfo(T), TValue.From<T>(aEnumValue).AsOrdinal);
  {$ENDIF}
end;

class function TEnum<T>.FromString(const aEnumString: string; const aDefault: T): T;
var
  OrdValue: Integer;
begin
  OrdValue := GetEnumValue(TypeInfo(T), aEnumString);
  if OrdValue > -1 then
  {$IFDEF FPC}
    Result := T(OrdValue)
  {$ELSE}
    Result := TValue.FromOrdinal(TypeInfo(T), OrdValue).AsType<T>
  {$ENDIF}
  else
    Result := aDefault;
end;

{* Only needed because TIStringComparer.Ordinal causes access violation in FPC
   https://lists.freepascal.org/fpc-pascal/2016-August/048648.html *}
{$IFDEF FPC}
  function EqualityComparisonCaseInsensitive(constref ALeft, ARight: String): Boolean;
  begin
    Result := LowerCase(ALeft) = LowerCase(ARight);
  end;

  function ExtendedHasher(constref AValue: String): UInt32;
  var
    temp: String;
  begin
    temp := LowerCase(AValue);
    Result := TDefaultHashFactory.GetHashCode(Pointer(temp), Length(temp) * SizeOf(Char), 0);
  end;
{$ENDIF}

function GetCaseInsensitveStringComparer: IEqualityComparer<String>;
begin
  {$IFDEF FPC}
    Result := TEqualityComparer<String>.Construct(EqualityComparisonCaseInsensitive, ExtendedHasher);
  {$ELSE}
    Result := TIStringComparer.Ordinal;
  {$ENDIF}
end;

{$IFDEF UNICODE}
  { Removes default MIME linebreak after 76 chars }
  procedure RemoveMIMELinebreak(var aInput: String); inline;
  begin
    aInput := aInput.Replace(sLineBreak, '', [rfReplaceAll, rfIgnoreCase]);
  end;
{$ENDIF}

function DoBase64Encode(const aInput: String): String;
begin
  {$IFDEF UNICODE}
    Result := TNetEncoding.Base64.Encode(aInput);
    RemoveMIMELinebreak(Result);
  {$ELSE}
    Result := EncodeStringBase64(aInput);
  {$ENDIF}
end;

function DoBase64Encode(const aInput: TBytes): String;
begin
  {$IFDEF UNICODE}
    Result := TNetEncoding.Base64.EncodeBytesToString(aInput);
    RemoveMIMELinebreak(Result);
  {$ELSE}
    SetLength(Result, Length(aInput));
    move(aInput[0], Result[1], Length(aInput));

    Result := DoBase64Encode(Result);
  {$ENDIF}
end;

function DoBase64DecodeToString(const aInput: String): String;
begin
  {$IFDEF UNICODE}
    Result := TNetEncoding.Base64.Decode(UTF8Encode(aInput));
  {$ELSE}
    Result := DecodeStringBase64(aInput);
  {$ENDIF}
end;

function DoBase64DecodeToBytes(const aInput: String): TBytes;
{$IFNDEF UNICODE}
  var
    fStrHelper: String;
{$ENDIF}
begin
  {$IFDEF UNICODE}
    Result := TNetEncoding.Base64.DecodeStringToBytes(UTF8Encode(aInput));
  {$ELSE}
    fStrHelper := DecodeStringBase64(aInput);
    SetLength(Result, fStrHelper.Length);
    move(fStrHelper[1], Result[0], fStrHelper.Length);
  {$ENDIF}
end;

function Count(const mi, miben: String): integer;
var
  s: String;
  i: integer;
begin
  s      := '';
  Result := 0;
  for i := 1 to length(miben) do
  begin
    s := s + miben[i];
    if 0 < Pos(mi, s) then
    begin
      Inc(Result);
      s := '';
    end;
  end;
end;

function RightStr(const Source: String; Count: integer): String;
var
  i: integer;
begin
  Result := '';
  for i := Count + 1 to length(Source) do
    Result := Result + Source[i];
end;
function SubString(const s, seperator: String; index: integer): String;
var
  akts: String;
  sz:   integer;
  i, l: integer;
begin
  akts   := s;
  sz     := 0;
  Result := '';
  l      := length(seperator);
  repeat
    i := Pos(seperator, akts);
    if i <> 0 then
    begin
      if sz + 1 = index then
      begin
        // ezt kerestuk
        Result := Copy(akts, 1, i - 1);
        exit;
      end;

      akts := Copy(akts, i + l, 100000);
      Inc(sz);
    end
    else
    begin
      // nincs tobb talalat.
      if sz + 1 = index then
        Result := akts;
      exit;
    end;
  until False;
end;

function MyDateToStr(const x: TDateTime): String;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', x);
end;

function MyStrToTime(const x: String): TDateTime;
var
  h, m: integer;
begin
  h      := StrToIntDef(Copy(x, 1, 2), 0);
  m      := StrToIntDef(Copy(x, 4, 2), 0);
  Result := EncodeTime(h, m, 0, 0);
end;

function MyStrToDate(const x: String): TDateTime;
var
  y, m, d, h, mm, s: integer;
begin
  y  := StrToIntDef(Copy(x, 1, 4), 0);
  m  := StrToIntDef(Copy(x, 6, 2), 0);
  d  := StrToIntDef(Copy(x, 9, 2), 0);
  h  := StrToIntDef(Copy(x, 12, 2), 0);
  mm := StrToIntDef(Copy(x, 15, 2), 0);
  s  := StrToIntDef(Copy(x, 18, 2), 0);
  if not TryEncodeDateTime(y, m, d, h, mm, s, 0, Result) then
    Result := 0;
end;

function myStrToFloat(s: String; const def: double): double;
var
  x: String;
  d: integer;
  e: integer;
begin
  Result := def;
  if s = '' then
    exit;
  s := ReplaceText(s, ',', '.');
  d := Count('.', s);
  if (d <= 1) then
  begin
    Result := StrToIntDef(SubString(s, '.', 1), 0);
    if d = 1 then
    begin
      x := SubString(s, '.', 2);
      if Result < 0 then
        e := -1
      else
        e := 1;
      Result := Result + e * StrToIntDef(x, 0) / Power(10, length(x));
    end;
  end;
end;

function RPos(const SubStr: Char; const Str: String): integer;
var
  m, i: integer;
begin
  Result := 0;
  m      := length(Str);
  for i := m downto 1 do
    if Str[i] = SubStr then
    begin
      Result := i;
      exit;
    end;
end;

function RTrimCRLF(const s: String): String;
var
  db, i, j: integer;
begin
  j  := length(s);
  db := 0;
  for i := j downto 1 do
  begin
    if not (s[i] in [#13, #10]) then
      break;
    Inc(db);
  end;
  Result := Copy(s, 1, j - db);
end;

function ParseResponseCode(s: String): integer;
var
  p, l: integer;
begin
  Result := 0;
  s      := RTrimCRLF(s);
  p      := RPos(#13, s);
  l      := length(s);
  if (p <= l - 3) then
  begin
    Inc(p);
    if (s[p] in [#13, #10]) then
      Inc(p);

    Result := StrToIntDef(Copy(s, p, 3), 0);
    if ((l > 3) and (s[p + 3] <> ' ')) then
      Inc(Result, 1000);// and (p + 3 <= l)
  end;
end;

function MyIncludeTrailingSlash(const s: String): String;
var
  fLength: Integer;
begin
  fLength := Length(s);
  if fLength > 0 then
  begin
    Result := s;
    if Result[fLength] <> '/' then
      Result := Result + '/';
  end
  else
    Result := '/';
end;

function ParsePASVString(s: String; out host: String; out port: integer): boolean;
begin
  Result := False;

  {
  * PASV
  * 227 Entering Passive Mode (ip,ip,ip,ip,port,port)
  }
  s := Copy(s, Pos('(', s) + 1, 100000);
  s := Copy(s, 1, Pos(')', s) - 1);
  if s = '' then
    exit;

  host := Fetch(s, ',', True, False) + '.' + Fetch(s, ',', True, False) + '.' + Fetch(s, ',', True, False) + '.' + Fetch(s, ',', True, False);
  if s = '' then
    exit;

  port := StrToIntDef(Fetch(s, ',', True, False), 0) * 256 + StrToIntDef(Fetch(s, ',', True, False), 0);
  if port = 0 then
    exit;

  Result := True;
end;

function ParseEPSVString(const aFTPdResponse: String; out aHost: String; out aPort: Integer; out aIPv4Transfermode: Boolean): Boolean;
var
  fBracketsContent: String;
  fDelimiter: Char;
  fHelper: TArray<String>;
begin
  Result := False;

  {
    -> Needed command sequence <-
  * CEPR on
  * 200 Custom Extended Passive Reply enabled
  * EPSV
  * 229 Entering Extended Passive Mode (|mode|ip.ip.ip.ip|port|)
  }
  fBracketsContent := aFTPdResponse.Split(['(', ')'])[1];
  if fBracketsContent.IsEmpty then
  begin
    Exit;
  end;
  // value of fBracketsContent is |<mode>|<ip>|<port>| now

  // delimiter in the range of ASCII 33-126
  fDelimiter := fBracketsContent[1];

  fHelper := aFTPdResponse.Split([fDelimiter]);

  // protocol family as defined by IANA (1 for IPv4, 2 for IPv6)
  aIPv4Transfermode := Boolean(fHelper[1].ToInteger = 1);

  aHost := fHelper[2];
  aPort := StrToInt(fHelper[3]);
  if aPort = 0 then
  begin
    exit;
  end;

  Result := True;
end;

function ParseXDupeResponseToFilenameList(const aResponseText: String; const aFileList: TList<String>): Boolean;
const
  XDUPE_RESPONSE_START = '553- X-DUPE: ';
var
  fHelpArray: TArray<String>;
  fSingleLine: String;
begin
  fHelpArray := aResponseText.Split([#13, #10]);

  for fSingleLine in fHelpArray do
  begin
    // example lines:
    // 553- X-DUPE: gimini-1080p-20190816124132.r14
    // 553- X-DUPE: 01_dynatec_-_get_up_(keep_the_fire_burning)_(factory_team_remix)-idc.mp3

    if fSingleLine.StartsWith(XDUPE_RESPONSE_START) then
      aFileList.Add(fSingleLine.Replace(XDUPE_RESPONSE_START, '').Trim);
  end;

  if aFileList.Count > 0 then
    Result := True
  else
    Result := False;
end;

function IsALetter(const c: Char): boolean;
begin
  Result := (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')));
end;

function IsANumber(const c: Char): boolean;
begin
  Result := ((c >= '0') and (c <= '9'));
end;

function OccurrencesOfNumbers(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    if IsANumber(s[i]) then
      Inc(Result);
  end;
end;

function FetchSL(var aInputText: String; const Args: array of Char): String;
var
  elso, utolso: integer;
  i, j:    integer;
  megvolt: boolean;
begin
  elso   := 0;
  utolso := 0;
  for i := 1 to length(aInputText) do
  begin
    megvolt := False;
    for j := Low(Args) to High(Args) do
      if aInputText[i] = Args[j] then
      begin
        if elso = 0 then
          elso := i;
        utolso := i;
        megvolt := True;
        Break;
      end;

    if not megvolt then
      if utolso <> 0 then
        Break;
  end;

  if (elso = 0) or (utolso = 0) then
  begin
    Result := aInputText;
    aInputText := '';
    exit;
  end;

  Result := Copy(aInputText, 1, elso - 1);
  Delete(aInputText, 1, utolso);
end;

function GetFirstLineFromTextViaNewlineIndicators(var aInputText: String): String;
begin
  Result := FetchSL(aInputText, [#13, #10]);
end;

function DatumIdentifierReplace(const aSrcString: String; aDatum: TDateTime = 0): String;
var
  yyyy, yy, mm, dd, ww: String;
begin
  if aDatum = 0 then
    aDatum := Now();

  yyyy := Format('%.4d', [YearOf(aDatum)]);
  yy   := Copy(yyyy, 3, 2);
  mm   := Format('%.2d', [MonthOf(aDatum)]);
  dd   := Format('%.2d', [DayOf(aDatum)]);
  ww   := Format('%.2d', [WeekOf(aDatum)]);

  Result := aSrcString;
  Result := ReplaceText(Result, '<yyyy>', yyyy);
  Result := ReplaceText(Result, '<yy>', yy);
  Result := ReplaceText(Result, '<mm>', mm);
  Result := ReplaceText(Result, '<dd>', dd);
  Result := ReplaceText(Result, '<ww>', ww);
end;

function onlyEnglishAlpha(const S: String): String;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if IsALetter(S[i]) then
    begin
      Result := Result + S[i];
    end;
  end;
end;

{$WARNINGS OFF}
function DateTimeAsString(const aThen: TDateTime; padded: boolean = False): String;
var
  i, seci, mini, houri, dayi, weeki, monthi, yeari:    int64;
  imsg, secs, mins, hours, days, weeks, months, years: String;
begin
  Result := '-1';
  if (aThen = 0) then
    exit;

  seci   := SecondsBetween(now, aThen);
  mini   := MinutesBetween(now, aThen);
  houri  := HoursBetween(now, aThen);
  dayi   := DaysBetween(now, aThen);
  weeki  := WeeksBetween(now, aThen);
  monthi := MonthsBetween(now, aThen);
  //yeari:=YearsBetween(now,aThen);
  try
    //sec
    if seci >= 60 then
    begin
      mini := seci div 60;
      seci := seci - (mini * 60);
    end
    else
      seci := seci;
    //min
    if mini > 60 then
    begin
      houri := mini div 60;
      mini  := mini - (houri * 60);
    end
    else
      mini := mini;
    if mini = 60 then
      mini := 0;

    //hour
    if houri > 24 then
    begin
      dayi  := houri div 24;
      houri := houri - (dayi * 24);
    end
    else
      houri := houri;
    if houri = 24 then
      houri := 0;

    //day
(*
if dayi > 7 then begin
weeki:=dayi div 7;
dayi:=dayi-(weeki * 7);
end else dayi:=dayi;
*)
    if dayi > 7 then
    begin
      weeki := dayi div 7;
      i     := weeki * 7;
      if dayi <> i then
        dayi := dayi - (weeki * 7)
      else
        dayi := 0;
    end
    else
      dayi := dayi;
    if dayi = 7 then
      dayi := 0;

    //week
    if weeki > 4 then
    begin
      monthi := weeki div 4;
      i      := monthi * 4;
      if weeki <> i then
        weeki := weeki - (monthi * 4)
      else
        weeki := 0;
    end
    else
      weeki := weeki;
    if weeki = 4 then
      weeki := 0;

    //month
    if monthi >= 12 then
    begin
      yeari  := monthi div 12;
      monthi := monthi - (yeari * 12);
    end
    else
      monthi := monthi;
    if monthi = 12 then
      monthi := 0;
    //year
    yeari := monthi div 12;

    if padded then
    begin
      if seci = 1 then
        secs := Format('%2d second', [seci])
      else
        secs := Format('%2d seconds', [seci]);
      if mini = 1 then
        mins := Format('%2d minute ', [mini])
      else
        mins := Format('%2d minutes ', [mini]);
      if houri = 1 then
        hours := Format('%2d hour ', [houri])
      else
        hours := Format('%2d hours ', [houri]);
      if dayi = 1 then
        days := Format('%d day ', [dayi])
      else
        days := Format('%d days ', [dayi]);
      if weeki = 1 then
        weeks := Format('%d week ', [weeki])
      else
        weeks := Format('%d weeks ', [weeki]);
      if monthi = 1 then
        months := Format('%2d month ', [monthi])
      else
        months := Format('%2d months ', [monthi]);
      if yeari = 1 then
        years := Format('%d year ', [yeari])
      else
        years := Format('%d years ', [yeari]);
    end
    else
    begin
      if seci = 1 then
        secs := Format('%d second', [seci])
      else
        secs := Format('%2d seconds', [seci]);
      if mini = 1 then
        mins := Format('%d minute ', [mini])
      else
        mins := Format('%2d minutes ', [mini]);
      if houri = 1 then
        hours := Format('%d hour ', [houri])
      else
        hours := Format('%2d hours ', [houri]);
      if dayi = 1 then
        days := Format('%d day ', [dayi])
      else
        days := Format('%d days ', [dayi]);
      if weeki = 1 then
        weeks := Format('%d week ', [weeki])
      else
        weeks := Format('%d weeks ', [weeki]);
      if monthi = 1 then
        months := Format('%d month ', [monthi])
      else
        months := Format('%2d months ', [monthi]);
      if yeari = 1 then
        years := Format('%d year ', [yeari])
      else
        years := Format('%d years ', [yeari]);
    end;
    imsg := '';
    if yeari > 0 then
      imsg := imsg + years;
    if monthi > 0 then
      imsg := imsg + months;
    if weeki > 0 then
      imsg := imsg + weeks;
    if dayi > 0 then
      imsg := imsg + days;
    if houri > 0 then
      imsg := imsg + hours;
    if mini > 0 then
      imsg := imsg + mins;
    if seci > 0 then
      imsg := imsg + secs;
  finally
    Result := imsg;
  end;
end;

{$WARNINGS ON}

procedure SplitString(const Source: String; const Delimiter: String; const Dest: TStringList);
var
  Count: integer;
  LStartpos, LEndepos, LSourcelength: integer;
  LDelimiterLength: integer;
begin
  Dest.Clear;
  Count     := 1;
  LStartpos := 0;
  LEndepos  := 0;
  LSourcelength := length(Source);
  LDelimiterLength := Length(Delimiter);
  while Count <= LSourcelength do
  begin
    if copy(Source, Count, LDelimiterLength) = Delimiter then
    begin
      LEndepos := Count;
      Dest.Add(Trim(copy(Source, LStartpos + 1, LEndepos - LStartpos - 1)));
      LStartpos := Count + LDelimiterLength - 1;
      Inc(Count, LDelimiterLength);
    end
    else
    begin
      Inc(Count);
    end;
  end;
  if LEndePos <> Count - LDelimiterLength then
    Dest.Add(Trim(copy(Source, LStartpos + 1, Count - LStartpos - 1)));
end;

procedure RecalcSizeValueAndUnit(var size: double; out sizevalue: String; StartFromSizeUnit: Integer = 0);
{$I common.inc}
begin
  if ((StartFromSizeUnit > FileSizeUnitCount) or (StartFromSizeUnit < 0)) then
  begin
    Debug(dpError, section, Format('[EXCEPTION] RecalcSizeValueAndUnit : %d cannot be smaller or bigger than %d', [StartFromSizeUnit, FileSizeUnitCount]));
    exit;
  end;

  while ( (size >= 1024) and (StartFromSizeUnit < FileSizeUnitCount) ) do
  begin
    size := size / 1024;
    Inc(StartFromSizeUnit);
  end;

  if (StartFromSizeUnit > FileSizeUnitCount) then
  begin
    Debug(dpError, section, Format('[EXCEPTION] RecalcSizeValueAndUnit : %d cannot be bigger than %d', [StartFromSizeUnit, FileSizeUnitCount]));
    exit;
  end;

  sizevalue := FileSizeUnits[StartFromSizeUnit];
end;

procedure ParseSTATLine(const aStatLine: String; out aCredits, aRatio: String);
var
  x: TRegExpr;
  ss, ratio: String;
  c: double;
  sizeValueIndex: Integer;
begin
  aRatio := '';
  aCredits := '';
  sizeValueIndex := 2;

  x := TRegExpr.Create;
  try
    x.ModifierI := True;

    x.Expression := config.ReadString('sites', 'ratio_regex', '(Ratio|R|Shield|Health\s?):.+?(\d+\:\d+|Unlimited|Leech)(\.\d+)?');
    if x.Exec(aStatLine) then
    begin
      if (AnsiContainsText(x.Match[2], 'Unlimited') or (x.Match[2] = '1:0')) then
        ratio := 'Unlimited'
      else
        ratio := x.Match[2];
    end;

    // ratio(UL: 1:3 | DL: 1:1)
    if ratio = '' then
    begin
      x.Expression := '(Ratio\(\w*:\s*(\d+:\d+).*?\))';
      if x.Exec(aStatLine) then
      begin
        ratio := x.Match[2];
      end;
    end;

    x.Expression := config.ReadString('sites', 'credits_regex', '(Credits|Creds|C|Damage|Ha\-ooh\!)\:?\(?\s?([\-\d\.\,]+)\s?([MGT][iB]{1,2}|[EZ]P)\]?');
    if x.Exec(aStatLine) then
    begin
      ss := x.Match[2];

      {$IFDEF FPC}
        ss := StringReplace(ss, '.', DefaultFormatSettings.DecimalSeparator, [rfReplaceAll, rfIgnoreCase]);
      {$ELSE}
        ss := StringReplace(ss, '.', {$IFDEF UNICODE}FormatSettings.DecimalSeparator{$ELSE}DecimalSeparator{$ENDIF}, [rfReplaceAll, rfIgnoreCase]);
      {$ENDIF}

      c := strtofloat(ss);
      ss := UpperCase(x.Match[3]);

      if (ss = 'MB') or (ss = 'MIB') then
      begin
        ss := 'MB';
        RecalcSizeValueAndUnit(c, ss, sizeValueIndex);
      end
      else if (ss = 'GB') or (ss = 'GIB') then
      begin
        ss := 'GB';
        RecalcSizeValueAndUnit(c, ss, sizeValueIndex+1);
      end
      else if (ss = 'TIB') then
      begin
        ss := 'TB';
      end;

      aCredits := Format('%.2f %s', [c, ss] );
      aCredits := StringReplace(aCredits, ',', '.', [rfReplaceAll, rfIgnoreCase]);
      aRatio := ratio;
    end;

  finally
    x.free;
  end;
end;

function ParsePathFromSiteSearchResult(const aSearchResult, aRlsToSearch: String): String;
var
  fRegex: TRegexpr;
  fPath: String;
begin
  Result := '';
  fRegex := TRegExpr.Create;
  try
    fRegex.Expression := '200- (/[a-zA-Z0-9\._\-()/]*)'; //200- /SECTION/Test.Release-ASDF
    if fRegex.Exec(aSearchResult) then
    begin
      repeat
        fPath := fRegex.Match[1];

        //index might contain stuff like /FILLED-Test.Release-ASDF/Test.Release-ASDF and also /FILLED-Test.Release-ASDF
        if not fPath.Contains('/' + aRlsToSearch) then
          continue;

        //index might contains stuff like /SECTION/Test.Release-ASDF/Sample (1F/154.3M/58d 18h)
        if fPath.Contains('/' + aRlsToSearch + '/') then
          continue;

        //200- /SECTION/Test.Release-ASDF *NUKED*
        if aSearchResult.Contains(fPath + (' *NUKED*')) then
          continue;

        Result := Result + fPath + #13#10;
      until not fRegex.ExecNext();
    end;
  finally
    fRegex.Free;
  end;
end;

function InternationalCharsToAsciiSceneChars(const aInput: String): String;
begin
  Result := aInput;

  // remove scene delimiters
  //Result := Result.Replace('.', '', [rfReplaceAll, rfIgnoreCase]);
  //Result := Result.Replace('_', '', [rfReplaceAll, rfIgnoreCase]);
  // change special international characters
  Result := Result.Replace('ÿ', 'y', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ü', 'ue', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ö', 'oe', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ï', 'i', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ë', 'e', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ä', 'ae', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('ß', 'ss', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('À', 'a', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Á', 'a', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Â', 'a', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ã', 'a', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Å', 'a', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Æ', 'ae', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ç', 'c', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('È', 'e', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('É', 'e', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ê', 'e', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ì', 'i', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Í', 'i', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Î', 'i', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ð', 'd', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ñ', 'n', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ò', 'o', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ó', 'o', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ô', 'o', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Õ', 'o', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ø', 'o', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Œ', 'oe', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ù', 'u', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ú', 'u', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Û', 'u', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Ý', 'y', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('Š', '', [rfReplaceAll, rfIgnoreCase]);
  // change punctuation characters
  Result := Result.Replace('&quot;', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('.', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace(';', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace(':', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace(',', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('''', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('-', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('?', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('!', '', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('&', '', [rfReplaceAll, rfIgnoreCase]);
  // finally replace more than one whitespace with one
  Result := Result.Replace('   ', ' ', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('  ', ' ', [rfReplaceAll, rfIgnoreCase]);

  Debug(dpSpam, section, Format('Changed international %s to ascii scene %s', [aInput, Result]));
end;

function IsRarExtension(const aExtension: string): boolean;
var
  fRegex: TRegexpr;
begin
  if aExtension = '.rar' then
  begin
    Result := True;
    exit;
  end;

  fRegex := TRegExpr.Create;
  try
    fRegex.ModifierI := True;
    fRegex.Expression := '\.[0-9rstuvwxyz][0-9][0-9]$';
    Result := fRegex.Exec(aExtension);
  finally
    fRegex.Free;
  end;
end;

function ParseSFV(aSFV: string): TDictionary<string, integer>;
var
  fLine: String;
begin
  Result := TDictionary<string, integer>.Create;

  while True do
  begin
    fLine := LowerCase(Trim(GetFirstLineFromTextViaNewlineIndicators(aSFV)));

    if fLine = '' then
      break;

    if fLine[1] = ';' then //skip comments
      continue;

    Result.AddOrSetValue(LeftStr(fLine, (fLine.IndexOf(' '))), 0);
  end;
end;

// Code taken from here: https://github.com/delphius/htmlparser/tree/main
function HTMLDecode(const aText: string): string;
var
  MatchPos, SemicolonPos: Integer;
  EntityCode, EntityName: string;
  Dec, I: Integer;
  FoundEntity: Boolean;
begin
  Result := aText;
  MatchPos := Pos('&', Result);
  while MatchPos > 0 do
  begin
    SemicolonPos := Pos(';', Result, MatchPos);
    if SemicolonPos > 0 then
    begin
      EntityCode := Copy(Result, MatchPos + 1, SemicolonPos - MatchPos - 1);
      if EntityCode[1] = '#' then
      begin
        EntityName := Copy(EntityCode, 2, Length(EntityCode));
        Dec := StrToIntDef(EntityName, 0);
        Result := StringReplace(Result, '&' + EntityCode + ';', UTF8Encode(WideChar(Dec)), []);
      end
      else
      begin
        FoundEntity := False;
        for I := Low(HTMLChars) to High(HTMLChars) do
        begin
          if HTMLChars[I].Name = ('&' + EntityCode + ';') then
          begin
            Result := StringReplace(Result, ('&' + EntityCode + ';'), HTMLChars[I].Value, []);
            FoundEntity := True;
            Break;
          end;
        end;
      end;

      MatchPos := Pos('&', Result, SemicolonPos + 1);
    end
    else
    begin
      Break;
    end;
  end;
end;

end.
