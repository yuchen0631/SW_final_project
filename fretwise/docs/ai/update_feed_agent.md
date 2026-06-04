#### 檔案 2：`update_feed_agent.md` (妳負責的 Inspiration 功能)
```markdown
# `updateFeed` Agent Spec

## Purpose
Analyze user's liked/disliked history to generate a fresh inspiration feed of 5 new songs with tutorial videos.

## Input Contract
```json
{
  "profile": { "skillLevel": "string" },
  "preferences": { "favoriteGenres": ["string"] },
  "recentFeedActions": [
    { "title": "string", "actionState": "liked | disliked" }
  ]
}

{
  "newItems": [
    {
      "title": "string",
      "artist": "string",
      "genre": "string",
      "description": "Short AI recommendation text",
      "videoUrl": "string (YouTube Tutorial URL)"
    }
  ]
}
