# Fretwise Firebase Schema Draft

## Purpose
This document proposes the Firestore and Storage layout for Fretwise.

Goals:
- support the class AI workflows
- keep per-user learning data isolated and easy to query

This schema assumes:
- Firebase Auth for user identity
- Firestore for structured data
- Firebase Storage for recordings

Human-only implementation and migration notes belong in `../implement/ai_backend_migration.md`.

## Design Rules
- Store user-specific learning state under the authenticated user.
- Keep reusable reference data separate from user progress when helpful.
- Save generated AI outputs that need to appear on later screens.
- Save large binary files in Storage, not Firestore.
- Prefer one source of truth per concern.

## Top-Level Structure

```text
users/{uid}
```

Most product state is user-scoped.

## `users/{uid}`
Purpose:
- root user document

Suggested fields:
- `displayName`: string
- `email`: string, optional
- `profile`: map, optional
- `preferences`: map, optional
- `createdAt`: timestamp
- `updatedAt`: timestamp
- `activePlanId`: string, optional
- `currentStreak`: number, optional
- `totalPracticeMinutes`: number, optional

Example:
```json
{
  "displayName": "Alex",
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

Nested map notes:
- `profile` follows the `UserProfile` shape from `shared_models.md`
- `preferences` follows the `Preference` shape from `shared_models.md`
- keeping these as maps is simpler because they are singleton objects for one user

## `users/{uid}/songLibrary/{songId}`
Purpose:
- user's saved songs and their core metadata

Fields:
- follow the `SongEntry` shape from `shared_models.md`

Important notes:
- this collection replaces the app's current in-memory library and removed-song tracking
- `songId` should stay stable even if title casing changes

Recommended queries:
- order by `lastPracticedAt` descending for recent songs
- filter by `isArchived == false` for normal library view
- filter by `isFavorite == true` for favorites

## `users/{uid}/songProfiles/{songId}`
Purpose:
- per-song learning state for the current user

Fields:
- follow the `SongProfile` shape from `shared_models.md`

Reason to keep separate from `songLibrary`:
- learning notes and AI summaries change often
- keeps the base library card data cleaner

## `users/{uid}/songLibrary/{songId}/practiceMaterials/{materialId}`
Purpose:
- generated material attached to a specific song

Fields:
- follow the `PracticeMaterial` shape from `shared_models.md`

Recommended queries:
- active material for one `songId`
- latest materials for one `songId`

Important notes:
- nesting materials under the song keeps song-specific reads simple
- when a new material replaces the current one, mark the old one `active: false`
- chat-driven requests are stored as metadata on the generated material itself
- if the app only needs one visible material per song, query `active == true`

## `users/{uid}/sessions/{sessionId}`
Purpose:
- completed session records from the session-complete flow

Fields:
- raw session fields from `SessionLog`
- nest the generated `sessionInfo` inside the same session document by default

Recommended links:
- include `practiceDate` so profile diary and day-detail screens can group sessions by day
- include `planId` if the session should be associated with a specific active plan

Recommended shape:
```json
{
  "sessionId": "session_001",
  "songId": "song_wonderwall",
  "practiceDate": "2026-06-03",
  "planId": "plan_june_goal",
  "durationSec": 1320,
  "userNote": "Bridge still feels awkward.",
  "deadlineDate": "2026-06-20",
  "recordingUrls": [
    "https://storage.example.com/rec1.m4a"
  ],
  "endedAt": "SERVER_TIMESTAMP",
  "sessionInfo": {
    "aiComment": "Timing improved, but the bridge still needs slower transition work.",
    "detectedMood": "mixed",
    "nextFocus": ["bridge transitions", "consistent strumming"]
  }
}
```

Why this works:
- Profile diary can read one collection
- Home and calendar can derive recent activity without joining multiple paths

## `users/{uid}/practicePlans/{planId}`
Purpose:
- stores generated plan summaries and their active windows

Fields:
- follow the `PracticePlan` shape from `shared_models.md`

Recommended queries:
- current active plan
- latest plan by `updatedAt`

Relationship:
- one `PracticePlan` can have many `PracticeDay` records
- the link is stored on each day as `planId`

## `users/{uid}/practiceDays/{dayId}`
Purpose:
- stores calendar day status and completion summary

Document ID recommendation:
- use the date string itself, such as `2026-06-03`

Fields:
- follow the `PracticeDay` shape from `shared_models.md`

Recommended queries:
- day range for current month
- upcoming planned days
- days where `planId == activePlanId`

Important notes:
- keep `linkedSongIds` for planning and display
- do not store `taskIds` here by default; query tasks by `dayId`
- use completion summary fields such as `completedMinutes` and `completedSessionCount` for quick calendar rendering

## `users/{uid}/practiceTasks/{taskId}`
Purpose:
- movable detailed tasks linked from days and plans

Fields:
- follow the `PracticeTask` shape from `shared_models.md`

Reason:
- tasks may need to move from one day to another if the user misses a practice day
- keeping tasks top-level makes rescheduling a simple field update instead of a document move

Recommended queries:
- tasks where `dayId == selectedDay`
- tasks where `planId == activePlanId`
- tasks where `status != completed`

Recommended links:
- `dayId` points to the currently assigned day
- `planId` points to the parent plan
- `originalDayId` keeps the initial planned day if rescheduling matters
- `rescheduledFromDayId` tracks the most recent move if needed

## `users/{uid}/feed/{feedItemId}`
Purpose:
- inspiration feed items and user action state

Fields:
- follow the `FeedItem` shape from `shared_models.md`

Recommended queries:
- latest feed items ordered by `createdAt`
- items with `actionState == liked`

## `users/{uid}/chatLogs/{chatLogId}` optional
Purpose:
- stores summarized AI coach interactions if the team wants persistent history

Fields:
- `fromScreen`: string
- `activeSongId`: string, optional
- `messages`: list of small role/text objects or summarized transcript
- `createdAt`: timestamp

Recommendation:
- keep this optional
- do not save full chat history unless it is actually needed

## Optional Shared Catalog: `songCatalog/{songId}`
Purpose:
- reusable song metadata shared across users

Possible fields:
- `title`
- `artist`
- `canonicalBpm`
- `durationSec`
- `defaultSectionLabel`
- `genre`
- `coverImageUrl`
- `referenceLinks`

When to use it:
- use it if multiple users will save the same songs
- skip it for now if the project only needs per-user data and faster implementation

## Firebase Storage Layout

```text
users/{uid}/recordings/{sessionId}/{filename}.m4a
users/{uid}/avatars/{filename}
```

### Practice recordings
Purpose:
- audio files created during or after practice

Store in Firestore:
- only the download URLs or storage paths

Do not store in Firestore:
- raw audio bytes
