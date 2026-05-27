# Fretwise Shared Models

## Purpose
This document defines the canonical data objects shared across screens, backend, and AI workflows.

Use these model names consistently in:
- Firebase documents
- backend functions
- AI input and output contracts
- Flutter model classes

## Format Rules
- Use `camelCase` for field names.
- Use Firestore `Timestamp` for date-time values.
- Use `YYYY-MM-DD` strings for date-only values such as deadlines or practice-day labels.
- Keep IDs stable and machine-safe.
- Prefer explicit nullable fields over ambiguous empty strings when possible.
- When a Firestore document path already provides an identifier such as `userId`, `songId`, or `sessionId`, storing the same ID inside the document is optional.
- Examples below default to the Firestore document shape that matches the current schema draft.

## Common Enums

### DifficultyLevel
- `beginner`
- `earlyIntermediate`
- `intermediate`
- `advanced`

### MaterialType
- `video`
- `image`
- `tabs`
- `chordChart`
- `exercise`
- `note`

### FeedAction
- `liked`
- `disliked`
- `addedToLibrary`
- `ignored`

### SessionMood
- `good`
- `mixed`
- `frustrated`
- `confident`
- `tired`

## UserAccount
Purpose:
- root user document stored at `users/{userId}`

Fields:
- `displayName`: string, required
- `email`: string, optional
- `profile`: `UserProfile`, optional
- `preferences`: `Preference`, optional
- `createdAt`: timestamp, required
- `updatedAt`: timestamp, required
- `activePlanId`: string, optional
- `currentStreak`: number, optional
- `totalPracticeMinutes`: number, optional

Example:
```json
{
  "displayName": "Alex",
  "email": "alex@example.com",
  "profile": {
    "skillLevel": "beginner",
    "experienceSummary": "Started acoustic guitar 3 months ago."
  },
  "preferences": {
    "favoriteGenres": ["folk", "classic rock"]
  },
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP",
  "activePlanId": "plan_june_goal",
  "currentStreak": 12,
  "totalPracticeMinutes": 2880
}
```

## UserProfile
Purpose:
- stores the user's detailed learning profile as the `profile` map on `users/{userId}`

Fields:
- `skillLevel`: `DifficultyLevel`, required
- `experienceSummary`: string, optional
- `currentGoals`: list of strings, optional
- `weakTechniques`: list of strings, optional
- `strongTechniques`: list of strings, optional
- `preferredSessionMinutes`: number, optional
- `updatedAt`: timestamp, required

Example:
```json
{
  "skillLevel": "beginner",
  "experienceSummary": "Started acoustic guitar 3 months ago.",
  "currentGoals": ["play full songs", "improve barre chords"],
  "weakTechniques": ["barre chords", "smooth chord transitions"],
  "strongTechniques": ["open chords"],
  "preferredSessionMinutes": 20
}
```

## Preference
Purpose:
- stores likes, dislikes, and learning preferences as the `preferences` map on `users/{userId}`

Fields:
- `favoriteGenres`: list of strings, optional
- `favoriteArtists`: list of strings, optional
- `dislikedGenres`: list of strings, optional
- `dislikedArtists`: list of strings, optional
- `preferredMaterialTypes`: list of `MaterialType`, optional
- `tempoPreference`: string, optional
- `updatedAt`: timestamp, required

Example:
```json
{
  "favoriteGenres": ["folk", "classic rock"],
  "favoriteArtists": ["The Beatles"],
  "dislikedGenres": ["metal"],
  "preferredMaterialTypes": ["video", "chordChart"]
}
```

## SongEntry
Purpose:
- canonical song record stored at `users/{userId}/songLibrary/{songId}`

Fields:
- `title`: string, required
- `artist`: string, required
- `durationSec`: number, optional
- `bpm`: number, optional
- `defaultSectionLabel`: string, optional
- `progressPercent`: number from `0` to `100`, required
- `lastPracticedAt`: timestamp, optional
- `firstSessionCompletedAt`: timestamp, optional
- `deadlineDate`: string in `YYYY-MM-DD`, optional
- `source`: string, optional
- `isArchived`: boolean, required
- `isFavorite`: boolean, required
- `createdAt`: timestamp, required
- `updatedAt`: timestamp, required

Example:
```json
{
  "title": "Wonderwall",
  "artist": "Oasis",
  "durationSec": 208,
  "bpm": 87,
  "defaultSectionLabel": "Bars 1-8",
  "progressPercent": 80,
  "deadlineDate": "2026-06-20",
  "source": "manualAdd",
  "isArchived": false,
  "isFavorite": true
}
```

## SongProfile
Purpose:
- stores learning-specific state at `users/{userId}/songProfiles/{songId}`

Fields:
- `difficultyForUser`: `DifficultyLevel`, optional
- `problemAreas`: list of strings, optional
- `strengthAreas`: list of strings, optional
- `recommendedFocus`: list of strings, optional
- `preferredMaterialTypes`: list of `MaterialType`, optional
- `latestAiSummary`: string, optional
- `updatedAt`: timestamp, required

Example:
```json
{
  "difficultyForUser": "beginner",
  "problemAreas": ["fast chord transitions"],
  "strengthAreas": ["strumming consistency"],
  "recommendedFocus": ["slow transition drills", "bridge repetition"],
  "preferredMaterialTypes": ["video", "chordChart"],
  "latestAiSummary": "User is close to full-song playthrough but still hesitates before the bridge."
}
```

## PracticeMaterial
Purpose:
- describes generated or selected material stored at `users/{userId}/songLibrary/{songId}/practiceMaterials/{materialId}`

Fields:
- `type`: `MaterialType`, required
- `title`: string, required
- `description`: string, optional
- `resourceUrl`: string, optional
- `thumbnailUrl`: string, optional
- `sectionLabel`: string, optional
- `active`: boolean, required
- `whyChosen`: string, optional
- `generatedReason`: string, optional
- `requestedByChat`: boolean, required
- `requestText`: string, optional
- `sourceContext`: string, optional
- `sourceProvider`: string, optional
- `createdAt`: timestamp, required

Example:
```json
{
  "type": "video",
  "title": "Wonderwall beginner chord walkthrough",
  "description": "Short tutorial focused on verse transitions.",
  "resourceUrl": "https://example.com/video",
  "sectionLabel": "Verse",
  "active": true,
  "whyChosen": "Matches beginner level and current transition weakness.",
  "generatedReason": "User asked for a slower visual explanation of the bridge.",
  "requestedByChat": true,
  "requestText": "I want a slower visual breakdown of the bridge.",
  "sourceContext": "chatAdjustment",
  "sourceProvider": "youtube",
  "createdAt": "SERVER_TIMESTAMP"
}
```

## SessionLog
Purpose:
- raw record of one completed practice session stored at `users/{userId}/sessions/{sessionId}`

Fields:
- `songId`: string, required
- `practiceDate`: string in `YYYY-MM-DD`, required
- `planId`: string, optional
- `durationSec`: number, required
- `userNote`: string, optional
- `deadlineDate`: string in `YYYY-MM-DD`, optional
- `recordingUrls`: list of strings, optional
- `sessionInfo`: `SessionInfo`, optional
- `startedAt`: timestamp, optional
- `endedAt`: timestamp, required

Example:
```json
{
  "songId": "song_wonderwall",
  "practiceDate": "2026-06-03",
  "planId": "plan_june_goal",
  "durationSec": 1320,
  "userNote": "Bridge still feels awkward.",
  "deadlineDate": "2026-06-20",
  "recordingUrls": ["https://storage.example.com/rec1.m4a"],
  "endedAt": "SERVER_TIMESTAMP"
}
```

## SessionInfo
Purpose:
- AI-generated summary usually nested as `sessionInfo` inside a `SessionLog`

Fields:
- `aiComment`: string, optional
- `detectedMood`: `SessionMood`, optional
- `nextFocus`: list of strings, optional
- `improvements`: list of strings, optional
- `warnings`: list of strings, optional
- `generatedAt`: timestamp, required

Example:
```json
{
  "aiComment": "Timing improved, but the bridge still needs slower transition work.",
  "detectedMood": "mixed",
  "nextFocus": ["bridge transitions", "consistent strumming"],
  "improvements": ["steady verse rhythm"]
}
```

## PracticeDay
Purpose:
- one calendar day stored at `users/{userId}/practiceDays/{dayId}`

Fields:
- `planId`: string, optional
- `date`: string in `YYYY-MM-DD`, required
- `status`: string, required
- `plannedMinutes`: number, optional
- `linkedSongIds`: list of strings, optional
- `completedMinutes`: number, optional
- `completedSessionCount`: number, optional
- `completedSongIds`: list of strings, optional
- `updatedAt`: timestamp, required

Suggested `status` values:
- `planned`
- `completed`
- `missed`
- `rest`

Example:
```json
{
  "planId": "plan_june_goal",
  "date": "2026-06-03",
  "status": "planned",
  "plannedMinutes": 20,
  "linkedSongIds": ["song_blackbird"],
  "completedMinutes": 0,
  "completedSessionCount": 0,
  "completedSongIds": []
}
```

## PracticeTask
Purpose:
- a single task stored at `users/{userId}/practiceTasks/{taskId}`

Fields:
- `planId`: string, optional
- `dayId`: string in `YYYY-MM-DD`, required
- `originalDayId`: string in `YYYY-MM-DD`, optional
- `rescheduledFromDayId`: string in `YYYY-MM-DD`, optional
- `songId`: string, optional
- `title`: string, required
- `instructions`: string, optional
- `minutes`: number, optional
- `materialId`: string, optional
- `orderIndex`: number, optional
- `status`: string, required
- `updatedAt`: timestamp, required

Suggested `status` values:
- `planned`
- `completed`
- `skipped`
- `carriedOver`

Example:
```json
{
  "planId": "plan_june_goal",
  "dayId": "2026-06-03",
  "originalDayId": "2026-06-01",
  "rescheduledFromDayId": "2026-06-01",
  "songId": "song_blackbird",
  "title": "Bars 1-8 fingerpicking",
  "instructions": "Play at half speed with clean bass notes.",
  "minutes": 15,
  "materialId": "material_013",
  "orderIndex": 1,
  "status": "planned",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

## PracticePlan
Purpose:
- stores the current generated plan at `users/{userId}/practicePlans/{planId}`

Fields:
- `title`: string, required
- `summary`: string, optional
- `activeFromDate`: string in `YYYY-MM-DD`, required
- `activeToDate`: string in `YYYY-MM-DD`, optional
- `linkedSongIds`: list of strings, optional
- `status`: string, optional
- `generatedReason`: string, optional
- `updatedAt`: timestamp, required

Example:
```json
{
  "title": "June performance prep",
  "summary": "Focus on Wonderwall transitions and Blackbird fingerpicking three times per week.",
  "activeFromDate": "2026-06-01",
  "activeToDate": "2026-06-20",
  "linkedSongIds": ["song_wonderwall", "song_blackbird"],
  "status": "active",
  "generatedReason": "User set a performance deadline."
}
```

## FeedItem
Purpose:
- one inspiration recommendation stored at `users/{userId}/feed/{feedItemId}`

Fields:
- `songId`: string, optional
- `title`: string, required
- `artist`: string, optional
- `genre`: string, optional
- `description`: string, optional
- `videoUrl`: string, optional
- `thumbnailUrl`: string, optional
- `bpm`: number, optional
- `actionState`: `FeedAction`, optional
- `rankScore`: number, optional
- `createdAt`: timestamp, required

Example:
```json
{
  "songId": "song_blackbird",
  "title": "Blackbird",
  "artist": "The Beatles",
  "genre": "Folk / Rock",
  "description": "Fingerstyle piece with accessible early sections.",
  "videoUrl": "https://example.com/shorts/blackbird",
  "bpm": 96,
  "actionState": "liked",
  "rankScore": 0.91
}
```

## ChatContext
Purpose:
- optional structured input for the AI coach

Fields:
- `fromScreen`: string, required
- `activeSongId`: string, optional
- `activeSongTitle`: string, optional
- `recentSessionId`: string, optional
- `recentMessages`: list of simple role/text objects, optional

Example:
```json
{
  "fromScreen": "practicing",
  "activeSongId": "song_wonderwall",
  "activeSongTitle": "Wonderwall",
  "recentSessionId": "session_001",
  "recentMessages": [
    {"role": "user", "text": "I keep messing up the bridge."}
  ]
}
```
