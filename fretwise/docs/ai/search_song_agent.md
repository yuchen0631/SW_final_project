# `searchSong` Agent Spec

## Purpose
Given a song title and artist, produce a normalized `SongEntry` and find exactly one high-quality YouTube guitar tutorial video.

## Input Contract
```json
{
  "title": "string",
  "artist": "string",
  "userPreferences": {
    "preferredMaterialTypes": ["video", "tabs", "chordChart"]
  }
}

{
  "song": {
    "title": "string",
    "artist": "string",
    "bpm": 0,
    "durationSec": 0,
    "seed": 0
  },
  "material": {
    "type": "video",
    "title": "Guitar Tutorial",
    "videoUrl": "string (YouTube watch URL)",
    "active": true
  }
}