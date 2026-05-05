# Dataflow-Guided Retrieval Augmentation for Repository-Level Code Completion

## 基本信息
- 论文：Dataflow-Guided Retrieval Augmentation for Repository-Level Code Completion
- 方法名：DRACO / DraCo
- 会议：ACL 2024
- 链接：https://aclanthology.org/2024.acl-long.431.pdf
- 关键词：Repository-level Code Completion、Code RAG、Dataflow Analysis、Context Graph、Prompt Construction

## 快速省流总结
这篇论文的核心问题是：**代码仓库级补全不能只靠“相似代码片段检索”**。真实仓库里的补全往往依赖跨文件定义、类型关系、导入路径、成员归属、继承层次等结构性信息，而这些信息并不会因为文本相似就自然被检出来。作者因此提出 DRACO：先离线分析仓库，提取代码实体并通过扩展的数据流分析建立一个 **repo-specific context graph**；在线补全时，再根据 unfinished code 中的细粒度 import / usage 信息，在图中定位相关实体，沿 depends 关系检索背景知识，最后把这些实体恢复成代码形式，与待补全代码拼接成 well-formed prompt 去查询 code LM。它其实是一种非常典型的“结构感知代码 RAG”，只是知识源不是普通文本库，而是程序实体图。

## Motivation
作者认为，近年来代码大模型在单文件补全上效果不错，但现实开发里很多补全需求都发生在**私有仓库、跨文件依赖、多模块协作**的环境中。  
在这些环境里，模型失败的原因通常不是不会写语法，而是缺少仓库内部知识，例如：

- 某个类具体定义在哪个文件
- 某个函数的返回类型是什么
- 一个对象上到底有哪些成员方法
- 局部变量经过了怎样的类型传播
- 某个 import 实际指向仓库里的哪个实体

这些信息如果只靠“文本相似检索”，很容易检错。  
因此作者想把“代码补全所依赖的结构关系”显式建成可检索图。

## Challenges
### 1. 代码补全依赖的是关系，不只是相似文本
很多真正关键的背景知识并不会在 lexical similarity 上最相近。

### 2. 仓库级上下文非常长
整个 repo 不可能直接塞给模型，只能选择性取最相关部分。

### 3. 相关上下文往往是细粒度实体，而不是整文件
模型真正需要的可能是某个 class、某个 method、某个 variable definition，而不是整个文件原文。

### 4. 需要兼顾离线建库与在线高效检索
如果在线再做复杂静态分析，代价太高；但如果离线只做简单索引，又抓不住真实依赖。

## Overview / 核心思路
DRACO 的框架可以拆成三部分：

1. **Offline indexing / 建库阶段**
   - 对仓库做静态分析
   - 抽取代码实体
   - 建立 repo-specific context graph

2. **Online retrieval / 检索阶段**
   - 读取 unfinished code
   - 提取细粒度 import / usage 信息
   - 在图中定位对应实体
   - 沿 depends 关系检索相关背景知识

3. **Prompt generation / 生成阶段**
   - 将检索到的实体恢复成自然代码片段
   - 与 unfinished code 拼接
   - 形成适合 code LM 的 prompt

这使得代码 RAG 不再是“把仓库切块做 embedding”，而是“把程序关系图作为检索骨架”。

## Technical Details / 方法细节（详细）

### 1. 为什么作者强调 dataflow-guided
传统代码检索常见两类思路：
- 基于 import 关系
- 基于文本/embedding 相似度

但这两者都不够。  
因为在实际补全中，最重要的问题往往是：“当前代码里的这个变量/对象，究竟是什么类型？它依赖的定义链条是什么？”  
这本质上是数据依赖和类型依赖问题，而不是文本相似问题。

所以作者引入 **dataflow-guided retrieval**，让检索围绕程序依赖关系展开。

### 2. DFG：扩展的数据流图
作者先通过扩展的数据流分析构造一个 **heterogeneous directed acyclic graph**。  
图中包括不同类型的代码实体与关系：

#### 实体（Entities）
- module
- class
- function
- variable

每类实体保存的属性也不一样，例如：
- module：路径、docstring
- class：名称、signature、docstring、起始行
- function：名称、signature、docstring、body、起始行
- variable：名称、语句、起始行

#### 关系（Relations）
除了自然的包含关系（contains），还包括作者强调的**type-sensitive depends relations**。  
例如：
- 某函数返回某类
- 某变量依赖某定义
- 某类继承某基类
- 某 import 指向另一模块中的实体

这里很关键的一点是：作者不只是建 AST，而是进一步把“类型传播与依赖信息”编码进图关系里。

### 3. Repo-specific Context Graph
在 DFG 基础上，作者形成 repo-specific context graph。  
这个图是 DRACO 的核心知识库。

#### 为什么不用“把代码当普通文本”
作者明确反对简单把 repo 当文本块来切。因为代码补全依赖的是：
- 程序实体的边界
- 成员归属
- 返回类型
- 跨文件导入指向
- 继承关系

这些都不是普通 chunking 能保真的。

#### 图中怎么组织
每个代码文件会被解析成实体集合，并通过：
- `contains`
- `depends`
等关系连接起来。  
最终形成一个适合在线定位和扩展的结构化索引。

### 4. 在线检索：如何从 unfinished code 出发
这是 DRACO 最实用的地方。

在线补全时，系统读取 unfinished code，并提取其中的**细粒度 import information** 与 usage cues。  
比如：
- import 了哪个类/模块
- 调用了哪个成员方法
- 某个对象变量后面出现了 `name.attr`
- 某个调用链在暗示什么类型信息

接着，系统会做几件事：

#### Step 1：定位 import 对应的模块实体
通过目录结构和字符串匹配，先把 import 语句指向的模块在 context graph 中定位出来。

#### Step 2：定位更细粒度的代码实体
在对应模块内部，继续用名称匹配、作用域信息等方法，找到 class / function / member function 等具体实体。

#### Step 3：沿 depends 关系做 DFS 检索
一旦找到起始实体，系统会沿 depends relations 做深度优先搜索，把与当前补全最相关的实体一起拉出来。

这里的关键在于：  
检索不是“相似度 top-k”，而是“从当前补全点出发，顺着程序依赖链向外找必要背景知识”。

### 5. Prompt Generation：不是简单拼文本，而是恢复为自然代码
拿到实体后，DRACO 并不会只返回抽象图节点，而是把这些实体**恢复成源码形式**，再与 unfinished code 组织成 well-formed prompt。

作者特别强调两个问题：

#### (1) 输入长度有限
Code LM 上下文窗口不是无限的，因此需要做 context allocation。

#### (2) 主次上下文要区分
作者采用动态上下文分配策略，大致把输入预算分给：
- relevant background knowledge
- unfinished code

如果某一部分较短，多余预算再分给另一部分。  
对于过长 unfinished code，则保留末尾片段，因为补全点附近上下文通常最关键。

### 6. Primary vs Secondary Background Knowledge
这一点很值得学。

作者把检索到的实体进一步区分为：
- **Er**：与当前补全行有直接数据关系的实体，属于 primary knowledge
- **Eo**：其他 local import 相关实体，属于 secondary knowledge

加入 prompt 时，先保证 Er 不被截断，再逐步添加 Eo。  
这说明 DRACO 不只是“检到了什么就全塞进去”，而是明确做了**上下文优先级管理**。

### 7. 为什么这个方法比文本相似检索更适合代码
因为代码补全里的关键问题常常是：
- 这个对象是什么类型
- 这个类型有什么方法
- 这个方法定义在哪
- 返回值又指向什么类型

这是一条关系链。  
文本相似检索可能把注释或看起来像的函数找出来，但未必能找出“真正能解释当前补全点”的实体链条。  
而 DRACO 的图检索正是围绕这条链展开。

## Implementation & Experiment
论文除了在已有仓库级补全数据集上评估，还构建了新的 ReccEval 数据集，以覆盖更多样的 completion targets。  
实验显示，DRACO 在 exact match 和 identifier F1 等指标上优于已有方法。

从结果上看，它证明了一件很重要的事：  
**代码 RAG 的关键不是更强的 embedding，而是更对路的结构检索。**

## 优点
### 1. 结构感知非常强
把 repo 理解为程序实体图，而不是文本库，这是本论文最大亮点。

### 2. 特别适合跨文件补全
对类、函数、返回类型、成员关系等跨文件依赖问题非常有效。

### 3. 上下文组织合理
不是乱拼检索结果，而是区分 primary / secondary knowledge。

### 4. 工程上可落地
离线建图、在线轻量检索的设计比较符合真实开发工具链。

## 局限性
### 1. 依赖静态分析质量
如果仓库语言特性复杂、动态行为强、类型不明确，图构建可能不完整。

### 2. 更适合结构明确语言/场景
动态语言和反射机制较多时，静态依赖不一定能全还原。

### 3. 任务聚焦在 code completion
虽然方法思想可迁移到其他代码任务，但论文实验主要围绕补全展开。

### 4. 不是 end-to-end 学出来的
检索主要依赖离线程序分析和图搜索，而不是统一学习框架。

## 对你当前研究的启发
这篇对你非常重要，因为你现在做的其实也是“不是平面文本，而是有强结构关系的工程知识检索”。

### 1. 你的 scene / script / object 本质上也可以建成 repo-specific context graph
只不过节点不是 module/class/function/variable，而可能是：
- scene object
- component
- script method
- interaction trigger
- state variable

### 2. 比起纯向量 chunk 检索，你更需要 relation-guided retrieval
例如某个 action 需要知道：
- 对象是否可抓取
- 它挂了哪个组件
- 组件里哪个方法在控制状态
- 方法又依赖哪些变量
这和 DRACO 的 depends-chain 检索高度相似。

### 3. Primary / Secondary knowledge 的思想很适合你做 prompt budgeting
你可以把：
- 直接关联当前 action 的对象/脚本信息当 primary
- 邻近但不直接相关的 scene context 当 secondary

### 4. 很适合做 verifier / executor 支持
当 Verifier 发现某个 action unsupported，可以沿 dependency graph 继续检索更深层脚本/对象关系，而不是全库重查。

## 一句话总结
DRACO 的核心贡献，是把仓库级代码补全中的“相关上下文检索”从文本相似匹配升级成了以程序实体和数据流依赖为中心的结构检索，从而让代码 RAG 真正围绕“代码为什么在这里需要这段知识”来工作。
