const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();

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
exports.searchSong = onCall({ cors: true, invoker: "public" }, async (request) => {
  const title = request.data.title || "Unknown";
  const artist = request.data.artist || "Unknown Artist";
  const uid = request.auth ? request.auth.uid : "test_user_123";

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
});

// --- 巧君負責的功能 2: 更新 Feed (無限延伸 + 隨機版) ---
exports.updateFeed = onCall({ cors: true, invoker: "public", timeoutSeconds: 120, secrets: ["GEMINI_API_KEY"] }, async (request) => {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const uid = request.auth ? request.auth.uid : "test_user_123";
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
  });