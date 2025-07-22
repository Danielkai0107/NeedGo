# Firebase 管理後台系統 PRD 文件

## 產品需求文件 (Product Requirements Document)

### 專案概述

**系統名稱**: MVP App Firebase 管理後台  
**版本**: v1.0  
**更新日期**: 2024 年 12 月  
**負責人**: 系統管理員

### 1. 系統架構概述

#### 1.1 技術架構

- **前端**: React.js + Ant Design Pro / Vue.js + Element Plus
- **後端**: Node.js + Express / Python Django
- **資料庫**: Firebase Firestore
- **認證**: Firebase Authentication (Admin SDK)
- **存儲**: Firebase Storage
- **部署**: Firebase Hosting / Vercel

#### 1.2 Firebase Collections 結構

- `user` - 用戶資料管理
- `posts` - 任務/貼文管理
- `chats` - 聊天室管理
- `systemLocations` - 系統地點管理
- `system` - 系統配置參數
- `notifications` - 通知記錄

---

## 2. 功能模組詳細規格

### 2.1 任務管理模組 (CRUD Posts)

#### 2.1.1 任務列表頁面

**頁面路由**: `/admin/tasks`

**功能特性**:

- **列表顯示**:

  - 任務標題、發布者、狀態、創建時間、到期時間
  - 任務類型標籤（開放/進行中/已完成/已過期）
  - 應徵者數量顯示
  - 任務地點（地址）
  - 價格顯示

- **篩選功能**:

  - 按狀態篩選（全部/開放/進行中/已完成/已過期）
  - 按發布時間篩選（今日/本週/本月/自定義）
  - 按價格範圍篩選
  - 按地區篩選
  - 按發布者篩選（支持用戶名/ID 搜索）

- **批量操作**:
  - 批量啟用/停用任務
  - 批量變更任務狀態
  - 批量刪除任務
  - 批量匯出數據

#### 2.1.2 任務詳細頁面

**頁面路由**: `/admin/tasks/:taskId`

**顯示資訊**:

- 任務完整資訊（標題、內容、圖片、價格、地點）
- 發布者資料（頭像、姓名、聯繫方式）
- 應徵者列表及狀態
- 聊天室連結
- 任務操作日誌
- 相關統計數據

**操作功能**:

- 編輯任務資訊
- 變更任務狀態
- 強制完成/取消任務
- 管理應徵者狀態
- 發送通知給參與者

#### 2.1.3 任務創建/編輯頁面

**頁面路由**: `/admin/tasks/create`, `/admin/tasks/:taskId/edit`

**表單欄位**:

- 任務標題（必填）
- 任務內容（必填）
- 任務圖片（支持多圖上傳）
- 價格設定（必填）
- 地點選擇（地址 + 座標）
- 執行日期和時間
- 任務狀態設定
- 發布者指定（管理員可代發）

**驗證規則**:

- 標題長度限制 1-50 字
- 內容長度限制 10-500 字
- 圖片格式限制 jpg/png，大小 < 5MB
- 價格必須為正整數
- 地點必須包含有效座標

### 2.2 聊天室管理模組 (CRUD Chats)

#### 2.2.1 聊天室列表頁面

**頁面路由**: `/admin/chats`

**功能特性**:

- **列表顯示**:

  - 聊天室 ID、關聯任務、參與者
  - 最後活動時間、訊息數量
  - 聊天室狀態（活躍/已關閉/失去聯繫）
  - 未讀訊息統計

- **篩選功能**:

  - 按聊天室狀態篩選
  - 按參與者篩選
  - 按關聯任務篩選
  - 按活動時間篩選

- **批量操作**:
  - 批量關閉聊天室
  - 批量清理訊息
  - 批量發送系統通知

#### 2.2.2 聊天室詳細頁面

**頁面路由**: `/admin/chats/:chatId`

**顯示內容**:

- 聊天室基本資訊
- 參與者資料（Parent/Player）
- 關聯任務資訊
- 完整聊天記錄
- 系統操作日誌

**管理功能**:

- 即時監控聊天內容
- 發送系統訊息
- 禁言用戶
- 強制關閉聊天室
- 清理聊天記錄
- 匯出聊天記錄

#### 2.2.3 聊天室設定頁面

**頁面路由**: `/admin/chats/settings`

**全域設定**:

- 聊天室自動關閉時間
- 系統訊息模板管理
- 敏感詞過濾設定
- 聊天記錄保存期限

### 2.3 系統地點管理模組 (CRUD System Locations)

#### 2.3.1 地點列表頁面

**頁面路由**: `/admin/locations`

**功能特性**:

- **列表顯示**:

  - 地點名稱、地址、座標
  - 地點分類、狀態
  - 創建時間、最後更新
  - 關聯任務數量

- **地圖視圖**:

  - Google Maps 整合
  - 地點標記顯示
  - 拖拽調整座標
  - 範圍搜索功能

- **分類管理**:
  - 新增/編輯/刪除分類
  - 分類排序調整
  - 分類圖標設定

#### 2.3.2 地點詳細/編輯頁面

**頁面路由**: `/admin/locations/:locationId`

**表單欄位**:

- 地點名稱（必填）
- 地點分類（下拉選擇）
- 詳細地址（必填）
- GPS 座標（lat, lng）
- 地點描述
- 地點圖片
- 啟用狀態

**地圖功能**:

- 可視化座標選擇
- 地址反查座標
- 附近地點建議

### 2.4 系統參數管理模組 (CRUD System Config)

#### 2.4.1 系統參數頁面

**頁面路由**: `/admin/system/config`

**參數分類**:

- **聊天室設定**:

  - `chatCloseTimer`: 聊天室關閉時間（分鐘）
  - `maxChatRooms`: 單用戶最大聊天室數
  - `messageRetentionDays`: 訊息保存天數

- **任務設定**:

  - `maxTasksPerUser`: 用戶最大發佈任務數
  - `taskExpiryHours`: 任務自動過期時間
  - `minTaskPrice`: 任務最低價格
  - `maxTaskPrice`: 任務最高價格

- **用戶設定**:

  - `verificationRequired`: 是否需要身份驗證
  - `maxImageUploads`: 最大圖片上傳數
  - `profileImageMaxSize`: 頭像最大尺寸（MB）

- **地圖設定**:
  - `defaultMapCenter`: 預設地圖中心點
  - `maxSearchRadius`: 最大搜索半徑（公里）
  - `locationCacheTime`: 地點快取時間

#### 2.4.2 系統監控頁面

**頁面路由**: `/admin/system/monitor`

**監控指標**:

- Firebase 讀寫次數統計
- Storage 使用量統計
- 活躍用戶數統計
- 任務創建/完成統計
- 錯誤日誌監控

### 2.5 用戶管理模組 (CRUD Users)

#### 2.5.1 用戶列表頁面

**頁面路由**: `/admin/users`

**功能特性**:

- **列表顯示**:

  - 用戶頭像、姓名、電話
  - 註冊時間、最後登入
  - 驗證狀態、帳號狀態
  - 發佈任務數、參與任務數
  - 用戶角色偏好

- **篩選功能**:

  - 按驗證狀態篩選
  - 按帳號狀態篩選
  - 按註冊時間篩選
  - 按活躍度篩選

- **批量操作**:
  - 批量啟用/停用帳號
  - 批量發送通知
  - 批量匯出用戶數據

#### 2.5.2 用戶詳細頁面

**頁面路由**: `/admin/users/:userId`

**顯示資訊**:

- 用戶完整個人檔案
- 身份驗證資料
- 發佈任務列表
- 參與任務列表
- 聊天室參與記錄
- 操作行為日誌

**管理功能**:

- 編輯用戶資料
- 變更驗證狀態
- 停用/啟用帳號
- 重置密碼
- 發送通知訊息

#### 2.5.3 用戶驗證管理

**頁面路由**: `/admin/users/verification`

**功能特性**:

- 待驗證用戶列表
- 驗證資料檢視
- 批准/拒絕驗證
- 驗證標準設定

### 2.6 通知設定管理模組

#### 2.6.1 通知範本管理

**頁面路由**: `/admin/notifications/templates`

**範本類型**:

- 任務相關通知
- 聊天室系統訊息
- 用戶帳號通知
- 系統維護通知

**範本編輯功能**:

- 標題和內容編輯
- 變數插入（用戶名、任務標題等）
- 多語言支持
- 預覽功能

#### 2.6.2 推播通知管理

**頁面路由**: `/admin/notifications/push`

**功能特性**:

- 即時推播發送
- 定時推播排程
- 目標用戶選擇
- 推播統計分析

#### 2.6.3 系統公告管理

**頁面路由**: `/admin/notifications/announcements`

**管理功能**:

- 創建系統公告
- 設定顯示時間
- 目標用戶群組
- 公告優先級設定

---

## 3. 技術實作規格

### 3.1 權限管理系統

#### 3.1.1 角色定義

- **超級管理員**: 所有模組完整權限
- **系統管理員**: 除系統參數外的完整權限
- **內容管理員**: 任務和聊天室管理權限
- **客服人員**: 用戶和通知管理權限

#### 3.1.2 權限控制

```javascript
// 權限配置範例
const permissions = {
  super_admin: ["*"],
  system_admin: [
    "users.*",
    "tasks.*",
    "chats.*",
    "locations.*",
    "notifications.*",
  ],
  content_admin: ["tasks.*", "chats.read", "chats.update"],
  support: ["users.read", "users.update", "notifications.*"],
};
```

### 3.2 API 接口設計

#### 3.2.1 RESTful API 規範

```
GET /api/admin/tasks - 獲取任務列表
POST /api/admin/tasks - 創建新任務
GET /api/admin/tasks/:id - 獲取任務詳情
PUT /api/admin/tasks/:id - 更新任務
DELETE /api/admin/tasks/:id - 刪除任務

GET /api/admin/users - 獲取用戶列表
POST /api/admin/users/:id/ban - 停用用戶
POST /api/admin/users/:id/verify - 驗證用戶

GET /api/admin/chats - 獲取聊天室列表
POST /api/admin/chats/:id/close - 關閉聊天室
DELETE /api/admin/chats/:id/messages - 清理聊天記錄
```

#### 3.2.2 Firebase SDK 整合

```javascript
// Firebase Admin SDK 配置
const admin = require("firebase-admin");
const serviceAccount = require("./service-account-key.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://your-project.firebaseio.com",
  storageBucket: "your-project.appspot.com",
});

const db = admin.firestore();
const auth = admin.auth();
const storage = admin.storage();
```

### 3.3 資料同步機制

#### 3.3.1 即時更新

- 使用 Firebase Firestore 即時監聽
- WebSocket 連接維護
- 前端狀態自動同步

#### 3.3.2 快取策略

- Redis 快取熱門查詢
- 本地快取系統配置
- CDN 快取靜態資源

### 3.4 安全性措施

#### 3.4.1 身份認證

- Firebase Auth Admin SDK
- JWT Token 驗證
- 雙因素驗證（2FA）

#### 3.4.2 資料保護

- 敏感資料加密存儲
- API 請求頻率限制
- 操作日誌完整記錄

---

## 4. UI/UX 設計規範

### 4.1 設計原則

- **響應式設計**: 支援桌面和平板瀏覽
- **Material Design**: 統一的視覺風格
- **易用性優先**: 簡化操作流程
- **無障礙支援**: WCAG 2.1 AA 標準

### 4.2 主要頁面佈局

#### 4.2.1 側邊導航選單

```
├── 儀錶板 (Dashboard)
├── 任務管理 (Tasks)
│   ├── 任務列表
│   ├── 新增任務
│   └── 任務分析
├── 用戶管理 (Users)
│   ├── 用戶列表
│   ├── 身份驗證
│   └── 用戶統計
├── 聊天室管理 (Chats)
│   ├── 聊天室列表
│   ├── 即時監控
│   └── 設定管理
├── 系統地點 (Locations)
│   ├── 地點列表
│   ├── 地圖管理
│   └── 分類設定
├── 通知中心 (Notifications)
│   ├── 範本管理
│   ├── 推播管理
│   └── 系統公告
└── 系統設定 (System)
    ├── 參數配置
    ├── 系統監控
    └── 權限管理
```

#### 4.2.2 頁面元件設計

- **統計卡片**: 顯示關鍵指標
- **資料表格**: 支援排序、篩選、分頁
- **操作按鈕**: 一致的行動呼籲設計
- **狀態指示器**: 清楚的視覺狀態反饋

---

## 5. 部署和維護規範

### 5.1 部署架構

- **開發環境**: Firebase Emulator Suite
- **測試環境**: Firebase Test Project
- **生產環境**: Firebase Production Project

### 5.2 CI/CD 流程

```yaml
# GitHub Actions 範例
name: Deploy Admin Backend
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Node.js
        uses: actions/setup-node@v2
        with:
          node-version: "16"
      - name: Install dependencies
        run: npm install
      - name: Build application
        run: npm run build
      - name: Deploy to Firebase
        run: firebase deploy --token ${{ secrets.FIREBASE_TOKEN }}
```

### 5.3 監控和告警

- **效能監控**: Firebase Performance Monitoring
- **錯誤追蹤**: Sentry / Firebase Crashlytics
- **日誌管理**: Google Cloud Logging
- **告警設定**: 關鍵指標閾值告警

---

## 6. 測試規範

### 6.1 測試類型

- **單元測試**: Jest + React Testing Library
- **整合測試**: Firebase Emulator + Cypress
- **端到端測試**: Playwright
- **效能測試**: Lighthouse CI

### 6.2 測試覆蓋率要求

- 程式碼覆蓋率 > 80%
- 關鍵功能覆蓋率 > 95%
- API 端點測試覆蓋率 100%

---

## 7. 專案時程規劃

### 7.1 開發階段 (8 週)

**Week 1-2: 基礎架構**

- 專案初始化和環境設定
- Firebase Admin SDK 整合
- 基本認證系統建置

**Week 3-4: 核心功能開發**

- 任務管理模組開發
- 用戶管理模組開發
- 基本 CRUD 功能實現

**Week 5-6: 進階功能開發**

- 聊天室管理模組
- 系統地點管理模組
- 系統參數管理模組

**Week 7-8: 完善和測試**

- 通知管理功能
- 整合測試和 UI 優化
- 部署和上線準備

### 7.2 維護階段 (持續)

- 用戶反饋收集和功能優化
- 系統效能監控和調優
- 新功能需求評估和開發

---

## 8. 結語

這個 Firebase 管理後台系統將為 MVP App 提供完整的後台管理功能，確保系統穩定運行和高效管理。透過模組化設計和標準化開發流程，系統具備良好的可擴展性和維護性。

建議優先開發核心的 CRUD 功能（任務、用戶、聊天室管理），再逐步完善進階功能如通知管理和系統監控等。這樣可以盡快上線基本功能，並根據實際使用情況調整後續開發重點。
