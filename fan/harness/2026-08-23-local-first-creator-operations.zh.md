# Agent Note: Local-first creator operations companion

Status: implemented

[English](2026-08-23-local-first-creator-operations.md) | 中文

## Problem

使用 DeepSeek Harness 进行研究和自动化的创作者仍需要一个持久化位置，把想法转化为带来源的简报、保留人工批准、安排官方平台发帖并比较汇总结果。每个规划步骤都发送给付费模型会把 token 花在日常格式整理上，而针对个人账户的浏览器自动化会带来脆弱的访问方式、隐私风险和平台策略风险。

Harness Web preset 负责 agent 会话和工具；内容日历、平台凭证、发布队列和效果数据库属于独立的应用关注点。把这些记录折叠进 Web preset 会把专用创作者工作流与通用 agent 运行时耦合，并让平台写入操作不再足够明确。

## Decision

`examples/jsonrpc-agent/creator_ops.py` 和 `creator_ops_gui.pyw` 组成一个独立桌面配套工具。现有 `ollama_preprompt.py` 客户端提供受 schema 约束的本地 Ollama 调用，以及显式的 DeepSeek Harness 审核交接。Creator Operations 不修改 Harness Web preset。

SQLite 存储主题、可编辑简报、批准、账户引用、计划、汇总观察、发布目标、指标、实验和工作流事件。数据库只存储各凭证环境变量的名称，绝不存储其值。编辑已批准简报会使其回到草稿状态。

每条发布路径都从试运行开始。实时官方 API 请求必须同时具备当前人工批准、已到期的计划发布目标、已启用账户、具名凭证，以及进程环境中的 `CREATOR_OPS_LIVE_PUBLISH=1`。worker 在网络调用前把发布目标声明为 `publishing`，并把结果不明确的失败留给操作员审核，而不是自动重试。实现支持 Facebook Page、Instagram 专业账户和 TikTok Content Posting API 照片帖子；不自动操作个人资料或平台界面。

本地生成只产生可由创作者编辑的简报，不生成媒体或证据。系统提示词禁止虚构事实和来源、伪造社区帖子、冒充、骚扰、隐蔽界面自动化、针对个人以及按个人追踪评论者。经授权的研究导入只包含汇总主题、情绪和权利依据。指标和 A/B 汇总使用发布目标的聚合结果，不声称相关性能够证明因果关系或病毒式传播。

## Alternatives considered

**修改 Harness Web 应用。** 否决，因为内容运营的数据生命周期、凭证集、计划模型和受众与 agent 会话不同。独立 GUI 导入受支持的 Python 编排代码，而不更改通用 Web preset。

**自动操作各平台的浏览器界面。** 否决，因为选择器和个人会话不稳定，会绕过官方审核与权限，并使人工批准难以证明。官方 API 会明确暴露账户身份、权限和错误。

**为方便而在 SQLite 中存储访问 token。** 否决，因为计划和分析适合备份或检查，而 bearer token 需要更严格的密钥管理生命周期。账户记录只保存环境变量名称。

**让模型自主发布或优化互动。** 否决，因为模型输出不是事实来源，互动指标不能证明受众价值，自动制造争议可能把不确定性变成欺骗或骚扰。创作者编辑并批准每个项目；实验比较已声明的变体并保留汇总证据。

## Testing

离线 Python 测试覆盖 schema 创建和主题播种、编辑后的批准失效、批准前拒绝计划、试运行不修改状态、凭证不持久化、本地简报验证、确定性的最新指标选择、仅汇总观察字段和 A/B 计算。使用支持 Tcl/Tk 的 Python 运行时检查 GUI 构造，但不启动事件循环。测试不发出平台请求或付费 DeepSeek 调用。

## Consequences

在创作者提供 Ollama 计算资源后，日常构思、计划和学习保持本地且免费。付费审核和平台写入都是具备可见前提的显式操作。代价是增加一个桌面应用，以及维护官方开发者应用、token、公共媒体托管、Task Scheduler 和平台版本配置的运维工作。

该配套工具不能承诺病毒式传播主题、变现邀请、收入结果或平台资格。它记录有来源支持的假设和汇总结果，使创作者能依据更好的证据作出下一步决定。
