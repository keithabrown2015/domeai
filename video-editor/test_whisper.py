#!/usr/bin/env python3
"""
Video Transcription Script using OpenAI Whisper

This script extracts audio from an MP4 video file and transcribes it using
OpenAI Whisper. The transcript is printed to console and saved to a text file.

Usage:
    python3 test_whisper.py <path_to_video.mp4>

Requirements:
    - FFmpeg must be installed and accessible in PATH
    - OpenAI Whisper must be installed
    - Python 3.9 or higher
"""

import sys
import os
import subprocess
import whisper
from pathlib import Path


def check_ffmpeg():
    """
    Check if FFmpeg is installed and accessible.
    
    Returns:
        bool: True if FFmpeg is available, False otherwise
    """
    try:
        result = subprocess.run(
            ['ffmpeg', '-version'],
            capture_output=True,
            text=True,
            check=True
        )
        print("✓ FFmpeg is installed and accessible")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("✗ ERROR: FFmpeg is not installed or not in PATH")
        print("  Please install FFmpeg using: brew install ffmpeg")
        return False


def extract_audio(video_path, audio_path):
    """
    Extract audio from video file using FFmpeg.
    
    Args:
        video_path (str): Path to the input video file
        audio_path (str): Path where the extracted audio will be saved
        
    Returns:
        bool: True if extraction was successful, False otherwise
    """
    try:
        print(f"\n📹 Extracting audio from video...")
        print(f"   Input: {video_path}")
        print(f"   Output: {audio_path}")
        
        # Use FFmpeg to extract audio
        # -i: input file
        # -vn: disable video
        # -acodec copy: copy audio codec (faster, but may not work for all formats)
        # -y: overwrite output file if it exists
        cmd = [
            'ffmpeg',
            '-i', video_path,
            '-vn',  # No video
            '-acodec', 'pcm_s16le',  # Convert to WAV format (compatible with Whisper)
            '-ar', '16000',  # Sample rate 16kHz (Whisper's preferred rate)
            '-ac', '1',  # Mono channel
            '-y',  # Overwrite output file
            audio_path
        ]
        
        # Run FFmpeg with progress output suppressed
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        
        print("✓ Audio extraction completed successfully")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"✗ ERROR: Failed to extract audio from video")
        print(f"   FFmpeg error: {e.stderr}")
        return False
    except Exception as e:
        print(f"✗ ERROR: Unexpected error during audio extraction: {str(e)}")
        return False


def transcribe_audio(audio_path, model_name='base'):
    """
    Transcribe audio file using OpenAI Whisper.
    
    Args:
        audio_path (str): Path to the audio file
        model_name (str): Whisper model to use (tiny, base, small, medium, large)
        
    Returns:
        str: Transcribed text, or None if transcription failed
    """
    try:
        print(f"\n🎤 Loading Whisper model '{model_name}'...")
        model = whisper.load_model(model_name)
        print("✓ Model loaded successfully")
        
        print(f"\n📝 Transcribing audio (this may take a while for long videos)...")
        print("   Please wait...")
        
        # Transcribe the audio
        result = model.transcribe(audio_path)
        
        transcript = result["text"]
        print("✓ Transcription completed successfully")
        
        return transcript
        
    except Exception as e:
        print(f"✗ ERROR: Failed to transcribe audio: {str(e)}")
        print("   Common issues:")
        print("   - Make sure OpenAI Whisper is installed: pip install -U openai-whisper")
        print("   - Check that the audio file is valid")
        return None


def save_transcript(transcript, output_path):
    """
    Save transcript to a text file.
    
    Args:
        transcript (str): The transcribed text
        output_path (str): Path where the transcript will be saved
    """
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(transcript)
        print(f"✓ Transcript saved to: {output_path}")
    except Exception as e:
        print(f"✗ ERROR: Failed to save transcript: {str(e)}")


def main():
    """
    Main function to orchestrate the video transcription process.
    """
    # Check command line arguments
    if len(sys.argv) != 2:
        print("Usage: python3 test_whisper.py <path_to_video.mp4>")
        print("\nExample:")
        print("  python3 test_whisper.py /path/to/my/video.mp4")
        sys.exit(1)
    
    video_path = sys.argv[1]
    
    # Validate video file exists
    if not os.path.exists(video_path):
        print(f"✗ ERROR: Video file not found: {video_path}")
        sys.exit(1)
    
    if not os.path.isfile(video_path):
        print(f"✗ ERROR: Path is not a file: {video_path}")
        sys.exit(1)
    
    # Check file extension
    if not video_path.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.webm')):
        print(f"⚠ WARNING: File extension may not be a standard video format")
        print(f"   Proceeding anyway...")
    
    print("=" * 60)
    print("Video Transcription Tool")
    print("=" * 60)
    print(f"\n📁 Video file: {video_path}")
    
    # Check FFmpeg availability
    if not check_ffmpeg():
        sys.exit(1)
    
    # Set up paths
    video_file = Path(video_path)
    audio_path = video_file.with_suffix('.wav')
    transcript_path = video_file.with_suffix('.txt')
    
    # Extract audio from video
    if not extract_audio(video_path, str(audio_path)):
        sys.exit(1)
    
    # Transcribe audio
    transcript = transcribe_audio(str(audio_path), model_name='base')
    
    if transcript is None:
        # Clean up audio file on error
        if os.path.exists(audio_path):
            os.remove(audio_path)
        sys.exit(1)
    
    # Print transcript to console
    print("\n" + "=" * 60)
    print("TRANSCRIPT")
    print("=" * 60)
    print(transcript)
    print("=" * 60)
    
    # Save transcript to file
    save_transcript(transcript, str(transcript_path))
    
    # Clean up temporary audio file
    try:
        if os.path.exists(audio_path):
            os.remove(audio_path)
            print(f"✓ Cleaned up temporary audio file: {audio_path}")
    except Exception as e:
        print(f"⚠ WARNING: Could not remove temporary audio file: {str(e)}")
    
    print("\n✓ Transcription process completed successfully!")
    print(f"   Transcript saved to: {transcript_path}")


if __name__ == "__main__":
    main()

