{@********************************************************}
{    Copyright (c) 1999-2020 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}
{.$DEFINE ZEOS_TEST_ONLY}
{$DEFINE GENERIC_INDEX}
{.$DEFINE DISABLE_ZPARAM}
//common compilation directives
{$DEFINE ZEOS72UP}
{$DEFINE ZEOS73UP}
{$DEFINE ZEOS80UP}

{$IF (defined(FPC) and (defined(CPU386) or defined(CPUX86_64))) or defined(MSWINDOWS)}
  {.$DEFINE INTEL_ASM} //allow intel syntax assembler commented is stated as buggy ):
{$IFEND}

// Uncomment these defines to disable some DB drivers (reduce binary size)
{.$DEFINE ZEOS_DISABLE_MYSQL}
{$DEFINE ZEOS_DISABLE_POSTGRESQL}
{$DEFINE ZEOS_DISABLE_DBLIB}
{$DEFINE ZEOS_DISABLE_ADO}
{$DEFINE ZEOS_DISABLE_INTERBASE}
{$DEFINE ZEOS_DISABLE_FIREBIRD}
{$DEFINE ZEOS_DISABLE_SQLITE}
{$DEFINE ZEOS_DISABLE_ORACLE}
{$DEFINE ZEOS_DISABLE_ASA}
{$DEFINE ZEOS_DISABLE_SQLANY}
{$DEFINE ZEOS_DISABLE_POOLED}
{$DEFINE ZEOS_DISABLE_OLEDB}
{$DEFINE ZEOS_DISABLE_ODBC}
{$DEFINE ZEOS_DISABLE_PROXY}
{$DEFINE ZEOS_PROXY_USE_INTERNAL_PROXY}

{.$DEFINE USE_SYNCOMMONS} //enable JSON content support by using SynCommons.pas from Synopse project v1.18
{.$DEFINE MORMOT2} //enable JSON content support by using mormot.db.core.pas from Synopse project v2+

{.$DEFINE DO_NOT_DERIVE_FROM_EDATABASEERROR} //don't derive Zeos Exceptions from EDatabaseError

// Enabling this directive will cause Zeos not to cache client connection libraries. This basically means
// that all handles will be immediately released once the final connection is closed
{$DEFINE ZEOS_DISABLE_DRIVER_CACHE}

// In Version 6.1.5 there are several bugs with the TZSQLMetadata-Component
// For Version 6.5.0 you should uncomment the following line
{$DEFINE USE_METADATA}

//Default. To validate an optimal updatecount of 1. Comment this define if this
//dafault behavior isn't wanted. On the other hand you can suppress this
//validation by adding the line ValidateUpdateCount=-1 or FALSE or OFF into the
// TZDataSet-Component.Properties(TStrings)
{$DEFINE WITH_VALIDATE_UPDATE_COUNT}

// Supported language. Now available languages:
// ENGLISH, GERMAN, PORTUGUESE, DUTCH, SPANISH, ROMANA, INDONESIAN, RUSSIAN, CZECH, POLISH, FRENCH
{$DEFINE ENGLISH} //see \core\ZMessages.pas

// enables a fake AutoEncodeStrings property for backwards compatibility with Zeos 7.2
{.$DEFINE WITH_FAKE_AUTOENCODESTRINGS}

// If defined, changing the .SQL property of an active TZAbstractRODataSet descendant will raise an exception instead of silently closing it
{.$DEFINE ACTIVE_DATASET_SQL_CHANGE_EXCEPTION}

// If defined the ZMemTable component allows importing and exporting it's layout and data to a TStream descendant. Only tested with D10.3+ !!!
{.$DEFINE ZMEMTABLE_ENABLE_STREAM_EXPORT_IMPORT}

{$DEFINE MISS_MATH_NATIVEUINT_MIN_MAX_OVERLOAD} //Compiler can't determine overload for NativeUInt(64-Bit)
 // Compilation directives for Lazarus/FPC
{$IFDEF FPC}
  {$I ZeosLazarus.inc}
{$ELSE}
  {$IF CompilerVersion >= 25}
    {$LEGACYIFEND ON}
  {$IFEND}
  {$IF not defined(CPU64) and (defined(CPUX64) or defined(CPU64BITS) or defined(CPUARM64) or defined(CPU64BITS))}
    {$DEFINE CPU64}
  {$IFEND}
  {$DEFINE DELPHI}
  // Defines that go for ALL still supported Delphi's   (usually means they were under ifndef fpc)
  {$DEFINE WITH_SqlTimSt_UNIT}            //Unit SqlTimSt.pas is available
  {$DEFINE WITH_TSQLTimeStamp}            //The TSQLTimeStamp is decalred in SqlTimSt.pas
  {$DEFINE WITH_SBCDOVERFLOW}             //DBConsts have error message SBcdOverflow
  {$DEFINE WITH_SInvalidBcdValue}         //DBConsts have error message SInvalidBcdValue
  {$DEFINE WITH_DBTABLES}                 //Have the BDE DBTables Unit
  {$DEFINE WITH_DBCONSTS}                 //Delphi DBCONSTS, FPC DBCONST
  {$DEFINE WITH_ASCURRENCY}               // Has AsCurrency.
  {$DEFINE WITH_ASVARIANT}                // Has AsVariant
  {$DEFINE WITH_IPROVIDER}                // Turn on IProviderSupport interface
  {$DEFINE WITH_IPROVIDERSUPPORT_GUID}    //IProviderSupport GUID is available
  {$DEFINE WITH_CHECKFIELDCOMPATIBILITY}
  {$DEFINE WITH_INLINE_ANSICOMPARETEXT}   //ANSICOMPARETEXT is inlined and need unit Windows for inlineing
  {$DEFINE WITH_FTDATASETSUPPORT}         //ftDataSet is supported
  {$DEFINE WITH_FTGUID}                   //ftGuid is supported (binary 16Bytes)
  {$IFDEF WIN32}
    {$DEFINE USE_FAST_TRUNC}              //use Fascode Trunc(): Int64 functions
    {$DEFINE USE_FAST_STRLEN}             //use FastCode StrLen() function with different instruction-sets
  {$ENDIF}
  {$DEFINE WITH_VIRTUAL_GETHASCONSTRAINTS}//TField has virtual methode GetHasConstraints
  {$DEFINE WITH_TOBJECTFIELD}             //unit DB contains TObjectField implementation
  {$DEFINE WITH_VIRTUAL_SETFIELDKIND}     //TField has virtual methode SetFieldKind
  {$DEFINE WITH_TARRAYFIELD}              //unit DB contains TArrayField
  {$DEFINE WITH_TDATASETFIELD}            //unit DB contains TDataSetField
  {$DEFINE WITH_VIRTUAL_TFIELD_BIND}      //TField has virtual Methode Bind()
  {$DEFINE WITH_OBJECTVIEW}               //TDataSet has ObjectView property
  {$DEFINE WITH_FIELDDEFLIST}             //TDataSet has TFieldDefList
  {$DEFINE WITH_OBJECTFIELDTYPES}         //unit db has set of TFieldTypes for TObjectFields
  {$DEFINE TFIELDDEF_HAS_CHILDEFS}        //TFieldDef has ChildDefs(TFieldDefs)
  {$DEFINE TFIELDEFS_OWNER_IS_TPERSISTENT}//TFieldDefs Owner is TPersistent
  {$DEFINE WITH_VIRTUAL_DEFCHANGED}       //TDataSet has virtual DefChanged Methode
  {$DEFINE WITH_TFIELD_PARENTFIELD}       //TField has public ParentField(TField) property
  {$DEFINE WITH_SPARSEARRAYS}             //TDataSet has SparseArrays property
  {$DEFINE WITH_NESTEDDATASETS}           //TDataSet has property NestedDataSets: TList read GetNestedDataSets;
  {$DEFINE WITH_DATASETFIELD}             //TDataSet has property SetDataSetField
  {$DEFINE WITH_NESTEDDATASETCLASS}       //TDataSet has property NestedDataSetclass
  {$DEFINE WITH_TFIELD_FREEBUFFERS}       //TField has virtual FreeBuffers procedure
  {$DEFINE WITH_FIELD_VALIDATELOOKUPINFO} //TField has private ValidateLookupInfo() procedure
  {$DEFINE WITH_FUNIDIRECTIONAL}          //TDataSet have SetUniDirectional and GetUnidirectional
  {$DEFINE WITH_TSQLTIMESTAMP_RECORD}     //FieldType TSQLTimeStamp record exists
  {$DEFINE WITH_FTTIMESTAMP_FIELD}        //TSQLTimeStamp field exists
  {$DEFINE WITH_TAUTOREFRESHFLAG}         //TField has TAutoRefreshFlag to indicate autogenerated values
  {$DEFINE WITH_TDATASETPROVIDER}         //just for the tests by now: DataSnap.Provider.TDataSetProvider exists
  {$DEFINE WITH_PARAM_ASBCD}              //TParam.AsBCD is supported
  {$DEFINE WITH_VIRTUAL_TFIELD_BIND}      //TField.Bind(Binding) is supported
  {$DEFINE WITH_INFINATE_DECLARED_IN_UNIT_WINDOWS} //old delphi <= 2010 declared const INFINITE in windows unit
  {$DEFINE WITH_TBLOBFIELD_GETASVARIANT_varNULL_BUG} //The TBlobFields do not test IsNull state for the GetAsVariant getter.
  {$DEFINE WITH_TMEMOFIELD_GETASVARIANT_varNULL_BUG} //The TMemoFields do not test IsNull state for the GetAsVariant getter.
  //now compiler related (un)defines do follow up here
  {$IF CompilerVersion < 15}
     "Delphi versions below Delphi 7 aren't supported anymore"
  {$ELSE}
    {$DEFINE NO_UINT64_MIN}                // The Math unit has no Min function for UINT64
    {$DEFINE WITH_FTWIDESTRING}                 //Have ftWideString
    {$DEFINE TWIDESTRINGFIELD_DATABUFFER_IS_PWIDESTRING}
    {$DEFINE WITH_UINT64_C1118_ERROR}       //D7-D2005 has proplems to assign code constants for UInt64
    {$DEFINE WITH_MILLISECONDOFTHEYEAR_BUG} //D7-D005 Bug -> a Int64 Cast of SecondOfTheYear(AValue) is missing
    {.$DEFINE PatchSystemMove}               //replaces System.Move by FastCode-Project Move proc
    {$DEFINE Use_FastCodeFillChar}          //use ZFastCode FillChar() instead
    {$DEFINE USE_FAST_CHARPOS}              //use ZFastCode CharPos function
    {$DEFINE VER150BELOW}                   //found in ZTestBugCompPostgreSql.pas
    {$DEFINE WITH_OVERLOAD_BUG}             //D7 Bug -> ambiguous overload error when both Func(Integer) and Func(Cardinal) exist and Func(a: Byte/Word) is called
    {$IF CompilerVersion >= 16} //Delphi 8+
      {$IF CompilerVersion >= 17} //Delphi 2005+
        {$DEFINE WITH_INLINE}          // compiler supports inline methodes
        {$DEFINE WITH_C5242_OR_C4963_INTERNAL_ERROR} //D2005..2009 Has an internal error with some inlined endian swap code.
        {$DEFINE NO_INLINE_SIZE_CHECK} //so old compilers need the Math unit for PUnicodeToRaw -> suppress hints
        {$IF CompilerVersion >= 18} //Delphi 2006+
          {$UNDEF TWIDESTRINGFIELD_DATABUFFER_IS_PWIDESTRING}
          {$UNDEF WITH_UINT64_C1118_ERROR}            //2006+ has no problems to assign code constants for UInt64
          {$UNDEF WITH_MILLISECONDOFTHEYEAR_BUG}      //D7-D005 Bug -> a Int64 Cast of SecondOfTheYear(AValue) is fixed
          {$UNDEF Use_FastCodeFillChar}               //FastCode FillChar() is included since D2006
          {$DEFINE WITH_DEPRECATED_EXTRACTFIELDNAME}  //DB.pas proc ExtractFieldName String overload is deprecated}
          {$DEFINE BCC32_vtDateTime_ERROR}            //[BCC32 Error] Zvariant.hpp(81): E2019 'TZVariant:: :: :: ()' cannot be declared in an anonymous union http://zeoslib.sourceforge.net/viewtopic.php?f=40&t=3795&start=180
          {$DEFINE WITH_WIDESTRUTILS}                 //WideStrUtils unit introduced.
          {$DEFINE SUPPORTS_UINT64_CONSTS}            //compiler supports integer constants with 20 didgits
          {$DEFINE WITH_WIDESTRINGS_GETFIELDNAMES}    //overload of GetFieldNames(List: TWideStrings) does exists;
          {$DEFINE WITH_WIDEDATASET}                  //TWidedataset exists
          {$DEFINE WITH_PWIDECHAR_TOWIDESTRING}       //Able to pass pwidechar to a widestring parameter
          {$DEFINE WITH_IPROVIDERWIDE}                //IProvider -W widestring using interface
          {$DEFINE WITH_ASLARGEINT}                   // tlargeint aslargeint. Fixed 2.6.0+ or 2.6.2+ probably
          {$DEFINE WITH_WIDEMEMO}                     //Have ftWideMemo
          {$DEFINE WITH_TWIDEMEMOFIELD_GETASVARIANT_varNULL_BUG} //The TWideMemoFields do not test IsNull state for the GetAsVariant getter.
          {$DEFINE WITH_PARAM_ASWIDESTRING}           //TParam support the AsWideString property
          {$DEFINE WITH_FTFIXEDWIDECHAR}              //Have ftFixedWideChar
          {$DEFINE WITH_CLASS_VARS}                   //Class variables/methods are supported
          {$DEFINE WITH_UNIT_WIDESTRINGS}             //unit WideStrings introduced
          {$DEFINE WITH_VIRTUAL_TFIELD_ASWIDESTRING}  //TField supports the AsWideString property

          {$IF CompilerVersion >= 18.5} //Delphi 2007+
            {$DEFINE WITH_TBYTES}
            {$UNDEF VER150BELOW}      //found in ZTestBugCompPostgreSql.pas
            {$DEFINE WITH_TCOLLECTION_CAPACITY}         //TCollection supports the capacity property
            {$IF CompilerVersion >= 20} //Delphi 2009+
              {$DEFINE TBLOBDATA_IS_TBYTES}             //TBlobdata is an alias for TBytes (FPC uses an AnsiString)
              {$DEFINE WITH_CLASS_CONST}                //compiler supports contants in class type declarations
              {$DEFINE FIELD_ASWIDESTRING_IS_UNICODESTRING} //TField.AsWideString is type UnicodeString not WideString
              {$DEFINE WITH_varUString}                 //Variant now supports refcounted UnicodeStrings
              {$DEFINE HAVE_CS_TRYENTER} //TCriticalSection has method TryEnter
              {$UNDEF WITH_OVERLOAD_BUG}                //2009+ has no problems with ambiguous overload (byte/word)
              {$UNDEF WITH_DEPRECATED_EXTRACTFIELDNAME} //DB.pas proc ExtractFieldName String overload is no more deprecated -> Unicode}
              {$UNDEF NO_INLINE_SIZE_CHECK}
              {$UNDEF BCC32_vtDateTime_ERROR}           //resolved by ide
              {$UNDEF USE_FAST_CHARPOS}                 // Since Unicode this function is useless
              {$DEFINE HAVE_UNICODESTRING}
              {$DEFINE WITH_TBOOKMARK}                  // Have TBookmark
              {$DEFINE WITH_TSTRINGS_TENCODING_LOADFROM}// TStrings.LoadFromFile/LoadFromStream have TEncoding
              {$DEFINE WITH_STSTRINGUNICODE}            // stString is unicodestring.
              {$DEFINE WITH_NEWTOBJECT}                 // allows new methods in TObject (D2009+/FPC 2.4.4)
              {$DEFINE WITH_CHARINSET}                  // D2009's poor substitute for character specific "xx in yy"
              {$DEFINE WITH_FTSHORTINT}                 // ftShortInt is supported
              {$DEFINE WITH_FTBYTE}                     // ftByte is supported
              {$DEFINE WITH_FTEXTENDED}                 // ftExtended is supported
              {$DEFINE WITH_FTLONGWORD}                 // ftLongWord is supported
              {$DEFINE WITH_TFIELD_ASEXTENDED}          // TField.AsExtended is supported
              {$DEFINE TPARAM_HAS_ASBYTES}              // TParam.AsBytes is supported
              {$DEFINE HAS_TPARAM_ASSTREAM}             // TParam.AsStream is supported
              {$DEFINE TFIELD_HAS_ASBYTES}              // TField.AsBytes is supported
              {$DEFINE WITH_RAWBYTESTRING}              // Have RawByteString CP $FFFFF
              {$DEFINE WITH_DEFAULTSYSTEMCODEPAGE}      // determine the AnsiString CP
              {$DEFINE WITH_UNITANSISTRINGS}            // Have unit AnsiStrings
              {$UNDEF WITH_IPROVIDERWIDE}               // IProvider -W widestring using interface is deprecated since UNICODE and won't be called anymore
              {$DEFINE PWIDECHAR_IS_PUNICODECHAR}       // PWideChar = ^UnicodeString
              {$DEFINE WITH_ASANSISTRING}               // T(Wide)StringField supports AsAnsiString property
              {$DEFINE WITH_INC_PBYTE_SUPPORT}          // Compiler supports incrementing PByte-Pointer
              {$DEFINE WITH_PARAM_ASLARGEINT}           // TParam.AsLargint is supported
              {$DEFINE WITH_VARIANT_UINT64}             // System.TVariant supports UInt64 Values
              {$DEFINE WITH_VARIANT_UNICODESTRING}      // System.TVariant supports UnicodeString Values
              {$DEFINE WITH_GETFIELDCLASS_TFIELDDEF_OVERLOAD} // TDataSet has the GetFieldClass(TFieldDef) overload
              {$DEFINE WITH_VIRTUAL_BINDFIELDS} //TDataSet has virtual protected method BindFields
              {$DEFINE TOBJECT_HAS_TOSTRING}            // TObject has a virtual ToString method
              {$IF CompilerVersion >= 21} //Delphi 2010+
                {$WEAKLINKRTTI ON}                    //suppress extended RTTI
                {.$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])} //suppress extended RTTI for some unknown reason we've compilation issues. So enable this define manually!
                {$DEFINE WITH_TSQLTimeStampOffset}    //The TSQLTimeStampOffset is declared in SqlTimSt.pas
                {$DEFINE WITH_DEPRECATED_MESSAGE}     //Compiler supports deprecated messages
                {$UNDEF WITH_INLINE_ANSICOMPARETEXT}  // AnsiCompareText is no more inline declared
                {$UNDEF WITH_C5242_OR_C4963_INTERNAL_ERROR} //those inlineing errors are resolved
                {$UNDEF WITH_TBLOBFIELD_GETASVARIANT_varNULL_BUG} //the compiler now tests against empty strings and assumes NULL if Stream.Size is zero. Is that correct?
                {$DEFINE WITH_PWIDECHAR_STRLEN}       // SysUtils.StrLen supports PWideChar
                {$DEFINE WITH_FTTIMESTAMPOFFSET}      // ftTimeStampOffset is supported
                {$DEFINE WITH_FTSINGLE}               // ftSingle is supported
                {$DEFINE TFIELD_HAS_ASLARGEINT}       // TField-baseclass hase AsLargeIntProperty
                {$DEFINE DELPHI14_UP}                 // used in ZTestStoredProcedure.pas only
                {$DEFINE WITH_FTTIMESTAMP_OFFSET}     // TSQLTimeStampOffset record and field exists
                {$IF CompilerVersion >= 22} //Delphi XE+
                  {$UNDEF NO_UINT64_MIN}              // I assume, from XE on Delphi has a Min function suitable for UINT64
                  {$DEFINE WITH_tagVARIANT_UINT64}          // ActivX.tagVariant supports UInt64 Values
                  {$DEFINE TENCODING_HAS_CODEPAGE}          //TEncoding has property CodePage
                  {$DEFINE WITH_FORMATSETTINGS}             //Unit SysUtils have global FormatSettings
                  {$DEFINE WITH_UNICODEFROMLOCALECHARS}
                  {$DEFINE WITH_RTLCONSTS_SInvalidGuidArray}
                  {$DEFINE HAVE_BCDTOSTR_FORMATSETTINGS} //(Try)BCDToStr/StrToBCD has parameter FormatSettings
                  {$DEFINE WITH_TOBJECTLIST_REQUIRES_CLASSES}       //TObjectList.Remove, add ... are inlined need unit classes
                  {$UNDEF WITH_INFINATE_DECLARED_IN_UNIT_WINDOWS} // the INFINATE constant is now declared in System.pas
                  {$IF CompilerVersion >= 23} //Delphi XE2+
				    {$DEFINE BCDTOSTR_WITH_FORMATSETTINGS} // Delphi has a BcdToStr function with TFormatSettings as a parameter
                    {$DEFINE WITH_ReturnAddress} //Exports ReturnAddress for error addressing
                    {$IFNDEF MSWINDOWS}
                      {$DEFINE HAVE_GetProcAddressW} //GetProcAddress uses a PWideChar
                    {$ENDIF}
                    {$IFNDEF WIN32}
                      {$UNDEF WITH_DBTABLES} //BDE unit DBTables (TestSuites) isn't supported on CPU64
                      {$IFNDEF PUREPASCAL}
                        {$DEFINE PUREPASCAL}
                      {$ENDIF}
                      {$IFOPT O+}
                        {$DEFINE WITH_PG_WEIGHT_OPT_BUG} //wrong otpimization in ZDbcPostgreSqlUtils according the weight variable, thus results are unexpected since min XE5 until?
                      {$ENDIF}
                    {$ELSE}
                      {$IFDEF PatchSystemMove}
                        {$UNDEF PatchSystemMove}  //FastCode-Project Move currently not ported to other plattforms
                      {$ENDIF}
                    {$ENDIF}
                    {$DEFINE WITH_MAXLISTSIZE_DEPRECATED} //Since XE2 64Bit Integer = Int64 this value is deprecated
                    {$DEFINE WITH_UNIT_NAMESPACES}        //units support namespaces (System.Win.xxx)
                    {$DEFINE TLIST_ISNOT_PPOINTERLIST}    //since XE2 TList is TPointerList not PPointerList
                    {$DEFINE HAVE_TRUE_NATIVE_TYPES}      //since XE2 NativeInt, NativeUint are fixed and behave like FPC SizeInt, PtrInt (4/8Byte)
                    {$DEFINE WITH_FASTCODE_INTTOSTR}      //Since XE2 the full purepascal IntToStr func is included
                    {$DEFINE WITH_PUREPASCAL_INTPOWER}    //Since XE2 a buggy pure pascal version of Math.IntPower was introduced
                    {$IF CompilerVersion >= 24} //Delphi XE3+
                      {$UNDEF WITH_WIDEDATASET}               //TWideDataset and TDataSet are merged together: https://forums.embarcadero.com/thread.jspa?messageID=499588
                      {$DEFINE WITH_TVALUEBUFFER}             //SetFieldData/GetFieldData and Parameters using TValueBuffer instead of Pointer
                      {$DEFINE WITH_BOOKMARKDATA_TBOOKMARK}
                      {$UNDEF WITH_WIDESTRINGS_GETFIELDNAMES} //GetFieldNames with TWideStrings has been removed
                      {$DEFINE WITH_GENERIC_TLISTTFIELD}      //GetFieldList() uses the generic TList<TField>
                      {$DEFINE WITH_GENERIC_TPARAM_LIST}      //GetParamList() uses the generic TList<TParam>
                      {$DEFINE WITH_GENERICS_TFIELD_ASBYTES}  //TField.AsBytes uses TArray<Byte>
                      {$IFDEF NEXTGEN}
                        {$UNDEF WITH_UNIT_WIDESTRINGS}
                        {$UNDEF WITH_ASANSISTRING}
                        {$UNDEF WITH_UNITANSISTRINGS}
                        {$UNDEF WITH_WIDESTRUTILS}
                        {$DEFINE ZERO_BASED_STRINGS}
                        {$DEFINE TLIST_IS_DEPRECATED}
                        {$DEFINE NO_INLINE_SIZE_CHECK}
                        {$DEFINE NO_ANSISTRING}
                        {$DEFINE NO_RAW_STRINGSTREAM}
                        {$DEFINE NO_TDATASET_TRANSLATE} //deprecated TDataSet procedure translate is omitted
                        {$DEFINE NO_PANSICHAR}
                        {$DEFINE NO_ANSICHAR}
                        {$DEFINE TSYSCHARSET_IS_DEPRECATED} //for compiler warning TSysCharSet is deprected use CharHelper function instead
                        {$DEFINE NO_RAW_HEXTOBIN} //raw/pAnsichar version of HexToBin does not exits
                        {$DEFINE MISS_RBS_SETSTRING_OVERLOAD} //system.SetString is not available for raw strings or i (EH) have no clue how to use it
                        {$DEFINE NO_UNIT_CONTNRS} //unit Contnrs (TObjectList) doesn't exist any mory
                        {$DEFINE WITH_USC2_ANSICOMPARESTR_ONLY} //nextgen doesn't have a raw ansicomnparestr function
                        {$DEFINE WITH_TRECBUF_PBYTE}
                        {$DEFINE WITH_InternalAddRecord_TRecBuf}
                        {$DEFINE WITH_AllocRecBuf_TRecBuf}
                        {$DEFINE WITH_FreeRecBuf_TRecBuf}
                        {$DEFINE NO_WIDESTRING} // no WideString type
                        {$DEFINE NO_SAFECALL} // no safecall calling convention

                        {$IF CompilerVersion <= 30}
                          {$DEFINE NO_UTF8STRING}
                          {$UNDEF WITH_RAWBYTESTRING}
                          {$DEFINE WITH_TBYTES_AS_RAWBYTESTRING} //this compiler is buggy: _RawByteString is declared but skope is in System.pas only (UTF8Encode returns a unusable value f.e.)
                        {$IFEND}
                      {$ENDIF}
                      {$IF CompilerVersion >= 25} //Delphi XE4+
                        {$DEFINE WITH_LEGACIFEND}               //Compiler supports the LEGACYIFEND directive
                        {$DEFINE WITH_VAR_TVALUEBUFFER}	        //GetFieldata overloads using !var! Buffer: TValueBuffer
                        {$DEFINE WITH_BUFFERS_IS_TRECBUF}       //Buffers[index] is TRecBuf type NativeInt
                        {$DEFINE WITH_GETCALCFIELDS_TRECBUF}    //GetCalcFields expected no TRecordBuffer use TRecBuf type NativeInt instead
						{$DEFINE WITH_ZEROBASEDSTRINGS}
                        {$IFNDEF NEXTGEN}
                          {$DEFINE WITH_ANSISTRINGPOS_DEPRECATED} //AnsiStringPos deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRLEN_DEPRECATED}        //StrLen deprecated moved to AnsiStrings
                          {$DEFINE WITH_TOBJECTLIST_REQUIRES_SYSTEM_TYPES} //TObjectList.Remove, add ... are inlined and System.Types
                          {$DEFINE WITH_ANSISTRCOMP_DEPRECATED}   //AnsiStrComp is deprecated moved to AnsiStrings
                          {$DEFINE WITH_ANSISTRLCOMP_DEPRECATED}  //AnsiStrLComp is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRDISPOSE_DEPRECATED}    //StrDispose is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRNEW_DEPRECATED}        //StrNew is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRCOPY_DEPRECATED}       //StrCopy is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRPCOPY_DEPRECATED}      //StrPCopy is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRPLCOPY_DEPRECATED}     //StrPLCopy is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRLCOPY_DEPRECATED}      //StrLCopy is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRLICOPY_DEPRECATED}     //StrLICopy is deprecated moved to AnsiStrings
                          {$DEFINE WITH_STRLICOMP_DEPRECATED}     //StrLIComp is deprecated moved to AnsiStrings
                          {$DEFINE WITH_FLOATTOTEXT_DEPRECATED}   //FloatToText(PAnsi...) is deprecated moved to AnsiStrings
                        {$ENDIF}
                        {$IF CompilerVersion >= 26} //Delphi XE5+
                          {$DEFINE TFIELD_HAS_ASLONGWORD}       //TField has supports virtual AsLongWord Gettet & Setter
                          {$IFDEF NEXTGEN}
                            {$DEFINE WITH_TSYSCHARSET_DEPRECATED}
                            {$IFDEF CPUARM}
                              {$DEFINE FPC_REQUIRES_PROPER_ALIGNMENT} //see https://sourceforge.net/p/zeoslib/tickets/337/
                            {$ENDIF}
                          {$ENDIF}
                          {$IF CompilerVersion >= 27} //Delphi XE6+
                            {$IF CompilerVersion >= 28} //Delphi XE7+
							  {$DEFINE WITH_NETENCODING}
                              {$DEFINE WITH_OMNIXML}
                              {$UNDEF WITH_DBTABLES} //M.A. In Delphi XE7 no BDE
                              {$DEFINE WITH_LIFECYCLES} //TDataSet.DefaultFields is deprecated use LifeCycles instead
                              {$IF CompilerVersion >= 29} //Delphi XE8+
                                {$IF CompilerVersion >= 30} //Delphi XE10 Seattle+
                                  {$IF CompilerVersion >= 31} //Delphi XE10.1 Berlin+
                                    {$IF CompilerVersion >= 32} //Delphi XE10.2 Tokyo+
                                      {$DEFINE WITH_TRYFINALLY_RESULT_EXCEPTION_CHECK} //the compiler is able to see through try finally block, which have nothing todo initializing the result
                                      {$DEFINE WITH_VIRTUAL_TFIELD_GETASGUID} //TField has now a virtual GetAsGUID function
                                      {$DEFINE WITH_IProviderSupportNG}   //TDataset now supports IProviderSupportNG
                                      {$DEFINE WITH_InternalGotoBookmark_TBookmark}
                                      {$DEFINE HAVE_TFIELD_32BIT_ASINTEGER} //TField.AsInteger setter and getter use 32Bit integer
                                      {$DEFINE HAVE_TFIELD_32BIT_ASLONGWORD} //TField.AsLongWord setter and getter use 32Bit unsigned integer
                                      {$DEFINE WITH_VIRTUAL_ASGUID} //TGUIDfield AsGUID has virtual setter and getter
                                      {$IFDEF WITH_PG_WEIGHT_OPT_BUG}
                                        {$UNDEF WITH_PG_WEIGHT_OPT_BUG} //Resolved minimum since XE10.3 or earlier?
                                      {$ENDIF}
                                      {$IF CompilerVersion >= 33} //Delphi XE10.3 Rio+
                                        {$IF CompilerVersion >= 34} // Delphi XE10.4 Sydney
                                          //It seems, this compiler doesn't define NEXTGEN on Android. So we need something else:
                                          {$IF DEFINED(MACOS) or DEFINED(IOS) or DEFINED(ANDROID)}
                                            {$DEFINE NO_UNIT_CONTNRS} //unit Contnrs (TObjectList) doesn't exist any more
                                            {$DEFINE NO_WIDESTRING} // no WideString type
                                            {$DEFINE NO_SAFECALL} // no safecall calling convention
                                          {$IFEND}
                                          {$UNDEF WITH_TWIDEMEMOFIELD_GETASVARIANT_varNULL_BUG} //The bug is resolved.
                                          {$UNDEF WITH_TMEMOFIELD_GETASVARIANT_varNULL_BUG} //The bug is resolved.
                                          {$DEFINE USE_SYNCOBJS_FOR_INLINING} //Add SyncObjs unit to the uses list to resolve a warning about inlining
                                          {$IF CompilerVersion >= 35} //Delphi 11 Alexandria
										    {$DEFINE TCERTIFICATE_HAS_PUBLICKEY}
                                            {$DEFINE MEMORYSTREAM_REALLOC_NATIVEINT} // TMemoryStream.Realloc uses NativeInt instead of Longint
                                            {$IF CompilerVersion >= 36} //Delphi 12 Athens
                                              {$DEFINE NATIVEINT_WEAK_REFERENCE} // TMemoryStream.Realloc uses NativeInt instead of Longint
                                            {$IFEND CompilerVersion >= 36} // Delphi 12 Athens
                                          {$IFEND CompilerVersion >= 35} // Delphi 11 Alexandria
                                        {$IFEND CompilerVersion >= 34}
                                      {$IFEND CompilerVersion >= 33}
                                    {$ELSE !CompilerVersion >= 32} //Delphi Berlin+
                                    {$IFEND CompilerVersion >= 32}
                                  {$ELSE !CompilerVersion >= 31} //Delphi Seattle+
                                  {$IFEND CompilerVersion >= 31}
                                {$ELSE !CompilerVersion >= 30} //Delphi XE8
                                {$IFEND CompilerVersion >= 30}
                              {$ELSE !CompilerVersion >= 29} //Delphi XE7
                              {$IFEND CompilerVersion >= 29}
                            {$ELSE !CompilerVersion >= 28} //Delphi XE6
                            {$IFEND CompilerVersion >= 28}
                          {$ELSE !CompilerVersion >= 27} //Delphi XE5
                          {$IFEND CompilerVersion >= 27}
                        {$ELSE !CompilerVersion >= 26} //Delphi XE4
                        {$IFEND CompilerVersion >= 26}
                      {$ELSE !CompilerVersion >= 25} //Delphi XE3
                      {$IFEND CompilerVersion >= 25}
                    {$ELSE !CompilerVersion >= 24} //Delphi XE2
                    {$IFEND CompilerVersion >= 24}
                  {$ELSE !CompilerVersion >= 23} //Delphi XE
                  {$IFEND CompilerVersion >= 23}
                {$ELSE !CompilerVersion >= 22} //Delphi 2010
                  {$DEFINE WITH_URW1111_ISSUE} //D2010 can't compile for some strange reasons with inlined code.
               {$IFEND CompilerVersion >= 22}
              {$ELSE !CompilerVersion >= 21} //Delphi 2009
                {$DEFINE WITH_INLINE_ANSISTRLCOMP} //AnsiStrLComp is inlined in D2009 only
                {$DEFINE WITH_URW1135_ISSUE} //D2009 can't compile for some strange reasons with inlined code.
              {$IFEND CompilerVersion >= 21} //D2007 Has an internal error with some inlined endian swap code.
            {$IFEND CompilerVersion >= 20} //Delphi 2007
          {$IFEND CompilerVersion >= 18.5} //Delphi 2006
        {$ELSE !CompilerVersion >= 18} //Delphi 2005
          {$DEFINE WITH_C11389_ERROR} //D2005 has some inline problems
        {$IFEND CompilerVersion >= 18}
      {$IFEND CompilerVersion >= 17} //Delphi 8
    {$IFEND CompilerVersion >= 16} //Delphi 7
    {$IF not defined(PatchSystemMove) and defined(WIN32)}
      {$DEFINE FAST_MOVE}
    {$IFEND}
  {$IFEND CompilerVersion < 15}
  {$IF DEFINED(VER360) OR DEFINED(VER370)}
    // see https://zeoslib.sourceforge.io/viewtopic.php?p=261006#p261006
	{$DEFINE ILINK_HAS_TBCD_IN_UNIONS_BUG}
  {$IFEND VER360}
{$ENDIF}

{$IFDEF LINUX}
  {$DEFINE UNIX}
{$ENDIF}
// END of per Delphi version defines

// Debug/release compiler options
{$D+}


{$Z+} //force 4 byte enumerations. We are interfacing with c libraries !!
{$B-} //Boolean short-circuit evaluation
{$H+} //set LongStrings ON
{$T-} //Type-checked pointers OFF
{$X+} //Extended syntax ON

{$IFOPT D-}
{$DEFINE BINARY_RELEASE}
{$ENDIF}

{$IFDEF BINARY_RELEASE}
// Settings for Release mode
{$C-}
{$I-}
{$R-}
{$L-}
{$Q-}
{$IFNDEF FPC}
{$O+}
{$W-}
{$ENDIF}

{$ELSE}

// Settings for Debug mode
{.$C+}
{.$I+}
{.$R+}
{.$L+}
{.$Q+}
{.$IFNDEF FPC}
{.$O-}
{.$W+}
{.$ENDIF}

{$ENDIF}

{$IFOPT R+}
  {$DEFINE RangeCheckEnabled}
{$ENDIF}

{$IFOPT Q+}
  {$DEFINE OverFlowCheckEnabled}
{$ENDIF}

// Disables checking code.
// Use Range checking option to turn on/off optimization
// 2018-09-23 - disabled for now because we don't want to test that with the
// test suites - even though we want the range checks to be enabled.
//{$IFOPT R-}
{$DEFINE DISABLE_CHECKING}
//{$ENDIF}


// Enables MySQL support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_MYSQL}
{$DEFINE ENABLE_MYSQL}
{$ENDIF}

// Enables PostgreSQL support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_POSTGRESQL}
{$DEFINE ENABLE_POSTGRESQL}
{$ENDIF}

// Enables Sybase/MSSQL support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_DBLIB}
{$DEFINE ENABLE_DBLIB}
{$ENDIF}

// Enables ADO support in TZConnection/TZDataset
{$IF defined(MSWINDOWS)}
  {$IF not defined(ZEOS_DISABLE_ADO)}
  {$DEFINE ENABLE_ADO}
  {$IFEND}
{$ELSE}
  {$DEFINE ZEOS_DISABLE_ADO}
{$IFEND}

// Enables Interbase/Firebird support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_INTERBASE}
{$DEFINE ENABLE_INTERBASE}
{$ENDIF}

// Enables Firebird support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_FIREBIRD}
{$DEFINE ENABLE_FIREBIRD}
{$ENDIF}

{$IF defined(ZEOS_DISABLE_FIREBIRD) and defined(ZEOS_DISABLE_INTERBASE)}
{$DEFINE DISABLE_INTERBASE_AND_FIREBIRD}
{$IFEND}

{$IF defined(ZEOS_DISABLE_ADO) and defined(ZEOS_DISABLE_DBLIB) and
     defined(ZEOS_DISABLE_ODBC) and defined(ZEOS_DISABLE_OLEDB)}
  {$DEFINE ZEOS_DISABLE_MSSQL_SYBASE}
{$IFEND}

// Enables SQLite support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_SQLITE}
{$DEFINE ENABLE_SQLITE}
{$ENDIF}

// Enables Oracle support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_ORACLE}
{$DEFINE ENABLE_ORACLE}
{$ENDIF}

// Enables ASA support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_ASA}
{$DEFINE ENABLE_ASA}
{$ENDIF}

// Enables SQLAnywhere support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_SQLANY}
{$DEFINE ENABLE_SQLANY}
{$ENDIF}

// Enables OleDB support in TZConnection/TZDataset
{$IF defined(MSWINDOWS)}
  {$IF not defined(ZEOS_DISABLE_OLEDB)}
  {$DEFINE ENABLE_OLEDB}
  {$IFEND}
{$ELSE}
  {$DEFINE ZEOS_DISABLE_OLEDB}
{$IFEND}

// Enables ODBC support in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_ODBC}
{$DEFINE ENABLE_ODBC}
{$ENDIF}

// Enables Pooled connection support for all enabled db drivers in TZConnection/TZDataset
{$IFNDEF ZEOS_DISABLE_POOLED}
{$DEFINE ENABLE_POOLED}
{$ENDIF}

// Enables Webservice connection support
{$IFNDEF ZEOS_DISABLE_PROXY}
  {$IF DEFINED(HAVE_UNICODESTRING) AND ((NOT DEFINED(FPC)) OR (DEFINED(WINDOWS)))}
    {$DEFINE ENABLE_PROXY}
    {$IF NOT DEFINED(FPC) AND DEFINED(ZEOS_PROXY_USE_INTERNAL_PROXY)}
       {$DEFINE ENABLE_INTERNAL_PROXY}
    {$IFEND}
  {$IFEND}
{$ENDIF}

// Prevents loading default libmysql.dll
{.$DEFINE MYSQL_STRICT_DLL_LOADING}

// Prevents loading default firebird.dll
{.$DEFINE FIREBIRD_STRICT_DLL_LOADING}

// Prevents loading default libpq.dll
{.$DEFINE POSTGRESQL_STRICT_DLL_LOADING}

// Loads libcrypt.so before Firebird client library.
// It fixes error "Undefined symbol: crypt".
{.$DEFINE INTERBASE_CRYPT}

// Excludes old ZeosDBO from the performance tests
{$DEFINE EXCLUDE_OLD_ZEOS_TEST}

// Excludes DBExpress from the performance tests
{$DEFINE EXCLUDE_DBX_TEST}

// Excludes IBX from the performance tests
{$DEFINE EXCLUDE_IBX_TEST}

// Excludes BDE from the performance tests
{$DEFINE EXCLUDE_BDE_TEST}

// Registers property editors for the components.
{$DEFINE WITH_PROPERTY_EDITOR}

// Turn on multithreading  EH???? nowhere used and can't locate the define for compilers
// TODO: seems unused
{.$DEFINE MULTI_THREADED}

// A large database may have many tables, colums and/or procedures!!!
// Therefore there is the ability to show a warning
// before retrieving a list of these database objects
{.$DEFINE SHOW_WARNING}

// Use libfbclient.so under linux
// and not libfbembed.so when Firebird 1.5.2 is used under linux
// TODO: seems unused
{.$DEFINE USELIBFBCLIENTSO}

// Use SynEdit for the SQL Editors.
// Uncomment it when you will use SynEdit instead of a MemoEdit.
// The SynEdit component must be installed on your system.
// You can get SynEdit at http://synedit.sourceforge.net/
// TODO: all uses are commented out. Could they be removed?
{.$DEFINE USE_SYNEDIT}

//run ZSysUtils benchmarks
{.$DEFINE BENCHMARK}

{$IF defined(USE_SYNCOMMONS) and defined(MORMOT2)}
  {$UNDEF USE_SYNCOMMONS}
{$IFEND}

{$IF defined(USE_SYNCOMMONS) or defined(MORMOT2)}
  {$DEFINE WITH_COLUMNS_TO_JSON} //enable JSON content support serialization used by mORMot
{$IFEND}
