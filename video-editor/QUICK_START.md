# Quick Start Guide

## Installation Commands (Run These in Order)

```bash
# 1. Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Install FFmpeg
brew install ffmpeg

# 3. Navigate to project directory
cd /Users/keithbrown/Projects/domeai/video-editor

# 4. Create virtual environment
python3 -m venv venv

# 5. Activate virtual environment
source venv/bin/activate

# 6. Upgrade pip
pip install --upgrade pip

# 7. Install Whisper
pip install -U openai-whisper
```

## Running the Script

```bash
# Make sure virtual environment is activated
source venv/bin/activate

# Run transcription
python3 test_whisper.py /path/to/your/video.mp4
```

## Example

```bash
python3 test_whisper.py ~/Downloads/my_video.mp4
```

This will create `my_video.txt` in the same directory with the transcript.

