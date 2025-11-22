# Installation Commands - Copy and Paste

## Current System Status

✅ **Python 3.9.6** is already installed at `/usr/bin/python3`  
❌ **FFmpeg** needs to be installed  
❌ **Homebrew** needs to be installed  

---

## Step-by-Step Installation

### Step 1: Install Homebrew

Copy and paste this command into your terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Note:** Follow any on-screen instructions. You may be asked to enter your password.

After installation, you may need to add Homebrew to your PATH. The installer will show you the exact commands, but typically it's:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify Homebrew is installed:

```bash
brew --version
```

---

### Step 2: Install FFmpeg

```bash
brew install ffmpeg
```

Verify FFmpeg installation:

```bash
ffmpeg -version
```

You should see version information. If you see an error, make sure Homebrew is in your PATH.

---

### Step 3: Navigate to Project Directory

```bash
cd /Users/keithbrown/Projects/domeai/video-editor
```

---

### Step 4: Create Python Virtual Environment

```bash
python3 -m venv venv
```

---

### Step 5: Activate Virtual Environment

```bash
source venv/bin/activate
```

You should see `(venv)` at the start of your terminal prompt.

**Important:** You need to activate the virtual environment every time you open a new terminal session.

---

### Step 6: Upgrade pip

```bash
pip install --upgrade pip
```

---

### Step 7: Install OpenAI Whisper

```bash
pip install -U openai-whisper
```

This will take a few minutes as it downloads and installs Whisper and its dependencies.

---

### Step 8: Verify Installation

Test that Whisper is installed correctly:

```bash
python3 -c "import whisper; print('Whisper installed successfully')"
```

---

## Testing the Script

### Make Script Executable (Optional)

```bash
chmod +x test_whisper.py
```

### Run the Test Script

Replace `/path/to/your/video.mp4` with the actual path to your video file:

```bash
python3 test_whisper.py /path/to/your/video.mp4
```

**Example:**

```bash
python3 test_whisper.py ~/Downloads/my_video.mp4
```

---

## Daily Usage

Every time you want to use the transcription tool:

1. **Navigate to the project:**
   ```bash
   cd /Users/keithbrown/Projects/domeai/video-editor
   ```

2. **Activate virtual environment:**
   ```bash
   source venv/bin/activate
   ```

3. **Run the script:**
   ```bash
   python3 test_whisper.py /path/to/video.mp4
   ```

---

## Troubleshooting

### "command not found: brew"
- Homebrew is not installed or not in your PATH
- Re-run Step 1 and follow the PATH setup instructions

### "ffmpeg: command not found"
- FFmpeg is not installed
- Run: `brew install ffmpeg`

### "No module named 'whisper'"
- Virtual environment is not activated
- Run: `source venv/bin/activate`
- Then reinstall: `pip install -U openai-whisper`

### "Permission denied" when running script
- Make script executable: `chmod +x test_whisper.py`
- Or run with: `python3 test_whisper.py` (no need for ./)

---

## What Gets Created

- **Virtual environment:** `venv/` directory (do not delete)
- **Transcript file:** `video_name.txt` (same location as input video)
- **Temporary audio:** Automatically deleted after transcription

---

## Next Steps

Once everything is working:
- Test with a short video first (1-2 minutes)
- Then try with longer videos (2-4 hours)
- The "base" model is recommended for initial testing
- For better accuracy, you can edit `test_whisper.py` and change `model_name='base'` to `model_name='small'` or `model_name='medium'`

