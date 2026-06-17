defmodule Radarpas.Pictures do
  @moduledoc """
  Picture storage and management module.
  Translated from the Storage section of RADAR.PAS (lines 1076-1202).

  The original system stored radar pictures as compressed scan-line data
  in files with the format HHMM<tilt><range><gain>.PIC.
  Pictures were managed in a 100-element array (Pic[0..100]) sorted by
  file date/time. The PicSave buffer used a clever signed-index technique
  (array[-20000..30000]) to allow up to 50KB of picture data storage.

  Original procedures translated:
    FetchPic, InsertPic, SavePic, Storage
  """

  alias Radarpas.CoreTypes.PicRec
  alias Radarpas.Graphics

  @doc """
  Load and display a picture from disk.
  Original: procedure FetchPic - lines 1080-1109
  Read the picture file into PicSave buffer, then decoded and displayed
  each scan line using DispLine until line 351.
  """
  def fetch_pic(pics, curr_pic, screen_state) do
    if curr_pic == 0 or curr_pic > length(pics) do
      # No picture selected - clear radar display
      {:ok, Graphics.clear_screen(Radarpas.Screen.circle1()), screen_state}
    else
      pic = Enum.at(pics, curr_pic - 1)

      case File.read(pic.file_name) do
        {:ok, data} ->
          # Decode and display all scan lines
          {commands, _} = decode_picture(data)
          {:ok, commands, screen_state}

        {:error, reason} ->
          {:error, "Cannot find that picture file: #{reason}"}
      end
    end
  end

  @doc """
  Decode an entire picture from its binary data.
  Original: the while loop in FetchPic (lines 1102-1106)
  Iterated through PicSave buffer, calling DispLine for each line
  until LastLine >= 351.
  """
  def decode_picture(data) when is_binary(data) do
    do_decode_picture(data, 0, [])
  end

  defp do_decode_picture(<<>>, _offset, acc), do: {Enum.reverse(acc), :complete}

  defp do_decode_picture(data, offset, acc) when byte_size(data) > 4 do
    {line_num, commands} = Graphics.disp_line(data)

    if line_num >= 351 do
      {Enum.reverse(List.flatten([commands | acc])), :complete}
    else
      # Find next line by scanning for $18 terminator
      line_size = find_line_end(data, 2)

      if line_size < byte_size(data) do
        rest = binary_part(data, line_size, byte_size(data) - line_size)
        do_decode_picture(rest, offset + line_size, [commands | acc])
      else
        {Enum.reverse(List.flatten([commands | acc])), :truncated}
      end
    end
  end

  defp do_decode_picture(_data, _offset, acc), do: {Enum.reverse(acc), :truncated}

  defp find_line_end(data, pos) when pos + 1 < byte_size(data) do
    if :binary.at(data, pos) == 0x18 and :binary.at(data, pos - 1) == 0x18 do
      pos + 2
    else
      find_line_end(data, pos + 2)
    end
  end

  defp find_line_end(data, _pos), do: byte_size(data)

  @doc """
  Insert a picture into the sorted list by date/time.
  Original: procedure InsertPic(ForPic: PicRec) - lines 1111-1125
  Scanned through the array comparing FileDate and FileTime fields.
  """
  def insert_pic(pics, %PicRec{} = new_pic) do
    {before, after_} =
      Enum.split_while(pics, fn pic ->
        cond do
          pic.file_date > new_pic.file_date -> false
          pic.file_date == new_pic.file_date and pic.file_time > new_pic.file_time -> false
          true -> true
        end
      end)

    before ++ [new_pic] ++ after_
  end

  @doc """
  Save a picture to disk.
  Original: procedure SavePic(Size: integer) - lines 1127-1146
  Generated filename from time/tilt/range/gain, then wrote the
  PicSave buffer contents to the .PIC file.
  """
  def save_pic(%PicRec{} = pic, data) when is_binary(data) do
    file_name = PicRec.generate_file_name(pic)

    case File.write(file_name, data) do
      :ok ->
        {:ok, %{pic | file_name: file_name}}

      {:error, reason} ->
        {:error, "Cannot save picture: #{reason}"}
    end
  end

  @doc """
  Delete a picture file and remove from the list.
  Original: within Storage procedure (lines 1186-1192)
  Called Erase(PicFile) and shifted remaining entries down.
  """
  def delete_pic(pics, index) when index > 0 and index <= length(pics) do
    pic = Enum.at(pics, index - 1)

    case File.rm(pic.file_name) do
      :ok ->
        new_pics = List.delete_at(pics, index - 1)
        {:ok, new_pics}

      {:error, reason} ->
        {:error, "Cannot delete picture: #{reason}"}
    end
  end

  @doc """
  Format a picture entry for display in the storage menu.
  Original: within Storage procedure (lines 1170-1178)
  Displayed Time, TiltVal, RangeVal, and Gain.
  """
  def format_pic_entry(%PicRec{} = pic) do
    alias Radarpas.CoreTypes

    time_str = format_time(pic.time)
    tilt_str = String.pad_leading("#{CoreTypes.tilt_val(pic.tilt)}", 4)
    range_str = String.pad_leading("#{CoreTypes.range_val(pic.range)}", 6)

    gain_str =
      if pic.gain < 17,
        do: String.pad_leading("#{pic.gain}", 5),
        else: "  PRE"

    "  #{time_str}#{tilt_str}#{range_str}#{gain_str}"
  end

  defp format_time(%Radarpas.CoreTypes.TimeRec{hour: h, minute: m}) do
    h_str = String.pad_leading("#{h}", 2)
    m_str = String.pad_leading("#{m}", 2, "0")
    "#{h_str}:#{m_str}"
  end
end
