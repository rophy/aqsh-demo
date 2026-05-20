# db-runbooks 開發計畫

## 目前狀態（2026-05-20）

### 已完成

- **架構重構**（commit `b91f828`）：改為 `cluster-region-a` + `cluster-region-b` + `cluster-apps-minio` 三叢集架構
- **Bug 修正**（commits `7dd1a8e` → `6dd498a`）：共修復 14 個部署阻斷問題：
  1. MinIO namespace 缺少定義
  2. kube-federated-auth configmap/secret 路徑錯誤
  3. test.sh context 名稱舊格式
  4. MongoDB keyFile 缺少 initContainer
  5. keyFile 含非法字元（連字號）
  6. MongoDB RS init 使用 NodePort（pod IP 不符）→ 改用 internal DNS
  7. nginx 啟動時 DNS 解析失敗 → aqsh Service 須先建立
  8. nginx port 名稱超過 15 字元
  9. nginx `rewrite` 將 `%2F` decode 成 `/`，aqsh 路由失敗 → 改用 `map $request_uri`
  10. `scripts/test.sh` 缺少 `CLUSTER_DBS_IP` 變數
  11. `tests/common/test.sh` in-pod NodePort 錯誤（30081/30082 → 30082/30083）

### 測試結果

| 執行方式 | 結果 |
|---------|------|
| 手動部署後首次執行（修正前） | 13/18 PASS（5 FAIL） |
| 套用所有修正後手動執行 | **19/19 PASS** ✅ |
| `make single` 全新部署後手動執行 | **19/19 PASS** ✅ |

### 已知問題

#### `make single` 在 Phase 3 (test.sh) 偶爾失敗

- **現象**：deployment 完全成功，但 setup.sh 隨即呼叫 test.sh 時部分 test 失敗（exit 1）
- **根因**：aqsh deployment 報告 `rollout status` 完成後，pod 實際上還需要幾秒鐘才能穩定接受流量；test.sh 在此空窗期送出請求而失敗
- **影響**：不影響功能正確性，手動補跑 `scripts/test.sh` 均 19/19 PASS
- **建議修正**：在 setup.sh 的 Phase 3 前加入短暫等待，或在 test.sh 對第一個請求加入 retry

---

## 下一步計畫

### P0 — 修正 `make single` 偶發 timing 失敗

- [ ] 在 `scripts/setup.sh` Phase 3 前加入 `sleep 5`（或對 nginx health 做 retry 等待）
- [ ] 驗證 `make single` 能端到端完成（deployment + test 全部 PASS）無需手動介入

### P1 — `make multi` 驗證

- [ ] 執行 `make multi`
- [ ] 確認 `cluster-region-b` 部署正常（MariaDB × 3、MongoDB × 3、aqsh、nginx）
- [ ] 確認跨叢集 kube-federated-auth token 驗證正常
- [ ] **跨 region MongoDB RS replication**（已知技術問題）：
  - RS init 使用 internal DNS（僅 cluster-region-a 內可解析）
  - 跨 region secondary 需用 NodePort 位址加入 RS
  - 計畫：init 後用 `rs.reconfig({force:true})` 修改 primary 位址為 NodePort，再 `rs.add` cross-region secondary
- [ ] 執行 `scripts/test.sh` 確認 multi mode 19/19 PASS

### P2 — MinIO 連線驗證

- [ ] 確認 aqsh 任務可寫入 MinIO（mariadb-backups / mongodb-backups bucket）
- [ ] 驗證 MinIO Console 可存取（http://\<APPS_MINIO_IP\>:30091）

### P3 — MongoDB sanity-check 狀態改善

- [ ] Test 10 目前回傳 `status=unknown pass=0 warn=0 fail=0`
- [ ] 調查 sanity-check script 是否需要 RS 為 PRIMARY 才能回傳有效結果
- [ ] 完整 RS 後重新驗證

---

## 關鍵技術說明

### 元件對應

| 元件 | Image | NodePort |
|------|-------|----------|
| nginx (proxy) | `nginx:alpine` | 30080 |
| kube-federated-auth | `ghcr.io/rophy/kube-federated-auth:3.2.0` | 30081 |
| aqsh-mariadb | `aqsh-mariadb:latest`（本機 build） | 30082 |
| aqsh-mongodb | `aqsh-mongodb:latest`（本機 build） | 30083 |
| MinIO API | `minio/minio:latest` | 30090 |
| MinIO Console | `minio/minio:latest` | 30091 |
| MongoDB stream | TCP stream via nginx | 30092–30097 |

### 重要 URL 格式

- aqsh task 提交：`POST /tasks/common%2Fhello`（`%2F` 不可 decode，aqsh 路由為單一 segment）
- nginx 透過 `map $request_uri` 保留原始編碼後轉發

### Git Branch

`feature/multi-region-arch`（最新 commit：`6dd498a`）
