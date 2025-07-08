# Firebase 修復部署指南

本指南說明如何部署 Firebase 索引和安全規則修復，解決登出和權限問題。

## 🔧 修復內容

### 1. Firestore 索引問題

- ✅ 添加了 `userId` + `createdAt` 複合索引
- ✅ 添加了 `isActive` + `createdAt` 複合索引
- ✅ 添加了 `applicants` + `createdAt` 複合索引
- ✅ 添加了聊天室相關索引

### 2. 安全規則問題

- ✅ 修復了用戶文檔讀取權限
- ✅ 添加了任務 CRUD 權限控制
- ✅ 添加了聊天室權限控制

### 3. Google 登出優化

- ✅ 改善了斷開連接邏輯
- ✅ 減少了警告信息
- ✅ 添加了更智能的錯誤處理

### 4. 查詢優化

- ✅ 添加了索引缺失時的後備方案
- ✅ 改善了錯誤處理邏輯

## 🚀 部署步驟

### 步驟 1: 部署 Firestore 索引

1. 確保您已安裝 Firebase CLI：

```bash
npm install -g firebase-tools
```

2. 登入 Firebase：

```bash
firebase login
```

3. 在項目根目錄中部署索引：

```bash
firebase deploy --only firestore:indexes
```

4. 等待索引建立完成（可能需要幾分鐘）：
   - 訪問 [Firebase Console](https://console.firebase.google.com)
   - 選擇您的項目
   - 進入 Firestore Database → 索引
   - 確認所有索引狀態為"已啟用"

### 步驟 2: 部署 Firestore 安全規則

1. 部署安全規則：

```bash
firebase deploy --only firestore:rules
```

2. 驗證規則部署：
   - 在 Firebase Console 中檢查 Firestore Database → 規則
   - 確認規則已更新

### 步驟 3: 測試修復

1. 重新啟動您的應用：

```bash
flutter clean
flutter pub get
flutter run
```

2. 測試以下功能：
   - ✅ 用戶登入/登出
   - ✅ 創建任務
   - ✅ 載入我的任務
   - ✅ 載入所有任務
   - ✅ 聊天功能

## 🔍 驗證修復效果

### 預期結果：

1. **索引錯誤消失**：

   - 不再看到 `FAILED_PRECONDITION` 錯誤
   - 任務載入正常工作

2. **權限錯誤消失**：

   - 不再看到 `PERMISSION_DENIED` 錯誤
   - 用戶可以正常讀取自己的數據

3. **登出優化**：

   - 減少 Google 斷開連接警告
   - 登出流程更加穩定

4. **查詢穩定性**：
   - 即使索引暫時不可用，應用仍能正常運行
   - 自動後備到替代查詢方法

## 🛠️ 故障排除

### 如果索引部署失敗：

1. 檢查 Firebase CLI 版本：`firebase --version`
2. 確保您有項目的部署權限
3. 手動在 Firebase Console 中創建索引

### 如果安全規則部署失敗：

1. 檢查規則語法：`firebase firestore:rules --dry-run`
2. 確認您有足夠的權限

### 如果問題仍然存在：

1. 檢查 Firebase Console 中的日誌
2. 確認項目 ID 正確
3. 重新部署：`firebase deploy --only firestore`

## 📋 檢查清單

- [ ] Firebase CLI 已安裝並登入
- [ ] 索引已部署並處於"已啟用"狀態
- [ ] 安全規則已部署
- [ ] 應用已重新啟動
- [ ] 登入/登出功能正常
- [ ] 任務載入功能正常
- [ ] 聊天功能正常
- [ ] 不再出現索引和權限錯誤

## 🎉 完成！

如果所有步驟都成功完成，您的應用現在應該：

- 沒有 Firestore 索引錯誤
- 沒有權限拒絕錯誤
- 登出流程更加流暢
- 整體穩定性提升

如果仍有問題，請檢查 Firebase Console 中的錯誤日誌和調試信息。
