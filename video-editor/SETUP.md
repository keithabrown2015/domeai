# Video Transcription Environment Setup Guide

This guide will help you set up a local video analysis environment on your Mac for processing long-form videos (2-4 hours) using OpenAI Whisper.

## Prerequisites Check

✅ **Python 3.9.6 is already installed** on your system at `/usr/bin/python3`

## Step 1: Install Homebrew (if not already installed)

Homebrew is a package manager for macOS. If you don't have it installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, you may need to add Homebrew to your PATH. Follow the instructions shown at the end of the installation.

Verify Homebrew installation:
```bash
brew --version
```

## Step 2: Install FFmpeg

FFmpeg is required for extracting audio from video files.

```bash
brew install ffmpeg
```

Verify FFmpeg installation:
```bash
ffmpeg -version
```

You should see version information if FFmpeg is installed correctly.

## Step 3: Set Up Python Virtual Environment

Navigate to the video-editor directory:

```bash
cd /Users/keithbrown/Projects/domeai/video-editor
```

Create a Python virtual environment:

```bash
python3 -m venv venv
```

Activate the virtual environment:

```bash
source venv/bin/activate
```

You should see `(venv)` at the beginning of your terminal prompt, indicating the virtual environment is active.

## Step 4: Install Required Python Packages

Install OpenAI Whisper:

```bash
pip install --upgrade pip
pip install -U openai-whisper
```

**Note:** The `python-ffmpeg` package mentioned in the requirements is not necessary - we'll use FFmpeg directly via subprocess calls, which is more reliable.

Verify Whisper installation:

```bash
python3 -c "import whisper; print('Whisper installed successfully')"
```

## Step 5: Test the Installation

Make the test script executable (optional):

```bash
chmod +x test_whisper.py
```

Run the test script with a video file:

```bash
python3 test_whisper.py /path/to/your/video.mp4
```

Replace `/path/to/your/video.mp4` with the actual path to your video file.

## Usage

### Running the Transcription Script

1. **Activate the virtual environment** (if not already active):
   ```bash
   cd /Users/keithbrown/Projects/domeai/video-editor
   source venv/bin/activate
   ```

2. **Run the script** with your video file:
   ```bash
   python3 test_whisper.py /path/to/video.mp4
   ```

### What the Script Does

1. ✅ Checks if FFmpeg is available
2. ✅ Extracts audio from the video file (saves as temporary WAV file)
3. ✅ Transcribes the audio using Whisper's "base" model
4. ✅ Prints the transcript to the console
5. ✅ Saves the transcript to a `.txt` file with the same name as the video
6. ✅ Cleans up the temporary audio file

### Output Files

- **Transcript file**: `video_name.txt` (same location as input video)
- **Temporary audio file**: Automatically deleted after transcription

## Troubleshooting

### FFmpeg Not Found

If you get an error that FFmpeg is not found:
- Make sure Homebrew is installed and in your PATH
- Run: `brew install ffmpeg`
- Verify with: `ffmpeg -version`

### Whisper Model Download Issues

The first time you run the script, Whisper will download the "base" model (~150MB). This is automatic but may take a few minutes depending on your internet connection.

### Memory Issues with Long Videos

For very long videos (2-4 hours), you might want to:
- Use a smaller model: Edit `test_whisper.py` and change `model_name='base'` to `model_name='tiny'` (faster but less accurate)
- Or use a larger model: Change to `model_name='small'` or `model_name='medium'` (slower but more accurate)

### Virtual Environment Not Activating

If you have issues activating the virtual environment:
- Make sure you're in the `video-editor` directory
- Try: `source ./venv/bin/activate`
- On some systems, you might need: `. venv/bin/activate`

## Next Steps (Phase 2+)

Once this local setup is working, you can:
- Integrate this into your web application
- Add batch processing for multiple videos
- Implement progress tracking for long videos
- Add support for different audio/video formats
- Create an API endpoint for video transcription

## Model Sizes Reference

- **tiny**: Fastest, least accurate (~39M parameters)
- **base**: Good balance of speed and accuracy (~74M parameters) - **default**
- **small**: Better accuracy, slower (~244M parameters)
- **medium**: High accuracy, much slower (~769M parameters)
- **large**: Best accuracy, very slow (~1550M parameters)

For 2-4 hour videos, "base" is recommended for initial testing.

