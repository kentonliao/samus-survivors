# Samus Survivors — Godot 移植計畫

> 建立日期：2026-08-12（HTML 版 v2.1.1 功能凍結點）
> 原則：HTML 版（index.html）保留為「網頁試玩版」持續部署於 GitHub Pages；
> Godot 版在同一 repo 的 `godot/` 資料夾內開發，目標 Steam 上架。

---

## 0. 為什麼是現在

PROJECT-STATUS.md 第 5 節的移植訊號已全數成立：
- 玩家確認「這個版本已經很棒」（美術/玩法基本盤完成：角色、敵人、頭目戰、背景、特效、UI、音效）
- 剩餘路線圖（配樂、收集要素/Meta 進度、存檔、成就、Steam）全部更適合在引擎內做

## 1. 環境準備（使用者的步驟）

1. 下載 **Godot 4.x 標準版**（不需要 .NET 版）：https://godotengine.org/download/windows/
   選「Godot Engine - Windows 64-bit」，下載後解壓縮即可執行，無需安裝程序
2. 把 `Godot_v4.x-stable_win64.exe` 放到一個固定位置（例如 `C:\Godot\`）
3. 告知 Claude 已完成＋Godot 版本號 → Claude 建立 `godot/` 專案骨架
4. 之後的循環：Claude 寫程式/場景檔 → 使用者開 Godot 編輯器按 F5 試玩 → 回報，
   與 HTML 時代的「改→部署→試玩→回饋」完全相同

## 2. 架構對映（HTML → Godot）

| HTML 版 | Godot 版 |
|---|---|
| index.html 單檔 | `godot/` 專案，場景(.tscn)+腳本(.gd)拆分 |
| canvas 繪製迴圈 | Node2D 場景樹；Sprite2D/AnimatedSprite2D |
| 像素矩陣（Samus/敵人/圖示） | 匯出成 PNG spritesheet（scratchpad 腳本代辦）放 `godot/assets/` |
| WEAPON_DEFS/PASSIVE_DEFS 資料表 | Resource(.tres) 或 GDScript 常數檔 `data/weapons.gd` |
| 武器行為 switch(category) | 每類武器一個 scene + 腳本（繼承共同基底 `WeaponBase` ） |
| enemies 陣列 + 手寫碰撞 | Area2D/CharacterBody2D + 物理層；效能用 MultiMeshInstance2D 視需要 |
| 巨型頭目戰 bossBattle 控制器 | `BossBattle.gd` 狀態機節點（設計照搬：進場/攻擊模式/死亡演出/截斷側貼邊） |
| Web Audio 程序化音效 | 預生成 .wav（一次性用Python合成同配方）+ AudioStreamPlayer；配樂用 .ogg |
| DOM overlay UI | Control 節點 + Theme（Super Metroid 配色規範照搬） |
| localStorage（未用） | `user://save.cfg`（ConfigFile）——收集要素/Meta 進度的基礎 |
| GitHub Pages 部署 | Godot export：Windows exe（Steam）＋可選 HTML5 export 保留網頁版 |

## 3. 移植順序（里程碑，每個都可試玩驗收）

- [x] **M0 專案骨架**：project.godot、960x540 視窗、像素渲染設定、資產匯入
- [x] **M1 可動的薩姆斯**：跑步動畫/待機呼吸/背景地形（靜態圖）——已驗收
- [x] **M2 敵人與生成**：7種雜兵+精英+難度曲線+經驗晶石+升級選單（先文字卡）——已驗收
- [x] **M3 武器系統**：12武器+8被動+12進化（資料表驅動，行為類別逐一移植）
      ——2026-08-12 完成，自動化煙霧測試全過（tests/m3_smoke.gd），待玩家實玩驗收
- [x] **M4 頭目戰**：4巨型中頭目+QUEEN（攻擊模式/死亡演出/連戰照搬）
      ——2026-08-12 完成，自動化煙霧測試全過（tests/m4_smoke.gd），待玩家實玩驗收
- [x] **M5 UI/音效**：SM風格 Theme、HUD、卡片、公告、8-bit 音效 wav 化
      ——2026-08-12 完成（Hud.gd/Sfx.gd+14wav+畫面震動），截圖驗證通過，音效聽感待玩家實測
- **M6 新內容**：配樂、收集要素/圖鑑/Meta解鎖、存檔、暫停選單、成就架構
- **M7 Steam**：Steamworks 整合（godotsteam 外掛）、成就、雲存檔、商店頁素材

## 4. 資產匯出待辦（Claude 代辦，M0 前完成）

- [ ] Samus：站姿 26x43 + 跑步 10 幀 34x37 → spritesheet PNG（4套動力服=4色版 或 shader換色）
- [ ] 敵人 12 種（含 metroid）+ 4 頭目高解析 + QUEEN 矩陣 → PNG
- [ ] 20 個 16x16 圖示 → PNG
- [ ] 8-bit 音效 14 種 → .wav（Python 依 SFX RECIPES 配方合成）
- [ ] 背景地形產生器 → 直接輸出 960x600 PNG（或移植產生器）

## 5. 風險與對策

- **手感差異**：Godot 物理/計時與 rAF 不同 → M1-M3 每步跟 HTML 版對照試玩
- **像素渲染模糊**：專案設定 `textures/canvas_textures/default_texture_filter = Nearest`
- **HTML 版凍結**：移植期間 HTML 版只修 bug 不加功能，避免兩邊追趕
