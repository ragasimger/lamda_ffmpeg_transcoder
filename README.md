# 🎬 AWS Lambda Video Transcoder with FFmpeg + DASH Output

This project provides a ready-to-deploy **AWS Lambda function** that:

- Accepts video uploads to an S3 bucket  
- Uses **FFmpeg** inside Lambda to transcode videos into **MPEG-DASH** format with multiple resolutions (adaptive bitrate streaming)  
- Uploads the resulting **manifest (MPD)** and segmented video files back to S3  
- Cleans up temporary files in Lambda's `/tmp` directory  

The setup includes a **Makefile** to package dependencies and binaries into deployable Lambda layer(s).

---

## 📂 Project Structure

```
.
├── Makefile           # Build system for layers and combined package
├── lambda_function.py # Main Lambda handler
├── requirements.txt   # (Optional) Python dependencies
└── dist/             # Output zips for upload
```

---

## ⚡ Features

- **FFmpeg** packaged into the Lambda bundle  
- **Python 3.13 runtime** supported  
- **DASH output** with multiple resolutions (720p, 480p, 360p, 240p)  
- Automatic **audio bitrate selection** per resolution  
- **Clean build process** with `make` commands  
- Supports both **manual deployment** and **AWS Lambda layers**  

---

## 🛠 Setup

### 1. Prerequisites

- AWS account with IAM permissions for **Lambda** and **S3**  
- AWS CLI installed and configured  
- `make` installed (Linux/Mac; on Windows use WSL or Git Bash)  
- Python 3.13 (recommended, but the Makefile handles dependencies via `uv`)  

### 2. Clone the Repository

```bash
git clone git@github.com:ragasimger/lamda_ffmpeg_transcoder.git
cd lamda_ffmpeg_transcoder
```
or
```bash
git clone https://github.com/ragasimger/lamda_ffmpeg_transcoder.git
cd lamda_ffmpeg_transcoder
```

### 3. Build the Packages

The Makefile automates everything:

Combined package (default):
```bash
make
```
→ Builds dist/lambda-layer.zip (FFmpeg + Python deps + Lambda function)

Python dependencies only:
```bash
make python-layer
```

FFmpeg binary only:
```bash
make ffmpeg-layer
```

Cleanup build artifacts:
```bash
make clean
```

## 🚀 Deploy to AWS Lambda

### Option 1: Upload Zip Directly

1. Go to AWS Console → Lambda
2. Create a new Lambda function:
   - Runtime: Python 3.13
   - Architecture: x86_64 (compatible with FFmpeg static binary)
3. Upload `dist/lambda-layer.zip` as the function code
4. AWS do it automatically:
```
lambda_function.lambda_handler
```

### Option 2: Use Lambda Layers

1. Upload `dist/python-layer.zip` as a Lambda layer (Python dependencies)
2. Upload `dist/ffmpeg-layer.zip` as a Lambda layer (FFmpeg binary)
3. Attach both layers to your Lambda function
4. Upload `lambda_function.py` directly as the function code

## ⚙️ S3 Configuration

This Lambda is triggered by S3 events:

1. In AWS Console → S3 → select your bucket
2. Under Properties → Event notifications, create a rule:
   - Event type: PUT (Object Created)
   - Prefix: `uploads/` (optional, if you only want to watch a folder)
   - Suffix: `.mp4` (optional, restrict to video extensions)
   - Destination: Your Lambda function

## 📡 How It Works

1. User uploads a video to S3 (e.g., `mybucket/uploads/video.mp4`)
2. S3 triggers the Lambda function
3. Lambda downloads the file into `/tmp`
4. FFmpeg transcodes the video into multiple resolutions and segments them for MPEG-DASH
5. Lambda uploads results into the S3 bucket under `dash/{filename}/` in another bucket. Yes another bucket, because we will enter into infinite loop of lambda trigger if used one bucket.

Outputs:
- `manifest.mpd` (DASH manifest file)
- Segmented video/audio `.m4s` chunks

Example output in S3:
```
s3://manifestdatabucket/dash/video/
 ├── manifest.mpd
 ├── init_0.m4s
 ├── segment_0_1.m4s
 ├── segment_0_2.m4s
 ├── ...
```


## ⚠️ Notes & Limitations

- Lambda has 512MB `/tmp` storage → large videos may not fit
- Default timeout should be increased (e.g., 5–10 minutes)
- Ensure your Lambda role has these IAM permissions:
  - `s3:GetObject`
  - `s3:PutObject`
  - `s3:ListBucket`