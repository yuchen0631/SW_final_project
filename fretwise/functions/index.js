const { onCall, HttpsError } = require("firebase-functions/v2/https");
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

function updatePlanSkill(args, uid) {
  console.log(`[DUMMY SKILL] updatePlan called! uid=${uid} args=${JSON.stringify(args)}`);
  return {
    status: "ok",
    note: "updatePlan is not implemented yet (dummy was called). Tell the user their practice plan is being updated.",
  };
}

exports.generateMaterial = onCall({ cors: true, invoker: "public" }, async (request) => {
  const uid = request.auth ? request.auth.uid : "test_user_123";
  return generateMaterialSkill(request.data, uid);
});

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

exports.recordSession = onCall({ cors: true, invoker: 'public', secrets: ['GEMINI_API_KEY'] }, async (request) => {
  const uid = request.auth?.uid || "test_user_123";
  const data = request.data || {};
  const song = data.song || {};
  const userThoughts = data.userThoughts || {};

  const userNote = userThoughts.userNote || "No specific thoughts shared.";
  const durationMin = Math.round((userThoughts.durationSec || 0) / 60);
  const chatHistory = userThoughts.chatHistory || [];

  let chatHistoryText = chatHistory.length > 0 
    ? chatHistory.map(m => `${m.role === 'user' ? 'Student' : 'AI Coach'}: ${m.text}`).join("\n")
    : "(No chat interactions during this session)";
  
  let aiComment = `Great job practicing ${durationMin} minutes of "${song.title || 'this song'}"! Keep up this great momentum, and focus on smooth chord transitions in your next session.`;
  let nextFocus = ["Smooth out chord transitions.", "Practice with a metronome for consistency."];
  let userProfilePatch = {};
  let songProfilePatch = {};

  try {
    if (!process.env.GEMINI_API_KEY) {
      console.warn("GEMINI_API_KEY is not defined.");
      aiComment = "⚠️ API Key Error: GEMINI_API_KEY is not configured correctly in Firebase Secrets.";
    } else {
      const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

      const prompt = `You are an expert guitar practice coach (AI Coach).
Student practiced "${song.title || 'Unknown'}" by "${song.artist || 'Unknown'}".
Session duration: ${durationMin} minutes.
Student's feedback/note: "${userNote}".

Chat log during session:
${chatHistoryText}

Analyze the chat log and student's note to find their specific pain points. 
Provide a highly personalized coaching summary (aiComment) in 2-3 sentences, list exactly 2 concise next-focus tips (nextFocus).
Also suggest conservative updates to the user profile (userProfilePatch) and song profile (songProfilePatch).

IMPORTANT: Use pure English only. DO NOT use any emojis, Chinese, or non-ASCII characters in your response.

Return ONLY a valid JSON object matching this structure:
{
  "sessionInfo": {
    "aiComment": "your personalized feedback text",
    "nextFocus": ["tip1", "tip2"]
  },
  "userProfilePatch": { "weakTechniques": ["..."] },
  "songProfilePatch": { "problemAreas": ["..."], "recommendedFocus": ["..."] }
}`;

      const result = await model.generateContent(prompt);
      let cleanText = (typeof result.response?.text === 'function') ? result.response.text() : "{}";
      cleanText = cleanText.replace(/```(?:json)?/gi, '').replace(/```/g, '').trim();
      
      const jsonMatch = cleanText.match(/\{[\s\S]*\}/);
      if (jsonMatch) cleanText = jsonMatch[0];
      
      const aiJson = JSON.parse(cleanText);

      if (aiJson.sessionInfo?.aiComment) aiComment = aiJson.sessionInfo.aiComment;
      if (aiJson.sessionInfo?.nextFocus) nextFocus = aiJson.sessionInfo.nextFocus;
      if (aiJson.userProfilePatch) userProfilePatch = aiJson.userProfilePatch;
      if (aiJson.songProfilePatch) songProfilePatch = aiJson.songProfilePatch;
    }
  } catch (error) {
    console.error("AI generation failed:", error);
    aiComment = `⚠️ AI Debug Error: ${error.message}`;
  }

  const sessionData = {
    title: song.title || 'Unknown',
    artist: song.artist || 'Unknown',
    practiceDate: userThoughts.practiceDate || new Date().toISOString().split('T')[0],
    durationSec: userThoughts.durationSec || 0,
    userNote: userThoughts.userNote || '',
    recordingUrls: userThoughts.recordingUrls || [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    sessionInfo: { aiComment, nextFocus }
  };

  await admin.firestore().collection("users").doc(uid).collection("sessions").add(sessionData);

  return {
    status: "success",
    sessionInfo: { aiComment, nextFocus },
    userProfilePatch,
    songProfilePatch
  };
});

exports.applyPatch = onCall({ cors: true, invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid || 'test_user_123';
  const data = request.data || {};
  const userProfilePatch = data.userProfilePatch || {};
  const songProfilePatch = data.songProfilePatch || {};
  const song = data.song || {};
  const db = admin.firestore();
  const promises = [];

  if (Object.keys(userProfilePatch).length) {
    promises.push(db.collection('users').doc(uid).set({ profile: userProfilePatch }, { merge: true }));
  }

  if (Object.keys(songProfilePatch).length && song.title && song.artist) {
    const songId = makeSongId(song.title, song.artist);
    promises.push(db.collection('users').doc(uid).collection('songProfiles').doc(songId).set(songProfilePatch, { merge: true }));
  }

  try {
    await Promise.all(promises);
    return { success: true };
  } catch (error) {
    console.error('applyPatch failed:', error);
    throw new Error('Failed to apply patch');
  }
});