# OptTab

Option+Tab でアクティブアプリのウィンドウをサムネイルHUDで切り替えるmacOSメニューバーアプリ。
別Space・フルスクリーン・最小化中のウィンドウにも届く（`Cmd+\`` の弱点を克服）。

## 操作

| キー | 動作 |
|---|---|
| Option+Tab | 発動・順送り |
| Option+Shift+Tab | 逆送り |
| Option を離す | 選択ウィンドウへジャンプ |
| Esc | キャンセル |
| カードをクリック | そのウィンドウへジャンプ |

## ビルドとインストール

```bash
./Scripts/bundle.sh
open ~/Applications/OptTab.app
```

初回起動時に **アクセシビリティ** と **画面収録** の許可が必要。
画面収録を許可しない場合もサムネイル無し（アイコン表示）で動く。

## 開発

```bash
swift build && swift test
```
