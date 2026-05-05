# SELF-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection

## 基本信息
- 论文：SELF-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection
- 会议：ICLR 2024
- 链接：https://openreview.net/pdf?id=hSyW5go0v8
- 关键词：Adaptive Retrieval、Self-reflection、Critique Tokens、Controllable RAG

## 快速省流总结
SELF-RAG 的核心不是简单把 RAG 做得更强，而是把传统 RAG 里三个一直被外置或硬编码的能力直接学进模型里：**要不要检索、检索到的内容是否相关、生成内容是否被证据支持、整体回答是否有用**。作者不是在推理阶段外加一个 evaluator，而是让模型学会输出一组特殊的 reflection tokens，用这些 token 对检索和生成过程进行自我评估。这样一来，模型既能像普通大模型一样在不需要外部知识时直接回答，也能在需要时主动触发检索，并在生成后自己打出“相关/不相关、支持/不支持、完整/不完整”之类的信号。它相当于把“检索 + 生成 + 自我批判”融合成一个统一的生成过程。

## Motivation
作者指出，传统 RAG 存在两个典型问题：

1. **检索是无差别触发的**  
   不管问题需不需要外部知识，模型都先检索 top-k 文档再生成。这会引入无谓成本，有时还会破坏模型原本的创造性和通用性。

2. **模型缺乏自我审查机制**  
   即便检索到了文档，模型也未必会去判断：
   - 文档到底相关不相关
   - 回答是否被文档真正支持
   - 生成结果是不是完整
   所以输出可能带着“看上去像有证据”的错觉，但其实并不 grounded。

作者的目标很清楚：让模型自己在生成过程中学会“先想清楚要不要查，再判断查来的东西值不值得信，再检查自己写的内容有没有被证据支持”。

## Challenges
SELF-RAG 要解决的难点比普通 RAG 更细：

### 1. 如何把“检索判断”和“生成判断”统一到一个语言模型里
传统做法通常把这些逻辑分散在多个模块里，比如独立 retriever、独立 reranker、独立 verifier。SELF-RAG 想把它们压缩进一个统一的生成式框架中。

### 2. 如何让模型学会输出“评判信号”
“相关”“支持”“有用”这类判断不是标准自然语言答案的一部分。作者需要设计一种让模型能学到这些 meta-level 信号的表示方式。

### 3. 如何在不采用高成本 RLHF 的情况下完成训练
如果把这些判断全都放进强化学习里做，会非常贵。作者希望用更便宜、可监督化的数据构造方式实现。

## Overview / 核心思路
SELF-RAG 的整体思路可以概括成一句话：

> 让模型在正常输出文本的同时，也生成用于控制和审查自身行为的特殊 token。

这些 token 被称为 **reflection tokens**，主要分成两类：

1. **Retrieve token**  
   判断当前这一步是否需要外部检索。

2. **Critique tokens**  
   用来评价检索结果与生成内容的质量，例如：
   - 检索文档是否 relevant
   - 当前回答是否 supported
   - 回答整体是否 useful / complete

于是整个系统不再是“输入 → 检索 → 生成”的固定流水线，而变成：

- 输入问题
- 模型先预测：需不需要检索
- 如果需要，再取回文档
- 对每篇文档分别判断其相关性
- 基于文档并行生成候选片段
- 再判断这些片段是否被支持、是否有用
- 最终在这些候选中选出更合适的输出

这使得 SELF-RAG 更像一个具有内部反思能力的 RAG agent，而不是普通 retrieve-then-generate 管道。

## Technical Details / 方法细节（详细）

### 1. 生成对象不再只是答案文本
SELF-RAG 不是只让模型生成自然语言答案，而是把输出扩展成“文本 + reflection tokens”的混合序列。

作者把输出按 segment 切分，在实验里通常以**句子**作为 segment。  
对于每个 segment，模型不仅要生成正文，还可能生成以下信号：

- `Retrieve=Yes / No`
- `ISREL`：检索文档是否相关
- `ISSUP`：该文档是否支持生成的内容
- `ISUSE`：最终输出整体是否有用

也就是说，SELF-RAG 的单位不是“整段回答一次性吐出来”，而是**逐段生成、逐段反思**。

### 2. 推理时的工作流程
SELF-RAG 的推理流程可以拆成以下步骤：

#### Step 1：判断是否需要检索
给定输入 \(x\) 和当前已生成内容 \(y_{<t}\)，模型首先预测一个 retrieval token。  
- 如果判断 **不需要检索**，就像普通 LM 那样直接继续生成下一个 segment。
- 如果判断 **需要检索**，则进入检索增强模式。

这一点非常关键，因为它让模型摆脱了传统 RAG 的“默认每次都查”的刚性机制。

#### Step 2：执行检索
如果 `Retrieve=Yes`，系统会用 retriever 找回 top-K passages。  
这里的 retrieval 不再是固定前处理，而是由模型在当前生成状态下触发，所以本质上是一种 adaptive retrieval。

#### Step 3：并行为每个 passage 生成评价与回答片段
对于每个 passage，模型会：
- 判断该 passage 是否 relevant（`ISREL`）
- 在 passage 条件下生成一个 response segment
- 判断这个 segment 是否被该 passage 支持（`ISSUP`）

也就是说，SELF-RAG 不是“把多个 passage 一锅炖”，而是让每个文档先各自对应一条“证据—回答”链。

#### Step 4：整体效用评估
在回答末尾，模型还会生成一个 overall utility token（`ISUSE`），表示这段回答整体上是否有帮助、是否满足任务目标。

#### Step 5：通过 soft / hard control 决定最终输出
推理时可以利用这些 reflection token 的概率来进行控制：
- **soft control**：把 token 概率作为 reranking 信号，对候选回答重排序
- **hard control**：设置阈值或规则，过滤不满足 groundedness 的回答

这意味着 SELF-RAG 天然具有“可控 RAG”的属性。你可以把 factuality 权重调高，也可以在开放式任务里降低检索频率、提高创造性权重。

### 3. 训练方式：不是 RLHF，而是离线构造监督数据
这是论文一个很聪明的地方。作者没有直接对最终模型做复杂 RL 训练，而是采用“两阶段离线构造 + 监督学习”的策略。

#### 阶段 A：训练 critic / 或借助 critic 生成标注
作者先使用 critic 模型来判断：
- 某个 segment 是否需要检索
- passage 是否相关
- generation 是否被支持
- 最终输出是否有用

这些判断被转成 reflection token 标签。

#### 阶段 B：构造带 reflection tokens 的训练样本
给定原始输入输出对 \((x, y)\)，作者会把原输出改造成一个“更接近真实推理过程”的增强序列。  
具体做法是：

- 对每个 segment \(y_t\)，判断是否需要 retrieval
- 若需要，则加入 `Retrieve=Yes`
- 对 top-K passages 逐个预测 `ISREL`
- 对生成内容预测 `ISSUP`
- 在整体输出末尾加 `ISUSE`

最终得到的数据不再是普通的 `(input, answer)`，而是 `(input, answer + reflection tokens)`。

#### 阶段 C：用标准 next-token objective 训练 generator
最终模型训练目标非常简单：仍然是语言模型常见的 next-token prediction。  
区别仅在于，它现在要同时学：
- 正常文本生成
- reflection tokens 的生成

这比 RLHF 显著便宜，同时又把“自反思行为模式”蒸馏到了模型内部。

### 4. SELF-RAG 为什么比传统 RAG 更灵活
传统 RAG 最大的问题之一是：是否检索、检索几篇、如何判断证据质量，很多时候都是**固定策略**。SELF-RAG 把这些步骤变成模型预测的一部分，因此它具备：

- **检索自适应性**：不是每题都查
- **证据质量意识**：知道某篇 passage 不相关
- **grounding 自评能力**：知道回答有没有被证据支撑
- **任务可控性**：能针对 factuality / utility 目标调整行为

### 5. 它与“Verifier 模块”的关系
从系统结构视角看，SELF-RAG 某种意义上是把 verifier 内化进了 generator。  
原来你可能需要：
- 一个 retriever
- 一个 generator
- 一个 verifier / critic

而 SELF-RAG 试图让 generator 自己输出 verifier-like 的判断信号。  
这并不意味着外部 verifier 没用了，而是说明“自验证”可以作为模型内部能力存在。

## Implementation & Experiment
作者在多个任务上评估 SELF-RAG，包括：
- 开放域问答
- 长回答问答
- 指令跟随
- 事实性生成等

实验结论主要说明：
1. SELF-RAG 在 factuality 和 citation precision 上表现更好
2. 它不是通过“强制每次检索”获得收益，而是通过更合理的 retrieval decisions 提升效果
3. 反思 token 的引入使推理阶段具备 controllability

## 优点
### 1. 把“是否检索”显式建模
这是相比经典 RAG 非常关键的升级。

### 2. 让生成具备自我批判能力
不仅知道“回答是什么”，还知道“这个回答靠不靠谱”。

### 3. 推理阶段可控
你可以通过阈值或 token score 调整模型偏向 factuality 还是 creativity。

### 4. 训练代价相对可控
相比 RLHF 路线，这种“离线批判标注 + 监督学习”的方式更工程友好。

## 局限性
### 1. 依赖 reflection token 质量
如果 critic 或离线标注过程本身不稳定，模型学到的“自评能力”就可能偏差。

### 2. 需要访问较细粒度的 token 概率
论文也提到，这会限制它直接适用于某些封闭 API 模型。

### 3. 自我评估不等于真实评估
模型说自己“supported”不代表一定真的严格 grounded，因此在高风险场景下仍可能需要外部 verifier。

### 4. 流程更复杂
相比普通 RAG，它在推理与训练上都多了多种特殊 token 与控制逻辑。

## 和其他 RAG 工作的关系
- 相比 **Lewis et al. 2020 RAG**：它不再默认每次都检索，而是学会判断是否需要检索。
- 相比 **动态检索类工作**：它更强调“内部可解释的检索与生成自评信号”。
- 相比 **CRAG / reranking 类工作**：SELF-RAG 更像把质量评估内化到模型自己生成的 token 中。
- 相比 **agent 系统**：它相当于把 planner / retriever / verifier 的一部分角色融合进单模型行为中。

## 对你当前研究的启发
这篇对你很有启发，尤其适合映射到 VRagent 2.0 的多 agent 流程。

### 1. 检索不应该是固定前处理
你完全可以让 Planner 先判断：
- 当前 action planning 是否需要 scene/script retrieval
- 如果只是简单对象引用，不一定要查全库
- 如果涉及交互逻辑、状态条件、trigger chain，再触发检索

### 2. 可以给你的系统设计“reflection schema”
例如每一步 action 之后输出：
- `need_retrieval`
- `evidence_relevance`
- `action_support`
- `plan_utility`
这就是 SELF-RAG 在工程系统里的直接迁移。

### 3. Verifier 可以部分内化
你现在虽然保留外部 Verifier 更稳，但也可以让 Planner 自己先给出一轮自评，再由外部 Verifier 做二次确认。

### 4. 很适合做 coverage-guided / failure-aware planning
如果某一步 evidence support 不足，就重新检索；如果 utility 低，就让 planner revise。这和你当前的闭环控制器天然契合。

## 一句话总结
SELF-RAG 的本质不是“更强的检索增强”，而是让模型学会在生成过程中主动决定是否检索、如何评价证据、以及如何审查自己的回答，从而把 RAG 从固定管道升级成一个带自反思能力的可控生成框架。
