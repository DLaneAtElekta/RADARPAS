// =============================================================================
// Picture encode/decode — maps between RLE-compressed storage and bitmap form
// =============================================================================
// Original Pascal DispLine procedure decompresses radar scan lines:
//   [LineNum:2bytes] [segments...] [0x18 terminator]
//   Each segment: [ColorSize:1byte] [Length:1byte]
//     Bits 5-6 of ColorSize → color (0=none, 1=red, 2=green, 3=both)
//     Bits 0-2 of ColorSize << 8 | Length → pixel run length (up to 2048)
//
// This module provides pure, side-effect-free codec predicates.
// =============================================================================

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;

namespace Radarpas;

/// <summary>Color of a radar pixel run (maps to EGA planes 0=red, 1=green)</summary>
public enum RadarColor : byte
{
    None  = 0,  // background
    Red   = 1,  // plane 0 only
    Green = 2,  // plane 1 only
    Both  = 3   // planes 0+1 (yellow on EGA)
}

/// <summary>A single run-length segment: pixel(Color, Count)</summary>
public readonly record struct PixelRun(RadarColor Color, int Count);

/// <summary>A decoded scan line: line(LineNum, Segments)</summary>
public sealed record BitmapLine(int LineNum, ImmutableArray<PixelRun> Segments)
{
    /// <summary>Total pixel width of this line</summary>
    public int Width => Segments.Sum(s => s.Count);
}

/// <summary>
/// Pure codec for radar picture data.
/// Prolog equivalents:
///   decode_picture(+Bytes, -Lines)
///   encode_picture(+Lines, -Bytes)
///   bitmap_to_storage(+Lines, -FlatPixels)
///   storage_to_bitmap(+FlatPixels, +Width, -Lines)
/// </summary>
public static class PictureCodec
{
    private const byte Terminator = 0x18;

    // -----------------------------------------------------------------------
    // Decode: compressed bytes → list of BitmapLine
    // -----------------------------------------------------------------------

    /// <summary>
    /// decode_picture(+CompressedBytes, -BitmapLines).
    /// Decompresses RLE-encoded radar picture into structured bitmap lines.
    /// </summary>
    public static ImmutableList<BitmapLine> Decode(ReadOnlySpan<byte> compressed)
    {
        var lines = ImmutableList.CreateBuilder<BitmapLine>();
        int pos = 0;

        while (pos + 2 < compressed.Length)
        {
            // First 2 bytes: line number (little-endian, as in original Pascal)
            int lineNum = compressed[pos] | (compressed[pos + 1] << 8);
            pos += 2;

            // Sanity check — line numbers in range [0, 350] for EGA
            if (lineNum > 500) break;

            var segments = ImmutableArray.CreateBuilder<PixelRun>();

            // Decode segments until terminator or end of data
            while (pos + 1 < compressed.Length)
            {
                byte header = compressed[pos];
                if (header == Terminator) { pos += 2; break; } // +2 skips terminator pair

                byte lengthByte = compressed[pos + 1];
                pos += 2;

                // Bits 5-6: color, bits 0-2 << 8 | lengthByte: run length
                var color = (RadarColor)((header >> 5) & 0x03);
                int count = ((header & 0x07) << 8) | lengthByte;

                if (count > 0)
                    segments.Add(new PixelRun(color, count));
            }

            lines.Add(new BitmapLine(lineNum, segments.ToImmutable()));
        }

        return lines.ToImmutable();
    }

    /// <summary>Convenience overload for ImmutableArray</summary>
    public static ImmutableList<BitmapLine> Decode(ImmutableArray<byte> compressed) =>
        Decode(compressed.AsSpan());

    // -----------------------------------------------------------------------
    // Encode: list of BitmapLine → compressed bytes
    // -----------------------------------------------------------------------

    /// <summary>
    /// encode_picture(+BitmapLines, -CompressedBytes).
    /// Compresses bitmap lines back to the original RLE storage format.
    /// </summary>
    public static ImmutableArray<byte> Encode(IReadOnlyList<BitmapLine> lines)
    {
        var buf = ImmutableArray.CreateBuilder<byte>();

        foreach (var line in lines)
        {
            // Line number (little-endian)
            buf.Add((byte)(line.LineNum & 0xFF));
            buf.Add((byte)((line.LineNum >> 8) & 0xFF));

            foreach (var seg in line.Segments)
            {
                // Pack color into bits 5-6, high bits of count into bits 0-2
                byte header = (byte)(((byte)seg.Color << 5) | ((seg.Count >> 8) & 0x07));
                byte lo = (byte)(seg.Count & 0xFF);
                buf.Add(header);
                buf.Add(lo);
            }

            // Terminator pair
            buf.Add(Terminator);
            buf.Add(0x00);
        }

        return buf.ToImmutable();
    }

    // -----------------------------------------------------------------------
    // Bitmap ↔ flat storage conversion
    // -----------------------------------------------------------------------

    /// <summary>
    /// bitmap_to_storage(+Lines, -FlatPixels).
    /// Expands RLE segments into a flat array of RadarColor values,
    /// one per pixel, arranged by scan line. Useful for rendering.
    /// </summary>
    public static ImmutableArray<RadarColor> BitmapToStorage(
        IReadOnlyList<BitmapLine> lines, int width, int height)
    {
        var pixels = new RadarColor[width * height];

        foreach (var line in lines)
        {
            if (line.LineNum < 0 || line.LineNum >= height) continue;
            int offset = line.LineNum * width;
            int x = 0;

            foreach (var seg in line.Segments)
            {
                int end = Math.Min(x + seg.Count, width);
                for (int i = x; i < end; i++)
                    pixels[offset + i] = seg.Color;
                x = end;
            }
        }

        return ImmutableArray.Create(pixels);
    }

    /// <summary>
    /// storage_to_bitmap(+FlatPixels, +Width, -Lines).
    /// Run-length encodes a flat pixel array back into BitmapLines.
    /// </summary>
    public static ImmutableList<BitmapLine> StorageToBitmap(
        ReadOnlySpan<RadarColor> pixels, int width, int height)
    {
        var lines = ImmutableList.CreateBuilder<BitmapLine>();

        for (int y = 0; y < height; y++)
        {
            var row = pixels.Slice(y * width, width);
            var segments = ImmutableArray.CreateBuilder<PixelRun>();
            int x = 0;

            while (x < width)
            {
                var color = row[x];
                int count = 1;
                while (x + count < width && row[x + count] == color && count < 2047)
                    count++;
                segments.Add(new PixelRun(color, count));
                x += count;
            }

            // Only emit non-empty lines (lines with at least one non-background pixel)
            if (segments.Any(s => s.Color != RadarColor.None))
                lines.Add(new BitmapLine(y, segments.ToImmutable()));
        }

        return lines.ToImmutable();
    }

    // -----------------------------------------------------------------------
    // EGA plane extraction — for faithful rendering of the original format
    // -----------------------------------------------------------------------

    /// <summary>
    /// Extract a single EGA bit-plane from bitmap lines.
    /// Plane 0 = red channel, Plane 1 = green channel.
    /// Returns packed bytes (8 pixels per byte, MSB first) per scan line,
    /// matching the original Mem[$A000:offset] layout.
    /// </summary>
    public static ImmutableArray<byte> ExtractPlane(
        IReadOnlyList<BitmapLine> lines, int plane, int bytesPerLine, int height)
    {
        byte planeBit = (byte)(1 << plane);
        var buffer = new byte[bytesPerLine * height];

        foreach (var line in lines)
        {
            if (line.LineNum < 0 || line.LineNum >= height) continue;
            int byteOffset = line.LineNum * bytesPerLine;
            int bitPos = 0;

            foreach (var seg in line.Segments)
            {
                bool on = ((byte)seg.Color & planeBit) != 0;
                for (int i = 0; i < seg.Count; i++)
                {
                    if (on)
                        buffer[byteOffset + bitPos / 8] |= (byte)(0x80 >> (bitPos % 8));
                    bitPos++;
                    if (bitPos / 8 >= bytesPerLine) break;
                }
            }
        }

        return ImmutableArray.Create(buffer);
    }

    // -----------------------------------------------------------------------
    // Filename codec — HHMM<tilt><range><gain>.WX
    // -----------------------------------------------------------------------

    /// <summary>
    /// pic_filename(+PicRec, -FileName).
    /// Encodes picture parameters into the canonical filename format.
    /// </summary>
    public static string EncodeFilename(PicRec pic)
    {
        int hour = pic.TimeOfPic.Minute / 60;
        int min  = pic.TimeOfPic.Minute % 60;
        char tilt  = (char)('A' + pic.Tilt);
        char range = (char)('A' + pic.Range);
        char gain  = (char)('@' + pic.Gain);
        return $"{hour:D2}{min:D2}{tilt}{range}{gain}.WX";
    }

    /// <summary>
    /// parse_pic_filename(+FileName, -PicRec).
    /// Decodes a filename back into a skeleton PicRec.
    /// Returns null if the filename doesn't match the expected format.
    /// </summary>
    public static PicRec? DecodeFilename(string fileName)
    {
        if (fileName.Length < 7) return null;

        var span = fileName.AsSpan();
        if (!int.TryParse(span[..2], out int hour) || hour >= 24) return null;
        if (!int.TryParse(span[2..4], out int min) || min >= 60) return null;

        byte tilt  = (byte)(span[4] - 'A');
        byte range = (byte)(span[5] - 'A');
        byte gain  = (byte)(span[6] - '@');

        if (tilt > 11 || range > 4 || gain < 1 || gain > 17) return null;

        return PicRec.Empty with
        {
            Tilt = tilt,
            Range = range,
            Gain = gain,
            TimeOfPic = new TimeRec(0, (ushort)(hour * 60 + min), 0)
        };
    }
}
