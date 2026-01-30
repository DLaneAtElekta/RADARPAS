%% ============================================================================
%% RADARPAS Prolog Translation - Storage Module
%% ============================================================================
%% Translation of picture file management from RADAR.PAS
%% Handles saving/loading pictures, picture catalog, and file operations.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(storage, [
    % Picture catalog management
    make_catalog/1,
    catalog_pics/2,
    catalog_current/2,
    catalog_max/2,

    % Picture operations
    insert_pic/3,
    delete_pic/3,
    select_pic/3,
    next_pic/2,
    prev_pic/2,

    % File operations
    save_pic/3,
    fetch_pic/2,
    load_station_pics/2,

    % Picture filename generation
    pic_filename_from_params/5,

    % Storage menu
    storage_menu_items/2
]).

:- use_module(types).

%% ============================================================================
%% Picture Catalog Structure
%% ============================================================================
%% catalog(Pictures, CurrentIndex, MaxIndex)
%% Pictures: list of pic_rec terms
%% CurrentIndex: index of currently selected picture (0 = none)
%% MaxIndex: number of pictures in catalog

make_catalog(catalog([], 0, 0)).

catalog_pics(catalog(Pics, _, _), Pics).
catalog_current(catalog(_, Curr, _), Curr).
catalog_max(catalog(_, _, Max), Max).

%% ============================================================================
%% Picture Filename Generation
%% ============================================================================

%% pic_filename_from_params(+Hour, +Minute, +Tilt, +Range, +Gain, -FileName)
%% Generate filename from radar parameters
%% Original format: HHMMABC.PIC
%%   HH = hour (2 digits)
%%   MM = minute (2 digits)
%%   A  = tilt index + 'A' (65)
%%   B  = range index + 'A' (65)
%%   C  = gain + '@' (64)
pic_filename_from_params(Hour, Minute, Tilt, Range, Gain, FileName) :-
    H1 is Hour // 10 + 48,
    H2 is Hour mod 10 + 48,
    M1 is Minute // 10 + 48,
    M2 is Minute mod 10 + 48,
    TiltChar is Tilt + 65,
    RangeChar is Range + 65,
    GainChar is Gain + 64,
    atom_codes(FileName, [H1, H2, M1, M2, TiltChar, RangeChar, GainChar,
                          0'., 0'P, 0'I, 0'C]).

%% ============================================================================
%% Picture Catalog Operations
%% ============================================================================

%% insert_pic(+PicRec, +CatalogIn, -CatalogOut)
%% Insert picture into catalog, sorted by file date/time
%% Original: procedure InsertPic
insert_pic(NewPic, catalog(Pics, _, Max), catalog(NewPics, NewMax, NewMax)) :-
    insert_sorted(NewPic, Pics, NewPics),
    NewMax is Max + 1.

%% Insert in sorted order by file date, then file time
insert_sorted(Pic, [], [Pic]).
insert_sorted(NewPic, [Pic | Rest], [NewPic, Pic | Rest]) :-
    pic_file_date(Pic, D1),
    pic_file_date(NewPic, D2),
    (   D1 > D2
    ->  true
    ;   D1 =:= D2,
        pic_file_time(Pic, T1),
        pic_file_time(NewPic, T2),
        T1 > T2
    ).
insert_sorted(NewPic, [Pic | Rest], [Pic | NewRest]) :-
    pic_file_date(Pic, D1),
    pic_file_date(NewPic, D2),
    (   D1 < D2
    ->  true
    ;   D1 =:= D2,
        pic_file_time(Pic, T1),
        pic_file_time(NewPic, T2),
        T1 =< T2
    ),
    insert_sorted(NewPic, Rest, NewRest).

%% delete_pic(+Index, +CatalogIn, -CatalogOut)
%% Delete picture at given index (1-based)
%% Original: part of Storage procedure
delete_pic(Index, catalog(Pics, Curr, Max), catalog(NewPics, NewCurr, NewMax)) :-
    Index >= 1,
    Index =< Max,
    nth1(Index, Pics, _Deleted, NewPics),
    NewMax is Max - 1,
    (   Curr > NewMax -> NewCurr = NewMax
    ;   Curr >= Index -> NewCurr is max(0, Curr - 1)
    ;   NewCurr = Curr
    ).

%% select_pic(+Index, +CatalogIn, -CatalogOut)
%% Select picture by index
select_pic(Index,
    catalog(Pics, _, Max),
    catalog(Pics, Index, Max)
) :-
    Index >= 0,
    Index =< Max.

%% next_pic(+CatalogIn, -CatalogOut)
%% Move to next picture in catalog
%% Original: '+' key in ModemLoop
next_pic(
    catalog(Pics, Curr, Max),
    catalog(Pics, Next, Max)
) :-
    (   Curr < Max
    ->  Next is Curr + 1
    ;   Next = Curr
    ).

%% prev_pic(+CatalogIn, -CatalogOut)
%% Move to previous picture in catalog
%% Original: '-' key in ModemLoop
prev_pic(
    catalog(Pics, Curr, Max),
    catalog(Pics, Prev, Max)
) :-
    (   Curr > 0
    ->  Prev is Curr - 1
    ;   Prev = 0
    ).

%% ============================================================================
%% File Operations
%% ============================================================================

%% save_pic(+PicRec, +PicData, -Result)
%% Save picture data to disk with metadata
%% Original: procedure SavePic
%% Creates file named HHMMABC.PIC containing raw picture data
save_pic(PicRec, PicData, Result) :-
    pic_time(PicRec, TimeRec),
    time_hour(TimeRec, Hour),
    time_minute(TimeRec, Minute),
    pic_tilt(PicRec, Tilt),
    pic_range(PicRec, Range),
    pic_gain(PicRec, Gain),
    pic_filename_from_params(Hour, Minute, Tilt, Range, Gain, FileName),
    (   catch(
            (   open(FileName, write, Stream, [type(binary)]),
                maplist(put_byte(Stream), PicData),
                close(Stream),
                Result = ok(FileName)
            ),
            Error,
            Result = error(Error)
        )
    ).

%% fetch_pic(+FileName, -PicData)
%% Load picture data from disk
%% Original: procedure FetchPic
fetch_pic(FileName, PicData) :-
    (   exists_file(FileName)
    ->  read_file_to_codes(FileName, PicData, [type(binary)])
    ;   PicData = []
    ).

%% load_station_pics(+StationDir, -Catalog)
%% Load all .PIC files from a station directory into catalog
%% Original: part of LoadStation procedure
load_station_pics(StationDir, catalog(Pics, 0, NumPics)) :-
    format(atom(Pattern), '~w/*.PIC', [StationDir]),
    expand_file_name(Pattern, Files),
    maplist(file_to_pic_rec, Files, Pics),
    length(Pics, NumPics).

%% file_to_pic_rec(+FilePath, -PicRec)
%% Parse .PIC filename to extract parameters
file_to_pic_rec(FilePath, pic_rec(FileName, 0, 0, time_rec(Hour, Minute), Tilt, Range, Gain)) :-
    file_base_name(FilePath, FileName),
    atom_codes(FileName, Codes),
    Codes = [H1, H2, M1, M2, TiltC, RangeC, GainC | _],
    Hour is (H1 - 48) * 10 + (H2 - 48),
    Minute is (M1 - 48) * 10 + (M2 - 48),
    Tilt is TiltC - 65,
    Range is RangeC - 65,
    Gain is GainC - 64.

%% ============================================================================
%% Storage Menu
%% ============================================================================

%% storage_menu_items(+Catalog, -MenuItems)
%% Generate menu display items for the Storage dialog
%% Original: procedure Storage - shows time, tilt, range, gain per picture
storage_menu_items(catalog(Pics, _, _), MenuItems) :-
    length(Pics, N),
    numlist(1, N, Indices),
    maplist(pic_menu_item, Indices, Pics, MenuItems).

pic_menu_item(Index, PicRec, menu_item(Index, TimeStr, TiltVal, RangeVal, GainStr)) :-
    pic_time(PicRec, TimeRec),
    time_hour(TimeRec, Hour),
    time_minute(TimeRec, Minute),
    format_time_display(Hour, Minute, TimeStr),
    pic_tilt(PicRec, TiltIdx),
    tilt_value(TiltIdx, TiltVal),
    pic_range(PicRec, RangeIdx),
    range_value(RangeIdx, RangeVal),
    pic_gain(PicRec, Gain),
    (   Gain < 17
    ->  number_codes(Gain, GainCodes), atom_codes(GainStr, GainCodes)
    ;   GainStr = 'PRE'
    ).

format_time_display(Hour, Minute, Str) :-
    format(atom(Str), '~|~`0t~d~2+:~|~`0t~d~2+', [Hour, Minute]).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
