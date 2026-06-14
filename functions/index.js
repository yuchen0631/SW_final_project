const { onCall, setGlobalOptions, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

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
  return "https://www.youtube.com/watch?v=mYpXn-P8y_4";
}

function makeSongId(title, artist) {
  const base = `${title.trim()}--${artist.trim()}`.toLowerCase();
  return base.replace(/[^a-z0-9_-]/g, '_');
}

async function generateSessionInfo(song, userThoughts) {
  const defaultComment = `Great job practicing ${song.title || 'this song'} by ${song.artist || 'your artist'}. Keep focusing on the chord transitions and timing to make your next session even stronger.`;
  const defaultNextFocus = [
    'Keep chord transitions smooth and even.',
    'Practice the most difficult sections slowly first.',
    'Listen for timing and rhythm consistency while playing.',
  ];

  if (!process.env.GEMINI_API_KEY) {
    return { aiComment: defaultComment, nextFocus: defaultNextFocus };
  }

  try {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-pro' });

    const chatHistoryText = (userThoughts.chatHistory || []).length 
      ? `Practice chat:\n${userThoughts.chatHistory.map(m => `${m.role}: ${m.text}`).join('\n')}` 
      : '';
    const prompt = `You are an expert guitar practice coach.
      The user practiced "${song.title || 'Unknown'}" by "${song.artist || 'Unknown'}".
      Session duration: ${userThoughts.durationSec || 0} seconds.
      User's note: "${userThoughts.userNote || ''}".
      ${userThoughts.recordingUrls?.length ? `Recordings submitted: ${userThoughts.recordingUrls.length}` : ''}
      ${chatHistoryText}

      Provide a personalized coaching summary and 3 next-focus tips.
      Return ONLY JSON: {"aiComment": "...", "nextFocus": ["tip1", "tip2", "tip3"]}`;
    const result = await model.generateContent({ prompt });
    const text = result.response?.text?.trim() || '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        aiComment: parsed.aiComment || defaultComment,
        nextFocus: Array.isArray(parsed.nextFocus) ? parsed.nextFocus : defaultNextFocus,
      };
    }
  } catch (error) {
    console.error('Gemini session summary generation failed:', error);
  }

  return { aiComment: defaultComment, nextFocus: defaultNextFocus };
}

exports.searchSong = onCall({ cors: true, invoker: 'public' }, async (request) => {
  const title = request.data?.title || 'Unknown';
  const artist = request.data?.artist || 'Unknown Artist';
  const uid = request.auth?.uid || 'test_user_123';

  const realVideoUrl = await getRealYouTubeVideo(title, artist);

  try {
    const db = admin.firestore();
    const songRef = db.collection('users').doc(uid).collection('songLibrary').doc();

    await songRef.set({
      title,
      artist,
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
    console.error('searchSong failed:', error);
    throw new Error(error.message || 'searchSong failed');
  }
});

exports.updateFeed = onCall({ cors: true, invoker: 'public', timeoutSeconds: 120, secrets: ['GEMINI_API_KEY'] }, async (request) => {
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const uid = request.auth?.uid || 'test_user_123';
  const db = admin.firestore();
  const feedCol = db.collection('users').doc(uid).collection('feed');

  try {
    let songs = [];
    try {
      const model = genAI.getGenerativeModel({ model: 'gemini-pro' });
      const randomSeed = Date.now();
      const prompt = `You are a guitar teacher. Recommend 3 different pop songs for guitar practice. Use seed ${randomSeed} to vary the output. Return only a JSON array like [{"title":"...","artist":"...","description":"..."}]`;
      const result = await model.generateContent({ prompt });
      const aiResponse = result.response?.text?.trim() || '';
      const jsonMatch = aiResponse.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        songs = JSON.parse(jsonMatch[0]);
      } else {
        throw new Error('No JSON array found');
      }
    } catch (aiError) {
      console.error('Gemini 解析失敗，啟用隨機備用名單', aiError);
      const fallbackPool = [
        { title: '愛人錯過', artist: '告五人', description: 'AI 備用推薦：節奏輕快，非常適合新手練習刷法。' },
        { title: 'Perfect', artist: 'Ed Sheeran', description: 'AI 備用推薦：經典的吉他情歌，和弦進行簡單。' },
        { title: 'Yellow', artist: 'Coldplay', description: 'AI 備用推薦：特殊的吉他調音與迷人的刷奏。' },
        { title: '說好不哭', artist: '周杰倫', description: 'AI 備用推薦：經典神曲，練習和弦轉換的好選擇。' },
        { title: 'Photograph', artist: 'Ed Sheeran', description: 'AI 備用推薦：優美的指彈前奏，適合進階練習。' },
        { title: '擁抱', artist: '五月天', description: 'AI 備用推薦：最經典的吉他社入門必學曲目。' },
      ];
      fallbackPool.sort(() => 0.5 - Math.random());
      songs = fallbackPool.slice(0, 3);
    }

    for (const s of songs) {
      const url = await getRealYouTubeVideo(s.title, s.artist);
      await feedCol.add({
        title: s.title || 'Unknown',
        artist: s.artist || 'Unknown',
        videoUrl: url,
        description: s.description || 'AI 推薦教學',
        genre: 'Pop/Rock',
        actionState: 'ignored',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return { success: true };
  } catch (error) {
    console.error('Feed 生成錯誤:', error);
    throw new Error('Internal Server Error');
  }
});

exports.recordSession = onCall({ cors: true, invoker: 'public', secrets: ['GEMINI_API_KEY'] },async (request) => {
  // 1. Verify user authentication status
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in to record a session.");
  }

  const uid = request.auth.uid;
  const data = request.data || {};
  const song = data.song || {};
  const userThoughts = data.userThoughts || {};

  // 2. Extract conversation history and user notes sent from the frontend
  const userNote = userThoughts.userNote || "No specific thoughts shared.";
  const durationMin = Math.round((userThoughts.durationSec || 0) / 60);
  const chatHistory = userThoughts.chatHistory || [];

  // 3. Format the conversation history to be used in the AI Prompt
  let chatHistoryText = chatHistory.map(m => {
    const roleLabel = m.role === 'user' ? 'Student' : 'AI Coach';
    return `${roleLabel}: ${m.text}`;
  }).join("\n");
  
  if (chatHistory.length === 0) {
    chatHistoryText = "(No chat interactions during this session)";
  }
  
  // Default fallback values if the AI API fails
  let aiComment = `Great job practicing ${durationMin} minutes of "${song.title || 'this song'}"! Keep up this great momentum, and focus on smooth chord transitions in your next session.`;
  let nextFocus = ["Smooth out chord transitions.", "Practice with a metronome for consistency."];

  // 4. Try generating personalized feedback using Gemini API
  try {
    
    if (!process.env.GEMINI_API_KEY) {
      console.warn("GEMINI_API_KEY is not defined in the environment. Using fallback comments.");
    } else {
      const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      
      // Using gemini-1.5-flash as it is fast, reliable, and perfectly suited for structured JSON tasks
      const model = genAI.getGenerativeModel({ 
        model: "gemini-1.5-flash" 
      });

      // Construct the explicit prompt with structured response requirements
      const prompt = `You are an expert guitar practice coach (AI Coach).
The student just finished practicing "${song.title || 'Unknown'}" by "${song.artist || 'Unknown'}".
Session duration: ${durationMin} minutes.
Student's feedback/note: "${userNote}".

Below is the dynamic chat log between the Student and you (AI Coach) during this session:
${chatHistoryText}

Analyze the chat log and student's note to find their specific pain points (e.g., fingering difficulty, hand fatigue, or chord transitions). 
Provide a highly personalized coaching summary (aiComment) in 2-3 sentences addressing these specific issues, and list exactly 2 concise next-focus tips (nextFocus).

Return ONLY a valid JSON object. Do NOT include markdown formatting like \`\`\`json.
Expected JSON structure:
{"aiComment": "your personalized feedback text", "nextFocus": ["tip1", "tip2"]}`;

      // Call Gemini API and enforce standard JSON schema mapping
      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
        }
      });

      // Extract text safely using the recommended method calls
      const responseText = result.response?.text?.()?.trim() || result.response?.text?.trim() || "{}";
      const aiJson = JSON.parse(responseText);

      // Overwrite default values if valid parameters are extracted
      if (aiJson.aiComment) {
        aiComment = aiJson.aiComment;
      }
      if (Array.isArray(aiJson.nextFocus) && aiJson.nextFocus.length > 0) {
        nextFocus = aiJson.nextFocus;
      }

      console.log("Successfully generated dynamic AI Coach feedback from Gemini.");
    }
  } catch (error) {
    console.error("AI generation failed, falling back to default comments:", error);
  }

  // 5. Structure the session log payload
  const sessionData = {
    title: song.title || 'Unknown',
    artist: song.artist || 'Unknown',
    practiceDate: userThoughts.practiceDate || new Date().toISOString().split('T')[0],
    durationSec: userThoughts.durationSec || 0,
    userNote: userThoughts.userNote || '',
    recordingUrls: userThoughts.recordingUrls || [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    sessionInfo: {
      aiComment: aiComment,
      nextFocus: nextFocus
    }
  };

  // 6. Write the record containing the personalized AI feedback into Firestore
  await admin.firestore()
    .collection("users")
    .doc(uid)
    .collection("sessions")
    .add(sessionData);

  // 7. Return the status and session info back to the frontend modal
  return {
    status: "success",
    sessionInfo: {
      aiComment: aiComment,
      nextFocus: nextFocus
    }
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

exports.chatWithCoach = onCall({ cors: true, invoker: 'public', secrets: ['GEMINI_API_KEY'] }, async (request) => {
  const data = request.data || {};
  const message = data.message || '';
  const history = data.history || [];
  const song = data.song || { title: 'Unknown', artist: 'Unknown' };

  if (!process.env.GEMINI_API_KEY) {
    return { reply: 'Coach is offline. Try again later.' };
  }

  try {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-pro' });
    const historyStr = history.map((m) => `${m.role}: ${m.text}`).join('\n');
    
    const prompt = `You are a friendly guitar coach. Keep responses short (1-2 sentences).
User practicing "${song.title}" by "${song.artist}".
${historyStr ? `Chat:\n${historyStr}` : ''}
User: ${message}

Reply as coach.`;

    const result = await model.generateContent({ prompt });
    return { reply: result.response?.text?.trim() || 'Keep practicing! 🎸' };
  } catch (error) {
    console.error('chatWithCoach failed:', error);
    return { reply: 'Let me rephrase that...' };
  }
});