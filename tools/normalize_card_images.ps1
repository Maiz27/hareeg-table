param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir,

  [int]$TargetWidth = 512,
  [int]$TargetHeight = 736,
  [int]$Threshold = 120,
  [int]$Padding = 8,
  [int]$CornerRadius = 28
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$normalizerSource = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public sealed class NormalizedCardRow
{
    public string Id;
    public string SourceName;
    public string OutputPath;
    public int SourceWidth;
    public int SourceHeight;
    public int CropX;
    public int CropY;
    public int CropWidth;
    public int CropHeight;
    public int TargetWidth;
    public int TargetHeight;
}

public static class CardBatchNormalizer
{
    public static NormalizedCardRow[] Run(
        string inputDir,
        string outputDir,
        int targetWidth,
        int targetHeight,
        int threshold,
        int padding,
        int cornerRadius)
    {
        Directory.CreateDirectory(outputDir);

        string[] files = Directory.GetFiles(inputDir, "*.png");
        Array.Sort(files, StringComparer.OrdinalIgnoreCase);

        var rows = new List<NormalizedCardRow>();
        for (int i = 0; i < files.Length; i++)
        {
            string file = files[i];
            string id = "card_" + (i + 1).ToString("D3", CultureInfo.InvariantCulture);
            string outputPath = Path.Combine(outputDir, id + ".png");

            using (var original = new Bitmap(file))
            using (var source = ToArgb(original))
            {
                Rectangle crop = DetectLightBounds(source, threshold, padding);

                using (var target = new Bitmap(targetWidth, targetHeight, PixelFormat.Format32bppArgb))
                using (var graphics = Graphics.FromImage(target))
                using (var clipPath = RoundedRectangle(new Rectangle(0, 0, targetWidth, targetHeight), cornerRadius))
                {
                    graphics.SmoothingMode = SmoothingMode.AntiAlias;
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    graphics.CompositingQuality = CompositingQuality.HighQuality;
                    graphics.Clear(Color.Transparent);
                    graphics.SetClip(clipPath);
                    graphics.DrawImage(
                        source,
                        new Rectangle(0, 0, targetWidth, targetHeight),
                        crop,
                        GraphicsUnit.Pixel);

                    target.Save(outputPath, ImageFormat.Png);
                }

                rows.Add(new NormalizedCardRow {
                    Id = id,
                    SourceName = Path.GetFileName(file),
                    OutputPath = outputPath,
                    SourceWidth = source.Width,
                    SourceHeight = source.Height,
                    CropX = crop.X,
                    CropY = crop.Y,
                    CropWidth = crop.Width,
                    CropHeight = crop.Height,
                    TargetWidth = targetWidth,
                    TargetHeight = targetHeight
                });
            }
        }

        WriteManifest(Path.Combine(outputDir, "manifest.csv"), rows);
        WriteContactSheet(Path.Combine(outputDir, "contact-sheet.png"), rows, 128, 184, 6);
        return rows.ToArray();
    }

    private static Bitmap ToArgb(Bitmap original)
    {
        var clone = new Bitmap(original.Width, original.Height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(clone))
        {
            graphics.DrawImage(original, 0, 0, original.Width, original.Height);
        }
        return clone;
    }

    private static Rectangle DetectLightBounds(Bitmap bitmap, int threshold, int padding)
    {
        int minX = bitmap.Width;
        int minY = bitmap.Height;
        int maxX = -1;
        int maxY = -1;

        Rectangle rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        BitmapData data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int stride = Math.Abs(data.Stride);
            int byteCount = stride * bitmap.Height;
            byte[] bytes = new byte[byteCount];
            Marshal.Copy(data.Scan0, bytes, 0, byteCount);

            for (int y = 0; y < bitmap.Height; y++)
            {
                int row = y * stride;
                for (int x = 0; x < bitmap.Width; x++)
                {
                    int offset = row + x * 4;
                    int b = bytes[offset];
                    int g = bytes[offset + 1];
                    int r = bytes[offset + 2];
                    int a = bytes[offset + 3];
                    int luminance = (int)(0.2126 * r + 0.7152 * g + 0.0722 * b);

                    if (a > 32 && luminance >= threshold)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
        }
        finally
        {
            bitmap.UnlockBits(data);
        }

        if (maxX < 0 || maxY < 0)
        {
            throw new InvalidOperationException("No light card body detected.");
        }

        minX = Math.Max(0, minX - padding);
        minY = Math.Max(0, minY - padding);
        maxX = Math.Min(bitmap.Width - 1, maxX + padding);
        maxY = Math.Min(bitmap.Height - 1, maxY + padding);

        return Rectangle.FromLTRB(minX, minY, maxX + 1, maxY + 1);
    }

    private static GraphicsPath RoundedRectangle(Rectangle rect, int radius)
    {
        int diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter - 1, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter - 1, rect.Bottom - diameter - 1, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter - 1, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static void WriteManifest(string path, List<NormalizedCardRow> rows)
    {
        using (var writer = new StreamWriter(path, false, new UTF8Encoding(false)))
        {
            writer.WriteLine("Id,SourceName,OutputPath,SourceWidth,SourceHeight,CropX,CropY,CropWidth,CropHeight,TargetWidth,TargetHeight");
            foreach (var row in rows)
            {
                writer.WriteLine(
                    Csv(row.Id) + "," +
                    Csv(row.SourceName) + "," +
                    Csv(row.OutputPath) + "," +
                    row.SourceWidth + "," +
                    row.SourceHeight + "," +
                    row.CropX + "," +
                    row.CropY + "," +
                    row.CropWidth + "," +
                    row.CropHeight + "," +
                    row.TargetWidth + "," +
                    row.TargetHeight);
            }
        }
    }

    private static string Csv(string value)
    {
        if (value == null) return "";
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    private static void WriteContactSheet(string path, List<NormalizedCardRow> rows, int thumbWidth, int thumbHeight, int columns)
    {
        int labelHeight = 28;
        int gap = 14;
        int rowCount = (int)Math.Ceiling(rows.Count / (double)columns);
        int width = columns * thumbWidth + (columns + 1) * gap;
        int height = rowCount * (thumbHeight + labelHeight) + (rowCount + 1) * gap;

        using (var sheet = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(sheet))
        using (var font = new Font("Segoe UI", 10, FontStyle.Regular))
        using (var brush = new SolidBrush(Color.FromArgb(245, 239, 227)))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.Clear(Color.FromArgb(21, 17, 14));

            for (int i = 0; i < rows.Count; i++)
            {
                int col = i % columns;
                int row = i / columns;
                int x = gap + col * (thumbWidth + gap);
                int y = gap + row * (thumbHeight + labelHeight + gap);

                using (var img = Image.FromFile(rows[i].OutputPath))
                {
                    graphics.DrawImage(img, x, y, thumbWidth, thumbHeight);
                }
                graphics.DrawString(rows[i].Id, font, brush, x, y + thumbHeight + 4);
            }

            sheet.Save(path, ImageFormat.Png);
        }
    }
}
"@

Add-Type -TypeDefinition $normalizerSource -ReferencedAssemblies System.Drawing

$resolvedInput = (Resolve-Path -LiteralPath $InputDir).Path
$rows = [CardBatchNormalizer]::Run(
  $resolvedInput,
  $OutputDir,
  $TargetWidth,
  $TargetHeight,
  $Threshold,
  $Padding,
  $CornerRadius
)

$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path
Write-Output "Normalized $($rows.Length) images."
Write-Output "Source untouched: $resolvedInput"
Write-Output "Output: $resolvedOutput"
Write-Output "Manifest: $(Join-Path $resolvedOutput 'manifest.csv')"
Write-Output "Contact sheet: $(Join-Path $resolvedOutput 'contact-sheet.png')"
