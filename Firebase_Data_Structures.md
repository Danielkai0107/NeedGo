# Firebase 資料結構文檔

## MVP App 專案完整資料模型

---

## 1. 用戶資料集合 (Collection: `user`)

### 文檔結構

```javascript
{
  // 文檔 ID = userId (Firebase Auth UID)
  "userId": "string",                    // Firebase Auth UID
  "name": "string",                      // 用戶姓名
  "gender": "string",                    // 性別
  "birthday": "Timestamp",               // 生日
  "avatarUrl": "string",                 // 頭像 URL
  "isVerified": "boolean",               // 身份驗證狀態
  "phoneNumber": "string",               // 電話號碼
  "email": "string",                     // 電子郵件
  "lineId": "string",                    // Line ID
  "socialLinks": {                       // 社群連結
    "other": "string"
  },
  "publisherResume": "string",           // 發布者簡介
  "applicantResume": "string",           // 應徵簡歷（向後相容）
  "education": "string",                 // 學歷
  "selfIntro": "string",                 // 自我介紹
  "hasCarLicense": "boolean",            // 汽車駕照
  "hasMotorcycleLicense": "boolean",     // 機車駕照
  "subscriptionStatus": "string",        // 訂閱狀態 (free/premium)
  "preferredRole": "string",             // 偏好角色 (parent/player)
  "isOnline": "boolean",                 // 在線狀態
  "lastSeen": "Timestamp",               // 最後活動時間
  "createdAt": "Timestamp"               // 創建時間
}
```

### 索引需求

- `phoneNumber` (用於登入驗證)
- `isVerified` (篩選已驗證用戶)
- `createdAt` (按註冊時間排序)

---

## 2. 任務集合 (Collection: `posts`)

### 文檔結構

```javascript
{
  // 文檔 ID = 自動生成
  "title": "string",                     // 任務標題
  "name": "string",                      // 任務名稱（別名）
  "content": "string",                   // 任務描述
  "price": "number",                     // 任務價格
  "images": ["string"],                  // 圖片 URL 陣列
  "address": "string",                   // 任務地址
  "lat": "number",                       // 緯度
  "lng": "number",                       // 經度
  "date": "string",                      // 任務日期 (ISO 8601)
  "time": {                              // 任務時間
    "hour": "number",
    "minute": "number"
  },
  "userId": "string",                    // 發布者 ID
  "applicants": ["string"],              // 應徵者 ID 陣列
  "acceptedApplicant": "string",         // 已接受的應徵者 ID
  "status": "string",                    // 任務狀態
  "isActive": "boolean",                 // 是否活躍
  "createdAt": "Timestamp",              // 創建時間
  "updatedAt": "Timestamp",              // 更新時間
  "completedAt": "Timestamp",            // 完成時間
  "expiredAt": "Timestamp"               // 過期時間
}
```

### 狀態值說明

- `status`:
  - `"open"` - 開放中
  - `"accepted"` - 已接受應徵者
  - `"completed"` - 已完成
  - `"expired"` - 已過期

### 索引需求

- `userId` + `createdAt` (查詢用戶的任務)
- `isActive` + `createdAt` (查詢活躍任務)
- `applicants` (查詢用戶應徵的任務)
- `lat` + `lng` (地理位置查詢)

---

## 3. 聊天室集合 (Collection: `chats`)

### 文檔結構

```javascript
{
  // 文檔 ID = "{parentId}_{playerId}_{taskId}"
  "parentId": "string",                  // 發布者 ID
  "playerId": "string",                  // 應徵者 ID
  "taskId": "string",                    // 關聯任務 ID
  "taskTitle": "string",                 // 任務標題
  "participants": ["string"],            // 參與者 ID 陣列 [parentId, playerId]
  "lastMessage": "string",               // 最後一條訊息
  "lastMessageSender": "string",         // 最後訊息發送者
  "unreadCount": {                       // 未讀訊息數
    "{userId}": "number"
  },
  "isActive": "boolean",                 // 聊天室是否活躍
  "isConnectionLost": "boolean",         // 是否失去聯繫
  "hiddenBy": ["string"],                // 隱藏此聊天室的用戶 ID 陣列
  "visibleTo": ["string"],               // 可見此聊天室的用戶 ID 陣列
  "isCleanedUp": "boolean",              // 是否已清理
  "cleanedUpAt": "Timestamp",            // 清理時間
  "createdAt": "Timestamp",              // 創建時間
  "updatedAt": "Timestamp"               // 更新時間
}
```

### 索引需求

- `participants` (查詢用戶的聊天室)
- `isActive` + `updatedAt` (查詢活躍聊天室)
- `taskId` (查詢任務相關聊天室)

---

## 4. 聊天訊息子集合 (SubCollection: `chats/{chatId}/messages`)

### 文檔結構

```javascript
{
  // 文檔 ID = 自動生成
  "senderId": "string",                  // 發送者 ID
  "senderName": "string",                // 發送者姓名
  "senderAvatar": "string",              // 發送者頭像 URL
  "content": "string",                   // 訊息內容
  "type": "string",                      // 訊息類型
  "isRead": "boolean",                   // 是否已讀
  "timestamp": "Timestamp"               // 發送時間
}
```

### 訊息類型說明

- `type`:
  - `"text"` - 文字訊息
  - `"system"` - 系統訊息
  - `"image"` - 圖片訊息

### 索引需求

- `timestamp` (按時間排序)

---

## 5. 系統地點集合 (Collection: `systemLocations`)

### 文檔結構

```javascript
{
  // 文檔 ID = 自動生成
  "name": "string",                      // 地點名稱
  "address": "string",                   // 地點地址
  "lat": "number",                       // 緯度
  "lng": "number",                       // 經度
  "category": "string",                  // 地點分類
  "description": "string",               // 地點描述
  "imageUrl": "string",                  // 地點圖片 URL
  "isActive": "boolean",                 // 是否啟用
  "createdAt": "Timestamp",              // 創建時間
  "updatedAt": "Timestamp"               // 更新時間
}
```

### 分類說明

- `category`: 地點分類如 "餐廳", "公園", "醫院", "學校" 等

### 索引需求

- `category` + `isActive` (按分類查詢)
- `lat` + `lng` (地理位置查詢)

---

## 6. 系統配置集合 (Collection: `system`)

### 文檔結構

```javascript
{
  // 文檔 ID = "DtLX3K2FgJEGWvguqplh" (固定)
  "chatCloseTimer": "number",            // 聊天室關閉時間（分鐘）
  "maxTasksPerUser": "number",           // 單用戶最大任務數
  "taskExpiryHours": "number",           // 任務過期時間（小時）
  "minTaskPrice": "number",              // 任務最低價格
  "maxTaskPrice": "number",              // 任務最高價格
  "verificationRequired": "boolean",     // 是否需要身份驗證
  "maxImageUploads": "number",           // 最大圖片上傳數
  "profileImageMaxSize": "number",       // 頭像最大尺寸（MB）
  "defaultMapCenter": {                  // 預設地圖中心點
    "lat": "number",
    "lng": "number"
  },
  "maxSearchRadius": "number",           // 最大搜索半徑（公里）
  "locationCacheTime": "number",         // 地點快取時間（分鐘）
  "messageRetentionDays": "number",      // 訊息保存天數
  "maxChatRooms": "number",              // 單用戶最大聊天室數
  "updatedAt": "Timestamp"               // 更新時間
}
```

---

## 7. 通知記錄集合 (Collection: `notifications`)

### 文檔結構

```javascript
{
  // 文檔 ID = 自動生成
  "userId": "string",                    // 接收者 ID
  "type": "string",                      // 通知類型
  "title": "string",                     // 通知標題
  "content": "string",                   // 通知內容
  "data": {                              // 額外數據
    "taskId": "string",
    "chatId": "string",
    "applicantId": "string"
  },
  "isRead": "boolean",                   // 是否已讀
  "createdAt": "Timestamp",              // 創建時間
  "readAt": "Timestamp"                  // 讀取時間
}
```

### 通知類型說明

- `type`:
  - `"new_applicant"` - 新應徵者
  - `"task_accepted"` - 任務被接受
  - `"task_completed"` - 任務完成
  - `"chat_message"` - 新聊天訊息
  - `"system_announcement"` - 系統公告

### 索引需求

- `userId` + `createdAt` (查詢用戶通知)
- `isRead` + `createdAt` (查詢未讀通知)

---

## 8. Firebase Storage 結構

### 存儲路徑規範

```
/avatars/
  ├── {userId}.jpg                      // 用戶頭像

/task_images/
  ├── {taskId}/
  │   ├── image_0.png                   // 任務圖片
  │   ├── image_1.png
  │   └── ...

/verification/
  ├── {userId}/
  │   ├── id_card.jpg                   // 身份證件
  │   └── selfie.jpg                    // 自拍照

/location_images/
  ├── {locationId}/
  │   └── main.jpg                      // 地點主圖
```

---

## 9. Firebase Authentication

### 用戶認證方式

- **主要**: 電話號碼 + SMS 驗證碼
- **輔助**: Google 登入
- **管理**: Firebase Admin SDK

### Custom Claims 結構

```javascript
{
  "role": "string",                      // 用戶角色 (user/admin/moderator)
  "isVerified": "boolean",               // 身份驗證狀態
  "subscriptionStatus": "string"         // 訂閱狀態
}
```

---

## 10. Firestore 安全規則概要

### 讀取權限

- `user`: 自己的文檔 + 公開資料
- `posts`: 所有活躍任務
- `chats`: 參與的聊天室
- `systemLocations`: 所有用戶可讀
- `system`: 僅管理員可讀

### 寫入權限

- `user`: 僅能更新自己的文檔
- `posts`: 僅能管理自己的任務
- `chats`: 參與者可發送訊息
- `systemLocations`: 僅管理員可寫
- `system`: 僅管理員可寫

---

## 11. 資料查詢模式

### 常用查詢

```javascript
// 查詢用戶的任務
posts.where("userId", "==", userId).orderBy("createdAt", "desc");

// 查詢活躍任務
posts.where("isActive", "==", true).orderBy("createdAt", "desc");

// 查詢用戶聊天室
chats
  .where("participants", "array-contains", userId)
  .orderBy("updatedAt", "desc");

// 查詢地點分類
systemLocations.where("category", "==", category).where("isActive", "==", true);
```

### 複合查詢索引需求

1. `posts`: `userId` + `createdAt`
2. `posts`: `isActive` + `createdAt`
3. `chats`: `participants` + `updatedAt`
4. `systemLocations`: `category` + `isActive`
5. `notifications`: `userId` + `createdAt`

---

## 12. 資料同步策略

### 即時監聽

- 聊天訊息 (Realtime)
- 聊天室狀態 (Realtime)
- 用戶在線狀態 (Realtime)

### 快取策略

- 系統地點 (Local Cache)
- 系統配置 (5 分鐘快取)
- 用戶基本資料 (Session Cache)

### 離線支援

- 聊天訊息離線存儲
- 任務資料離線緩存
- 圖片預載和緩存

---

## 備註

1. **Timestamp 類型**: 使用 Firebase Timestamp，在客戶端轉換為 DateTime
2. **地理位置**: lat/lng 使用 double 類型，精度約 1 公尺
3. **圖片存儲**: 所有圖片存在 Firebase Storage，Firestore 僅存 URL
4. **資料一致性**: 使用 Transaction 確保關鍵操作的原子性
5. **擴展性**: 所有 ID 欄位預留擴展，支援未來功能需求
