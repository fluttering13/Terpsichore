const easterEggs = <String, ({String title, String message, String trigger})>{
  'logo': (
    trigger: '10 秒內連點首頁 Logo 10 次。',
    title: '女神被戳醒',
    message: '如此執著地戳本女神……若你練舞也有一半這麼勤快就好了',
  ),
  'night': (
    trigger: '於凌晨 00:00 至 06:00 前，當天第一次進入 App。',
    title: '深夜練舞',
    message: 'Nyx 已經將夜幕覆上 Olympus，你竟還在凡間起舞？',
  ),
  'hundredLoops': (
    trigger: '學習影片或音樂的同一片段完成 100 次循環後停止播放；更換來源或區間會重新計算。',
    title: '再一次就好',
    message: '一百次。凡人，你口中的『最後一次』，跟 Zeus 的承諾一樣不太可信。',
  ),
  'mirror': (
    trigger: '10 秒內切換鏡像 6 次，學習影片、自拍鏡頭與 A/B 影片共同計算。',
    title: '鏡像迷宮',
    message: '你再切下去，Moirai 都要以為你有六個命運了。',
  ),
  'secret': (
    trigger: '連續使用達 100 天、解鎖百日 Logo 後，長按首頁 Logo。',
    title: '百日秘密',
    message: '一百天。連 Moirai 都替你記下來了。這份紀錄，本女神准你帶走。',
  ),
  'gaze': (
    trigger: '在首頁連續停留 3 分鐘。',
    title: '凝視女神',
    message: '欣賞本女神三分鐘了。本女神很好看，本女神知道。但你是不是該動了？',
  ),
  'language': (
    trigger: '10 秒內切換中英文 6 次。',
    title: '語言迷航',
    message: '中文也好，English 也罷。換哪種語言，本女神都會叫你去練舞。',
  ),
  'frozen': (
    trigger: '在學習模式將影片暫停於同一畫面超過 300 秒。',
    title: '時間停滯',
    message: '這個定格很有藝術感。只是……你本人也定格了嗎？',
  ),
  'camera': (
    trigger: '本次使用中，在學習模式切換「關閉 B」鏡頭開關 11 次。',
    title: '鏡頭攻防戰',
    message: '十次了。你到底是在關鏡頭，還是在跟另一個自己談判？',
  ),
  'speed': (
    trigger: '本次使用中，在學習模式變更播放倍速 11 次。',
    title: '時間魔法師',
    message: '一下快，一下慢。你是想學舞，還是想把時間玩壞？',
  ),
  'quarter': (
    trigger: '在學習模式將影片播放速度調整至 0.25 倍。',
    title: '時間本體',
    message: '很好，我們現在可以看見時間本人。它走得比你還慢。',
  ),
  'repeat': (
    trigger: '本次使用中，在學習模式切換循環播放 11 次。',
    title: '無限輪迴',
    message: '十次了。你是真的想循環，還是捨不得讓這一段結束？',
  ),
  'unseal': (
    trigger: '當天第一次以慢速實際播放後，從慢速恢復至 1 倍速。',
    title: '解除封印',
    message: '封印解除。很好，現在讓本女神看看你剛才到底學會了什麼。',
  ),
  'sculpt': (
    trigger: '10 秒內變更循環區間 11 次；完成一次拖曳或變更八拍區間計算一次。',
    title: '十秒神蹟',
    message: '你不是在剪片，你是在雕刻。Michelangelo 看了都想拜你為師',
  ),
  'duel': (
    trigger: '在 A/B 分析中，A、B 匯入同一支或內容完全相同的影片。',
    title: '神之對決',
    message: '自己對上自己。很好，這場比賽你總算不會輸給別人了。',
  ),
  'sides': (
    trigger: '本次使用中，在 A/B 分析切換影片鏡像 11 次。',
    title: '左右為難',
    message: '換邊不會改變結果，但本女神理解你……就是很想再確認一次。',
  ),
  'bones': (
    trigger: '當天第一次在 A/B 分析手動顯示骨架。',
    title: '骨感現實',
    message: '別緊張，每個舞者都有一點骨感。只是你今天特別明顯。',
  ),
  'hades': (
    trigger: '本次使用中，在 A/B 分析切換骨架顯示 11 次。',
    title: '冥界變身',
    message: '你切得這麼勤快，連 Hades 都以為你在報到。',
  ),
  'monday': (
    trigger: '星期一當天第一次開始學習播放或錄影、A/B 播放或音樂練習。',
    title: '星期一倖存者',
    message: '星期一沒有打敗你。值得記上一筆。',
  ),
  'friday': (
    trigger: '星期五 18:00 後開始學習播放或錄影、A/B 播放或音樂練習。',
    title: '週五舞池',
    message: '今晚的舞池，不需要排隊。',
  ),
  'newYear': (
    trigger: '練習持續跨越新年，並在跨年後結束播放或錄影。',
    title: '跨年一舞',
    message: '新年已經到了，你還在跳。很好，本女神喜歡這種執著 。',
  ),
  'leap': (
    trigger: '2 月 29 日當天第一次進入 App。',
    title: '四年一天',
    message: '四年才多出來的一天，你拿來跳舞了。',
  ),
  'april': (
    trigger: '4 月 1 日當天第一次進入首頁。',
    title: '四月愚人',
    message: '今日課程改為數學。第一題：五、六、七、八。答錯就重跳。',
  ),
  'lastBeat': (
    trigger: '12 月 31 日當天第一次進入學習頁面。',
    title: '最後一拍',
    message: '今年最後一拍，本女神准你把它帶進明年。',
  ),
  'exports': (
    trigger: '本次使用中成功儲存或匯出 10 支影片，包含錄影、A/B 匯出與影片轉檔。',
    title: '十份存檔',
    message: '十支。很好，你的黑歷史又多了十份。',
  ),
  'notifications': (
    trigger: '本次使用中切換每日通知開關 11 次。',
    title: '通知之戰',
    message: '十次了。你到底是在設定通知，還是在跟本女神鬥智？',
  ),
  'void': (
    trigger: '本次使用中點擊設定內容下方空白處 11 次。',
    title: '虛空之手',
    message: '十次了。你是在敲門，還是在召喚什麼東西？',
  ),
  'return': (
    trigger: '本次使用中從其他模式或設定頁返回首頁 11 次。',
    title: '歸來之人',
    message: '又回來了？本女神開始懷疑，你其實住在這裡。',
  ),
  'vocalVacation': (
    title: '主唱請假',
    trigger: '只選人聲以外的聲部，連續實際播放滿 30 秒。',
    message: '主唱已經被你請出去了。很好，現在沒有人能替你數拍了。',
  ),
  'heartbeat': (
    title: '心跳之外',
    trigger: '只開鼓聲，連續實際播放滿 30 秒。',
    message: '只剩鼓聲了。這次再說聽不到拍子，本女神可不接受。',
  ),
  'bassLover': (
    title: '地下情人',
    trigger: '只開貝斯，連續實際播放滿 30 秒。',
    message: '原來你喜歡藏在下面的聲音。品味不錯，它一直都在，只是很少有人聽見。',
  ),
  'sixGods': (
    title: '六神合體',
    trigger: '完成六軌分離後，選取全部六個聲部並實際播放。',
    message: '拆成六份，再全部放回去。連 Dionysus 都想問你剛才在忙什麼。',
  ),
  'oracleRejected': (
    title: '神諭駁回',
    trigger: 'AI 對齊成功提出建議後，明確選擇「保留原設定」。',
    message: '連神諭都敢駁回。很好，本女神欣賞有主見的凡人。希望你的拍子也這麼堅定。',
  ),
  'intermission': (
    title: '中場也是舞蹈',
    trigger: '在學習或音樂模式，同一片段完成 5 輪循環，每輪完整休息至少 10 秒。',
    message: '懂得停下來，也是舞者的本事。這次本女神沒有在諷刺你。',
  ),
  'yesterday': (
    title: '昨日未完',
    trigger: '載入昨天儲存的專案，並開始播放。',
    message: '你真的回來接著練了。昨天那個說『明天再練』的人，竟然沒有騙本女神。',
  ),
  'reunion': (
    title: '久別重逢',
    trigger: '載入至少 30 天未開啟的專案，並開始播放；尚無開啟紀錄時，以最後儲存時間計算。',
    message: '這支舞還記得你。至於你的肌肉記不記得，我們馬上就知道了。',
  ),
  'solo': (
    title: '獨當一面',
    trigger: 'A/B 都已載入，選擇「只輸出 B」並成功匯出。',
    message: '參考影片可以退場了。這一次，畫面裡只留下你。',
  ),
  'silence': (
    title: '無聲勝有聲',
    trigger: 'A/B 音源設為靜音，連續實際播放滿 30 秒。',
    message: '沒有音樂，動作就得自己說話。放心，本女神正在聽。',
  ),
  'collector': (
    title: '眾神的收藏家',
    trigger: 'YouTube、Instagram、Facebook、Threads 各成功下載至少一支影片，跨次使用累計。',
    message: '四個地方的舞都被你帶回來了。你的收藏室，比 Olympus 的宴會還熱鬧。',
  ),
  'oracleSoundcheck': (
    title: '神諭試音',
    trigger: '本次使用中按「發送測試通知」3 次。',
    message: '一、二、三。聽得到，本女神一直都聽得到。你是在測試通知，還是在確認本女神有沒有想你？',
  ),
};

const easterEggsEnglish = <String, ({String title, String message, String trigger})>{
  'logo': (
    title: "You Woke the Goddess",
    trigger: "Tap the home screen logo 10 times within 10 seconds.",
    message:
        "Such dedication to poking your goddess… If only you practiced dancing half as diligently.",
  ),
  'night': (
    title: "Dancing After Midnight",
    trigger:
        "Enter the app for the first time that day between midnight and 6:00 a.m.",
    message:
        "Nyx has already draped Olympus in night, and you are still dancing down in the mortal world?",
  ),
  'hundredLoops': (
    title: "Just One More Time",
    trigger:
        "Complete 100 loops of the same learning video or music segment, then stop playback. Changing the source or range resets the count.",
    message:
        "One hundred times. Mortal, your “last time” is about as reliable as a promise from Zeus.",
  ),
  'mirror': (
    title: "Mirror Maze",
    trigger:
        "Toggle mirroring 6 times within 10 seconds across the learning video, selfie camera, or A/B videos.",
    message:
        "Keep flipping like that and the Moirai will think you have six different destinies.",
  ),
  'secret': (
    title: "The Hundred-Day Secret",
    trigger:
        "Use the app for 100 consecutive days to unlock the anniversary logo, then long-press the home screen logo.",
    message:
        "One hundred days. Even the Moirai have kept count for you. Your goddess grants you permission to take this keepsake home.",
  ),
  'gaze': (
    title: "Gazing at the Goddess",
    trigger: "Stay on the home screen continuously for 3 minutes.",
    message:
        "Three minutes admiring your goddess. Yes, I know I am beautiful. But should you not be moving by now?",
  ),
  'language': (
    title: "Lost in Translation",
    trigger: "Switch between Chinese and English 6 times within 10 seconds.",
    message:
        "Chinese or English, it makes no difference. In either language, your goddess will tell you to go practice.",
  ),
  'frozen': (
    title: "Frozen in Time",
    trigger:
        "Keep the learning video paused on the same frame for more than 300 seconds.",
    message: "An artistic freeze-frame. Although… have you frozen too?",
  ),
  'camera': (
    title: "Camera Negotiations",
    trigger:
        "Toggle the B camera on or off 11 times in Learning mode during one app session.",
    message:
        "Ten times already. Are you turning off the camera, or negotiating with your other self?",
  ),
  'speed': (
    title: "Time Mage",
    trigger:
        "Change playback speed 11 times in Learning mode during one app session.",
    message:
        "Fast, then slow. Are you here to learn the dance, or to break time itself?",
  ),
  'quarter': (
    title: "Time in Person",
    trigger: "Change the learning video playback speed to 0.25x.",
    message:
        "Wonderful. We can now see time itself. It moves even more slowly than you do.",
  ),
  'repeat': (
    title: "Eternal Return",
    trigger: "Toggle looping 11 times in Learning mode during one app session.",
    message:
        "Ten times already. Do you really want to loop, or can you simply not bear to let this part end?",
  ),
  'unseal': (
    title: "Breaking the Seal",
    trigger:
        "After actually playing at a slower speed, return to 1x speed for the first time that day.",
    message:
        "The seal is broken. Good. Now show your goddess what you actually learned.",
  ),
  'sculpt': (
    title: "A Ten-Second Miracle",
    trigger:
        "Change the loop range 11 times within 10 seconds. Each completed drag or eight-count range change counts once.",
    message:
        "You are sculpting, not trimming a video. Even Michelangelo would ask to be your apprentice.",
  ),
  'duel': (
    title: "A Divine Duel",
    trigger:
        "Import the same video, or videos with identical contents, into both A and B in A/B Analysis.",
    message:
        "You against yourself. Good. At last, a contest where you cannot lose to someone else.",
  ),
  'sides': (
    title: "Taking Sides",
    trigger:
        "Toggle video mirroring 11 times in A/B Analysis during one app session.",
    message:
        "Switching sides will not change the result. But your goddess understands… you just need to check one more time.",
  ),
  'bones': (
    title: "The Bare Bones",
    trigger:
        "Manually show the skeleton in A/B Analysis for the first time that day.",
    message:
        "Relax. Every dancer has a bony side. Yours just happens to be especially visible today.",
  ),
  'hades': (
    title: "Underworld Makeover",
    trigger:
        "Toggle the skeleton display 11 times in A/B Analysis during one app session.",
    message: "You switch so often that even Hades thinks you are checking in.",
  ),
  'monday': (
    title: "Monday Survivor",
    trigger:
        "Start learning playback or recording, A/B playback, or music practice for the first time on a Monday.",
    message: "Monday did not defeat you. That deserves a note in the record.",
  ),
  'friday': (
    title: "Friday Dance Floor",
    trigger:
        "Start learning playback or recording, A/B playback, or music practice at or after 6:00 p.m. on a Friday.",
    message: "No waiting in line for tonight’s dance floor.",
  ),
  'newYear': (
    title: "Dancing into the New Year",
    trigger:
        "Keep practicing across the start of a new year, then end playback or recording after midnight.",
    message:
        "The new year has arrived, and you are still dancing. Good. Your goddess likes that kind of persistence.",
  ),
  'leap': (
    title: "One Day in Four Years",
    trigger: "Enter the app for the first time on February 29.",
    message: "One extra day in four years, and you spent it dancing.",
  ),
  'april': (
    title: "April Fool",
    trigger: "Visit the home screen for the first time on April 1.",
    message:
        "Today’s lesson is mathematics. Question one: five, six, seven, eight. Get it wrong and dance it again.",
  ),
  'lastBeat': (
    title: "The Last Beat",
    trigger: "Enter Learning mode for the first time on December 31.",
    message:
        "The final beat of the year. Your goddess grants you permission to carry it into the next.",
  ),
  'exports': (
    title: "Ten for the Archives",
    trigger:
        "Successfully save or export 10 videos in one app session, including recordings, A/B exports, and video conversions.",
    message:
        "Ten videos. Good. Ten more entries in your archive of embarrassing memories.",
  ),
  'notifications': (
    title: "Notification Warfare",
    trigger: "Toggle daily notifications 11 times during one app session.",
    message:
        "Ten times already. Are you adjusting notifications, or trying to outwit your goddess?",
  ),
  'void': (
    title: "Reaching into the Void",
    trigger:
        "Tap the blank area below the settings content 11 times during one app session.",
    message:
        "Ten times already. Are you knocking on a door, or trying to summon something?",
  ),
  'return': (
    title: "The Returning One",
    trigger:
        "Return to the home screen from another mode or Settings 11 times during one app session.",
    message: "Back again? Your goddess is beginning to suspect you live here.",
  ),
  'vocalVacation': (
    title: "The Singer Takes a Day Off",
    trigger:
        "Select only non-vocal stems and actually play them continuously for 30 seconds.",
    message:
        "You have shown the singer out. Good. Now there is no one left to count the beats for you.",
  ),
  'heartbeat': (
    title: "Beyond the Heartbeat",
    trigger: "Play only the drums continuously for 30 seconds.",
    message:
        "Only the drums remain. This time, your goddess will not accept “I cannot hear the beat” as an excuse.",
  ),
  'bassLover': (
    title: "A Love Below",
    trigger: "Play only the bass continuously for 30 seconds.",
    message:
        "So you like the sound hiding underneath. Good taste. It has always been there; few people stop to hear it.",
  ),
  'sixGods': (
    title: "Six Gods Reunited",
    trigger:
        "After separating all six stems, select all six and start playback.",
    message:
        "Split it into six pieces, then put them all back together. Even Dionysus wants to know what you were doing.",
  ),
  'oracleRejected': (
    title: "Oracle Overruled",
    trigger:
        "After AI alignment successfully offers a suggestion, explicitly choose to keep your original settings.",
    message:
        "You dare overrule an oracle. Good. Your goddess admires a mortal with conviction. I hope your timing is just as firm.",
  ),
  'intermission': (
    title: "The Pause Is Part of the Dance",
    trigger:
        "In Learning or Music mode, complete 5 loops of the same segment, each followed by a full rest of at least 10 seconds.",
    message:
        "Knowing when to stop is part of being a dancer. Your goddess is not being sarcastic this time.",
  ),
  'yesterday': (
    title: "Yesterday, Unfinished",
    trigger: "Load a project saved yesterday and start playback.",
    message:
        "You really came back to keep practicing. The person who said “tomorrow” yesterday actually kept their promise to your goddess.",
  ),
  'reunion': (
    title: "A Long-Awaited Reunion",
    trigger:
        "Load a project that has not been opened for at least 30 days and start playback. If no opening history exists, the last save time is used.",
    message:
        "This dance remembers you. Whether your muscles remember it… we are about to find out.",
  ),
  'solo': (
    title: "Standing on Your Own",
    trigger:
        "With both A and B loaded, choose to export only B and successfully finish the export.",
    message:
        "The reference video may leave the stage. This time, the frame belongs to you alone.",
  ),
  'silence': (
    title: "Louder Than Words",
    trigger:
        "Mute the audio in A/B Analysis and actually play continuously for 30 seconds.",
    message:
        "Without music, the movements must speak for themselves. Do not worry. Your goddess is listening.",
  ),
  'collector': (
    title: "Collector of the Gods",
    trigger:
        "Successfully download at least one video from each of YouTube, Instagram, Facebook, and Threads. Progress carries over between app sessions.",
    message:
        "You brought home dances from four different places. Your collection is livelier than a banquet on Olympus.",
  ),
  'oracleSoundcheck': (
    title: "Oracle Soundcheck",
    trigger: "Tap “Test notification” 3 times during one app session.",
    message:
        "One, two, three. Yes, your goddess can hear you. I could hear you all along. Are you testing notifications, or checking whether I miss you?",
  ),
};
