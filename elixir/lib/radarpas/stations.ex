defmodule Radarpas.Stations do
  @moduledoc """
  Station management module.
  Translated from the station-related routines in RADAR.PAS (lines 1204-1393).

  The original system stored each station as a subdirectory with a .STA extension,
  containing PHONENUM.TXT (modem phone number), MAP1.DAT, MAP2.DAT (map overlays),
  and *.PIC files (radar pictures). Stations were enumerated using DOS FindFirst/
  FindNext (INT 21h, AH=$4E/$4F) with the mask '????????.STA'.

  Original procedures translated:
    LoadStation, SelectStation, AddStation, DelStation, CallStation
  """

  alias Radarpas.CoreTypes.PicRec
  alias Radarpas.Screen.{Landmark, Segment}

  # ============================================================================
  # Station Record
  # Original global variables: StationName, PhoneNum, Map1, Map2, Map1Size,
  #   Pic[0..100], CurrPic, MaxPic, Stat['A'..'M']
  # ============================================================================

  defstruct name: "",
            phone: "",
            pics: [],
            curr_pic: 0,
            max_pic: 0,
            map1: %{landmarks: [], segments: []},
            map2: %{landmarks: [], segments: []}

  @doc """
  Load station data from a directory.
  Original: procedure LoadStation - lines 1204-1250
  Changed into the station directory, read PHONENUM.TXT,
  loaded MAP1.DAT and MAP2.DAT, then enumerated all *.PIC files
  using DOS directory search (SetDir/DirEntry).
  """
  def load_station(base_dir, station_name) do
    station_dir = Path.join(base_dir, station_name)

    with {:ok, _} <- check_directory(station_dir) do
      # Read phone number
      phone =
        case File.read(Path.join(station_dir, "PHONENUM.TXT")) do
          {:ok, content} -> String.trim(content)
          {:error, _} -> ""
        end

      # Load map data
      map1 = load_map_data(station_dir, "MAP1.DAT")
      map2 = load_map_data(station_dir, "MAP2.DAT")

      # Enumerate picture files
      # Original: SetDir('????????.PIC'+#0,$00) then while not ErrorFlag loop
      pics = load_picture_list(station_dir)

      station = %__MODULE__{
        name: station_name,
        phone: phone,
        pics: pics,
        curr_pic: 0,
        max_pic: length(pics),
        map1: map1,
        map2: map2
      }

      {:ok, station}
    end
  end

  @doc """
  List all station directories in the base directory.
  Original: within SelectStation (lines 1362-1367)
  Used SetDir('????????.STA'+#0,$10) with attribute $10 (directory).
  Stations were assigned letters A-M for selection.
  """
  def list_stations(base_dir) do
    case File.ls(base_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".STA"))
        |> Enum.sort()
        |> Enum.with_index()
        |> Enum.map(fn {name, idx} -> {<<idx + ?A>>, name} end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Add a new station.
  Original: procedure AddStation (nested in SelectStation) - lines 1303-1331
  Created the .STA directory and wrote PHONENUM.TXT.
  """
  def add_station(base_dir, name, phone_num) do
    station_name = name <> ".STA"
    station_dir = Path.join(base_dir, station_name)

    case File.mkdir(station_dir) do
      :ok ->
        if phone_num != "" do
          File.write(Path.join(station_dir, "PHONENUM.TXT"), phone_num <> "\n")
        end

        {:ok, station_name}

      {:error, reason} ->
        {:error, "Unable to create directory: #{reason}"}
    end
  end

  @doc """
  Delete a station and all its contents.
  Original: procedure DelStation (nested in SelectStation) - lines 1333-1354
  Changed into the directory, deleted all files using SetDir('????????.???'),
  then changed back and removed the directory with RmDir.
  """
  def delete_station(base_dir, station_name) do
    station_dir = Path.join(base_dir, station_name)

    case File.rm_rf(station_dir) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, "Cannot delete station: #{reason}"}
    end
  end

  @doc """
  Format a station entry for the selection menu.
  Original: within SelectStation (lines 1365-1366)
  Displayed letter key and station directory name.
  """
  def format_station_entry({letter, name}) do
    " #{letter} \xB3 #{String.pad_trailing(name, 12)}"
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_directory(dir) do
    if File.dir?(dir), do: {:ok, dir}, else: {:error, "Directory not found: #{dir}"}
  end

  @doc """
  Load map overlay data from a binary file.
  Original: within LoadStation (lines 1222-1235)
  Map data was stored as raw binary records:
  - Landmarks: 8 bytes each (Bear:int, Range:int, Name:3 chars, padding:1 byte)
  - Segments: 8 bytes each (Range1:int, Bear1:int, Range2:int, Bear2:int)
  Landmarks come first (terminated by zero bear+range), then segments.
  """
  def load_map_data(station_dir, filename) do
    path = Path.join(station_dir, filename)

    case File.read(path) do
      {:ok, data} ->
        parse_map_data(data)

      {:error, _} ->
        %{landmarks: [], segments: []}
    end
  end

  defp parse_map_data(data) do
    {landmarks, rest} = parse_landmarks(data, [])
    {segments, _} = parse_segments(rest, [])
    %{landmarks: landmarks, segments: segments}
  end

  defp parse_landmarks(<<0::16-little, 0::16-little, _rest::binary>> = data, acc) do
    # Zero bearing and range = end of landmarks, start of segments
    {Enum.reverse(acc), data}
  end

  defp parse_landmarks(
         <<bear::16-little, range::16-little, n1, n2, n3, _pad, rest::binary>>,
         acc
       ) do
    landmark = %Landmark{bearing: bear, range: range, name: <<n1, n2, n3>>}
    parse_landmarks(rest, [landmark | acc])
  end

  defp parse_landmarks(data, acc), do: {Enum.reverse(acc), data}

  defp parse_segments(<<0::16-little, 0::16-little, _rest::binary>>, acc) do
    {Enum.reverse(acc), <<>>}
  end

  defp parse_segments(
         <<r1::16-little, b1::16-little, r2::16-little, b2::16-little, rest::binary>>,
         acc
       ) do
    segment = %Segment{range1: r1, bearing1: b1, range2: r2, bearing2: b2}
    parse_segments(rest, [segment | acc])
  end

  defp parse_segments(data, acc), do: {Enum.reverse(acc), data}

  defp load_picture_list(station_dir) do
    case File.ls(station_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".PIC"))
        |> Enum.sort()
        |> Enum.map(fn name ->
          case PicRec.parse_file_name(name) do
            {:ok, pic} ->
              # Get file metadata for date sorting
              path = Path.join(station_dir, name)

              case File.stat(path) do
                {:ok, %File.Stat{mtime: mtime}} ->
                  {{y, m, d}, {h, min, _s}} = mtime

                  %{
                    pic
                    | file_name: path,
                      time: %Radarpas.CoreTypes.TimeRec{
                        year: y,
                        month: m,
                        day: d,
                        hour: h,
                        minute: min
                      }
                  }

                _ ->
                  %{pic | file_name: path}
              end

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end
end
