import os
import boto3
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote_plus

s3 = boto3.client("s3")

# Allowed video extensions
ALLOWED_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".webm"}

# Define DASH resolutions: (width, height)
RESOLUTIONS = [
    (1280, 720),  # 720p
    (854, 480),   # 480p
    (640, 360),   # 360p
    (426, 240)    # 240p
]

# Audio bitrates based on resolution height
AUDIO_BITRATES = {
    720: "128k",
    480: "96k",
    360: "64k",
    240: "48k"
}


def run_ffmpeg_dash(input_path: str, output_dir: Path, resolutions: list):
    """
    Run FFmpeg to generate adaptive bitrate DASH output with multiple resolutions.
    Outputs: MPD manifest + segmented .m4s files.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(output_dir, 0o777)  # Ensure write permissions

    filters = []
    stream_mappings = []
    output_params = []

    for idx, (width, height) in enumerate(resolutions):
        # Video filter: scale, preserve aspect ratio, pad to even dimensions
        v_filter = (
            f"[0:v]scale={width}x{height}:force_original_aspect_ratio=decrease,"
            f"pad=width=ceil(iw/2)*2:height=ceil(ih/2)*2:x=(ow-iw)/2:y=(oh-ih)/2,"
            # f"format=yuv420p[v{idx}]"
            f"format=yuv420p,setsar=1[v{idx}]"
        )
        filters.append(v_filter)

        # Audio filter: resample audio uniformly
        a_filter = f"[0:a]aresample=async=1[a{idx}]"
        filters.append(a_filter)

        # Map video and audio streams
        stream_mappings.extend(["-map", f"[v{idx}]", "-map", f"[a{idx}]"])

        # Output parameters per stream
        output_params.extend([
            f"-c:v:{idx}", "libx264",
            f"-crf:{idx}", "23",
            f"-preset:{idx}", "fast",
            f"-b:v:{idx}", f"{width}k",
            f"-maxrate:{idx}", f"{width}k",
            f"-bufsize:{idx}", f"{width * 2}k",
            f"-c:a:{idx}", "aac",
            f"-b:a:{idx}", AUDIO_BITRATES.get(height, "64k"),
        ])

    if not filters or not stream_mappings:
        raise ValueError("No valid FFmpeg filter chains or stream mappings generated.")
    ffmpeg_path = "/var/task/bin/ffmpeg"

    cmd = [
        # "ffmpeg",
        ffmpeg_path,
        "-i", input_path,
        "-y",  # Overwrite output files
        "-filter_complex", ";".join(filters),
    ] + stream_mappings + [
        "-f", "dash",
        "-seg_duration", "6",
        "-use_timeline", "1",
        "-use_template", "1",
        "-init_seg_name", "init_$RepresentationID$.m4s",
        "-media_seg_name", "segment_$RepresentationID$_$Number$.m4s",
        "-adaptation_sets", "id=0,streams=v id=1,streams=a",  # Group video/audio
    ] + output_params + [
        str(output_dir / "manifest.mpd")
    ]

    # Run FFmpeg
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg failed with error: {result.stderr}")

    return [f.name for f in output_dir.iterdir() if f.is_file()]


def lambda_handler(event, context):
    """
    Lambda entrypoint: Processes S3 upload event, converts video to DASH, uploads to S3, cleans up.
    """
    try:
        # parse S3 event and check for supported file extension
        record = event["Records"][0]
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        ext = Path(key).suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            return {
                "statusCode": 400,
                "body": f"Unsupported format: {ext}. Allowed: {ALLOWED_EXTENSIONS}"
            }

        file_id = Path(key).stem
        dash_prefix = f"dash/{file_id}"

        temp_dir = Path("/tmp")
        input_path = temp_dir / f"{file_id}{ext}"
        output_dir = temp_dir / f"{file_id}_dash_output"

        # Ensure clean state
        if input_path.exists():
            input_path.unlink()
        if output_dir.exists():
            shutil.rmtree(output_dir)

        try:
            s3.download_file(bucket, key, str(input_path))

            # conversion
            output_files = run_ffmpeg_dash(str(input_path), output_dir, RESOLUTIONS)


            output_bucket = "manifestdatabucket"

            # Upload DASH files to S3
            for file in output_dir.iterdir():
                if file.is_file():
                    content_type = "application/dash+xml" if file.suffix == ".mpd" else "video/mp4"
                    s3.upload_file(
                        str(file),
                        output_bucket,
                        f"{dash_prefix}/{file.name}",
                        ExtraArgs={"ContentType": content_type}
                    )

            manifest_url = f"https://{bucket}.s3.amazonaws.com/{dash_prefix}/manifest.mpd"

            # Optional: Notify your backend that conversion was successful
            # requests.post("https://your-api.com/update", json={"dash_url": manifest_url})

            return {
                "statusCode": 200,
                "body": {
                    "message": "DASH conversion successful",
                    "manifest_url": manifest_url,
                    "files": output_files,
                    "output_prefix": f"s3://{bucket}/{dash_prefix}/"
                }
            }

        except Exception as e:
            raise e  # Re-raise to trigger cleanup

        finally:
            # Cleanup: Always remove temporary files
            if input_path.exists():
                try:
                    os.remove(input_path)
                except Exception as e:
                    print(f"Warning: Failed to delete {input_path}: {e}")

            if output_dir.exists():
                try:
                    shutil.rmtree(output_dir)
                except Exception as e:
                    print(f"Warning: Failed to delete {output_dir}: {e}")

    except Exception as e:
        print(f"Error processing video: {str(e)}")
        return {
            "statusCode": 500,
            "body": f"Error: {str(e)}"
        }