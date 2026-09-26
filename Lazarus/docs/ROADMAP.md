# 実施ロードマップ（2026-09-26改訂）

要件は[REQUIREMENTS](REQUIREMENTS.md)、依存・作業・合否は[DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md)を正本とする。日付約束ではなく品質ゲート方式。旧Phase/Stepとの対応は開発計画7節に記録する。

| 段階 | 成果 | 次へ進む条件 |
|---|---|---|
| M0 | 再現可能な検証基盤 | G0: core/両OS GUI、toolchain/reference/fixture/測定契約 |
| M1 | 1件を記録・復旧する基礎 | G1: package保存復旧、ack欠落0、UI/終了/競合/保存性能 |
| M2 | 履歴付き訂正・検索logbook | G2: 100k表示・編集・復元、負荷中も記録 |
| M3 | 国内4・国際2contestのログ中核 | G3: golden、import/export/backup/rollback、keyboard/性能 |
| M4 | CATと送信安全 | G4: 実機support、PTT/watchdog/停止・障害隔離 |
| M5 | CW/RTTY送受信・audio・waterfall | G5: WAV/実audio/AFSK/FSK、BER/CPU、24h・安全 |
| M6 | cluster/spotを統合した運用MVP | G6: 両OSで全体scenario完走、複合負荷入力継続 |
| M7 | multi-op・SO2R/2BSIQ・録音・拡張 | G7: partition復旧、禁止TX0、拡張互換 |
| M8 | 移行と正式リリース | G8: 署名・pilot・24/48h・restore/rollback・support |

現在はM0/M1のhardeningが最優先。CAT/audio/RTTY spikeは後続の材料で、前段gate合格の証拠ではない。CQRLOG由来のonline/地図/QSL/awardは候補として残し、M8までに採否・理由・受入条件を記録する。

Windows/macOSを各gateで同時検証する。M3を製品MVPと呼ばず、元のMVP範囲（CAT・CW/RTTY送受信・cluster）が揃うM6と区別する。未検証構成・experimental decoderを明示する。data loss、誤得点、誤TX、秘密情報漏洩をリリース判断で許容しない。
