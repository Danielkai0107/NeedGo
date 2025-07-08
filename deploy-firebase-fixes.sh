#!/bin/bash

# Firebase 修復快速部署腳本
# 本腳本將自動部署索引和安全規則修復

echo "🚀 開始部署 Firebase 修復..."

# 檢查是否安裝了 Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ 未找到 Firebase CLI"
    echo "請先安裝 Firebase CLI："
    echo "npm install -g firebase-tools"
    exit 1
fi

# 檢查是否已登入
if ! firebase projects:list &> /dev/null; then
    echo "❌ 未登入 Firebase"
    echo "請先登入："
    echo "firebase login"
    exit 1
fi

echo "✅ Firebase CLI 檢查通過"

# 部署索引
echo "🔍 部署 Firestore 索引..."
if firebase deploy --only firestore:indexes; then
    echo "✅ 索引部署成功"
else
    echo "❌ 索引部署失敗"
    exit 1
fi

# 部署安全規則
echo "🔒 部署 Firestore 安全規則..."
if firebase deploy --only firestore:rules; then
    echo "✅ 安全規則部署成功"
else
    echo "❌ 安全規則部署失敗"
    exit 1
fi

echo ""
echo "🎉 Firebase 修復部署完成！"
echo ""
echo "📋 接下來請："
echo "1. 等待索引建立完成（2-5分鐘）"
echo "2. 在 Firebase Console 中確認索引狀態為'已啟用'"
echo "3. 重新啟動您的應用："
echo "   flutter clean && flutter pub get && flutter run"
echo ""
echo "🔗 Firebase Console: https://console.firebase.google.com"
echo "📖 詳細說明請參考: FIREBASE_FIXES_DEPLOYMENT_GUIDE.md" 