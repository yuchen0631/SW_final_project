# Fretwise AI Overview

## Goal
Fretwise uses AI to personalize guitar learning across practice, reflection, discovery, and planning.

This document defines:
- which screen uses which AI workflow
- when each workflow is triggered
- what data each workflow reads
- what data each workflow writes
- where runtime data should live

This file is a product-level overview. Detailed object definitions belong in `shared_models.md`. Firestore layout belongs in `firebase_schema.md`.

## Core Principles
- Firebase is the runtime source of truth.
- `.md` files are design contracts for the team.
- AI should receive structured inputs assembled from backend data, not raw markdown at runtime.
- Each AI workflow should have explicit input and output formats.
- AI outputs that must be reused later should be persisted to backend.

## Shared Runtime Layers
- Flutter client: renders UI, collects user actions, displays data
- Firebase Auth: identifies the user
- Firestore: stores structured app state
- Firebase Storage: stores audio recordings and other uploaded files
- AI/backend function layer: reads backend data, calls AI, validates output, writes results back

## Current Storage Shape
- `users/{uid}` stores root account fields plus embedded `profile` and `preferences` maps
- `users/{uid}/songLibrary/{songId}` stores library songs
- `users/{uid}/songProfiles/{songId}` stores song-specific learning state
- `users/{uid}/songLibrary/{songId}/practiceMaterials/{materialId}` stores generated practice materials
- `users/{uid}/sessions/{sessionId}` stores completed practice sessions and nested `sessionInfo`
- `users/{uid}/practicePlans/{planId}` stores plan-level summaries
- `users/{uid}/practiceDays/{dayId}` stores per-day plan and completion summaries
- `users/{uid}/practiceTasks/{taskId}` stores movable tasks assigned to days
- `users/{uid}/feed/{feedItemId}` stores inspiration feed items
- `users/{uid}/chatLogs/{chatLogId}` is optional and stores summarized AI coach interactions

## Workflow Mapping

### `chatCoach(chatContext, userMessage) -> chatReply`
Purpose:
- answer user questions about guitar technique, songs, practice, and learning

Triggered by:
- the user sending a message on AI Chat Page

Page input:
- `userMessage` typed on AI Chat Page
- `fromScreen` and active song context if chat was opened from Practicing Page or Session Complete Page

Firebase reads:
- embedded `UserProfile` from `users/{uid}.profile`
- embedded `Preference` from `users/{uid}.preferences`
- active `PracticeMaterial` under `songLibrary/{songId}/practiceMaterials/{materialId}` if the question is material-related

Firebase writes:
- optional `users/{uid}/chatLogs/{chatLogId}`

Displayed on:
- AI Chat Page

Notes:
- this function itself returns chat content only
- if the user asks to change practice material, the backend may call `generateMaterial(...)` as a follow-up action
- **TODO**: might call other functions as well!!

### `generateMaterial(song, profile, preference, requestContext) -> practiceMaterial`
Purpose:
- generate or refresh practice material for a song

Triggered by:
- first time the user starts practicing a song from Library Page or Inspiration Page
- a post-session refresh after Session Complete Page
- a chat-driven material change request from AI Chat Page

Page input:
- selected song from Library Page or Inspiration Page
- optional chat request text from AI Chat Page

Firebase reads:
- `SongEntry` from `users/{uid}/songLibrary/{songId}`
- `SongProfile` from `users/{uid}/songProfiles/{songId}`
- embedded `UserProfile` from `users/{uid}.profile`
- embedded `Preference` from `users/{uid}.preferences`
- current active `PracticeMaterial` for the same song if context is needed

Firebase writes:
- new `PracticeMaterial` at `users/{uid}/songLibrary/{songId}/practiceMaterials/{materialId}`
- previous active material for that song may be updated to `active: false`

Displayed on:
- Practicing Page

Notes:
- there is no separate `materialOverrides` collection in the current system
- chat-driven requests are stored as metadata on the generated `PracticeMaterial`

### `recordSession(song, songProfile, profile, userThoughts) -> newProfile, newSongProfile, sessionInfo`
Purpose:
- save a completed session and update learning state

Triggered by:
- the user leaving Session Complete Page

Page input:
- session duration from Practicing Page
- free-text reflection from Session Complete Page
- optional deadline from Session Complete Page

Firebase reads:
- `SongEntry` from `users/{uid}/songLibrary/{songId}`
- `SongProfile` from `users/{uid}/songProfiles/{songId}`
- embedded `UserProfile` from `users/{uid}.profile`
- current session summary such as recording URLs if available

Firebase writes:
- `sessions/{sessionId}` with nested `SessionInfo`
- updated embedded `UserProfile` on `users/{uid}`
- updated `songProfiles/{songId}`
- optional updates to `practiceDays/{dayId}` completion summary

Displayed on:
- Profile Page diary and day-detail views
- Calendar Page history/completion state
- Home Page recent activity

### `searchSong(title, artist, preference) -> song`
Purpose:
- normalize user-entered song info and create a library-ready song record

Triggered by:
- the user confirming add-to-library on Library Page

Page input:
- song title and artist entered on Library Page

Firebase reads:
- embedded `Preference` from `users/{uid}.preferences` if prioritization is needed

Firebase writes:
- `SongEntry` into `users/{uid}/songLibrary/{songId}`
- optional initial `SongProfile` into `users/{uid}/songProfiles/{songId}`

Displayed on:
- Library Page
- Practicing Page after the user starts that song
- Calendar Page if the song becomes part of a plan

### `updateFeed(profile, preference, likeAndDislike, currentFeed) -> newPreference, newFeed`
Purpose:
- refresh the inspiration feed using user taste and feedback

Triggered by:
- feed refresh logic on Inspiration Page
- app-exit refresh if the team keeps that behavior from the class spec

Page input:
- likes and dislikes from Inspiration Page

Firebase reads:
- embedded `UserProfile` from `users/{uid}.profile`
- embedded `Preference` from `users/{uid}.preferences`
- existing feed items from `users/{uid}/feed/{feedItemId}`

Firebase writes:
- updated embedded `Preference`
- refreshed `feed/{feedItemId}` records

Displayed on:
- Inspiration Page

### `updatePlan(preference, practiceDays, practicePlan, library, externalCalendar) -> newPracticePlan, newPracticeDays, newPracticeTasks`
Purpose:
- create or refresh the user’s practice schedule

Triggered by:
- plan creation or refresh on Calendar Page
- external calendar changes
- meaningful changes in deadlines or library state

Page input:
- calendar-related user actions from Calendar Page

Firebase reads:
- embedded `Preference` from `users/{uid}.preferences`
- existing `PracticePlan` from `users/{uid}/practicePlans/{planId}`
- existing `PracticeDay` records from `users/{uid}/practiceDays/{dayId}`
- existing `PracticeTask` records from `users/{uid}/practiceTasks/{taskId}`
- library songs from `users/{uid}/songLibrary/{songId}`
- external calendar data if connected

Firebase writes:
- updated `practicePlans/{planId}`
- updated `practiceDays/{dayId}`
- created or updated `practiceTasks/{taskId}`

Displayed on:
- Calendar Page
- Home Page

Notes:
- `PracticePlan` is the high-level plan over a date range
- `PracticeDay` is one day summary within that plan
- `PracticeTask` is one movable task assigned to a day
- `SessionLog.practiceDate` links completed sessions back to a day for diary and history views

## Pages That Mainly Read Backend State
- Profile Page reads `sessions/{sessionId}` and nested `sessionInfo`
- Home Page reads `users/{uid}`, `practicePlans`, `practiceDays`, `practiceTasks`, recent `sessions`, and `songLibrary`
- Practicing Page reads the selected song, its `SongProfile`, and active `PracticeMaterial`

## Shared Data Flow
1. User opens or modifies a feature in the client.
2. Client reads current state from Firestore.
3. Client or backend function assembles structured AI inputs.
4. AI returns validated structured output.
5. Backend writes persistent results to Firestore or Storage.
6. UI re-renders from backend state.

## Ownership of Persistent Data
- Persist in Firestore:
  - user account root fields
  - embedded user profile
  - embedded preferences
  - library songs
  - song learning state
  - session logs
  - nested session summaries
  - generated practice materials
  - calendar plans
  - practice-day summaries
  - movable practice tasks
  - inspiration feed items
  - optional chat logs
- Persist in Storage:
  - practice recordings
- Do not treat markdown as runtime storage:
  - markdown exists only as specification and team reference
