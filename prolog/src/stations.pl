%% ============================================================================
%% RADARPAS Prolog Translation - Station Management Module
%% ============================================================================
%% Translation of station selection, loading, adding, and deleting from
%% RADAR.PAS. Manages the station directory and phone number configuration.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(stations, [
    % Station record
    make_station/3,
    station_name/2,
    station_phone/2,

    % Station directory
    make_station_dir/1,
    station_list/2,
    station_count/2,

    % Station operations
    load_station/3,
    add_station/4,
    del_station/3,
    select_station/3,

    % Phone number operations
    load_phone_number/2,
    save_phone_number/3,

    % Map data operations
    load_map_data/3,

    % Station directory listing
    list_stations/2,
    station_by_letter/3
]).

:- use_module(types).

%% ============================================================================
%% Station Record
%% ============================================================================
%% station(Name, PhoneNum)
%% Name: station directory name (up to 8 chars + .STA extension)
%% PhoneNum: modem phone number string

make_station(Name, Phone, station(Name, Phone)).
station_name(station(Name, _), Name).
station_phone(station(_, Phone), Phone).

%% ============================================================================
%% Station Directory
%% ============================================================================
%% station_dir(Stations, CurrentStation)
%% Stations: list of station records
%% CurrentStation: currently selected station name ('' if none)

make_station_dir(station_dir([], '')).

station_list(station_dir(Stations, _), Stations).
station_count(station_dir(Stations, _), Count) :-
    length(Stations, Count).

%% ============================================================================
%% Station Operations
%% ============================================================================

%% load_station(+StationName, +BasePath, -StationData)
%% Load a station's configuration from its directory
%% Original: procedure LoadStation
%% Reads PHONENUM.TXT and scans for *.PIC files
load_station(StationName, BasePath, station_data(Station, MapData1, MapData2, PicCatalog)) :-
    % Construct station directory path
    format(atom(StationPath), '~w/~w', [BasePath, StationName]),

    % Load phone number
    format(atom(PhonePath), '~w/PHONENUM.TXT', [StationPath]),
    load_phone_number(PhonePath, Phone),
    make_station(StationName, Phone, Station),

    % Load map overlay data
    format(atom(Map1Path), '~w/MAP1.DAT', [StationPath]),
    format(atom(Map2Path), '~w/MAP2.DAT', [StationPath]),
    load_map_data(Map1Path, map1, MapData1),
    load_map_data(Map2Path, map2, MapData2),

    % Load picture catalog
    load_station_pics_from_dir(StationPath, PicCatalog).

%% add_station(+Name, +Phone, +DirIn, -DirOut)
%% Add a new station to the directory
%% Original: procedure AddStation (nested in SelectStation)
add_station(Name, Phone, station_dir(Stations, Curr), station_dir(NewStations, Curr)) :-
    atom_concat(Name, '.STA', StationDir),
    make_station(StationDir, Phone, NewStation),
    append(Stations, [NewStation], NewStations).

%% del_station(+StationName, +DirIn, -DirOut)
%% Remove a station from the directory
%% Original: procedure DelStation (nested in SelectStation)
del_station(StationName, station_dir(Stations, Curr), station_dir(NewStations, NewCurr)) :-
    exclude(station_matches(StationName), Stations, NewStations),
    (   Curr = StationName -> NewCurr = ''
    ;   NewCurr = Curr
    ).

station_matches(Name, station(Name, _)).

%% select_station(+Index, +DirIn, -DirOut)
%% Select station by letter index (A=1, B=2, etc.)
%% Original: part of SelectStation procedure
select_station(LetterIndex, station_dir(Stations, _), station_dir(Stations, SelectedName)) :-
    nth1(LetterIndex, Stations, Station),
    station_name(Station, SelectedName).

%% ============================================================================
%% Phone Number Operations
%% ============================================================================

%% load_phone_number(+FilePath, -PhoneNum)
%% Read phone number from PHONENUM.TXT
%% Original: part of LoadStation
load_phone_number(FilePath, Phone) :-
    (   exists_file(FilePath)
    ->  catch(
            (   open(FilePath, read, Stream),
                read_line_to_string(Stream, Phone),
                close(Stream)
            ),
            _Error,
            Phone = ''
        )
    ;   Phone = ''
    ).

%% save_phone_number(+StationPath, +Phone, -Result)
%% Write phone number to PHONENUM.TXT
%% Original: part of AddStation
save_phone_number(StationPath, Phone, Result) :-
    format(atom(FilePath), '~w/PHONENUM.TXT', [StationPath]),
    (   Phone \= ''
    ->  catch(
            (   open(FilePath, write, Stream),
                write(Stream, Phone),
                nl(Stream),
                close(Stream),
                Result = ok
            ),
            Error,
            Result = error(Error)
        )
    ;   Result = ok   % No phone number to save
    ).

%% ============================================================================
%% Map Data Operations
%% ============================================================================

%% load_map_data(+FilePath, +MapId, -MapData)
%% Load map overlay data from MAP1.DAT or MAP2.DAT
%% Original: BlockRead(MapFile, Map1/Map2, FileSize)
load_map_data(FilePath, MapId, map_data(MapId, Data)) :-
    (   exists_file(FilePath)
    ->  catch(
            read_file_to_codes(FilePath, Data, [type(binary)]),
            _Error,
            Data = []
        )
    ;   Data = []
    ).

%% ============================================================================
%% Station Directory Listing
%% ============================================================================

%% list_stations(+StationDir, -StationLetters)
%% List stations with letter assignments (A, B, C, ...)
%% Original: part of SelectStation - iterates *.STA directories
list_stations(station_dir(Stations, _), StationLetters) :-
    length(Stations, N),
    numlist(1, N, Indices),
    maplist(station_letter, Indices, Stations, StationLetters).

station_letter(Index, Station, letter_entry(Letter, Name)) :-
    station_name(Station, Name),
    LetterCode is Index + 64,  % A=65, B=66, ...
    char_code(Letter, LetterCode).

%% station_by_letter(+Letter, +StationDir, -Station)
%% Look up station by letter
station_by_letter(Letter, station_dir(Stations, _), Station) :-
    char_code(Letter, Code),
    Index is Code - 64,
    nth1(Index, Stations, Station).

%% ============================================================================
%% Internal Helpers
%% ============================================================================

%% load_station_pics_from_dir(+DirPath, -PicCatalog)
%% Scan directory for .PIC files and build catalog
load_station_pics_from_dir(DirPath, catalog(Pics, 0, NumPics)) :-
    format(atom(Pattern), '~w/*.PIC', [DirPath]),
    (   catch(expand_file_name(Pattern, Files), _, Files = [])
    ->  true
    ;   Files = []
    ),
    include(is_pic_file, Files, PicFiles),
    maplist(parse_pic_filename, PicFiles, Pics),
    length(Pics, NumPics).

is_pic_file(File) :-
    file_name_extension(_, pic, File).
is_pic_file(File) :-
    file_name_extension(_, 'PIC', File).

parse_pic_filename(FilePath, pic_rec(BaseName, 0, 0, time_rec(Hour, Minute), Tilt, Range, Gain)) :-
    file_base_name(FilePath, BaseName),
    atom_codes(BaseName, [H1, H2, M1, M2, TiltC, RangeC, GainC | _]),
    Hour is (H1 - 48) * 10 + (H2 - 48),
    Minute is (M1 - 48) * 10 + (M2 - 48),
    Tilt is TiltC - 65,
    Range is RangeC - 65,
    Gain is GainC - 64.
parse_pic_filename(_, pic_rec('UNKNOWN', 0, 0, time_rec(0, 0), 0, 0, 1)).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
