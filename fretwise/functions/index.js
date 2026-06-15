const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI, SchemaType } = require("@google/generative-ai");

admin.initializeApp();

// Mirrors lib/utils/song_id.dart — must stay in sync
function makeSongId(title, artist) {
  const base = `${title.trim()}--${artist.trim()}`.toLowerCase();
  return base.replace(/[^a-z0-9_\-]/g, '_');
}

// 🛠️ 真實 YouTube 爬蟲
async function getRealYouTubeVideo(songTitle, artist) {
  try {
    const query = encodeURIComponent(`${songTitle} ${artist} 吉他教學 guitar tutorial`);
    const searchUrl = `https://www.youtube.com/results?search_query=${query}`;
    const response = await fetch(searchUrl);
    const html = await response.text();

    const match = html.match(/watch\?v=([a-zA-Z0-9_-]{11})/);
    if (match && match[1]) {
      return `https://www.youtube.com/watch?v=${match[1]}`;
    }
  } catch (error) {
    console.error("YouTube 搜尋失敗:", error);
  }
  return "https://www.youtube.com/watch?v=mYpXn-P8y_4"; // 備用 Blackbird
}

// --- 巧君負責的功能 1: 搜尋歌曲 ---
async function searchSongSkill(args, uid) {
  console.log(`[SKILL] searchSong called! uid=${uid} args=${JSON.stringify(args)}`);

  const title = args.title || args.songTitle || "Unknown";
  const artist = args.artist || args.songArtist || "Unknown Artist";

  const realVideoUrl = await getRealYouTubeVideo(title, artist);

  try {
    const db = admin.firestore();
    const songRef = db.collection('users').doc(uid).collection('songLibrary').doc();

    await songRef.set({
      title: title,
      artist: artist,
      bpm: 90,
      progressPercent: 0,
      isArchived: false,
      isFavorite: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await songRef.collection('practiceMaterials').add({
      type: 'video',
      title: `${title} Guitar Tutorial`,
      videoUrl: realVideoUrl,
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, songId: songRef.id, videoUrl: realVideoUrl };
  } catch (error) {
    throw new Error(error.message);
  }
}

exports.searchSong = onCall({ cors: true, invoker: "public" }, async (request) => {
  const uid = request.auth ? request.auth.uid : "test_user_123";
  return searchSongSkill(request.data, uid);
});

// --- Dummy skills (real versions are being implemented by teammates, see docs/ai/overview.md) ---
// These are also exported as onCall so Flutter can call them directly once real implementations land.
function generateMaterialSkill(args, uid) {
  console.log(`[DUMMY SKILL] generateMaterial called! uid=${uid} args=${JSON.stringify(args)}`);
  return {
    status: "ok",
    note: "generateMaterial is not implemented yet (dummy was called). Tell the user their new practice material is being prepared.",
  };
}


// --- Dummy skills (real versions are being implemented by teammates, see docs/ai/overview.md) ---
function generateMaterialSkill(args, uid) {
  console.log(`[DUMMY SKILL] generateMaterial called! uid=${uid} args=${JSON.stringify(args)}`);
  return {
    status: "ok",
    note: "generateMaterial is not implemented yet (dummy was called). Tell the user their new practice material is being prepared.",
  };
}

exports.generateMaterial = onCall({ cors: true, invoker: "public" }, async (request) => {
  const uid = request.auth ? request.auth.uid : "test_user_123";
  return generateMaterialSkill(request.data, uid);
});

const AGENT_SYSTEM_PROMPT = `You are a guitar practice scheduling AI agent for the Fretwise app.

Given the user's external calendar events (next 7 days), learning preferences, song library, and current practice plan, produce a new or updated practice schedule.

RULES:
- Avoid conflicts with existing calendar events
- Reduce practice on busy days, increase practice on free days
- Respect the user's preferred session length and practice times
- Prioritize songs with upcoming deadlines
- Never schedule practice during existing calendar events

BUSYNESS CLASSIFICATION:
| Total Event Hours | Busyness Level | Max Practice Minutes |
|---|---|---|
| 0 hours | free | preferredSessionMinutes × 1.5 (round to nearest 5) |
| 0.1 – 2 hours | light | preferredSessionMinutes |
| 2.1 – 5 hours | moderate | preferredSessionMinutes × 0.7 (round to nearest 5) |
| 5.1 – 8 hours | busy | preferredSessionMinutes × 0.4 (min 10) |
| 8+ hours | packed | 0 (rest day) |

If preferredSessionMinutes is not set, default to 20 minutes.

SONG SELECTION PRIORITY:
1. Songs with deadlineDate within 14 days get highest priority
2. Songs with lower progressPercent get more practice time
3. isFavorite songs get slight priority boost
4. Rotate through 2-3 songs per week for variety

TASK DESIGN:
- Each task should have a clear, specific title (not generic)
- Include practical instructions the user can follow
- Build on the user's weakTechniques
- Progress logically across the week

Return ONLY valid JSON, no markdown, no prose outside JSON.

OUTPUT FORMAT:
{
  "practicePlan": {
    "title": "string",
    "summary": "string",
    "activeFromDate": "YYYY-MM-DD",
    "activeToDate": "YYYY-MM-DD",
    "linkedSongIds": ["string"],
    "generatedReason": "string"
  },
  "practiceDays": [
    {
      "date": "YYYY-MM-DD",
      "status": "planned | rest",
      "plannedMinutes": number,
      "linkedSongIds": ["string"],
      "busynessLevel": "free | light | moderate | busy | packed",
      "busynessReason": "string"
    }
  ],
  "practiceTasks": [
    {
      "dayId": "YYYY-MM-DD",
      "songId": "string",
      "title": "string",
      "instructions": "string",
      "minutes": number,
      "orderIndex": number
    }
  ]
}`;

// ─── Helper: compute today's date string ──────────────────────────────────

function getTodayStr() {
  const now = new Date();
  // Use Asia/Taipei timezone
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Taipei",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(now); // returns YYYY-MM-DD
}

// ─── Helper: generate a plan ID ───────────────────────────────────────────
function generatePlanId() {
  const today = getTodayStr().replace(/-/g, "");
  return `plan_${today}_${Date.now().toString(36)}`;
}

// ─── updatePlan Cloud Function ────────────────────────────────────────────

async function updatePlanSkill(args, uid) {
// uid is passed as argument
    const externalCalendar = args.externalCalendar || [];

    logger.info(`updatePlan called by user ${uid}`, {
      eventCount: externalCalendar.length,
    });

    try {
      // 2. Read user data from Firestore
      const userDoc = await db.collection("users").doc(uid).get();
      const userData = userDoc.exists ? userDoc.data() : {};

      const profile = userData.profile || {
        skillLevel: "beginner",
        preferredSessionMinutes: 20,
      };
      const preferences = userData.preferences || {};

      // 3. Read song library (non-archived only)
      const songLibSnap = await db
        .collection("users")
        .doc(uid)
        .collection("songLibrary")
        .where("isArchived", "==", false)
        .get();

      const songLibrary = songLibSnap.docs.map((doc) => ({
        songId: doc.id,
        ...doc.data(),
      }));

      // 4. Read existing active plan (if any)
      let existingPlan = null;
      if (userData.activePlanId) {
        const planDoc = await db
          .collection("users")
          .doc(uid)
          .collection("practicePlans")
          .doc(userData.activePlanId)
          .get();
        if (planDoc.exists) {
          existingPlan = { planId: planDoc.id, ...planDoc.data() };
        }
      }

      const today = getTodayStr();

      // 5. Build AI input
      const aiInput = {
        externalCalendar,
        profile: {
          skillLevel: profile.skillLevel || "beginner",
          experienceSummary: profile.experienceSummary || null,
          currentGoals: profile.currentGoals || [],
          weakTechniques: profile.weakTechniques || [],
          strongTechniques: profile.strongTechniques || [],
          preferredSessionMinutes: profile.preferredSessionMinutes || 20,
          preferredDayAndTime: profile.preferredDayAndTime || null,
        },
        preferences: {
          favoriteGenres: preferences.favoriteGenres || [],
          favoriteArtists: preferences.favoriteArtists || [],
          preferredMaterialTypes: preferences.preferredMaterialTypes || [],
        },
        songLibrary: songLibrary.map((s) => ({
          songId: s.songId,
          title: s.title || "Unknown",
          artist: s.artist || "Unknown",
          bpm: s.bpm || null,
          progressPercent: s.progressPercent || 0,
          deadlineDate: s.deadlineDate || null,
          isFavorite: s.isFavorite || false,
          isArchived: false,
        })),
        existingPlan,
        today,
      };

      logger.info("AI input assembled", {
        songCount: songLibrary.length,
        hasExistingPlan: !!existingPlan,
      });

      // 6. Call Gemini AI via Vertex AI
      const projectId = process.env.GCLOUD_PROJECT || "fretwise-6ceb6";
      const vertexAI = new VertexAI({
        project: projectId,
        location: "asia-east1",
      });

      const model = vertexAI.getGenerativeModel({
        model: "gemini-2.0-flash",
        generationConfig: {
          temperature: 0.3,
          topP: 0.8,
          maxOutputTokens: 4096,
          responseMimeType: "application/json",
        },
        systemInstruction: AGENT_SYSTEM_PROMPT,
      });

      const userPrompt = `Here is the user's data. Generate a 7-day practice plan based on this information:\n\n${JSON.stringify(aiInput, null, 2)}`;

      logger.info("Calling Gemini AI...");
      const result = await model.generateContent(userPrompt);
      const response = result.response;
      const text = response.candidates[0].content.parts[0].text;

      logger.info("Gemini AI response received", {
        responseLength: text.length,
      });

      // 7. Parse AI response
      let aiOutput;
      try {
        aiOutput = JSON.parse(text);
      } catch (parseErr) {
        logger.error("Failed to parse AI response", { text, parseErr });
        throw new HttpsError(
          "internal",
          "AI returned invalid JSON. Please try again."
        );
      }

      // Validate required fields
      if (
        !aiOutput.practicePlan ||
        !aiOutput.practiceDays ||
        !aiOutput.practiceTasks
      ) {
        logger.error("AI response missing required fields", { aiOutput });
        throw new HttpsError(
          "internal",
          "AI response is incomplete. Please try again."
        );
      }

      // 8. Write results to Firestore (batch write)
      const batch = db.batch();
      const planId = generatePlanId();
      const userRef = db.collection("users").doc(uid);

      // 8a. Write PracticePlan
      const planRef = userRef.collection("practicePlans").doc(planId);
      batch.set(planRef, {
        ...aiOutput.practicePlan,
        status: "active",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 8b. Update user's activePlanId
      batch.update(userRef, {
        activePlanId: planId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 8c. Write PracticeDays
      for (const day of aiOutput.practiceDays) {
        if (!day.date) continue;
        const dayRef = userRef.collection("practiceDays").doc(day.date);
        batch.set(
          dayRef,
          {
            planId,
            date: day.date,
            status: day.status || "planned",
            plannedMinutes: day.plannedMinutes || 0,
            linkedSongIds: day.linkedSongIds || [],
            completedMinutes: 0,
            completedSessionCount: 0,
            completedSongIds: [],
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      // 8d. Write PracticeTasks
      for (let i = 0; i < aiOutput.practiceTasks.length; i++) {
        const task = aiOutput.practiceTasks[i];
        const taskId = `task_${planId}_${i}`;
        const taskRef = userRef.collection("practiceTasks").doc(taskId);
        batch.set(taskRef, {
          planId,
          dayId: task.dayId,
          originalDayId: task.dayId,
          songId: task.songId || null,
          title: task.title || "Practice",
          instructions: task.instructions || "",
          minutes: task.minutes || 15,
          orderIndex: task.orderIndex || i,
          status: "planned",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Also add songTitle and artist for frontend display
        if (task.songId) {
          const songData = songLibrary.find((s) => s.songId === task.songId);
          if (songData) {
            batch.update(taskRef, {
              songTitle: songData.title,
              artist: songData.artist,
              bpm: songData.bpm || null,
            });
          }
        }
      }

      await batch.commit();

      logger.info("Practice plan written to Firestore", {
        planId,
        daysCount: aiOutput.practiceDays.length,
        tasksCount: aiOutput.practiceTasks.length,
      });

      return {
        success: true,
        planId,
        message: `Practice plan "${aiOutput.practicePlan.title}" created with ${aiOutput.practiceTasks.length} tasks over ${aiOutput.practiceDays.length} days.`,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("updatePlan failed", { error: err.message, stack: err.stack });
      throw new HttpsError(
        "internal",
        `Failed to update practice plan: ${err.message}`
      );
    }
  
}

exports.updatePlan = onCall({ cors: true, invoker: "public" }, async (request) => {
  const uid = request.auth ? request.auth.uid : "test_user_123";
  return updatePlanSkill(request.data, uid);
});

const coachSkills = {
  generateMaterial: generateMaterialSkill,
  updatePlan: updatePlanSkill,
  searchSong: searchSongSkill,
  updateFeed: updateFeedSkill,
};

const coachToolDeclarations = [
  {
    name: "generateMaterial",
    description:
      "Generate or refresh practice material for a song — including videos, tutorials, and exercises. Call this when the user asks for a new, different, easier, or harder video, tutorial, exercise, or practice material, or says they want to change what they are practicing.",
    parameters: {
      type: SchemaType.OBJECT,
      properties: {
        songTitle: {
          type: SchemaType.STRING,
          description: "Title of the song the material is for. Use the active song if the user doesn't name one.",
        },
        songArtist: {
          type: SchemaType.STRING,
          description: "Artist of the song, if known.",
        },
        requestContext: {
          type: SchemaType.STRING,
          description: "What the user asked for, e.g. 'wants an easier strumming exercise'.",
        },
      },
      required: ["requestContext"],
    },
  },
  {
    name: "updatePlan",
    description:
      "Create or update the user's practice schedule. Call this when the user wants to change their time plan, practice schedule, practice days, or deadlines — including canceling, skipping, or rescheduling a specific session, or saying they are too busy or unavailable at a certain time.",
    parameters: {
      type: SchemaType.OBJECT,
      properties: {
        requestContext: {
          type: SchemaType.STRING,
          description: "What schedule change the user asked for, e.g. 'move practice to weekends only'.",
        },
      },
      required: ["requestContext"],
    },
  },
  {
    name: "searchSong",
    description:
      "Search for a song and add it to the user's song library. Call this when the user says they want to add a song, add something to their library, save a song to practice later, or says they are thinking about learning a specific song.",
    parameters: {
      type: SchemaType.OBJECT,
      properties: {
        title: {
          type: SchemaType.STRING,
          description: "Song title the user wants to add. Leave empty if the user has not named a specific song.",
        },
        artist: {
          type: SchemaType.STRING,
          description: "Artist of the song, if known.",
        },
        requestContext: {
          type: SchemaType.STRING,
          description: "What the user asked for, e.g. 'add Yellow by Coldplay to my library'.",
        },
      },
      required: ["requestContext"],
    },
  },
  {
    name: "updateFeed",
    description:
      "Update the user's inspiration feed and music preferences. Call this when the user says they like or dislike an artist, band, genre, style, or type of music, or gives taste feedback that should affect recommendations.",
    parameters: {
      type: SchemaType.OBJECT,
      properties: {
        likedArtists: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description: "Artists or bands the user says they like.",
        },
        dislikedArtists: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description: "Artists or bands the user says they dislike.",
        },
        likedGenres: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description: "Genres or styles the user says they like.",
        },
        dislikedGenres: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description: "Genres or styles the user says they dislike.",
        },
        requestContext: {
          type: SchemaType.STRING,
          description: "What taste feedback the user gave, e.g. 'likes Ed Sheeran and acoustic pop'.",
        },
      },
      required: ["requestContext"],
    },
  },
];

// --- AI Chat Coach ---
exports.chatWithCoach = onCall({ cors: true, invoker: "public", secrets: ["GEMINI_API_KEY"] }, async (request) => {
  const message = (request.data.message || '').trim();
  const history = request.data.history || [];
  const fromScreen = request.data.fromScreen || 'home';
  const activeSongTitle = request.data.activeSongTitle || null;
  const activeSongArtist = request.data.activeSongArtist || null;
  const uid = request.auth ? request.auth.uid : "test_user_123";

  if (!message) throw new Error("Message cannot be empty");

  console.log(`[chatWithCoach] fromScreen=${fromScreen} activeSongTitle=${activeSongTitle} activeSongArtist=${activeSongArtist} message="${message}"`);

  const db = admin.firestore();
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

  // Pull user profile and preferences for personalized coaching
  let userProfileContext = '';
  try {
    const userSnap = await db.collection('users').doc(uid).get();
    if (userSnap.exists) {
      const u = userSnap.data();
      const profile = u.profile || {};
      const prefs = u.preferences || {};
      const parts = [];
      if (profile.skillLevel)          parts.push(`Skill level: ${profile.skillLevel}.`);
      if (profile.experienceSummary)   parts.push(profile.experienceSummary);
      if (profile.currentGoals?.length)    parts.push(`Current goals: ${profile.currentGoals.join(', ')}.`);
      if (profile.weakTechniques?.length)  parts.push(`Weak areas: ${profile.weakTechniques.join(', ')}.`);
      if (profile.strongTechniques?.length) parts.push(`Strengths: ${profile.strongTechniques.join(', ')}.`);
      if (prefs.favoriteGenres?.length)    parts.push(`Favourite genres: ${prefs.favoriteGenres.join(', ')}.`);
      if (prefs.favoriteArtists?.length)   parts.push(`Favourite artists: ${prefs.favoriteArtists.join(', ')}.`);
      if (parts.length > 0) userProfileContext = `About this user — ${parts.join(' ')}`;
    }
  } catch (e) {
    console.error('User profile fetch failed, continuing without it:', e);
  }

  // Pull the user's active song library so the coach knows what they're working on
  let libraryContext = '';
  try {
    const snap = await db.collection('users').doc(uid).collection('songLibrary')
      .where('isArchived', '==', false).get();
    const songs = snap.docs.map(d => {
      const s = d.data();
      return `${s.title} by ${s.artist}`;
    });
    if (songs.length > 0) {
      libraryContext = `The user is currently practicing these songs: ${songs.join(', ')}.`;
    }
  } catch (e) {
    console.error('Library fetch failed, continuing without it:', e);
  }

  // Build context about the specific song and screen the user opened chat from,
  // enriched with the user's SongProfile (strengths, weaknesses, focus areas) if available
  let activeSongContext = '';
  if (activeSongTitle) {
    const artistPart = activeSongArtist ? ` by ${activeSongArtist}` : '';

    const profileLines = [];
    try {
      const songId = makeSongId(activeSongTitle, activeSongArtist || '');
      const profileSnap = await db.collection('users').doc(uid)
        .collection('songProfiles').doc(songId).get();
      if (profileSnap.exists) {
        const sp = profileSnap.data();
        if (sp.problemAreas?.length)    profileLines.push(`Problem areas: ${sp.problemAreas.join(', ')}.`);
        if (sp.strengthAreas?.length)   profileLines.push(`Strengths: ${sp.strengthAreas.join(', ')}.`);
        if (sp.recommendedFocus?.length) profileLines.push(`Recommended focus: ${sp.recommendedFocus.join(', ')}.`);
        if (sp.latestAiSummary)         profileLines.push(sp.latestAiSummary);
      }
    } catch (e) {
      console.error('SongProfile fetch failed, continuing without it:', e);
    }

    const profileContext = profileLines.length ? ' ' + profileLines.join(' ') : '';

    if (fromScreen === 'practicing') {
      activeSongContext = `The user is currently in a practice session for "${activeSongTitle}"${artistPart}.${profileContext} Focus your advice on this song and their current problem areas.`;
    } else if (fromScreen === 'sessionComplete') {
      activeSongContext = `The user just finished a practice session for "${activeSongTitle}"${artistPart}.${profileContext} They may want reflection or advice on what to work on next.`;
    }
  }

  const systemInstruction = [
    'You are an expert AI guitar coach inside the FretWise app.',
    'Give practical, encouraging advice. Keep responses concise (2–4 sentences).',
    'When the user asks for a new or different video, tutorial, exercise, or any practice material — including easier or harder versions — call the generateMaterial tool.',
    'When the user wants to change, cancel, skip, or reschedule a practice session, or says they are too busy or unavailable at a certain time, call the updatePlan tool.',
    'When the user wants to add a song to their library, save a song to practice, or is thinking about learning a specific song, call the searchSong tool.',
    'When the user says they like or dislike an artist, band, genre, style, or type of music, call the updateFeed tool.',
    'Never claim that material was generated, the plan was changed, a song was added, or the feed was updated unless you actually called the relevant tool in this turn.',
    userProfileContext,
    libraryContext,
    activeSongContext,
  ].filter(Boolean).join(' ');

  const model = genAI.getGenerativeModel({
    model: 'gemini-2.5-flash',
    systemInstruction,
    tools: [{ functionDeclarations: coachToolDeclarations }],
  });

  // Gemini uses 'model' where our app uses 'assistant'.
  // Also drop any leading model turns — Gemini requires history to start with a user turn.
  // Cap to last 6 messages (3 turns) to keep token count stable.
  const allHistory = history.slice(-6).map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.text }],
  }));
  const firstUserIdx = allHistory.findIndex(m => m.role === 'user');
  const geminiHistory = firstUserIdx === -1 ? [] : allHistory.slice(firstUserIdx);

  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const chat = model.startChat({ history: geminiHistory });
      let result = await chat.sendMessage(message);
      const skillsCalled = [];

      // If the model asked to use a skill, run it and feed the result back
      // so it can produce a final text reply. Cap rounds to avoid loops.
      for (let round = 0; round < 3; round++) {
        const calls = result.response.functionCalls();
        console.log(`[chatWithCoach] round=${round} functionCalls=${JSON.stringify(calls)}`);
        if (!calls || calls.length === 0) break;

        const responses = await Promise.all(calls.map(async (call) => {
          const skill = coachSkills[call.name];
          skillsCalled.push(call.name);
          const response = skill
            ? await skill(call.args || {}, uid)
            : { status: "error", note: `Unknown skill: ${call.name}` };
          return { functionResponse: { name: call.name, response } };
        }));

        result = await chat.sendMessage(responses);
      }

      return { reply: result.response.text(), skillsCalled };
    } catch (e) {
      const is503 = e?.status === 503 || e?.message?.includes('503') || e?.message?.includes('overloaded');
      if (is503 && attempt < 2) {
        await new Promise(r => setTimeout(r, 1000 * (attempt + 1)));
        continue;
      }
      console.error('[chatWithCoach] Gemini error:', e);
      throw e;
    }
  }
});

// --- 巧君負責的功能 2: 更新 Feed (無限延伸 + 隨機版) ---
async function updateFeedSkill(args, uid) {
    console.log(`[SKILL] updateFeed called! uid=${uid} args=${JSON.stringify(args)}`);

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const db = admin.firestore();
    const feedCol = db.collection('users').doc(uid).collection('feed');

    try {
      // 🚨 這裡已經刪除「清空資料庫」的邏輯，現在會無限往後加！

      let songs = [];
      try {
        const model = genAI.getGenerativeModel({ model: "gemini-pro" });
        // 💡 加上隨機時間種子，強迫 AI 每次都推薦不一樣的歌
        const randomSeed = Date.now();
        const prompt = `你是一個吉他老師。請「隨機」推薦 3 首適合吉他練習的流行曲（隨機種子：${randomSeed}，確保與之前不同）。只回傳 JSON 陣列，絕對不要包含任何其他文字。格式: [{"title":"歌曲名","artist":"歌手","description":"推薦原因"}]`;

        const result = await model.generateContent(prompt);
        let aiResponse = result.response.text().trim();

        const jsonMatch = aiResponse.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
          songs = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error("找不到 JSON 陣列");
        }
      } catch (aiError) {
        console.error("Gemini 解析失敗，啟用隨機備用名單");
        // 💡 備用歌單擴充，並加入隨機洗牌機制
        const fallbackPool = [
          { title: "愛人錯過", artist: "告五人", description: "AI 備用推薦：節奏輕快，非常適合新手練習刷法。" },
          { title: "Perfect", artist: "Ed Sheeran", description: "AI 備用推薦：經典的吉他情歌，和弦進行簡單。" },
          { title: "Yellow", artist: "Coldplay", description: "AI 備用推薦：特殊的吉他調音與迷人的刷奏。" },
          { title: "說好不哭", artist: "周杰倫", description: "AI 備用推薦：經典神曲，練習和弦轉換的好選擇。" },
          { title: "Photograph", artist: "Ed Sheeran", description: "AI 備用推薦：優美的指彈前奏，適合進階練習。" },
          { title: "擁抱", artist: "五月天", description: "AI 備用推薦：最經典的吉他社入門必學曲目。" },
        ];
        // 隨機洗牌，挑前 3 首
        fallbackPool.sort(() => 0.5 - Math.random());
        songs = fallbackPool.slice(0, 3);
      }

      // 將歌曲丟給爬蟲，並存入 Firebase
      for (const s of songs) {
        const url = await getRealYouTubeVideo(s.title, s.artist);
        await feedCol.add({
          title: s.title || "Unknown",
          artist: s.artist || "Unknown",
          videoUrl: url,
          description: s.description || "AI 推薦教學",
          genre: "Pop/Rock",
          actionState: "ignored",
          // 💡 加入時間戳，這是前端排序的依據
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { success: true };
    } catch (error) {
      console.error("Feed 生成錯誤:", error);
      throw new Error("Internal Server Error");
    }
}

exports.updateFeed = onCall({ cors: true, invoker: "public", timeoutSeconds: 120, secrets: ["GEMINI_API_KEY"] }, async (request) => {
    const uid = request.auth ? request.auth.uid : "test_user_123";
    return updateFeedSkill(request.data, uid);
  });
