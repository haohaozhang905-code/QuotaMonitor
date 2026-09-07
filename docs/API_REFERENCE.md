# QuotaMonitor 平台接口参考文档

> 本文档整理了 WorkBuddy / CodeBuddy、TraeWork、豆包工作三个平台的额度查询接口，通过浏览器抓包逆向获得。
>
> 最后更新：2026-08-28

---

## 目录

- [平台总览对比](#平台总览对比)
- [1. WorkBuddy / CodeBuddy（腾讯云代码助手）](#1-workbuddy--codebuddy腾讯云代码助手)
- [2. TraeWork](#2-traework)
- [3. 豆包工作](#3-豆包工作)
- [统一监控建议](#统一监控建议)

---

## 平台总览对比

| 维度 | WorkBuddy / CodeBuddy | TraeWork | 豆包工作 |
|------|----------------------|----------|---------|
| API 域名 | `www.codebuddy.cn` / `www.workbuddy.cn` | `api.trae.cn` | `www.doubao.com` |
| 认证方式 | Cookie（登录态） | `Authorization: Cloud-IDE-JWT <token>` | Cookie（登录态） |
| 额度单位 | credits | credits | 百分比制（无具体数值） |
| 能否获取具体数值 | ✅ 可以 | ✅ 可以 | ❌ 仅百分比 |
| 额度明细粒度 | 每条请求 | 每个会话 + token 数 | 无（仅窗口百分比） |
| token 消耗明细 | ✅ model + client + credit | ✅ input/output/cache token | ❌ |
| JWT 过期刷新 | 不需要 | 需要（有 exp 字段） | 不需要 |
| 主要限制 | 需保持登录 Cookie | JWT token 定期过期 | 无具体数值，只能百分比预警 |

---

## 1. WorkBuddy / CodeBuddy（腾讯云代码助手）

### 1.1 基本信息

- **产品说明**：WorkBuddy（workbuddy.cn）和 CodeBuddy（codebuddy.cn）共用腾讯云后端计费系统，接口路径一致，但查询参数不同导致返回的资源包范围不同。
- **认证方式**：Cookie 登录态，请求头无需额外 Authorization。
- **Content-Type**：`application/json`

### 1.2 核心接口一：获取用户资源（额度余额）

```
POST /billing/meter/get-user-resource
```

#### 请求体（CodeBuddy 网页版，指定 PackageCodes）

```json
{
  "PageNumber": 1,
  "PageSize": 200,
  "ProductCode": "p_tcaca",
  "Status": [0, 3],
  "OnlyValidPeriod": true,
  "PackageCodes": [
    "TCACA_code_008_cfWoLwvjU4",
    "TCACA_code_002_AkiJS3ZHF5",
    "TCACA_code_023_4xbGhMrE6q"
  ]
}
```

#### 请求体（WorkBuddy 应用版，时间范围查询，返回全部资源包）

```json
{
  "PageNumber": 1,
  "PageSize": 100,
  "ProductCode": "p_tcaca",
  "Status": [0, 3],
  "PackageStartTimeRangeBegin": "2024-12-01 21:25:00",
  "PackageStartTimeRangeEnd": "2026-08-28 00:29:13"
}
```

> **关键区别**：WorkBuddy 应用版用时间范围查询可拉取全部 41 个资源包（含 2500 裂变赠送包）；CodeBuddy 网页版用 PackageCodes 只查询特定包，可能遗漏赠送包。

#### 响应体结构

```json
{
  "code": 0,
  "msg": "OK",
  "requestId": "xxx",
  "data": {
    "Response": {
      "Data": {
        "TotalCount": 41,
        "TotalDosage": 3000,
        "Accounts": [
          {
            "AccountId": 3088983,
            "CapacityType": 4,
            "CapacityUnit": "credits",
            "PackageCode": "TCACA_code_008_cfWoLwvjU4",
            "PackageName": "CodeBuddy个人体验版",
            "PackageType": "1",
            "PkgSourceType": 0,
            "ProductCode": "p_tcaca",
            "ProductName": "腾讯云代码助手",
            "SubProductCode": "sp_tcaca_codebuddy_ide",
            "SubProductName": "腾讯云代码助手 (IDE)",
            "Status": 0,
            "CapacitySize": 500,
            "CapacityRemain": 500,
            "CapacityUsed": 0,
            "CapacitySizePrecise": "500",
            "CapacityRemainPrecise": "500",
            "CapacityUsedPrecise": "0",
            "CycleCapacitySize": 500,
            "CycleCapacityRemain": 445,
            "CycleCapacityUsed": 54,
            "CycleCapacitySizePrecise": "500",
            "CycleCapacityRemainPrecise": "445.65000109",
            "CycleCapacityUsedPrecise": "54.34999891",
            "CycleStartTime": "2026-08-01 00:00:00",
            "CycleEndTime": "2026-08-31 23:59:59",
            "DeductionStartTime": 1773074857000,
            "DeductionEndTime": 2033484456000,
            "RemainCycles": 0,
            "TotalCycles": 1,
            "ResourceId": "codebuddy-k19000gvNiFv_qt",
            "ResourceType": "2",
            "FeeType": 1,
            "Region": "ap-others",
            "Zone": "ap-others-4"
          }
        ]
      },
      "RequestId": "xxx"
    }
  }
}
```

#### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `TotalCount` | int | 资源包总数 |
| `TotalDosage` | int | 总剂量（所有有效包额度之和） |
| `Accounts[].PackageName` | string | 资源包名称（如"CodeBuddy个人体验版"、"CodeBuddy个人版国内运营裂变包"） |
| `Accounts[].Status` | int | 状态：0=有效，3=已过期/用完 |
| `Accounts[].CapacitySize` | int | 包总额度（credits） |
| `Accounts[].CapacityRemain` | int | 包剩余额度（整数，可能有精度损失） |
| `Accounts[].CapacityUsed` | int | 包已用额度 |
| `Accounts[].CapacityRemainPrecise` | string | 精确剩余额度（字符串，高精度） |
| `Accounts[].CycleCapacitySize` | int | 当前周期总额度 |
| `Accounts[].CycleCapacityRemain` | int | 当前周期剩余额度 |
| `Accounts[].CycleCapacityUsed` | int | 当前周期已用额度 |
| `Accounts[].CycleCapacityRemainPrecise` | string | 当前周期精确剩余（如 "445.65000109"） |
| `Accounts[].DeductionEndTime` | long | 到期时间（毫秒级时间戳） |
| `Accounts[].PkgSourceType` | int | 包来源类型：0=常规，10=福利积分等 |

#### 实际数据样例（当前账号）

| 包名称 | 数量 | 单包额度 | 总额度 | 状态 | 周期已用 |
|--------|------|---------|--------|------|---------|
| CodeBuddy个人体验版 | 1 | 500 | 500 | 有效 | 54.35 |
| CodeBuddy个人版国内运营裂变包 | 25 | 100 | 2500 | 有效 | 0 |
| CodeBuddy个人版国内运营裂变包 | 1 | 2000 | 2000 | 已过期 | 2000 |
| **有效包合计** | **26** | — | **3000** | — | **54.35** |

> **当前总剩余 ≈ 2945.65 credits**（3000 - 54.35）

---

### 1.3 核心接口二：获取请求用量明细

```
POST /billing/meter/get-user-request-usage
```

#### 请求体

```json
{
  "startTime": "2026-08-20 00:00:00",
  "endTime": "2026-08-27 23:59:59",
  "pageNum": 1,
  "pageSize": 10
}
```

#### 响应体结构

```json
{
  "code": 0,
  "msg": "OK",
  "requestId": "xxx",
  "data": {
    "total": 234,
    "data": [
      {
        "requestId": "f9bab20ee1674e8dabed04114d693a04",
        "credit": 3.68,
        "model": "hy3-x",
        "client": "WorkBuddy",
        "requestTime": "2026-08-27 23:46:00",
        "input": "",
        "inputTrunc": "",
        "agentPurpose": ""
      },
      {
        "requestId": "71177d144efe4767b950c6a359eaf339",
        "credit": 18.12,
        "model": "hy3-x",
        "client": "WorkBuddy",
        "requestTime": "2026-08-27 22:06:00",
        "input": "继续",
        "inputTrunc": "继续",
        "agentPurpose": "conversation"
      }
    ]
  }
}
```

#### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `total` | int | 总记录数 |
| `data[].requestId` | string | 请求唯一 ID |
| `data[].credit` | float | 本次请求消耗的 credits |
| `data[].model` | string | 模型名称（如 hy3-x、hy3） |
| `data[].client` | string | 客户端来源（WorkBuddy / CodeBuddy 等） |
| `data[].requestTime` | string | 请求时间（格式：`YYYY-MM-DD HH:mm:ss`） |
| `data[].input` | string | 用户输入内容（可能为空） |
| `data[].agentPurpose` | string | Agent 用途标识（如 conversation） |

---

### 1.4 辅助接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/billing/meter/checkin-status` | POST | 签到状态查询 |
| `/v2/user/cloudagent/entitlement` | GET | WorkBuddy 云代理权益（WorkBuddy 特有） |
| `/billing/ide/trial` | POST | IDE 试用状态 |
| `/console/user/from` | POST | 用户来源信息 |

---

### 1.5 注意事项

1. **资源包查询方式**：务必使用时间范围查询（WorkBuddy 应用版方式），不要用 PackageCodes 硬编码，否则会遗漏赠送包（如 2500 裂变包）。
2. **精度问题**：`CapacityRemain` 等整数字段有精度损失，应使用 `CapacityRemainPrecise` 字符串字段获取精确值。
3. **周期概念**：`CycleCapacity*` 是当前计费周期（通常自然月）的数据，`Capacity*` 是包生命周期总计。监控余额应看 `CycleCapacityRemain`。
4. **状态过滤**：`Status: [0, 3]` 同时查询有效和已过期包，便于历史分析；仅监控当前余额可只取 `Status=0`。
5. **Cookie 有效期**：需保持登录态，Cookie 过期后需重新登录获取。

---

## 2. TraeWork

### 2.1 基本信息

- **API 域名**：`api.trae.cn`
- **认证方式**：`Authorization: Cloud-IDE-JWT <token>`（JWT 令牌，有过期时间）
- **Content-Type**：`application/json`
- **JWT 获取**：通过 `POST /cloudide/api/v3/common/GetUserToken` 接口获取，或登录后从请求头提取。

### 2.2 核心接口一：用户当前权益列表（额度汇总）

```
POST /trae/api/v2/pay/user_current_entitlement_list
```

#### 请求体

```json
{
  "require_usage": true,
  "full_data": true
}
```

#### 响应体结构

```json
{
  "is_credits_billing": true,
  "is_dollar_usage_billing": false,
  "is_pay_freshman": true,
  "trial_status": {
    "is_eligible_for_trial": false,
    "is_in_trial": false
  },
  "usage_summary": {
    "consumed_amount": 3001.55,
    "consumption_ratio": 0.42275352112676057,
    "total_amount": 7100
  },
  "user_entitlement_pack_list": [
    {
      "display_desc": "老用户福利",
      "entitlement_base_info": {
        "entitlement_id": "339961611778",
        "product_id": 208,
        "product_type": 2,
        "quota": {
          "credits_limit": 2000,
          "no_bonus_quota": true
        },
        "start_time": 1786700741,
        "end_time": 1789379141,
        "ent_status": 0,
        "user_id": "58720492756857",
        "product_extra": {
          "package_extra": {
            "package_name": "福利积分",
            "package_source_type": 10,
            "duration": 0,
            "package_duration_type": 0,
            "quota": {
              "credits_limit": 2000,
              "no_bonus_quota": true
            }
          }
        }
      },
      "usage": {
        "credits_amount": 501.5528
      },
      "group_name": "用户福利",
      "group_type": 4,
      "status": 0,
      "expire_time": 1789379141,
      "source_id": "339961611778",
      "is_hide": false
    },
    {
      "display_desc": "每月登录赠送",
      "entitlement_base_info": {
        "entitlement_id": "monthly_bonus_20268_58720492756857",
        "product_id": 221,
        "product_type": 2,
        "quota": {
          "credits_limit": 500,
          "enable_solo_agent": true,
          "enable_solo_builder": true,
          "enable_solo_coder": true,
          "enable_solo_lite": true,
          "enable_solo_web": true,
          "no_bonus_quota": true,
          "solo_agent_parallel_limit": 2
        },
        "start_time": 1785513600,
        "end_time": 1788191999,
        "ent_status": 0
      },
      "usage": {
        "credits_amount": 500
      },
      "group_name": "每月登录积分",
      "group_type": 3,
      "status": 1,
      "expire_time": 1788191999
    },
    {
      "display_desc": "签到奖励",
      "entitlement_base_info": {
        "entitlement_id": "checkin_20260827_58720492756857",
        "product_id": 209,
        "product_type": 2,
        "quota": {
          "credits_limit": 200
        },
        "start_time": 1787767113,
        "end_time": 1790445513,
        "ent_status": 0,
        "product_extra": {
          "package_extra": {
            "package_name": "签到奖励",
            "package_source_type": 9,
            "duration": 31,
            "package_duration_type": 0,
            "quota": {
              "credits_limit": 200
            }
          }
        }
      },
      "usage": {},
      "group_name": "每日签到",
      "group_type": 1,
      "status": 1,
      "expire_time": 1790445513
    }
  ]
}
```

#### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `usage_summary.total_amount` | float | 总额度（credits） |
| `usage_summary.consumed_amount` | float | 已消耗额度（credits） |
| `usage_summary.consumption_ratio` | float | 消耗比例（0~1，如 0.423 = 42.3%） |
| `user_entitlement_pack_list[].display_desc` | string | 权益包显示名称（如"老用户福利"、"每月登录赠送"、"签到奖励"） |
| `user_entitlement_pack_list[].group_name` | string | 分组名称（"用户福利"、"每月登录积分"、"每日签到"） |
| `user_entitlement_pack_list[].group_type` | int | 分组类型：1=每日签到，3=每月登录，4=用户福利 |
| `user_entitlement_pack_list[].entitlement_base_info.quota.credits_limit` | int | 包额度上限（credits） |
| `user_entitlement_pack_list[].usage.credits_amount` | float | 包已用额度（credits），空对象表示未使用 |
| `user_entitlement_pack_list[].status` | int | 状态：0=有效，1=已用完/过期 |
| `user_entitlement_pack_list[].entitlement_base_info.start_time` | long | 开始时间（秒级时间戳） |
| `user_entitlement_pack_list[].entitlement_base_info.end_time` | long | 结束时间（秒级时间戳） |
| `user_entitlement_pack_list[].entitlement_base_info.product_extra.package_extra.package_source_type` | int | 来源类型：9=签到，10=福利活动 |

#### 实际数据样例（当前账号）

| 权益包 | 额度 | 已用 | 剩余 | 分组 | 状态 |
|--------|------|------|------|------|------|
| 老用户福利（product_id=208） | 2000 | 501.55 | 1498.45 | 用户福利 | 有效 |
| 老用户福利（product_id=209） | 2000 | 2000 | 0 | 用户福利 | 已用完 |
| 免费套餐 | — | — | — | — | 有效 |
| 每月登录赠送 | 500 | 500 | 0 | 每月登录积分 | 已用完 |
| 签到奖励 × 14天 | 200×14 | 0 | 2800 | 每日签到 | 有效 |
| **汇总** | **7100** | **3001.55** | **4098.45** | — | — |

> **当前总剩余 ≈ 4098.45 credits**（7100 - 3001.55）

---

### 2.3 核心接口二：按会话查询用量（含 token 明细）

```
POST /trae/api/v1/pay/query_user_usage_group_by_session
```

#### 请求体

```json
{
  "start_time": 1787328000,
  "end_time": 1787932799,
  "page_size": 20,
  "page_num": 1,
  "usage_type": [7]
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `start_time` | long | 开始时间（秒级 Unix 时间戳） |
| `end_time` | long | 结束时间（秒级 Unix 时间戳） |
| `page_size` | int | 每页条数 |
| `page_num` | int | 页码（从1开始） |
| `usage_type` | int[] | 用量类型，`[7]` 为常规对话用量 |

#### 响应体结构

```json
{
  "total": 9,
  "user_usage_group_by_sessions": [
    {
      "session_id": "6a8fff69f784fbd690152c0d",
      "model_name": "DeepSeek-V4-Flash 正式版",
      "credits_float": 266.9096,
      "amount_float": 266.9096,
      "cost_money_float": 6.67274,
      "dollar_float": 0,
      "usage_time": 1787821953,
      "usage_source": 2,
      "user_input_preview": "\nUse Skill: media-de",
      "extra_info": {
        "input_token": 52299168,
        "output_token": 391849,
        "cache_read_token": 50379376,
        "cache_write_token": 0
      },
      "usage_group_details": [
        {
          "group_key": "default",
          "model_display_name": "DeepSeek-V4-Flash 正式版",
          "credits_float": 266.9096,
          "amount_float": 266.9096,
          "cost_money_float": 6.67274,
          "extra_info": {
            "input_token": 52299168,
            "output_token": 391849,
            "cache_read_token": 50379376,
            "cache_write_token": 0
          }
        }
      ]
    }
  ]
}
```

#### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `total` | int | 总会话数 |
| `user_usage_group_by_sessions[].session_id` | string | 会话 ID |
| `user_usage_group_by_sessions[].model_name` | string | 模型名称（如"DeepSeek-V4-Flash 正式版"） |
| `user_usage_group_by_sessions[].credits_float` | float | 本会话消耗 credits |
| `user_usage_group_by_sessions[].cost_money_float` | float | 折算金额（元） |
| `user_usage_group_by_sessions[].usage_time` | long | 使用时间（秒级时间戳） |
| `user_usage_group_by_sessions[].user_input_preview` | string | 用户输入预览（截断） |
| `user_usage_group_by_sessions[].extra_info.input_token` | int | 输入 token 数 |
| `user_usage_group_by_sessions[].extra_info.output_token` | int | 输出 token 数 |
| `user_usage_group_by_sessions[].extra_info.cache_read_token` | int | 缓存读取 token 数（通常远大于 input_token，因包含上下文） |
| `user_usage_group_by_sessions[].extra_info.cache_write_token` | int | 缓存写入 token 数 |

> **注意**：`cache_read_token` 是模型实际计费的 token 基数（包含完整上下文缓存），`input_token` 是本次新增输入。实际计费通常基于 cache_read + output。

---

### 2.4 辅助接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/trae/api/v2/pay/cn_credits_billing_status` | POST | credits 计费状态，请求体 `{}`，返回 `{"is_credits_billing":true,"should_force_switch":true}` |
| `/trae/api/v2/pay/web_user_pay_status` | POST | 用户支付状态 |
| `/trae/api/v2/pay/expired_ents` | POST | 已过期权益列表 |
| `/cloudide/api/v3/trae/GetUserInfo` | POST | 获取用户信息 |
| `/cloudide/api/v3/common/GetUserToken` | POST | 获取 JWT token（用于刷新） |
| `/cloudide/api/v3/trae/CheckLogin` | POST | 检查登录状态 |

---

### 2.5 注意事项

1. **JWT 过期**：JWT token 包含 `exp` 字段（过期时间戳），需定期调用 `GetUserToken` 刷新。当前 token 有效期约 8 小时。
2. **时间戳单位**：Trae 接口使用**秒级** Unix 时间戳（WorkBuddy 部分字段用毫秒级，注意区分）。
3. **额度扣减顺序**：系统优先使用最先到期的积分包，监控时需按 `end_time` 排序计算可用余额。
4. **usage_type**：`[7]` 是常规对话用量，其他类型值待探索。
5. **签到积分**：每日签到奖励 200 credits，有效期 31 天，`usage` 为空对象 `{}` 表示未使用。
6. **缓存 token**：`cache_read_token` 数值很大（含完整上下文），是实际计费基数，不要与 `input_token` 混淆。

---

## 3. 豆包工作

### 3.1 基本信息

- **API 域名**：`www.doubao.com`
- **认证方式**：Cookie 登录态
- **Content-Type**：`application/json`
- **额度机制**："5小时滚动窗口 + 7天总额度"双限制，**仅返回使用百分比，不返回具体数值**

### 3.2 核心接口一：订阅额度汇总

```
POST /alice/commerce/sale/subscription/quota/summary/
```

#### 请求体

```json
{
  "product_line": "membership"
}
```

#### 响应体结构

```json
{
  "data": {
    "current_subscription": {
      "agreement_price": 0,
      "agreement_status": 1,
      "agreement_type": 1,
      "currency_code": "CNY",
      "display": {
        "logo_url": "https://.../豆包订阅 标准套餐.png",
        "product_name": "豆包订阅",
        "short_name": "标准套餐"
      },
      "end_time": 1790239887593,
      "is_gift": true,
      "period_type": 8,
      "sku_key": "doubao_personal_std",
      "source_type": 2,
      "start_time": 1787647887593,
      "status": 3,
      "subscription_id": "7677888570250772495",
      "subscription_type": 2,
      "timezone": -480,
      "trial_info": {
        "is_trialing": false
      }
    },
    "window_limit_section": {
      "entitlement_count": 1,
      "usage_exhausted": false,
      "window_limit_groups": [
        {
          "feature_group": "general",
          "feature_group_name": "",
          "should_prompt_purchase": true,
          "window_limits": [
            {
              "window_type": 1,
              "item_type": 0,
              "used_percent": 12,
              "less_than_one_percent": false,
              "start_time": 1787832539031,
              "end_time": 1787850539031
            },
            {
              "window_type": 2,
              "item_type": 0,
              "used_percent": 97,
              "less_than_one_percent": false,
              "start_time": 1787658700141,
              "end_time": 1788263500141
            }
          ]
        }
      ]
    },
    "member_info": {
      "hasActiveSubscription": true,
      "hasEnterpriseSubscription": false,
      "usr_type": 1
    }
  },
  "code": 0,
  "msg": "",
  "message": ""
}
```

#### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.current_subscription.sku_key` | string | 套餐标识：`doubao_personal_std`=标准套餐，`doubao_personal_pro`=专业版 |
| `data.current_subscription.display.short_name` | string | 套餐显示名（如"标准套餐"） |
| `data.current_subscription.is_gift` | bool | 是否为赠送套餐 |
| `data.current_subscription.status` | int | 订阅状态：3=有效 |
| `data.current_subscription.start_time` | long | 订阅开始时间（**毫秒级**时间戳） |
| `data.current_subscription.end_time` | long | 订阅结束时间（**毫秒级**时间戳） |
| `data.window_limit_section.usage_exhausted` | bool | 额度是否已用尽（true=任一窗口达到100%） |
| `data.window_limit_section.window_limit_groups[].window_limits[].window_type` | int | 窗口类型：**1=5小时滚动窗口**，**2=7天总额度窗口** |
| `data.window_limit_section.window_limit_groups[].window_limits[].used_percent` | int | 已使用百分比（0~100，整数） |
| `data.window_limit_section.window_limit_groups[].window_limits[].less_than_one_percent` | bool | 是否小于1%（当用量极少时 used_percent 可能为0，此字段为true） |
| `data.window_limit_section.window_limit_groups[].window_limits[].start_time` | long | 窗口开始时间（毫秒级） |
| `data.window_limit_section.window_limit_groups[].window_limits[].end_time` | long | 窗口结束/重置时间（毫秒级时间戳），即额度重置时刻 |

#### 实际数据样例（当前账号）

| 窗口类型 | 已用百分比 | 剩余百分比 | 窗口起始 | 重置时间（end_time） |
|---------|-----------|-----------|---------|---------------------|
| 5小时滚动窗口 | 12% | 88% | 2026-08-27 20:08:59 | 2026-08-28 01:08:59 |
| 7天总额度 | 97% | 3% | 2026-08-25 19:51:40 | 2026-09-01 19:51:40 |

> ⚠️ **7天额度仅剩 3%，即将触顶！**

---

### 3.3 核心接口二：订阅概览

```
POST /alice/commerce/sale/subscription/overview/
```

#### 请求体

```json
{
  "product_line": "membership"
}
```

#### 响应体说明

与 `quota/summary/` 类似，但额外包含：
- `entitlements[]`：具体权益列表
- `package_entitlement_groups[]`：套餐权益分组
- `quota_package_entitlement_groups[]`：额度包权益分组
- `upgrade_guide`：升级引导信息（含升级链接）
- `quota_package_purchase_entry`：额度包购买入口

---

### 3.4 辅助接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/alice/commerce/intake/entitlement/query` | POST | 权益查询 |
| `/alice/commerce/marketing/card/balance/` | POST | 营销卡余额 |
| `/alice/commerce/marketing/card/list/` | POST | 营销卡列表 |
| `/alice/commerce/sale/subscription/status/` | POST | 订阅状态 |
| `/alice/commerce/sale/subscription/entry/config/` | POST | 订阅入口配置 |

---

### 3.5 注意事项

1. **无具体数值**：豆包工作从设计上不暴露总额度、已用量、剩余量的具体数值，只返回 `used_percent`（整数百分比）。无法做精确数值监控，只能做百分比预警。
2. **时间戳单位**：豆包接口使用**毫秒级** Unix 时间戳（Trae 用秒级，注意转换）。
3. **双窗口机制**：
   - `window_type=1`：5小时滚动窗口，每5小时重置一次
   - `window_type=2`：7天总额度，每周重置一次
   - 任一窗口达到100%即无法继续使用，需等待重置或购买额度包
   - **重置时间可通过 `window_limits[].end_time` 字段获取**（毫秒级时间戳），每个窗口独立计算重置时刻，监控时可据此推算"距离重置还有多久"
4. **百分比精度**：`used_percent` 是整数（0~100），当用量小于1%时 `less_than_one_percent=true`，无法获知精确小数。
5. `usage_exhausted` 字段可直接判断是否已用尽，是监控告警的关键指标。
6. **额度包购买**：可通过 `quota_package_purchase_entry.order_page_url` 跳转购买额度包，购买后额度会叠加。

---

## 统一监控建议

### 监控指标设计

| 平台 | 核心指标 | 告警阈值建议 |
|------|---------|-------------|
| WorkBuddy | `CycleCapacityRemain`（周期剩余） | < 100 credits 或 < 10% |
| TraeWork | `usage_summary.consumption_ratio`（消耗比例） | > 80% 或剩余 < 500 credits |
| 豆包工作 | `window_limits[].used_percent` + `usage_exhausted` | 5h窗口 > 80% 或 7天窗口 > 90% |

### 数据刷新频率建议

| 平台 | 刷新频率 | 原因 |
|------|---------|------|
| WorkBuddy | 5~10 分钟 | Cookie 稳定，接口无明确限流 |
| TraeWork | 5~10 分钟 | JWT 需定期刷新，注意 token 有效期 |
| 豆包工作 | 10~15 分钟 | 百分比制，变化相对缓慢；且无精确数值，过频无意义 |

### 实现要点

1. **认证持久化**：
   - WorkBuddy / 豆包工作：保存 Cookie，定期检查登录态有效性
   - TraeWork：保存 JWT token + refresh token，自动调用 `GetUserToken` 刷新

2. **额度计算**：
   - WorkBuddy：遍历所有 `Status=0` 的资源包，累加 `CycleCapacityRemainPrecise`
   - TraeWork：直接使用 `usage_summary.total_amount - consumed_amount`
   - 豆包工作：只能展示百分比，计算 `100 - used_percent` 作为剩余百分比

3. **历史趋势**：
   - WorkBuddy / TraeWork 可记录每日余额，生成消耗趋势图
   - 豆包工作只能记录百分比变化趋势

4. **多账号支持**：三个平台均支持多账号切换，需为每个账号独立保存认证信息和额度数据。

---

> **文档结束**。如有接口变更或新平台接入，请及时更新本文档。
