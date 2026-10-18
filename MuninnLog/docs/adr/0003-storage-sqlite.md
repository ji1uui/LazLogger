# 0003: SQLite の使い方とスキーマのマイグレーション

- 状態：提案（この ADR を含む PR のマージで決定）
- 日付：2026-10-18
- 関連：M0 タスク T5（[05_DEVELOPMENT_PROCESS.md](../05_DEVELOPMENT_PROCESS.md) 第 13 節）、[00_DEVELOPMENT_POLICY.md](../00_DEVELOPMENT_POLICY.md) 決定事項 D10・D15

## 背景

D10 で保存方式を SQLite と決めた。T5 では、次の 4 点を決める必要がある。

- SQLite を呼び出す方法
- 3 OS で SQLite のライブラリをどう用意するか
- 強制終了や停電のときに交信記録を失わない設定
- スキーマの版の管理

制約は次のとおり。

- FPC 3.2.2 で使える部品だけを使う。
- 交信を失わないことを最優先とする（00 第 3 節）。

## 選択肢

### SQLite を呼び出す方法

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **`sqlite3dyn`（FPC 標準）で C API を直接呼ぶ** | トランザクションの開始・終了を自分で決められる。依存が最小。ライブラリを実行時に読み込むため、ビルドに SQLite が不要 | 薄いラッパーを自分で書く |
| `sqldb` の `TSQLite3Connection` | FPC・Lazarus に標準で付属。データ対応部品と組み合わせやすい | トランザクションを暗黙に開始する。WAL や PRAGMA を設定する時機を制御しにくい |
| SQLite を静的にリンクする | ライブラリの配布が不要 | OS ごとにビルド手順が増える。FPC 3.2.2 の標準の手順ではない |

### ライブラリの入手（CI）

| OS | 方法 |
|---|---|
| Linux | apt の `libsqlite3-0`（`sqlite3dyn` は `fp-units-db` に含まれる） |
| macOS | OS に付属する `/usr/lib/libsqlite3.dylib` |
| Windows | sqlite.org の公式 DLL（版を固定）を CI でダウンロードする |

## 決定

1. **呼び出し方**
   - `sqlite3dyn` で C API を直接呼ぶ。
   - 薄いラッパーは `Muninn.Storage.Sqlite`：`TSqliteDatabase`、`TSqliteStatement`、`ESqliteError`。
2. **ライブラリの読み込み**
   - 実行時に読み込む。
   - 環境変数 `MUNINN_SQLITE_LIBRARY` があれば、その 1 つだけを試す。
   - 無ければ、OS ごとの名前を順に試す：
     - Windows：`sqlite3.dll`
     - macOS：`libsqlite3.dylib`、`/usr/lib/libsqlite3.dylib`
     - Linux：`libsqlite3.so.0`、`libsqlite3.so`
   - 3.37.0 より古い場合は拒否する（`STRICT` テーブルのため）。
3. **接続の設定**
   - `journal_mode = WAL`
   - `synchronous = FULL`
   - `foreign_keys = ON`
   - `busy_timeout = 5000`
   - WAL に切り替えられない場合は開かない。
4. **スキーマの版**
   - `PRAGMA user_version` で管理する。
   - マイグレーションは前進のみで、版 1, 2, 3, … と連番にする。
   - 各マイグレーションは、`user_version` の更新と同じ 1 つのトランザクション（`BEGIN IMMEDIATE`）で行う。途中で失敗または強制終了しても、直前の版に戻る。
   - アプリより新しい版の DB は、何も変更せずに開くのを拒否する。WAL への切り替えもしない。
5. **テーブル**
   - `STRICT` を使い、型の違う値を拒否する。
   - 列名は ADIF のフィールド名に合わせる。
   - 単位は列名に含める：周波数は `_hz`、時刻は UTC の Unix ミリ秒 `_ms`、出力は `_mw`。
   - 列挙は固定の文字列コードで保存する（AGENTS.md 第 4 節）。
   - 列の無い ADIF フィールドは `qso_field` に保存し、取り込みと書き出しで失われないようにする。
6. **テスト**
   - SQLite を使うテストは結合テスト（`tests/integration/`）に置く。
   - 強制終了のテストは補助プログラム `muninn-crash-helper` で行う。補助プログラムは、トランザクションの途中で自分のプロセスを終了させる（Unix は `SIGKILL`、Windows は `TerminateProcess`）。テスト側は、その後の DB の内容と `integrity_check` を検査する。

## 結果

スキーマ v1 のテーブルは次のとおり。

| テーブル | 内容 |
|---|---|
| `station` | 局。`kind` の値は `personal`、`club`、`special`、`foreign` |
| `station_location` | 運用地 |
| `operation` | 運用。`kind` の値は `general`、`contest`、`pota`、`sota`、`other` |
| `qso` | 交信。記録時点の値をコピーで持つ |
| `qso_field` | 列の無い ADIF フィールド |

その他の影響：

- `scripts/test.sh` が、単体テストに加えて結合テストもビルド・実行する。
- CI は 3 OS で SQLite を用意する。
- Windows の CI では x64 版の DLL（3.50.4）を使い、SHA-256 を固定して検証する。
- アプリの配布物には、Windows 用の `sqlite3.dll` を同梱する必要がある（配布の作業で扱う）。

**見直す条件：**

- macOS の OS 付属の SQLite が使えなくなったとき（同梱に切り替える）
- 複数のスレッドから DB を使う必要が出たとき（接続をスレッドごとに分ける方針を決める）
- `sqldb` のデータ対応部品が UI に必要になったとき
